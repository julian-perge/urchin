# lookup answers one question about the game's code from the two indexes: where
# is this, who calls it, and what does it call. A query is a function name, a
# repo path of a .gd file, or a repo path with a line. The GDScript answers
# come from gd_index.jsonl and the tracked .gd files. A query for the original
# ActionScript, and any name that the ActionScript index holds, is answered by
# as_lookup. This module does not import the parser, so a lookup starts fast.
from __future__ import annotations

import argparse
import difflib
import json
import re
from collections.abc import Sequence
from pathlib import Path

from urchin_dev import ACTION_SCRIPT, REPO_ROOT, as_lookup
from urchin_dev.as_lookup import (
    _LINES_SHOWN,
    _NEAREST,
    _SOURCE_LINES,
    Citation,
    Fact,
    _blocks,
    _holders,
    _shown,
    cited_ranges,
    fact_row,
    resolve,
)

GD_INDEX = as_lookup.CONVERTED_JSON / "gd_index.jsonl"

# At most this many callers, or string lines, print. The rest are counted.
_ROWS = 40

_NO_CASE = "no exact match for {query}, so this is a match without case"
_HANDLER = re.compile(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*")
_BOUND = re.compile(r"\.(?:bind|bindv|unbind)\(.*\)\s*$", re.DOTALL)


def load_gd(path: Path = GD_INDEX) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines()]


def _span(record: dict) -> tuple[int, int]:
    if record["kind"] == "gd_script":
        return 1, record["lines"]
    return record["start"], record["end"]


def _location(record: dict) -> str:
    start, end = _span(record)
    return f"{record['file']}:{start}-{end}"


def _signature(record: dict) -> str:
    return f"{record['name']}({', '.join(record['params'])})"


def _source(root: Path, file: str, start: int, end: int) -> list[str]:
    lines = (root / file).read_text().splitlines()
    return [f"{n:>5}  {lines[n - 1]}" for n in range(start, end + 1)]


def _handler(target: str) -> tuple[str, str] | None:
    """-> the name and the written path of the function that a connect target
    names, or None for a lambda or any other expression. `_on_x.bind(1)` is
    `_on_x`, and `Audio.voice` is `voice`."""
    path = _BOUND.sub("", target.strip())
    if not _HANDLER.fullmatch(path):
        return None
    return path.rpartition(".")[2], path


def _kind(file: str) -> str:
    return "test" if file.startswith("test/") else "call"


def _sites(name: str, functions: list[dict]) -> list[tuple]:
    """-> every call site of the name as (kind, file, line, holder, receiver,
    written, same_file). `same_file` is true when the call is a bare call or a
    call on self, so it can only reach a definition in the caller's file."""
    sites = []
    for caller in functions:
        for found in caller["calls"]:
            if found["name"] != name:
                continue
            receiver = found["receiver"]
            written = ".".join(filter(None, [receiver, name]))
            same_file = receiver in (None, "self")
            sites.append(
                (
                    _kind(caller["file"]),
                    caller["file"],
                    found["line"],
                    caller["name"],
                    written,
                    same_file,
                )
            )
        for connect in caller["connects"]:
            handler = _handler(connect["target"])
            if handler is None or handler[0] != name:
                continue
            signal = ".".join(filter(None, [connect["receiver"], connect["signal"]]))
            sites.append(
                (
                    "test" if caller["file"].startswith("test/") else "connect",
                    caller["file"],
                    connect["line"],
                    caller["name"],
                    f"{signal} -> {handler[1]}",
                    False,
                )
            )
    return sites


def _callers(record: dict, functions: list[dict]) -> list[str]:
    """The call sites of a function by name. When more functions share the
    name, a bare call or a call on self belongs to the definition in the
    caller's own file, so it is left out of the other definitions' lists."""
    others = [
        r["file"]
        for r in functions
        if r["name"] == record["name"] and r["file"] != record["file"]
    ]
    sites = []
    for kind, file, line, holder, written, same_file in _sites(
        record["name"], functions
    ):
        if same_file and file in others and file != record["file"]:
            continue
        sites.append((kind == "test", file, line, holder, written, kind))
    sites.sort()
    rows = [
        f"  {file}:{line}  {holder}  {written}  {kind}"
        for _, file, line, holder, written, kind in sites[:_ROWS]
    ]
    if len(sites) > _ROWS:
        rows.append(f"  ... {len(sites) - _ROWS} more callers")
    return rows


