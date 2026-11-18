# gd_index.py
# Writes dev/converted_json/gd_index.jsonl: one record for each tracked .gd file
# under scripts/, test/ and dev/, and one for each function a file defines. It
# reads only those files, so it runs on a fresh checkout with no SWF and no
# Godot. The addons/ folder is vendored code and is not indexed.
#
# The index is for navigation, like as_index.jsonl. It says where a function
# is, which indexed functions it calls by name, which signals it connects and
# emits, and how a long function divides into blocks. A call is matched by
# name only, so the receiver is recorded and the reader judges whether it can
# hold that function.
#
# The parser is tree-sitter's GDScript grammar.
#
# Run: uv run extract_gd_index
from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

import tree_sitter_gdscript
from tree_sitter import Language, Node, Parser

from urchin_dev import CONVERTED_JSON, REPO_ROOT
from urchin_dev.swf.as_index import (
    _BLOCK_LINES,
    _HEAD_LENGTH,
    _OUTLINE_DEPTH,
    _OUTLINED_LINES,
    Block,
    Call,
    dumps,
)

OUT = CONVERTED_JSON / "gd_index.jsonl"

_PATHSPECS = ("scripts/*.gd", "test/*.gd", "dev/*.gd")
_PARSER = Parser(Language(tree_sitter_gdscript.language()))
# The grammar parses `func _init()` as a constructor_definition.
_FUNCTIONS = ("function_definition", "constructor_definition")
_IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


@dataclass(frozen=True)
class Connect:
    """One `X.connect(Y)` call. `signal` is the last name of X and `receiver`
    is the text before it, or None. `target` is the source text of Y."""

    signal: str
    line: int
    receiver: str | None
    target: str


@dataclass(frozen=True)
class Emit:
    signal: str
    line: int


