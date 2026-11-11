# Checks the committed as_index.jsonl against the tracked AS export. Neither
# the SWF nor the XML dump is read, since both are absent from a fresh
# checkout.
from __future__ import annotations

import json
import re
from pathlib import Path

import pytest
from urchin_dev import ACTION_SCRIPT
from urchin_dev.swf.as_index import OUT, build, dumps, is_game_script, parse_script

EXECUTE_MOVE_FILE = "frame_42/DoAction_8.as"
CONDUCTOR = (
    "frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(enterFrame).as"
)
_DECLARATION = re.compile(r"^\s*function\s+[A-Za-z_$][A-Za-z0-9_$]*\s*\(", re.MULTILINE)


@pytest.fixture(scope="module")
def built() -> list[dict]:
    return build(ACTION_SCRIPT)


@pytest.fixture(scope="module")
def records() -> list[dict]:
    return [json.loads(line) for line in OUT.read_text().splitlines()]


def game_files() -> list[Path]:
    """The game scripts, found without the builder's own file walk."""
    folders = ("frame_", "DefineSprite_", "DefineButton2_")
    return [
        path
        for path in ACTION_SCRIPT.rglob("*.as")
        if path.relative_to(ACTION_SCRIPT).parts[0].startswith(folders)
    ]


def export_lines(file: str) -> list[str]:
    return (ACTION_SCRIPT / file).read_text().splitlines()


def functions_named(records: list[dict], name: str) -> list[dict]:
    return [r for r in records if r["kind"] == "function" and r["name"] == name]


def script_record(records: list[dict], file: str) -> dict:
    (record,) = [r for r in records if r["kind"] == "script" and r["file"] == file]
    return record


def invariant_failures(records: list[dict], lines_of) -> list[str]:
    """Every way a record disagrees with the source lines it points at.
    `lines_of` maps a record's file to that file's lines."""
    failures = []
    for record in records:
        lines = lines_of(record["file"])
        where = record["file"]
        if record["kind"] == "script":
            if record["lines"] != len(lines):
                failures.append(f"{where}: lines {record['lines']} != {len(lines)}")
        else:
            start, end = record["start"], record["end"]
            where = f"{where}:{start}-{end} {record['name']}"
            if not 1 <= start <= end <= len(lines):
                failures.append(f"{where}: range outside the file")
                continue
            if record["name"] not in lines[start - 1]:
                failures.append(f"{where}: first line does not hold the name")
        for call in record["calls"]:
            line = call["line"]
            if not 1 <= line <= len(lines) or call["name"] + "(" not in lines[line - 1]:
                failures.append(f"{where}: no call of {call['name']} on line {line}")
            if record["kind"] == "function" and not start <= line <= end:
                failures.append(f"{where}: call on line {line} is outside the range")
    return failures


def test_the_index_is_current(built):
    assert dumps(built).encode() == OUT.read_bytes()


def test_a_deleted_index_line_fails_the_currency_check(built, tmp_path):
    lines = OUT.read_bytes().splitlines(keepends=True)
    copy = tmp_path / OUT.name
    copy.write_bytes(b"".join(lines[:100] + lines[101:]))
    assert dumps(built).encode() != copy.read_bytes()


def test_a_second_build_writes_the_same_bytes(built):
    assert dumps(build(ACTION_SCRIPT)) == dumps(built)


def test_records_are_sorted_by_file_then_start(records):
    keys = [(r["file"], r.get("start", 0)) for r in records]
    assert keys == sorted(keys)


def test_each_line_has_sorted_keys_and_no_spaces(records):
    for line, record in zip(OUT.read_text().splitlines(), records, strict=True):
        assert line == json.dumps(record, sort_keys=True, separators=(",", ":"))


def test_every_game_script_parses_and_has_one_script_record(records):
    files = game_files()
    assert files
    for path in files:
        assert not parse_script(path.read_bytes()).has_error, path
    indexed = [r["file"] for r in records if r["kind"] == "script"]
    expected = sorted(p.relative_to(ACTION_SCRIPT).as_posix() for p in files)
    assert indexed == expected


