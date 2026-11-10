# avm1.py
# Reads AVM1 bytecode, which the SWF's frame scripts and clip actions compile
# to, out of a code block swf_index.py found. It decodes the action records,
# and it lists the assignments a script makes without running the script: the
# variable or member each one sets, and its value, which can be built from
# numbers and from variables the script reads. It works a value out only from
# variables it is given. assignments() works out everything a script sets when
# the script does nothing but assign numbers, as a clip's onClipEvent(load)
# does when it sets the clip's starting variables, and refuses any other
# script.
#
# Formats are from the SWF spec v19, chapter 5:
# https://open-flash.github.io/mirrors/swf-spec-19.pdf
from __future__ import annotations

import struct
from dataclasses import dataclass

from urchin_dev.swf.swf_index import CodeBlock, SwfIndex

ACTION_END = 0x00
ACTION_STOP = 0x07
ACTION_SUBTRACT = 0x0B
ACTION_MULTIPLY = 0x0C
ACTION_DIVIDE = 0x0D
ACTION_GET_VARIABLE = 0x1C
ACTION_SET_VARIABLE = 0x1D
ACTION_ADD2 = 0x47
ACTION_GET_MEMBER = 0x4E
ACTION_SET_MEMBER = 0x4F
ACTION_CONSTANT_POOL = 0x88
ACTION_DEFINE_FUNCTION2 = 0x8E
ACTION_PUSH = 0x96
ACTION_DEFINE_FUNCTION = 0x9B

# A DefineFunction2 can preload these values into registers. It puts them in
# registers from register 1 on, in this order, and each comes with the byte and
# the bit of the record's flags that ask for it.
PRELOADS = (
    ("this", 0, 0x01),
    ("arguments", 0, 0x04),
    ("super", 0, 0x10),
    ("_root", 0, 0x40),
    ("_parent", 0, 0x80),
    ("_global", 1, 0x01),
)

ARITHMETIC = {
    ACTION_ADD2: lambda a, b: a + b,
    ACTION_SUBTRACT: lambda a, b: a - b,
    ACTION_MULTIPLY: lambda a, b: a * b,
    ACTION_DIVIDE: lambda a, b: a / b,
}


@dataclass(frozen=True)
class Register:
    """A Push of a register's value, which only a running script has."""

    number: int


# A Push of undefined reads as this, and a Push of null reads as None.
UNDEFINED = object()


@dataclass(frozen=True)
class Action:
    """One action record. code is its opcode. args holds a Push's values, with
    each constant pool index already swapped for its string, or a
    ConstantPool's strings. A DefineFunction's or a DefineFunction2's args are
    the function's name, the (register, name) pairs of the values its caller
    puts in registers, and how many of the actions after it are its body. args
    is empty for every other action."""

    code: int
    args: tuple = ()


@dataclass(frozen=True)
class Read:
    """A value that only a running script knows: a variable, or a member of
    one, named by its path from the variable, such as "_root.zoomRatioNEW"."""

    path: str


@dataclass(frozen=True)
class Arithmetic:
    """Add2, Subtract, Multiply or Divide, by its code, on two values that are
    not both numbers."""

    code: int
    left: object
    right: object


@dataclass(frozen=True)
class Assignment:
    """A SetVariable or a SetMember: the path it sets, the value it sets it to,
    and at, the index in actions()'s list of the action that sets it."""

    target: str
    value: object
    at: int


# statements() puts this where a value comes out of something it doesn't run.
UNKNOWN = object()


def actions(index: SwfIndex, block: CodeBlock) -> list[Action]:
    """-> the block's action records in order, up to the End action. A
    function's body follows its DefineFunction or DefineFunction2 in the
    list."""
    result: list[Action] = []
    _decode(index.data, *block.span, [()], result)
    return result


def _decode(data: bytes, pos: int, end: int, pool: list, result: list) -> None:
    """Appends the action records from pos to end, or up to an End action, to
    result. pool[0] holds the constant pool, so that a ConstantPool inside a
    function's body still holds for the actions after the body."""
    while pos < end:
        code = data[pos]
        pos += 1
        if code == ACTION_END:
            break
        if code < 0x80:
            result.append(Action(code))
            continue
        (length,) = struct.unpack_from("<H", data, pos)
        body = data[pos + 2 : pos + 2 + length]
        pos += 2 + length
        if code == ACTION_CONSTANT_POOL:
            pool[0] = _strings(body, 2, struct.unpack_from("<H", body)[0])
            result.append(Action(code, pool[0]))
        elif code == ACTION_PUSH:
            result.append(Action(code, _push_values(body, pool[0])))
        elif code in (ACTION_DEFINE_FUNCTION, ACTION_DEFINE_FUNCTION2):
            name, registers, size = _function(code, body)
            inner: list[Action] = []
            _decode(data, pos, pos + size, pool, inner)
            result.append(Action(code, (name, registers, len(inner))))
            result.extend(inner)
            pos += size
        else:
            result.append(Action(code))


