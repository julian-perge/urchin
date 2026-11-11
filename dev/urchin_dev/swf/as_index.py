# as_index.py
# Writes dev/converted_json/as_index.jsonl: one record for each game script in
# ffdec's script export under dev/source_files/action_script/, and one for
# each function a game script defines. It reads only that export, so it runs
# on a fresh checkout with no SWF. `uv run as_lookup` reads the output.
#
# The index is for navigation. It says where a piece of the original is, what
# it calls, which names it writes and reads, and how a long piece divides
# into blocks. It is not an authority on behavior, so read the original
# lines before you port or review against them.
#
# A game script is an .as file under a frame_*, DefineSprite_* or
# DefineButton2_* folder. Every other .as file must be Flash's mx component
# library, and build() raises on one that is not, so a game class cannot be
# left out without anyone seeing it.
#
# The parser is tree-sitter's JavaScript grammar. ffdec's AS1/2 output is
# JavaScript once a handler's header line becomes a function header.
#
# Run: uv run extract_as_index
from __future__ import annotations

import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

import tree_sitter_javascript
from tree_sitter import Language, Node, Parser

from urchin_dev import ACTION_SCRIPT, CONVERTED_JSON
from urchin_dev.swf.label_xref import parse_script_path

OUT = CONVERTED_JSON / "as_index.jsonl"

_GAME_FOLDER = re.compile(r"(frame|DefineSprite|DefineButton2)_")
_LIBRARY_CLASS = re.compile(r"\s*class mx\.")
_REGISTERED_CLASS = re.compile(r'Object\.registerClass\("[^"]*",\s*([^)\s]+)\)')

# ffdec writes a handler's first line as `on(release){` or
# `onClipEvent(load){`, which is not JavaScript. The rewrite keeps every
# line number, so a node's row is the line an agent reads in the export.
_HANDLER = re.compile(rb"^(\s*)(on|onClipEvent)\s*\(([^)]*)\)\s*\{", re.MULTILINE)
_HANDLER_NAME = "__handler"

_PARSER = Parser(Language(tree_sitter_javascript.language()))

# A record that spans more lines than _OUTLINED_LINES gets an outline. The
# outline lists each statement of _BLOCK_LINES lines or more, down to
# _OUTLINE_DEPTH levels of nesting.
_OUTLINED_LINES = 60
_BLOCK_LINES = 15
_OUTLINE_DEPTH = 3
_HEAD_LENGTH = 100
_LOOPS = {"while_statement", "for_in_statement", "for_statement", "do_statement"}

# A path that starts with one of these keeps it, as in `_root.Krin.LIFEN`.
_SCOPES = {"_root", "_global", "_parent", "this"}
_PATH = {"identifier", "this", "member_expression", "subscript_expression"}
_IDENTIFIER = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")
_READ, _WRITE, _BOTH = "read", "write", "both"

# A bare name that Flash defines is not a global of the game, so the index
# leaves it out. _PROPERTIES is Action.propertyNames in ffdec's Action.java at
# commit cde1cc21a, in lower case, because ffdec writes `_X` and `_Y`.
_PROPERTY_NAMES = """
_x _y _xscale _yscale _currentframe _totalframes _alpha _visible _width
_height _rotation _target _framesloaded _name _droptarget _url _highquality
_focusrect _soundbuftime _quality _xmouse _ymouse
"""
_PROPERTIES = frozenset(_PROPERTY_NAMES.split())
# Every name that Ruffle's core/src/avm1/globals.rs defines on _global at
# commit 4a8d39661e, less `o`, which the game uses as a variable. The last
# line adds `arguments` and the `mx` package of the component library.
_PLAYER_GLOBAL_NAMES = """
ASnative Object Function NaN Infinity MovieClip XMLSocket AsBroadcaster Color
NetConnection NetStream Camera Microphone SharedObject ContextMenuItem
ContextMenu Error AsSetupError AssetCache RemoteLSOUsage ASSetPropFlags
ASSetNative ASSetNativeAccessor escape unescape parseInt parseFloat trace
updateAfterEvent isNaN isFinite setInterval clearTimeout clearInterval
setTimeout Number Boolean Date String Array Math Sound XMLNode XML LoadVars
Selection Mouse Key Button TextField TextFormat Stage Video Accessibility
SoundCodec System flash textRenderer LocalConnection MovieClipLoader PrintJob
TextSnapshot
arguments mx
"""
_PLAYER_GLOBALS = frozenset(_PLAYER_GLOBAL_NAMES.split())