def test_every_record_agrees_with_its_source_lines(records):
    assert invariant_failures(records, export_lines) == []


def test_a_line_added_to_an_export_file_fails_an_invariant(records, tmp_path):
    copy = tmp_path / "DoAction_8.as"
    copy.write_text("\n" + (ACTION_SCRIPT / EXECUTE_MOVE_FILE).read_text())

    def lines_of(file: str) -> list[str]:
        if file == EXECUTE_MOVE_FILE:
            return copy.read_text().splitlines()
        return export_lines(file)

    failures = invariant_failures(records, lines_of)
    assert any("first line does not hold the name" in f for f in failures)
    assert any("no call of" in f for f in failures)


def test_declarations_match_a_regex_count_over_the_same_files(records):
    by_regex = sum(len(_DECLARATION.findall(p.read_text())) for p in game_files())
    declared = [r for r in records if r.get("declared_as") == "declaration"]
    assert by_regex > 0
    assert len(declared) == by_regex


def test_only_the_fields_of_this_schema_are_written(records):
    script = {"kind", "file", "lines", "owner", "calls"}
    function = {"kind", "name", "declared_as", "file", "start", "end", "params"}
    function |= {"calls"}
    for record in records:
        if record["kind"] == "script":
            assert set(record) - {"event"} == script, record["file"]
        elif record["declared_as"] == "assignment":
            assert set(record) == function | {"target"}, record["file"]
        else:
            assert record["declared_as"] == "declaration"
            assert set(record) == function, record["file"]


def test_execute_move_is_a_declaration_with_its_range_and_params(records):
    (record,) = functions_named(records, "executeMove")
    assert (record["file"], record["start"], record["end"]) == (
        EXECUTE_MOVE_FILE,
        1,
        250,
    )
    assert record["declared_as"] == "declaration"
    assert record["params"] == ["IDKM", "IDKM2", "IDKC", "IDKT"]


def test_life_bar_update_is_an_assignment_with_its_target(records):
    (record,) = functions_named(records, "lifeBarUpdate")
    assert (record["file"], record["start"]) == (EXECUTE_MOVE_FILE, 271)
    assert (record["declared_as"], record["target"]) == ("assignment", "lifeBarUpdate")
    assert record["params"] == ["PWLC"]


def test_the_conductor_calls_execute_move_twice_through_root(records):
    conductor = script_record(records, CONDUCTOR)
    calls = [c for c in conductor["calls"] if c["name"] == "executeMove"]
    assert [c["receiver"] for c in calls] == ["_root", "_root"]
    assert conductor["event"] == "onClipEvent(enterFrame)"
    assert conductor["owner"] == {
        "kind": "clip",
        "timeline": 0,
        "frame": 217,
        "placed": 3389,
        "depth": 480,
        "button": None,
    }


def test_a_call_inside_a_function_is_not_on_its_script_record(records):
    (execute_move,) = functions_named(records, "executeMove")
    inside = [c for c in execute_move["calls"] if c["name"] == "perScript"]
    assert inside
    script = script_record(records, EXECUTE_MOVE_FILE)
    lines = {c["line"] for c in script["calls"]}
    assert not lines & {c["line"] for c in inside}


def test_a_frame_script_has_no_event(records):
    assert "event" not in script_record(records, EXECUTE_MOVE_FILE)


def test_parse_reads_a_declaration_and_its_calls():
    source = b"function f(a, b)\n{\n   g(a);\n   _root.h.g(b);\n}\ng(1);\n"
    script = parse_script(source)
    (f,) = script.functions
    assert (f.name, f.declared_as, f.target) == ("f", "declaration", None)
    assert (f.start, f.end, f.params) == (1, 5, ("a", "b"))
    assert [(c.name, c.line, c.receiver) for c in f.calls] == [
        ("g", 3, None),
        ("g", 4, "_root.h"),
    ]
    assert [(c.name, c.line, c.receiver) for c in script.calls] == [("g", 6, None)]
    assert script.event is None
    assert script.lines == 6