def _calls(record: dict, functions: list[dict]) -> list[str]:
    lines: dict[tuple[str, str], list[int]] = {}
    for found in record["calls"]:
        written = ".".join(filter(None, [found["receiver"], found["name"]]))
        lines.setdefault((written, found["name"]), []).append(found["line"])
    rows = []
    for (written, name), at in lines.items():
        defined = ", ".join(_location(r) for r in functions if r["name"] == name)
        rows.append(f"  {written}  {_shown(at)}  {defined}".rstrip())
    return rows


def _range_text(first: int, last: int) -> str:
    return str(first) if first == last else f"{first}-{last}"


def _signals(record: dict) -> list[str]:
    rows = [
        (c["line"], f"  connects  {_connected(c)}  {c['line']}")
        for c in record["connects"]
    ]
    rows += [
        (e["line"], f"  emits  {e['signal']}  {e['line']}") for e in record["emits"]
    ]
    return [row for _, row in sorted(rows)]


def _connected(connect: dict) -> str:
    signal = ".".join(filter(None, [connect["receiver"], connect["signal"]]))
    return f"{signal} -> {connect['target']}"


def _owned(record: dict, functions: list[dict], citation: Citation) -> bool:
    """Whether a citation belongs to the function. A comment inside the range
    does. A comment above a func belongs to the first func of that name that
    starts below it, so two functions of one name in a file keep their own."""
    if citation.gd != record["file"] or citation.function != record["name"]:
        return False
    if record["start"] <= citation.line <= record["end"]:
        return True
    below = [
        r["start"]
        for r in functions
        if r["file"] == record["file"]
        and r["name"] == record["name"]
        and r["start"] > citation.line
    ]
    return citation.line < record["start"] and record["start"] == min(below)


def _port_ranges(
    record: dict,
    functions: list[dict],
    as_records: list[dict],
    citations: Sequence[Citation],
) -> list[tuple[Citation, str, tuple[int, int] | None, str]]:
    """The AS ranges that the comments of a function cite, each as the citation,
    the export file, the range (None for a citation with no line part) and the
    AS function that holds the range."""
    as_files = [r["file"] for r in as_records if r["kind"] == "script"]
    as_functions = [r for r in as_records if r["kind"] == "function"]
    found = []
    for cited in citations:
        if not _owned(record, functions, cited):
            continue
        files = resolve(cited.path, as_files)
        if len(files) != 1:
            continue
        for span in cited.lines or [None]:
            holder = "script"
            if span is not None:
                holding = [
                    r
                    for r in as_functions
                    if r["file"] == files[0] and r["start"] <= span[0] <= r["end"]
                ]
                innermost = min(
                    holding, key=lambda r: r["end"] - r["start"], default=None
                )
                holder = innermost["name"] if innermost else "script"
            found.append((cited, files[0], span, holder))
    return found


def _ports(
    ranges: list[tuple[Citation, str, tuple[int, int] | None, str]],
) -> list[str]:
    rows = []
    for cited, file, span, holder in ranges:
        where = f"{as_lookup.EXPORT}/{file}"
        if span is not None:
            where += f":{_range_text(*span)}"
        rows.append(f"  {where}  {holder}  {cited.gd}:{cited.line}  {cited.comment}")
    return rows


def _names_in_text(record: dict, fact: Fact) -> bool:
    """Whether the section names the .gd path of the record. For a function
    the same paragraph must also name the function in backticks."""
    if record["kind"] == "gd_script":
        return record["file"] in fact.text
    return any(
        record["file"] in paragraph and f"`{record['name']}`" in paragraph
        for paragraph in fact.text.split("\n\n")
    )