def _function(code: int, body: bytes) -> tuple[str, tuple, int]:
    """-> the name, the (register, name) pairs and the code size of a
    DefineFunction or DefineFunction2 record's body. Only a DefineFunction2
    keeps values in registers."""
    name, pos = _cstring(body, 0)
    (count,) = struct.unpack_from("<H", body, pos)
    pos += 2
    in_registers = code == ACTION_DEFINE_FUNCTION2
    registers = []
    if in_registers:
        flags = body[pos + 1 : pos + 3]
        pos += 3
        for preload, byte, bit in PRELOADS:
            if flags[byte] & bit:
                registers.append((len(registers) + 1, preload))
    for _ in range(count):
        register = body[pos] if in_registers else 0
        param, pos = _cstring(body, pos + 1 if in_registers else pos)
        if register:
            registers.append((register, param))
    (size,) = struct.unpack_from("<H", body, pos)
    return name, tuple(registers), size


def assignments(index: SwfIndex, block: CodeBlock) -> dict[str, object]:
    """-> {variable: value} for every variable the block sets, in the order it
    first sets them, once the block has run. Raises on any action other than a
    Push, a ConstantPool, a GetVariable of a variable the block has set, a
    SetVariable or Add2, Subtract, Multiply and Divide."""
    assigning = {
        ACTION_PUSH,
        ACTION_CONSTANT_POOL,
        ACTION_GET_VARIABLE,
        ACTION_SET_VARIABLE,
        *ARITHMETIC,
    }
    for action in actions(index, block):
        if action.code not in assigning:
            raise ValueError(
                f"{_where(block)} runs action 0x{action.code:02X}, which is not an"
                " assignment"
            )
    variables: dict[str, object] = {}
    for assignment in statements(index, block):
        try:
            variables[assignment.target] = evaluate(assignment.value, variables)
        except ValueError as error:
            raise ValueError(f"{_where(block)} {error}") from error
    return variables


def evaluate(value, variables: dict[str, object]):
    """-> `value` worked out: each Read swapped for the value `variables` holds
    for its path, and each Arithmetic done. Raises on a Read of a path that
    `variables` doesn't hold, and on UNKNOWN."""
    if isinstance(value, Read):
        if value.path not in variables:
            raise ValueError(f"reads {value.path} before it has a value")
        return variables[value.path]
    if isinstance(value, Arithmetic):
        left = evaluate(value.left, variables)
        return ARITHMETIC[value.code](left, evaluate(value.right, variables))
    if value is UNKNOWN:
        raise ValueError("works out a value from an action it doesn't run")
    return value


def statements(index: SwfIndex, block: CodeBlock) -> list[Assignment]:
    """-> every SetVariable and SetMember in the block, function bodies
    included, whose target it can name without running the script, in order. A
    value is a number, a string or a boolean, a Read, an Arithmetic or UNKNOWN.
    In a function's body, a register that the function's caller fills reads as
    the value it holds. Every action other than a Push, a ConstantPool, a
    GetVariable, a GetMember, a SetVariable, a SetMember, the four arithmetic
    ones and a function definition empties the stack, so an assignment of what
    a call or a branch works out is left out."""
    result = []
    stack: list = []
    registers: dict[int, str] = {}
    # For each function body being read, this holds the index of the first
    # action after the body, and the registers and the stack of the code around
    # it.
    around: list[tuple[int, dict, list]] = []
    for at, action in enumerate(actions(index, block)):
        while around and at == around[-1][0]:
            _, registers, stack = around.pop()
        code = action.code
        if code == ACTION_PUSH:
            stack.extend(_named(value, registers) for value in action.args)
        elif code in (ACTION_DEFINE_FUNCTION, ACTION_DEFINE_FUNCTION2):
            name, names, length = action.args
            # A function with no name is a value, which the code around it
            # finds on its stack after the body.
            after = stack if name else [*stack, UNKNOWN]
            around.append((at + 1 + length, registers, after))
            registers, stack = dict(names), []
        elif code == ACTION_GET_VARIABLE:
            stack.append(_read(None, _pop(stack)))
        elif code == ACTION_GET_MEMBER:
            name = _pop(stack)
            stack.append(_read(_pop(stack), name))
        elif code in ARITHMETIC:
            right, left = _pop(stack), _pop(stack)
            stack.append(_arithmetic(code, left, right))
        elif code in (ACTION_SET_VARIABLE, ACTION_SET_MEMBER):
            value, name = _pop(stack), _pop(stack)
            owner = _pop(stack) if code == ACTION_SET_MEMBER else None
            target = _read(owner, name)
            if isinstance(target, Read):
                result.append(Assignment(target.path, value, at))
        elif code != ACTION_CONSTANT_POOL:
            stack = []
    return result