@dataclass(frozen=True)
class Call:
    """One call site. `receiver` is the source text before the last "." of
    the callee, or None for a bare call."""

    name: str
    line: int
    receiver: str | None


@dataclass(frozen=True)
class Write:
    """One written name, with each line that holds the last segment of the
    name in a write of it."""

    name: str
    lines: tuple[int, ...]


@dataclass(frozen=True)
class Block:
    """One outline entry: a statement of 15 lines or more. `head` is its
    first source line. An `else` is an entry at the depth of its `if`."""

    start: int
    end: int
    depth: int
    head: str


@dataclass(frozen=True)
class Function:
    """One function a script defines. declared_as is "declaration", or
    "assignment" with `target` holding the full text it is assigned to.
    `calls`, `writes` and `reads` leave out what a function nested in this
    one calls, writes and reads. `outline` is None on a short function."""

    name: str
    declared_as: str
    target: str | None
    start: int
    end: int
    params: tuple[str, ...]
    calls: tuple[Call, ...]
    writes: tuple[Write, ...]
    reads: tuple[str, ...]
    outline: tuple[Block, ...] | None


@dataclass(frozen=True)
class ParsedScript:
    """One script's parse. `event` is a handler's header, as in
    "onClipEvent(load)", and None on a frame script. `calls`, `writes` and
    `reads` hold only what the code outside every function the script
    defines calls, writes and reads. `outline` is None on a short script."""

    lines: int
    event: str | None
    has_error: bool
    calls: tuple[Call, ...]
    functions: tuple[Function, ...]
    writes: tuple[Write, ...]
    reads: tuple[str, ...]
    outline: tuple[Block, ...] | None


def is_game_script(rel: Path) -> bool:
    return _GAME_FOLDER.match(rel.parts[0]) is not None


def as_javascript(source: bytes) -> bytes:
    return _HANDLER.sub(lambda m: m.group(1) + b"function __handler(){", source)


def _text(node: Node) -> str:
    return node.text.decode()


def _call(node: Node) -> Call | None:
    callee = node.child_by_field_name("function")
    if callee.type == "identifier":
        return Call(_text(callee), callee.start_point[0] + 1, None)
    if callee.type == "member_expression":
        name = callee.child_by_field_name("property")
        receiver = _text(callee.child_by_field_name("object"))
        return Call(_text(name), name.start_point[0] + 1, receiver)
    return None


def _assigned_name(target: Node) -> str:
    if target.type == "identifier":
        return _text(target)
    if target.type == "member_expression":
        return _text(target.child_by_field_name("property"))
    raise ValueError(f"function assigned to a computed target: {_text(target)}")


class _Body:
    """What the walk has found so far in one function, or in the code of a
    script that is outside every function."""

    def __init__(self):
        self.calls: list[Call] = []
        self.writes: dict[str, set[int]] = {}
        self.reads: set[str] = set()

    def written(self) -> tuple[Write, ...]:
        return tuple(
            Write(name, tuple(sorted(lines)))
            for name, lines in sorted(self.writes.items())
        )


def _locals(function: Node) -> frozenset[str]:
    """-> the params of a function and the names it declares with `var`. The
    names of a function nested in it are not in the result."""
    names = {
        _text(p) for p in function.child_by_field_name("parameters").named_children
    }
    stack = [function.child_by_field_name("body")]
    while stack:
        node = stack.pop()
        if node.type in ("function_declaration", "function_expression"):
            continue
        if node.type == "variable_declarator":
            names.add(_text(node.child_by_field_name("name")))
        elif node.type == "for_in_statement" and node.child_by_field_name("kind"):
            names.add(_text(node.child_by_field_name("left")))
        stack.extend(node.children)
    return frozenset(names)