def test_parse_reads_an_assigned_function_with_a_dotted_target():
    script = parse_script(b"x = 1;\n_root.lifeBar = function(p)\n{\n   g();\n};\n")
    (f,) = script.functions
    assert (f.name, f.declared_as, f.target) == (
        "lifeBar",
        "assignment",
        "_root.lifeBar",
    )
    assert (f.start, f.end, f.params) == (2, 5, ("p",))
    assert [c.name for c in f.calls] == ["g"]
    assert script.calls == ()


def test_parse_gives_a_nested_function_its_own_record_and_calls():
    source = (
        b"onClipEvent(load){\n   function outer()\n   {\n      a();\n"
        b"      function inner()\n      {\n         b();\n      }\n   }\n   c();\n}\n"
    )
    script = parse_script(source)
    outer, inner = script.functions
    assert (outer.name, outer.start, outer.end) == ("outer", 2, 9)
    assert (inner.name, inner.start, inner.end) == ("inner", 5, 8)
    assert [c.name for c in outer.calls] == ["a"]
    assert [c.name for c in inner.calls] == ["b"]
    assert [(c.name, c.line) for c in script.calls] == [("c", 10)]
    assert script.event == "onClipEvent(load)"
    assert not script.has_error


def test_parse_keeps_the_event_text_of_a_key_handler():
    script = parse_script(b'on(keyPress "<Tab>"){\n   this.tabHandler();\n}\n')
    assert script.event == 'on(keyPress "<Tab>")'
    assert [(c.name, c.receiver) for c in script.calls] == [("tabHandler", "this")]


def test_parse_reports_a_syntax_error():
    assert parse_script(b"function f(\n{\n").has_error


def write_export(root: Path, files: dict[str, str]) -> Path:
    for name, text in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    return root


def test_build_records_a_call_only_when_a_game_script_defines_the_name(tmp_path):
    export = write_export(
        tmp_path,
        {
            "frame_1/DoAction.as": "function known()\n{\n}\n",
            "frame_2/DoAction.as": "known();\ngotoAndStop(2);\n_root.known();\n",
        },
    )
    records = build(export)
    assert [r["kind"] for r in records] == ["script", "function", "script"]
    assert records[2]["calls"] == [
        {"name": "known", "line": 1, "receiver": None},
        {"name": "known", "line": 3, "receiver": "_root"},
    ]


def test_build_leaves_out_the_component_library(tmp_path):
    export = write_export(
        tmp_path,
        {
            "frame_1/DoAction.as": "stop();\n",
            "Border.as": 'Object.registerClass("Border",mx.skins.Border);\n',
            "__Packages/mx/skins/Border.as": (
                "class mx.skins.Border extends mx.core.UIObject\n{\n}\n"
            ),
        },
    )
    assert [r["file"] for r in build(export)] == ["frame_1/DoAction.as"]


@pytest.mark.parametrize(
    ("name", "text"),
    [
        ("__Packages/game/Unit.as", "class game.Unit\n{\n}\n"),
        ("Unit.as", 'Object.registerClass("Unit",game.Unit);\n'),
        ("Loose.as", "_root.x = 1;\n"),
    ],
)
def test_build_refuses_a_left_out_file_that_is_not_library_code(tmp_path, name, text):
    export = write_export(tmp_path, {"frame_1/DoAction.as": "stop();\n", name: text})
    with pytest.raises(ValueError, match=re.escape(name)):
        build(export)


def test_the_real_export_leaves_out_only_library_files(records):
    left_out = [
        p
        for p in ACTION_SCRIPT.rglob("*.as")
        if not is_game_script(p.relative_to(ACTION_SCRIPT))
    ]
    assert len(left_out) + len(game_files()) == len(list(ACTION_SCRIPT.rglob("*.as")))
    assert left_out
