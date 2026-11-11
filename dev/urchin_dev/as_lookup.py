# as_lookup answers one question about the original ActionScript from the
# index that extract_as_index writes. A query is a function name, a global
# name, an export path, or an export path with a line. The answer gives the
# location, the source lines or the outline, the callers, the calls and the
# globals. This module does not import the parser, so a lookup starts fast.
from __future__ import annotations

import argparse
import difflib
import json
import re
from collections.abc import Callable, Collection, Sequence
from pathlib import Path

from urchin_dev import ACTION_SCRIPT, CONVERTED_JSON, REPO_ROOT

INDEX = CONVERTED_JSON / "as_index.jsonl"
EXPORT = ACTION_SCRIPT.relative_to(REPO_ROOT).as_posix()

_SOURCE_LINES = 120
_LINES_SHOWN = 12
_NEAREST = 8
_ROW_WIDTH = 100


def load(path: Path = INDEX) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines()]


def resolve(path: str, files: Collection[str]) -> list[str]:
    """The export files that a path names: the file with that path, or every
    file that ends with the path as whole components. The result has one file,
    no file or more than one file."""
    path = path.removeprefix(f"{EXPORT}/")
    if path in files:
        return [path]
    return [file for file in files if file.endswith(f"/{path}")]


def _span(record: dict) -> tuple[int, int]:
    if record["kind"] == "script":
        return 1, record["lines"]
    return record["start"], record["end"]


def _location(record: dict) -> str:
    start, end = _span(record)
    return f"{EXPORT}/{record['file']}:{start}-{end}"


def _holder(record: dict) -> str:
    return record.get("name", "script")


def _signature(record: dict) -> str:
    return f"{record['name']}({', '.join(record['params'])})"


def _title(record: dict) -> str:
    if record["kind"] == "script":
        return " ".join(["script", *filter(None, [record.get("event")])])
    title = f"function {_signature(record)}"
    if record["declared_as"] == "assignment":
        title += f", assigned to {record['target']}"
    return title


def _shown(lines: list[int]) -> str:
    text = ", ".join(str(line) for line in lines[:_LINES_SHOWN])
    if len(lines) > _LINES_SHOWN:
        text += f" ... ({len(lines)} lines)"
    return text


def _wrapped(names: list[str]) -> list[str]:
    rows = [f"  {names[0]}"]
    for name in names[1:]:
        if len(rows[-1]) + len(f", {name},") > _ROW_WIDTH:
            rows[-1] += ","
            rows.append(f"  {name}")
        else:
            rows[-1] += f", {name}"
    return rows


def _blocks(entries: list[dict]) -> list[str]:
    return [
        f"{'  ' * entry['depth']}{entry['start']}-{entry['end']}  {entry['head']}"
        for entry in entries
    ]


def _holders(outline: list[dict], line: int) -> list[dict]:
    """The outline blocks that hold a line, from the outermost to the
    innermost. A later block of the same depth replaces an earlier one, so a
    line in an else branch names the else block and not its if block."""
    chain: list[dict] = []
    for entry in outline:
        if entry["start"] <= line <= entry["end"]:
            del chain[entry["depth"] - 1 :]
            chain.append(entry)
    return chain


def _source(export: Path, file: str, start: int, end: int) -> list[str]:
    lines = (export / file).read_text().splitlines()
    return [f"{n:>5}  {lines[n - 1]}" for n in range(start, end + 1)]


def _callers(record: dict, records: list[dict]) -> list[str]:
    sites = sorted(
        (caller["file"], call["line"], _holder(caller), call["receiver"])
        for caller in records
        for call in caller["calls"]
        if call["name"] == record["name"]
    )
    return [
        f"  {EXPORT}/{file}:{line}  {holder}  "
        + ".".join(filter(None, [receiver, record["name"]]))
        for file, line, holder, receiver in sites
    ]


def _calls(record: dict, records: list[dict]) -> list[str]:
    lines: dict[tuple[str, str], list[int]] = {}
    for call in record["calls"]:
        written = ".".join(filter(None, [call["receiver"], call["name"]]))
        lines.setdefault((written, call["name"]), []).append(call["line"])
    rows = []
    for (written, name), at in lines.items():
        defined = ", ".join(
            _location(r)
            for r in records
            if r["kind"] == "function" and r["name"] == name
        )
        rows.append(f"  {written}  {_shown(at)}  {defined}".rstrip())
    return rows


def _record_answer(
    record: dict,
    records: list[dict],
    source: bool | None,
    export: Path,
    line: int | None = None,
) -> str:
    out = [_title(record), _location(record)]
    start, end = _span(record)
    outline = record.get("outline", [])
    if line is not None:
        chain = _holders(outline, line)
        if chain:
            out += [f"line {line} is in", *_blocks(chain)]
            start, end = chain[-1]["start"], chain[-1]["end"]
            outline = []
        else:
            out.append(f"line {line} is in no outline block")
    if source is None:
        source = end - start + 1 <= _SOURCE_LINES
    if source:
        out += ["source", *_source(export, record["file"], start, end)]
    elif outline:
        out += ["outline", *_blocks(outline)]

    if record["kind"] == "script":
        inside = [
            f"  {_signature(r)}  {_location(r)}"
            for r in records
            if r["kind"] == "function" and r["file"] == record["file"]
        ]
        if inside:
            out += ["functions", *inside]
    else:
        out += ["callers", *(_callers(record, records) or ["  none"])]
    out += ["calls", *(_calls(record, records) or ["  none"])]
    writes = [f"  {w['name']}  {_shown(w['lines'])}" for w in record["writes"]]
    out += ["writes", *(writes or ["  none"])]
    out += ["reads", *(_wrapped(record["reads"]) if record["reads"] else ["  none"])]
    return "\n".join(out)