def _facts(
    record: dict,
    ranges: list[tuple[Citation, str, tuple[int, int] | None, str]],
    as_records: list[dict],
    facts: Sequence[Fact],
) -> list[str]:
    """The sections that name the record's path (and function), and the
    sections that cite an AS range that the record's comments cite."""
    as_files = [r["file"] for r in as_records if r["kind"] == "script"]
    rows = []
    for fact in facts:
        linked = _names_in_text(record, fact)
        if not linked:
            cited = [
                (files[0], spans)
                for path, spans in cited_ranges(fact)
                if len(files := resolve(path, as_files)) == 1
            ]
            linked = any(
                file == port_file
                and (
                    span is None
                    or any(
                        first <= span[1] and last >= span[0] for first, last in spans
                    )
                )
                for _, port_file, span, _ in ranges
                for file, spans in cited
            )
        if linked:
            rows.append(fact_row(fact))
    return rows


def _record_answer(
    record: dict,
    records: list[dict],
    source: bool | None,
    root: Path,
    as_records: list[dict],
    citations: Sequence[Citation],
    facts: Sequence[Fact],
    line: int | None = None,
) -> str:
    functions = [r for r in records if r["kind"] == "gd_function"]
    if record["kind"] == "gd_script":
        title = f"script {record['file']}"
        if "class_name" in record:
            title += f", class_name {record['class_name']}"
        if "extends" in record:
            title += f", extends {record['extends']}"
    else:
        title = f"function {record['owner']}.{_signature(record)}"
    out = [title, _location(record)]
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
        out += ["source", *_source(root, record["file"], start, end)]
    elif outline:
        out += ["outline", *_blocks(outline)]

    ranges = []
    if record["kind"] == "gd_script":
        inside = [
            f"  {_signature(r)}  {_location(r)}"
            for r in functions
            if r["file"] == record["file"]
        ]
        if inside:
            out += ["functions", *inside]
    else:
        out += ["callers", *(_callers(record, functions) or ["  none"])]
        out += ["calls", *(_calls(record, functions) or ["  none"])]
        out += ["signals", *(_signals(record) or ["  none"])]
        ranges = _port_ranges(record, functions, as_records, citations)
        out += ["ports", *(_ports(ranges) or ["  none"])]
    linked = _facts(record, ranges, as_records, facts)
    if linked:
        out += ["facts", *linked]
    return "\n".join(out)


def _gd_names(records: list[dict]) -> list[str]:
    return sorted({r["name"] for r in records if r["kind"] == "gd_function"})


def _gd_path(path: str, records: list[dict]) -> dict | str:
    """The gd_script record that a path names, or the text that says why the
    path names no single file."""
    scripts = {r["file"]: r for r in records if r["kind"] == "gd_script"}
    found = resolve(path, scripts)
    if len(found) == 1:
        return scripts[found[0]]
    if found:
        out = [f"{path} is the end of {len(found)} paths:"]
        out += [f"  {file}" for file in found[:_LINES_SHOWN]]
        if len(found) > _LINES_SHOWN:
            out.append(f"  ... {len(found) - _LINES_SHOWN} more paths")
        return "\n".join(out)
    near = difflib.get_close_matches(path, sorted(scripts), _NEAREST)
    out = [f"no .gd file is {path}"]
    if near:
        out += ["nearest paths", *(f"  {file}" for file in near)]
    return "\n".join(out)


def _gd_line_query(
    path: str,
    line: int,
    records: list[dict],
    source: bool | None,
    root: Path,
    as_records: list[dict],
    citations: Sequence[Citation],
    facts: Sequence[Fact],
) -> tuple[int, str]:
    script = _gd_path(path, records)
    if isinstance(script, str):
        return 1, script
    if not 1 <= line <= script["lines"]:
        return 1, f"{script['file']} has {script['lines']} lines"
    holders = [
        r
        for r in records
        if r["kind"] == "gd_function"
        and r["file"] == script["file"]
        and r["start"] <= line <= r["end"]
    ]
    innermost = min(holders, key=lambda r: r["end"] - r["start"], default=script)
    answer = _record_answer(
        innermost, records, source, root, as_records, citations, facts, line
    )
    return 0, answer


