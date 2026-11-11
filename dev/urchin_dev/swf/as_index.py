# as_index.py
# Writes dev/converted_json/as_index.jsonl: one record for each game script in
# ffdec's script export under dev/source_files/action_script/, and one for
# each function a game script defines. It reads only that export, so it runs
# on a fresh checkout with no SWF. `uv run as_lookup` reads the output.
#
# The index is for navigation. It says where a piece of the original is and
# what it calls. It is not an authority on behavior, so read the original
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


@dataclass(frozen=True)
class Call:
    """One call site. `receiver` is the source text before the last "." of
    the callee, or None for a bare call."""

    name: str
    line: int
    receiver: str | None


@dataclass(frozen=True)
class Function:
    """One function a script defines. declared_as is "declaration", or
    "assignment" with `target` holding the full text it is assigned to.
    `calls` leaves out the calls of a function nested in this one."""

    name: str
    declared_as: str
    target: str | None
    start: int
    end: int
    params: tuple[str, ...]
    calls: tuple[Call, ...]


@dataclass(frozen=True)
class ParsedScript:
    """One script's parse. `event` is a handler's header, as in
    "onClipEvent(load)", and None on a frame script. `calls` holds only the
    calls outside every function the script defines."""

    lines: int
    event: str | None
    has_error: bool
    calls: tuple[Call, ...]
    functions: tuple[Function, ...]


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


def parse_script(source: bytes) -> ParsedScript:
    handler = _HANDLER.search(source)
    event = None
    if handler:
        event = f"{handler.group(2).decode()}({handler.group(3).decode()})"
    root = _PARSER.parse(as_javascript(source)).root_node

    script_calls: list[Call] = []
    found: list[tuple[Node, str, str, str | None, Node, list[Call]]] = []
    # The walk is a loop with its own stack, because a long chain of "+" or
    # "else if" nests deeper than Python's recursion limit.
    stack: list[tuple[Node, list[Call]]] = [(root, script_calls)]
    while stack:
        node, calls = stack.pop()
        if node.type == "function_declaration":
            name = _text(node.child_by_field_name("name"))
            if name != _HANDLER_NAME:
                calls = []
                found.append((node, name, "declaration", None, node, calls))
        elif node.type == "assignment_expression":
            target = node.child_by_field_name("left")
            value = node.child_by_field_name("right")
            if value.type == "function_expression":
                inner: list[Call] = []
                name = _assigned_name(target)
                found.append((node, name, "assignment", _text(target), value, inner))
                stack.append((value, inner))
                stack.append((target, calls))
                continue
        elif node.type == "call_expression":
            call = _call(node)
            if call is not None:
                calls.append(call)
        stack.extend((child, calls) for child in reversed(node.children))

    functions = tuple(
        Function(
            name,
            declared_as,
            target,
            span.start_point[0] + 1,
            span.end_point[0] + 1,
            tuple(
                _text(p)
                for p in function.child_by_field_name("parameters").named_children
            ),
            tuple(calls),
        )
        for span, name, declared_as, target, function, calls in found
    )
    return ParsedScript(
        len(source.decode().splitlines()),
        event,
        root.has_error,
        tuple(script_calls),
        tuple(sorted(functions, key=lambda f: (f.start, f.end))),
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
        f" {sum(len(r['calls']) for r in records)} calls",
        file=sys.stderr,
    )
    print("wrote", OUT, file=sys.stderr)


if __name__ == "__main__":
    main()