def _global_answer(name: str, records: list[dict]) -> str:
    written = []
    for record in records:
        for write in record["writes"]:
            if write["name"] != name:
                continue
            path = f"{EXPORT}/{record['file']}"
            written += [
                f"  {path}:{line}  {_holder(record)}"
                for line in write["lines"][:_LINES_SHOWN]
            ]
            more = len(write["lines"]) - _LINES_SHOWN
            if more > 0:
                written.append(f"  ... {more} more lines in {path}")
    read = [f"  {_location(r)}  {_holder(r)}" for r in records if name in r["reads"]]
    out = [f"global {name}", "written", *(written or ["  none"])]
    out += ["read", *(read or ["  none"])]
    return "\n".join(out)


def _name_query(
    query: str, records: list[dict], source: bool | None, export: Path
) -> tuple[int, str]:
    functions = [r for r in records if r["kind"] == "function"]
    names = sorted(
        {w["name"] for r in records for w in r["writes"]}
        | {name for r in records for name in r["reads"]}
    )

    def matches(same: Callable[[str], bool]) -> tuple[list[dict], list[str]]:
        return (
            [r for r in functions if same(r["name"])],
            [n for n in names if same(n) or same(n.rpartition(".")[2])],
        )

    note = []
    found = matches(lambda name: name == query)
    if not any(found):
        found = matches(lambda name: name.lower() == query.lower())
        note = [f"no exact match for {query}, so this is a match without case"]
    if not any(found):
        known = (
            {r["name"] for r in functions}
            | set(names)
            | {n.rpartition(".")[2] for n in names}
        )
        near = difflib.get_close_matches(query, sorted(known), _NEAREST)
        out = [f"no match for {query}"]
        if near:
            out += ["nearest names", *(f"  {name}" for name in near)]
        return 1, "\n".join(out)
    answers = [_record_answer(r, records, source, export) for r in found[0]]
    answers += [_global_answer(name, records) for name in found[1]]
    return 0, "\n\n".join(note + answers)


def _script(path: str, records: list[dict]) -> dict | str:
    """The script record that a path names, or the text that says why the path
    names no single file."""
    scripts = {r["file"]: r for r in records if r["kind"] == "script"}
    found = resolve(path, scripts)
    if len(found) == 1:
        return scripts[found[0]]
    if found:
        out = [f"{path} is the end of {len(found)} paths:"]
        out += [f"  {EXPORT}/{file}" for file in found[:_LINES_SHOWN]]
        if len(found) > _LINES_SHOWN:
            out.append(f"  ... {len(found) - _LINES_SHOWN} more paths")
        return "\n".join(out)
    parts = path.removeprefix(f"{EXPORT}/").count("/") + 1
    ends: dict[str, list[str]] = {}
    for file in scripts:
        ends.setdefault("/".join(file.split("/")[-parts:]), []).append(file)
    near = difflib.get_close_matches(path, sorted(ends), _NEAREST)
    out = [f"no export file is {path}"]
    if near:
        out.append("nearest paths")
        out += [f"  {EXPORT}/{file}" for end in near for file in ends[end]][:_NEAREST]
    return "\n".join(out)


def _line_query(
    path: str, line: int, records: list[dict], source: bool | None, export: Path
) -> tuple[int, str]:
    script = _script(path, records)
    if isinstance(script, str):
        return 1, script
    if not 1 <= line <= script["lines"]:
        return 1, f"{EXPORT}/{script['file']} has {script['lines']} lines"
    holders = [
        r
        for r in records
        if r["kind"] == "function"
        and r["file"] == script["file"]
        and r["start"] <= line <= r["end"]
    ]
    innermost = min(holders, key=lambda r: r["end"] - r["start"], default=script)
    return 0, _record_answer(innermost, records, source, export, line)


def lookup(
    query: str,
    records: list[dict],
    *,
    source: bool | None = None,
    export: Path = ACTION_SCRIPT,
) -> tuple[int, str]:
    """The exit code and the text for one query. `source` forces the source
    lines in or out, and None prints them for a range of 120 lines or less."""
    with_line = re.fullmatch(r"(.+\.as):(\d+)", query)
    if with_line:
        path, line = with_line.groups()
        return _line_query(path, int(line), records, source, export)
    if query.endswith(".as"):
        script = _script(query, records)
        if isinstance(script, str):
            return 1, script
        return 0, _record_answer(script, records, source, export)
    return _name_query(query, records, source, export)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Look up a function, a global, a script or a line of the"
        " original ActionScript."
    )
    parser.add_argument(
        "query",
        nargs="+",
        help="a function name, a global name, an export path or a unique end of"
        " one, or a path with a line (frame_42/DoAction_8.as:82)",
    )
    lines = parser.add_mutually_exclusive_group()
    lines.add_argument(
        "--source",
        action="store_true",
        default=None,
        help="print the source lines of a range of any length",
    )
    lines.add_argument(
        "--no-source",
        dest="source",
        action="store_false",
        default=None,
        help="print no source lines",
    )
    args = parser.parse_args(argv)
    code, out = lookup(" ".join(args.query), load(), source=args.source)
    print(out)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