def _prefix(index: Node) -> Node | None:
    """-> the string that starts a computed segment like `["playerKrin" + n]`,
    or None when the segment does not start with a string that can be a name."""
    node = index
    while (
        node.type == "binary_expression"
        and node.child_by_field_name("operator").type == "+"
    ):
        node = node.child_by_field_name("left")
    if node.type != "string" or node.id == index.id:
        return None
    if _IDENTIFIER.fullmatch(_text(node)[1:-1]) is None:
        return None
    return node


def _record_path(node: Node, body: _Body, local: frozenset[str], use: str) -> list:
    """Record the name of one path as a write, a read or both, and -> the
    nodes inside the path that the walk still has to visit.

    The name is the longest static path. A computed segment that starts with
    a string becomes that string and "*", and the path goes on after it. Any
    other computed segment ends the name. A bare name is left out when it is
    a param or a `var` of a function around it, or a name Flash defines."""
    links = []
    while node.type in ("member_expression", "subscript_expression"):
        links.append(node)
        node = node.child_by_field_name("object")
    named = node.type in ("identifier", "this")
    inside = [] if named else [node]
    segments = [_text(node)]
    last = node
    growing = named
    for link in reversed(links):
        if link.type == "member_expression":
            if growing:
                last = link.child_by_field_name("property")
                segments.append(_text(last))
            continue
        index = link.child_by_field_name("index")
        inside.append(index)
        prefix = _prefix(index) if growing else None
        if prefix is None:
            growing = False
        else:
            last = prefix
            segments.append(_text(prefix)[1:-1] + "*")

    head = segments[0]
    if not named or (head in _SCOPES and len(segments) == 1):
        return inside
    if head not in _SCOPES and (
        head in local or head in _PLAYER_GLOBALS or head.lower() in _PROPERTIES
    ):
        return inside
    name = ".".join(segments)
    if use != _READ:
        body.writes.setdefault(name, set()).add(last.start_point[0] + 1)
    if use != _WRITE:
        body.reads.add(name)
    return inside


def _statements(block: Node) -> list[Node]:
    return block.named_children if block.type == "statement_block" else [block]


def _outline(statements: list[Node], lines: list[str]) -> tuple[Block, ...]:
    blocks = []
    stack = [(statement, 1) for statement in reversed(statements)]
    while stack:
        node, depth = stack.pop()
        start, end = node.start_point[0], node.end_point[0]
        if end - start + 1 < _BLOCK_LINES:
            continue
        head = lines[start].strip()[:_HEAD_LENGTH]
        blocks.append(Block(start + 1, end + 1, depth, head))
        # An `else if` is an else clause that holds an if statement. Its
        # entry is the clause, so the if statement inside adds no entry.
        if node.type == "else_clause":
            node = node.named_children[0]
        if node.type == "if_statement":
            inner = node.child_by_field_name("consequence")
            alternative = node.child_by_field_name("alternative")
            if alternative is not None:
                stack.append((alternative, depth))
        elif node.type in _LOOPS:
            inner = node.child_by_field_name("body")
        elif node.type == "statement_block":
            inner = node
        else:
            continue
        if depth < _OUTLINE_DEPTH:
            stack.extend((s, depth + 1) for s in reversed(_statements(inner)))
    return tuple(blocks)


def _script_statements(root: Node) -> list[Node]:
    """-> the statements of a script. A handler's statements are the ones
    inside its header's braces."""
    statements = []
    for node in root.named_children:
        handler = (
            node.type == "function_declaration"
            and _text(node.child_by_field_name("name")) == _HANDLER_NAME
        )
        if handler:
            statements.extend(node.child_by_field_name("body").named_children)
        else:
            statements.append(node)
    return statements