def _signal_names(records: list[dict]) -> set[str]:
    """-> every signal name that a script declares, connects or emits."""
    names = set()
    for record in records:
        if record["kind"] == "gd_script":
            names.update(s["name"] for s in record["signals"])
        else:
            names.update(c["signal"] for c in record["connects"])
            names.update(e["signal"] for e in record["emits"])
    return names


def _gd_name_matches(
    query: str, records: list[dict]
) -> tuple[list[dict], list[str], bool]:
    """-> the function records and the signal names called `query`, and whether
    they match only without case. An exact match wins over a match without
    case."""
    functions = [r for r in records if r["kind"] == "gd_function"]
    signals = _signal_names(records)
    exact = [r for r in functions if r["name"] == query]
    if exact or query in signals:
        return exact, [query] * (query in signals), False
    same = query.lower()
    return (
        [r for r in functions if r["name"].lower() == same],
        sorted(n for n in signals if n.lower() == same),
        True,
    )


def _signal_answer(name: str, records: list[dict]) -> str:
    declared, connects, emits = [], [], []
    for record in records:
        if record["kind"] == "gd_script":
            declared += [
                f"  {record['file']}:{s['line']}  {name}({', '.join(s['params'])})"
                for s in record["signals"]
                if s["name"] == name
            ]
            continue
        connects += [
            f"  {record['file']}:{c['line']}  {record['name']}  {_connected(c)}"
            for c in record["connects"]
            if c["signal"] == name
        ]
        emits += [
            f"  {record['file']}:{e['line']}  {record['name']}"
            for e in record["emits"]
            if e["signal"] == name
        ]
    out = [f"signal {name}"]
    for head, rows in (
        ("declared", declared),
        ("connects", connects),
        ("emits", emits),
    ):
        out += [head, *(rows or ["  none"])]
    return "\n".join(out)


def _near_names(query: str, gd: list[dict], as_text: str) -> str:
    """The no-match answer: the nearest names of both indexes, each with the
    languages that hold it. The ActionScript names come from as_lookup's own
    no-match text."""
    languages: dict[str, set[str]] = {}
    known = sorted(set(_gd_names(gd)) | _signal_names(gd))
    for name in difflib.get_close_matches(query, known, _NEAREST):
        languages.setdefault(name, set()).add("GDScript")
    lines = as_text.splitlines()
    if "nearest names" in lines:
        for row in lines[lines.index("nearest names") + 1 :]:
            languages.setdefault(row.strip(), set()).add("ActionScript")
    out = [f"no match for {query}"]
    near = difflib.get_close_matches(query, sorted(languages), _NEAREST)
    if near:
        out.append("nearest names")
        out += [f"  {name}  {', '.join(sorted(languages[name]))}" for name in near]
    return "\n".join(out)


def _string_answer(
    query: str, records: list[dict], prefix: str
) -> tuple[str, bool] | None:
    """-> the answer for a string value and whether it matches only without
    case, or None when no record holds the value. Each row is the line of a
    literal and the function that holds it, or `script` for a literal outside
    every function. `prefix` starts each path."""
    for no_case in (False, True):
        rows = sorted(
            (record["file"], line, record.get("name", "script"))
            for record in records
            for held in record.get("strings", [])
            if (
                held["value"].lower() == query.lower()
                if no_case
                else held["value"] == query
            )
            for line in held["lines"]
        )
        if rows:
            break
    else:
        return None
    shown = [f"  {prefix}{file}:{line}  {holder}" for file, line, holder in rows]
    out = [f"string {query}", *shown[:_ROWS]]
    if len(shown) > _ROWS:
        out.append(f"  ... {len(shown) - _ROWS} more lines")
    return "\n".join(out), no_case


