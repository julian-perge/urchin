# avm1.py
# Reads AVM1 bytecode, which the SWF's frame scripts and clip actions compile
# to, out of a code block swf_index.py found. It decodes the action records, and
# it works out the variables a script sets when the script does nothing but
# assign numbers, as a clip's onClipEvent(load) does when it sets the clip's
# starting variables. It runs no other ActionScript, so a script that branches,
# calls a function or reads a property is refused rather than half run.
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
ACTION_CONSTANT_POOL = 0x88
ACTION_PUSH = 0x96

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


# A Push of undefined. Null reads as None.
UNDEFINED = object()


@dataclass(frozen=True)
class Action:
    """One action record. code is its opcode. args holds a Push's values, with
    each constant pool index already swapped for its string, or a
    ConstantPool's strings. It is empty for every other action."""

    code: int
    args: tuple = ()


def actions(index: SwfIndex, block: CodeBlock) -> list[Action]:
    """-> the block's action records in order, up to the End action."""
    data = index.data
    pos, end = block.span
    pool: tuple[str, ...] = ()
    result = []
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
            pool = _strings(body, 2, struct.unpack_from("<H", body)[0])
            result.append(Action(code, pool))
        elif code == ACTION_PUSH:
            result.append(Action(code, _push_values(body, pool)))
        else:
            result.append(Action(code))
    return result


def assignments(index: SwfIndex, block: CodeBlock) -> dict[str, object]:
    """-> {variable: value} for every variable the block sets, in the order it
    first sets them, once the block has run. Raises on any action other than a
    Push, a ConstantPool, a GetVariable of a variable the block has set, a
    SetVariable or Add2, Subtract, Multiply and Divide."""
    variables: dict[str, object] = {}
    stack: list = []
    for action in actions(index, block):
        if action.code == ACTION_CONSTANT_POOL:
            continue
        if action.code == ACTION_PUSH:
            stack.extend(action.args)
        elif action.code == ACTION_GET_VARIABLE:
            name = stack.pop()
            if name not in variables:
                raise ValueError(f"{_where(block)} reads {name!r} before it sets it")
            stack.append(variables[name])
        elif action.code == ACTION_SET_VARIABLE:
            value = stack.pop()
            variables[stack.pop()] = value
        elif action.code in ARITHMETIC:
            right, left = stack.pop(), stack.pop()
            stack.append(ARITHMETIC[action.code](left, right))
        else:
            raise ValueError(
                f"{_where(block)} runs action 0x{action.code:02X}, which is not an"
                " assignment"
            )
    return variables


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


def _strings(body: bytes, pos: int, count: int) -> tuple[str, ...]:
    result = []
    for _ in range(count):
        end = body.index(0, pos)
        result.append(body[pos:end].decode("utf-8", "replace"))
        pos = end + 1
    return tuple(result)


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