def parse_script(source: bytes) -> ParsedScript:
    handler = _HANDLER.search(source)
    event = None
    if handler:
        event = f"{handler.group(2).decode()}({handler.group(3).decode()})"
    root = _PARSER.parse(as_javascript(source)).root_node
    lines = source.decode().splitlines()

    script = _Body()
    found: list[tuple[Node, str, str, str | None, Node, _Body]] = []
    # The walk is a loop with its own stack, because a long chain of "+" or
    # "else if" nests deeper than Python's recursion limit. Each entry holds
    # the function the node is in, the local names there, and how the node
    # is used. Nodes are pushed last first, so calls come out in source order.
    stack: list[tuple[Node, _Body, frozenset[str], str]] = [
        (root, script, frozenset(), _READ)
    ]
    while stack:
        node, body, local, use = stack.pop()
        kind = node.type
        if kind == "function_declaration":
            name = _text(node.child_by_field_name("name"))
            # A handler is not a function in Flash, so a `var` in it is a
            # variable of the clip and the handler adds no local names.
            if name != _HANDLER_NAME:
                body = _Body()
                local = local | _locals(node)
                found.append((node, name, "declaration", None, node, body))
            stack.append((node.child_by_field_name("body"), body, local, _READ))
        elif kind == "function_expression":
            inner_local = local | _locals(node)
            stack.append((node.child_by_field_name("body"), body, inner_local, _READ))
        elif kind == "assignment_expression":
            target = node.child_by_field_name("left")
            value = node.child_by_field_name("right")
            if value.type == "function_expression":
                inner = _Body()
                name = _assigned_name(target)
                found.append((node, name, "assignment", _text(target), value, inner))
                inner_local = local | _locals(value)
                inner_body = value.child_by_field_name("body")
                stack.append((inner_body, inner, inner_local, _READ))
            else:
                stack.append((value, body, local, _READ))
            stack.append((target, body, local, _WRITE))
        elif kind == "augmented_assignment_expression":
            stack.append((node.child_by_field_name("right"), body, local, _READ))
            stack.append((node.child_by_field_name("left"), body, local, _BOTH))
        elif kind == "update_expression":
            stack.append((node.child_by_field_name("argument"), body, local, _BOTH))
        elif kind == "variable_declarator":
            value = node.child_by_field_name("value")
            if value is not None:
                stack.append((value, body, local, _READ))
                stack.append((node.child_by_field_name("name"), body, local, _WRITE))
        elif kind == "for_in_statement":
            stack.append((node.child_by_field_name("body"), body, local, _READ))
            stack.append((node.child_by_field_name("right"), body, local, _READ))
            stack.append((node.child_by_field_name("left"), body, local, _WRITE))
        elif kind in ("call_expression", "new_expression"):
            if kind == "call_expression":
                callee = node.child_by_field_name("function")
                call = _call(node)
                if call is not None:
                    body.calls.append(call)
            else:
                callee = node.child_by_field_name("constructor")
            arguments = node.child_by_field_name("arguments")
            if arguments is not None:
                stack.append((arguments, body, local, _READ))
            # The called name is in `calls`, so it is not a read. The path
            # before the last "." of the callee is a read.
            if callee.type == "member_expression":
                receiver = callee.child_by_field_name("object")
                stack.append((receiver, body, local, _READ))
            elif callee.type != "identifier":
                stack.append((callee, body, local, _READ))
        elif kind in _PATH:
            inside = _record_path(node, body, local, use)
            stack.extend((child, body, local, _READ) for child in reversed(inside))
        else:
            stack.extend(
                (child, body, local, _READ) for child in reversed(node.children)
            )

    functions = []
    for span, name, declared_as, target, function, body in found:
        start, end = span.start_point[0] + 1, span.end_point[0] + 1
        outline = None
        if end - start + 1 > _OUTLINED_LINES:
            block = function.child_by_field_name("body")
            outline = _outline(_statements(block), lines)
        params = function.child_by_field_name("parameters").named_children
        functions.append(
            Function(
                name,
                declared_as,
                target,
                start,
                end,
                tuple(_text(p) for p in params),
                tuple(body.calls),
                body.written(),
                tuple(sorted(body.reads)),
                outline,
            )
        )
    outline = None
    if len(lines) > _OUTLINED_LINES:
        outline = _outline(_script_statements(root), lines)
    return ParsedScript(
        len(lines),
        event,
        root.has_error,
        tuple(script.calls),
        tuple(sorted(functions, key=lambda f: (f.start, f.end))),
        script.written(),
        tuple(sorted(script.reads)),
        outline,
    )