def tracked_gd_files(root: Path = REPO_ROOT) -> list[str]:
    """-> the repo-relative paths of the .gd files that git tracks under
    scripts/, test/ and dev/, sorted."""
    out = subprocess.run(
        ["git", "ls-files", "-z", "--", *_PATHSPECS],
        cwd=root,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return sorted(out.split("\0")[:-1])


def _text(node: Node) -> str:
    return node.text.decode()


def _flat(text: str) -> str:
    """-> the text on one line, so a receiver that spans lines prints as one."""
    return " ".join(text.split())


def _end_row(node: Node) -> int:
    """-> the 0-based row of the last line the node covers. A node that ends
    at column 0 stops on the line before."""
    row, column = node.end_point
    return row - 1 if column == 0 and row > node.start_point[0] else row


def _function_name(node: Node) -> str:
    """-> the declared name. A constructor has no name node and is `_init`."""
    name = node.child_by_field_name("name")
    return _text(name) if name is not None else "_init"


def _param_names(parameters: Node | None) -> list[str]:
    names = []
    for parameter in parameters.named_children if parameters is not None else []:
        identifier = parameter if parameter.type == "identifier" else None
        if identifier is None:
            identifier = next(
                (c for c in parameter.named_children if c.type == "identifier"), None
            )
        if identifier is not None:
            names.append(_text(identifier))
    return names


def _string_value(node: Node) -> str:
    text = _text(node)
    quote = text[:3] if text[:3] in ('"""', "'''") else text[:1]
    return text[len(quote) : len(text) - len(quote)]


def _arguments(call: Node) -> list[Node]:
    arguments = call.child_by_field_name("arguments")
    return arguments.named_children if arguments is not None else []


def _signal_and_receiver(text: str) -> tuple[str, str | None]:
    """-> the signal name and the receiver of the path in front of `.connect`
    or `.emit`. A path whose last segment is not a name stays whole."""
    head, dot, last = text.rpartition(".")
    if dot and _IDENTIFIER.fullmatch(last):
        return last, head
    return text, None


@dataclass
class _Body:
    calls: list[Call]
    connects: list[Connect]
    emits: list[Emit]


def _record_call(node: Node, source: bytes, body: _Body) -> None:
    """Add the call of one `call` or `attribute_call` node to the body: the
    call itself, and a connect or an emit when its name is one."""
    if node.type == "call":
        callee = node.named_children[0]
        if callee.type != "identifier":
            return
        receiver = None
    else:
        callee = node.named_children[0]
        parent = node.parent
        receiver = _flat(source[parent.start_byte : node.start_byte].decode())
        receiver = receiver.rstrip(". ").rstrip()
    name = _text(callee)
    line = callee.start_point[0] + 1
    arguments = _arguments(node)
    body.calls.append(Call(name, line, receiver or None))

    first = arguments[0] if arguments else None
    if name == "connect" and first is not None:
        if first.type == "string" and len(arguments) > 1:
            body.connects.append(
                Connect(_string_value(first), line, receiver, _text(arguments[1]))
            )
        elif receiver:
            signal, head = _signal_and_receiver(receiver)
            body.connects.append(Connect(signal, line, head, _text(first)))
    elif name == "emit" and receiver:
        body.emits.append(Emit(_signal_and_receiver(receiver)[0], line))
    elif name == "emit_signal" and first is not None and first.type == "string":
        body.emits.append(Emit(_string_value(first), line))


def _statements(node: Node | None) -> list[Node]:
    return [n for n in node.named_children if n.type != "comment"] if node else []


def _children_of(node: Node) -> list[Node]:
    """-> the nested blocks of a statement that the outline lists inside it."""
    if node.type == "if_statement":
        return _statements(node.child_by_field_name("body"))
    if node.type in ("elif_clause", "else_clause", "for_statement", "while_statement"):
        return _statements(node.child_by_field_name("body"))
    if node.type == "match_statement":
        return _statements(node.child_by_field_name("body"))
    if node.type == "pattern_section":
        return _statements(node.child_by_field_name("body"))
    return []


def _outline(statements: list[Node], lines: list[str]) -> tuple[Block, ...]:
    blocks = []
    stack = [(statement, 1) for statement in reversed(statements)]
    while stack:
        node, depth = stack.pop()
        start, end = node.start_point[0], _end_row(node)
        if end - start + 1 < _BLOCK_LINES:
            continue
        blocks.append(
            Block(start + 1, end + 1, depth, lines[start].strip()[:_HEAD_LENGTH])
        )
        # An elif or else clause is an entry at the depth of its `if`.
        if node.type == "if_statement":
            alternatives = [
                c
                for c in node.children_by_field_name("alternative")
                if c.type in ("elif_clause", "else_clause")
            ]
            stack.extend((c, depth) for c in reversed(alternatives))
        if depth < _OUTLINE_DEPTH:
            stack.extend((c, depth + 1) for c in reversed(_children_of(node)))
    return tuple(blocks)


@dataclass(frozen=True)
class Function:
    name: str
    owner: str
    start: int
    end: int
    params: tuple[str, ...]
    calls: tuple[Call, ...]
    connects: tuple[Connect, ...]
    emits: tuple[Emit, ...]
    outline: tuple[Block, ...] | None


@dataclass(frozen=True)
class ParsedFile:
    lines: int
    class_name: str | None
    extends: str | None
    signals: tuple[tuple[str, int, tuple[str, ...]], ...]
    functions: tuple[Function, ...]


def parse_file(source: bytes, stem: str) -> ParsedFile | None:
    """-> the file's parse, or None when the file has a syntax error."""
    root = _PARSER.parse(source).root_node
    if root.has_error:
        return None
    lines = source.decode().splitlines()

    class_name = extends = None
    signals = []
    for node in root.named_children:
        if node.type == "class_name_statement":
            class_name = _text(node.child_by_field_name("name"))
        elif node.type == "extends_statement" and extends is None:
            extends = _text(node).removeprefix("extends").strip()
    file_owner = class_name or stem

    functions = []
    # The walk is a loop with its own stack, because a long chain of "+" nests
    # deeper than Python's recursion limit. Each entry holds the owner and the
    # body that the node belongs to. Nodes are pushed last first, so calls come
    # out in source order.
    stack: list[tuple[Node, str, _Body | None]] = [(root, file_owner, None)]
    found: list[tuple[Node, str, _Body]] = []
    while stack:
        node, owner, body = stack.pop()
        if node.type == "signal_statement":
            name = _text(node.child_by_field_name("name"))
            params = _param_names(node.child_by_field_name("parameters"))
            signals.append((name, node.start_point[0] + 1, tuple(params)))
            continue
        if node.type == "class_definition":
            owner = _text(node.child_by_field_name("name"))
        elif node.type in _FUNCTIONS:
            body = _Body([], [], [])
            found.append((node, owner, body))
        elif body is not None and node.type in ("call", "attribute_call"):
            _record_call(node, source, body)
        stack.extend((child, owner, body) for child in reversed(node.named_children))

    for node, owner, body in found:
        start, end = node.start_point[0], _end_row(node)
        outline = None
        if end - start + 1 > _OUTLINED_LINES:
            outline = _outline(_statements(node.child_by_field_name("body")), lines)
        functions.append(
            Function(
                _function_name(node),
                owner,
                start + 1,
                end + 1,
                tuple(_param_names(node.child_by_field_name("parameters"))),
                tuple(body.calls),
                tuple(body.connects),
                tuple(body.emits),
                outline,
            )
        )
    functions.sort(key=lambda f: (f.start, f.end))
    return ParsedFile(
        len(lines),
        class_name,
        extends,
        tuple(sorted(signals, key=lambda s: s[1])),
        tuple(functions),
    )


def index_sources(sources: dict[str, bytes]) -> list[dict]:
    """-> the index records for the files, sorted by file and then by start
    line. `sources` maps a repo-relative path to the file's bytes."""
    parsed: dict[str, ParsedFile] = {}
    for file in sorted(sources):
        result = parse_file(sources[file], Path(file).stem)
        if result is None:
            raise ValueError(f"{file} does not parse")
        parsed[file] = result

    defined = {f.name for p in parsed.values() for f in p.functions}
    records = []
    for file, script in parsed.items():
        record = {
            "kind": "gd_script",
            "file": file,
            "lines": script.lines,
            "signals": [
                {"name": name, "line": line, "params": list(params)}
                for name, line, params in script.signals
            ],
        }
        if script.class_name is not None:
            record["class_name"] = script.class_name
        if script.extends is not None:
            record["extends"] = script.extends
        records.append(record)
        for function in script.functions:
            record = {
                "kind": "gd_function",
                "name": function.name,
                "owner": function.owner,
                "file": file,
                "start": function.start,
                "end": function.end,
                "params": list(function.params),
                "calls": [asdict(c) for c in function.calls if c.name in defined],
                "connects": [asdict(c) for c in function.connects],
                "emits": [asdict(e) for e in function.emits],
            }
            if function.outline is not None:
                record["outline"] = [asdict(b) for b in function.outline]
            records.append(record)
    return records


def build(root: Path = REPO_ROOT) -> list[dict]:
    """-> the index records of the tracked .gd files under `root`."""
    return index_sources({f: (root / f).read_bytes() for f in tracked_gd_files(root)})


def main():
    records = build()
    OUT.write_text(dumps(records))
    scripts = sum(r["kind"] == "gd_script" for r in records)
    print(
        f"{scripts} scripts, {len(records) - scripts} functions,"
        f" {sum(len(r.get('calls', [])) for r in records)} calls,"
        f" {sum(len(r.get('connects', [])) for r in records)} connects,"
        f" {sum(len(r.get('emits', [])) for r in records)} emits,"
        f" {sum('outline' in r for r in records)} outlines",
        file=sys.stderr,
    )
    print("wrote", OUT, f"({OUT.stat().st_size} bytes)", file=sys.stderr)


if __name__ == "__main__":
    main()