def numbers(index: SwfIndex, block: CodeBlock) -> list[float]:
    """-> every number the block pushes, in order. A boolean is not a
    number."""
    return [
        value
        for action in actions(index, block)
        if action.code == ACTION_PUSH
        for value in action.args
        if isinstance(value, (int, float)) and not isinstance(value, bool)
    ]


def _where(block: CodeBlock) -> str:
    return f"the {block.kind} code on timeline {block.owner} frame {block.frame}"


def _pop(stack: list):
    return stack.pop() if stack else UNKNOWN


def _named(value, registers: dict[int, str]):
    """-> a pushed value, with a register swapped for a Read of what the
    function's caller put in it, or UNKNOWN when the script fills it as it
    runs."""
    if not isinstance(value, Register):
        return value
    return Read(registers[value.number]) if value.number in registers else UNKNOWN


def _is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _read(owner, name):
    """-> a Read of the variable `name` when owner is None, or of the member
    `name` of owner when owner is a Read. Anything else is UNKNOWN."""
    if isinstance(name, str):
        key = name
    elif _is_number(name):
        key = str(int(name)) if float(name).is_integer() else str(name)
    else:
        return UNKNOWN
    if owner is None:
        return Read(key) if isinstance(name, str) else UNKNOWN
    return Read(f"{owner.path}.{key}") if isinstance(owner, Read) else UNKNOWN


def _arithmetic(code: int, left, right):
    if _is_number(left) and _is_number(right):
        return ARITHMETIC[code](left, right)
    if left is UNKNOWN or right is UNKNOWN:
        return UNKNOWN
    return Arithmetic(code, left, right)


def _strings(body: bytes, pos: int, count: int) -> tuple[str, ...]:
    result = []
    for _ in range(count):
        text, pos = _cstring(body, pos)
        result.append(text)
    return tuple(result)


def _cstring(body: bytes, pos: int) -> tuple[str, int]:
    """-> the null-terminated string at pos, and where the bytes after it
    start."""
    end = body.index(0, pos)
    return body[pos:end].decode("utf-8", "replace"), end + 1


def _push_values(body: bytes, pool: tuple[str, ...]) -> tuple:
    """A Push's values. A double is stored as two little-endian 32-bit halves
    with the high half first."""
    values = []
    pos = 0
    while pos < len(body):
        kind = body[pos]
        pos += 1
        if kind == 0:
            (text,) = _strings(body, pos, 1)
            values.append(text)
            pos += len(text.encode()) + 1
        elif kind == 1:
            values.append(struct.unpack_from("<f", body, pos)[0])
            pos += 4
        elif kind == 2:
            values.append(None)
        elif kind == 3:
            values.append(UNDEFINED)
        elif kind == 4:
            values.append(Register(body[pos]))
            pos += 1
        elif kind == 5:
            values.append(bool(body[pos]))
            pos += 1
        elif kind == 6:
            high, low = struct.unpack_from("<II", body, pos)
            values.append(struct.unpack("<d", struct.pack("<II", low, high))[0])
            pos += 8
        elif kind == 7:
            values.append(struct.unpack_from("<i", body, pos)[0])
            pos += 4
        elif kind == 8:
            values.append(pool[body[pos]])
            pos += 1
        elif kind == 9:
            values.append(pool[struct.unpack_from("<H", body, pos)[0]])
            pos += 2
        else:
            raise ValueError(f"Push value of unknown type {kind}")
    return tuple(values)