def check_library(rel: Path, text: str) -> None:
    """Raise unless a file outside the game folders is mx component code. A
    __Packages file must declare an mx class. A file beside the game folders
    must register classes, and every class it registers must be an mx class."""
    if rel.parts[0] == "__Packages":
        library = _LIBRARY_CLASS.match(text) is not None
    else:
        registered = _REGISTERED_CLASS.findall(text)
        library = bool(registered) and all(c.startswith("mx.") for c in registered)
    if not library:
        raise ValueError(
            f"{rel.as_posix()} is outside the game script folders and is not mx"
            " component code, so the index would leave game code out"
        )


def _calls(calls: tuple[Call, ...], defined: set[str]) -> list[dict]:
    return [asdict(call) for call in calls if call.name in defined]


def _names(piece: ParsedScript | Function) -> dict:
    """-> the `writes` and `reads` of a record, and its `outline` when the
    script or function is long enough to have one."""
    fields = {
        "writes": [{"name": w.name, "lines": list(w.lines)} for w in piece.writes],
        "reads": list(piece.reads),
    }
    if piece.outline is not None:
        fields["outline"] = [asdict(block) for block in piece.outline]
    return fields


def build(action_script: Path) -> list[dict]:
    """-> the index records, sorted by file and then by start line."""
    scripts: dict[str, ParsedScript] = {}
    for path in action_script.rglob("*.as"):
        rel = path.relative_to(action_script)
        if not is_game_script(rel):
            check_library(rel, path.read_text())
            continue
        script = parse_script(path.read_bytes())
        if script.has_error:
            raise ValueError(f"{rel.as_posix()} does not parse")
        scripts[rel.as_posix()] = script

    defined = {f.name for script in scripts.values() for f in script.functions}
    records = []
    for file in sorted(scripts):
        script = scripts[file]
        owner = asdict(parse_script_path(Path(file)))
        del owner["path"]
        record = {
            "kind": "script",
            "file": file,
            "lines": script.lines,
            "owner": owner,
            "calls": _calls(script.calls, defined),
            **_names(script),
        }
        if script.event is not None:
            record["event"] = script.event
        records.append(record)
        for function in script.functions:
            record = {
                "kind": "function",
                "name": function.name,
                "declared_as": function.declared_as,
                "file": file,
                "start": function.start,
                "end": function.end,
                "params": list(function.params),
                "calls": _calls(function.calls, defined),
                **_names(function),
            }
            if function.target is not None:
                record["target"] = function.target
            records.append(record)
    return records


def dumps(records: list[dict]) -> str:
    """One record per line with sorted keys, so a regenerated file diffs by
    record and a second run writes the same bytes."""
    return "".join(
        json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n"
        for record in records
    )


def main():
    records = build(ACTION_SCRIPT)
    OUT.write_text(dumps(records))
    scripts = sum(r["kind"] == "script" for r in records)
    print(
        f"{scripts} scripts, {len(records) - scripts} functions,"
        f" {sum(len(r['calls']) for r in records)} calls,"
        f" {sum(len(r['writes']) for r in records)} written names,"
        f" {sum('outline' in r for r in records)} outlines",
        file=sys.stderr,
    )
    print("wrote", OUT, file=sys.stderr)


if __name__ == "__main__":
    main()