def _name_query(
    query: str,
    as_records: list[dict],
    gd: list[dict],
    source: bool | None,
    export: Path,
    root: Path,
    citations: Sequence[Citation],
    facts: Sequence[Fact],
) -> tuple[int, str]:
    matches, signals, gd_no_case = _gd_name_matches(query, gd)
    as_code, as_text = as_lookup.lookup(
        query,
        as_records,
        source=source,
        export=export,
        citations=citations,
        facts=facts,
    )
    note = _NO_CASE.format(query=query)
    as_no_case = as_code == 0 and as_text.startswith(note)
    if as_no_case:
        as_text = as_text.removeprefix(note).lstrip("\n")

    # Each piece is one answer with its language and whether it matched only
    # without case. An exact match wins over a match without case, in the same
    # language and in the other.
    pieces: list[tuple[str, str, bool]] = []
    if matches:
        answers = [
            _record_answer(r, gd, source, root, as_records, citations, facts)
            for r in matches
        ]
        pieces.append(("GDScript", "\n\n".join(answers), gd_no_case))
    if signals:
        answers = [_signal_answer(name, gd) for name in signals]
        pieces.append(("GDScript", "\n\n".join(answers), gd_no_case))
    if found := _string_answer(query, gd, ""):
        pieces.append(("GDScript", *found))
    if as_code == 0:
        pieces.append(("ActionScript", as_text, as_no_case))
    if found := _string_answer(query, as_records, f"{as_lookup.EXPORT}/"):
        pieces.append(("ActionScript", *found))

    if not pieces:
        return 1, _near_names(query, gd, as_text)
    if any(not no_case for _, _, no_case in pieces):
        pieces = [piece for piece in pieces if not piece[2]]
    languages = list(dict.fromkeys(language for language, _, _ in pieces))
    blocks = []
    for language in languages:
        text = "\n\n".join(t for lang, t, _ in pieces if lang == language)
        blocks.append(text if len(languages) == 1 else f"{language}\n{text}")
    body = "\n\n".join(blocks)
    if all(no_case for _, _, no_case in pieces):
        body = f"{note}\n\n{body}"
    return 0, body


def lookup(
    query: str,
    as_records: list[dict],
    gd_records: list[dict],
    *,
    source: bool | None = None,
    export: Path = ACTION_SCRIPT,
    root: Path = REPO_ROOT,
    citations: Sequence[Citation] = (),
    facts: Sequence[Fact] = (),
) -> tuple[int, str]:
    """The exit code and the text for one query. `source` forces the source
    lines in or out, and None prints them for a range of 120 lines or less."""
    as_args = {
        "source": source,
        "export": export,
        "citations": citations,
        "facts": facts,
    }
    if re.fullmatch(r".+\.as(?::\d+)?", query):
        return as_lookup.lookup(query, as_records, **as_args)
    with_line = re.fullmatch(r"(.+\.gd):(\d+)", query)
    if with_line:
        path, line = with_line.groups()
        return _gd_line_query(
            path, int(line), gd_records, source, root, as_records, citations, facts
        )
    if query.endswith(".gd"):
        script = _gd_path(query, gd_records)
        if isinstance(script, str):
            return 1, script
        return 0, _record_answer(
            script, gd_records, source, root, as_records, citations, facts
        )
    return _name_query(
        query, as_records, gd_records, source, export, root, citations, facts
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Look up a function, a script or a line of the GDScript, or"
        " a function, a global, a script or a line of the original ActionScript."
    )
    parser.add_argument(
        "query",
        nargs="+",
        help="a function name, a global name, a repo path of a .gd file or a"
        " unique end of one, an export path, or a path with a line"
        " (scripts/battle/battle_runner.gd:119, frame_42/DoAction_8.as:82)",
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
    code, out = lookup(
        " ".join(args.query),
        as_lookup.load(),
        load_gd(),
        source=args.source,
        citations=as_lookup.tracked_citations(),
        facts=as_lookup.tracked_facts(),
    )
    print(out)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
