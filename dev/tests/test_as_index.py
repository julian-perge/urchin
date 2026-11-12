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
        for write in record["writes"]:
            segment = write["name"].rsplit(".", 1)[-1].rstrip("*")
            for line in write["lines"]:
                if not 1 <= line <= len(lines) or segment not in lines[line - 1]:
                    failures.append(f"{where}: no {write['name']} on line {line}")
        first, last = (1, len(lines)) if record["kind"] == "script" else (start, end)
        for entry in record.get("outline", []):
            if not first <= entry["start"] <= entry["end"] <= last:
                failures.append(f"{where}: outline entry outside the record")
            elif entry["head"] != lines[entry["start"] - 1].strip()[:100]:
                failures.append(f"{where}: outline head is not line {entry['start']}")
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
    assert any("no AVGNUMC on line 3" in f for f in failures)
    assert any("outline head is not line" in f for f in failures)


def test_declarations_match_a_regex_count_over_the_same_files(records):
    by_regex = sum(len(_DECLARATION.findall(p.read_text())) for p in game_files())
    declared = [r for r in records if r.get("declared_as") == "declaration"]
    assert by_regex > 0
    assert len(declared) == by_regex


def test_only_the_fields_of_this_schema_are_written(records):
    script = {"kind", "file", "lines", "owner", "calls", "writes", "reads"}
    function = {"kind", "name", "declared_as", "file", "start", "end", "params"}
    function |= {"calls", "writes", "reads"}
    for record in records:
        fields = set(record) - {"outline"}
        if record["kind"] == "script":
            assert fields - {"event"} == script, record["file"]
        elif record["declared_as"] == "assignment":
            assert fields == function | {"target"}, record["file"]
        else:
            assert record["declared_as"] == "declaration"
            assert fields == function, record["file"]


def span(record: dict) -> int:
    if record["kind"] == "script":
        return record["lines"]
    return record["end"] - record["start"] + 1


def test_a_record_has_an_outline_only_when_it_spans_more_than_60_lines(records):
    assert any("outline" in r for r in records)
    for record in records:
        assert ("outline" in record) == (span(record) > 60), record["file"]


def test_outline_entries_are_long_statements_to_depth_3_in_line_order(records):
    for record in records:
        outline = record.get("outline", [])
        assert [e["start"] for e in outline] == sorted(e["start"] for e in outline)
        for entry in outline:
            assert set(entry) == {"start", "end", "depth", "head"}
            assert entry["end"] - entry["start"] + 1 >= 15
            assert 1 <= entry["depth"] <= 3


def test_writes_and_reads_are_sorted_with_one_entry_per_name(records):
    for record in records:
        names = [w["name"] for w in record["writes"]]
        assert names == sorted(set(names)), record["file"]
        assert record["reads"] == sorted(set(record["reads"])), record["file"]
        for write in record["writes"]:
            assert set(write) == {"name", "lines"}
            assert write["lines"] == sorted(set(write["lines"])) != []


def test_execute_move_writes_and_reads_its_globals(records):
    (record,) = functions_named(records, "executeMove")
    writes = {w["name"]: w["lines"] for w in record["writes"]}
    assert writes["AVGNUMC"] == [3]
    assert writes["_root.perKSuccess"] == [21]
    assert "_root.perKSuccess" in record["reads"]
    assert not {"IDKM", "IDKM2", "IDKC", "IDKT"} & {n.split(".")[0] for n in writes}
    assert not [n for n in record["reads"] if n.split(".")[0] == "IDKT"]


def test_the_conductor_outline_starts_at_the_battle_block(records):
    outline = script_record(records, CONDUCTOR)["outline"]
    entries = [(e["start"], e["end"], e["depth"], e["head"]) for e in outline]
    assert entries[0] == (10, 588, 1, "if(_root.InBattle)")
    assert (12, 111, 2, "if(_root.BAMBAMBAM)") in entries
    assert (139, 587, 2, "if(_root.nextPlayer)") in entries


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


def names(script_or_function) -> tuple[dict, list]:
    writes = {w.name: list(w.lines) for w in script_or_function.writes}
    return writes, list(script_or_function.reads)


def test_a_name_is_the_longest_static_path_and_stops_at_a_computed_segment():
    source = (
        b"x = _root.Krin.zoneName[_root.Krin.sectionIn];\n"
        b"_root.a.b[i].c = _root.d.e.f(g);\n"
    )
    writes, reads = names(parse_script(source))
    assert writes == {"x": [1], "_root.a.b": [2]}
    assert reads == [
        "_root.Krin.sectionIn",
        "_root.Krin.zoneName",
        "_root.d.e",
        "g",
        "i",
    ]


def test_a_path_keeps_its_root_parent_global_or_this_prefix():
    source = b"_parent.a = this.b;\n_global.c = _root.d;\ne = this;\nf = _root;\n"
    writes, reads = names(parse_script(source))
    assert writes == {"_parent.a": [1], "_global.c": [2], "e": [3], "f": [4]}
    assert reads == ["_root.d", "this.b"]


def test_a_bare_name_is_kept_unless_it_is_a_param_a_var_or_a_built_in():
    source = (
        b"function f(p)\n{\n   var v = 1;\n   AVGNUMC = p.level + v + Math.PI;\n"
        b"   p.life = other.life;\n   _X = _alpha + NaN;\n"
        b"   function inner()\n   {\n      v = p;\n      deep = 1;\n   }\n}\n"
    )
    f, inner = parse_script(source).functions
    assert names(f) == ({"AVGNUMC": [4]}, ["other.life"])
    assert names(inner) == ({"deep": [10]}, [])


def test_a_var_outside_every_function_is_a_name_of_the_script():
    frame = parse_script(b"var listener = new Object();\nlistener.x = 1;\n")
    assert names(frame) == ({"listener": [1], "listener.x": [2]}, [])
    handler = parse_script(b"onClipEvent(load){\n   var c = new Color(this);\n}\n")
    assert names(handler) == ({"c": [2]}, [])


def test_a_computed_segment_with_a_string_prefix_keeps_the_prefix_and_a_star():
    source = (
        b'a = _root["playerKrin" + n];\n_root["playerKrin" + n].LIFEN = 5;\n'
        b'this["b" + i + "x"].COVER.gotoAndStop(1);\nb = _root[n + "tail"].c;\n'
    )
    writes, reads = names(parse_script(source))
    assert writes == {"a": [1], "_root.playerKrin*.LIFEN": [2], "b": [4]}
    assert reads == ["_root.playerKrin*", "i", "n", "this.b*.COVER"]


def test_an_update_or_a_compound_assignment_writes_and_reads_the_name():
    writes, reads = names(
        parse_script(b"_root.n += 1;\ni++;\nfor(k in _root.t)\n{\n}\n")
    )
    assert writes == {"_root.n": [1], "i": [2], "k": [3]}
    assert reads == ["_root.n", "_root.t", "i"]


def test_a_called_name_is_not_a_read_and_an_assigned_function_is_a_write():
    source = (
        b"g(_root.a);\n_root.h.run(b);\n_root.tick = function()\n{\n   c = 1;\n};\n"
    )
    script = parse_script(source)
    assert names(script) == ({"_root.tick": [3]}, ["_root.a", "_root.h", "b"])
    assert names(script.functions[0]) == ({"c": [5]}, [])


def test_parse_outlines_long_statements_and_keeps_an_else_at_the_depth_of_its_if():
    body = "".join(f"   a{n} = {n};\n" for n in range(16))
    source = (
        f"function f()\n{{\nif(x)\n{{\n{body}while(y)\n{{\n{body}}}\n}}\n"
        f"else if(z)\n{{\n{body}}}\nelse\n{{\nfor(k in t)\n{{\n{body}}}\n}}\n}}\n"
    ).encode()
    script = parse_script(source)
    (f,) = script.functions
    assert [(e.start, e.end, e.depth, e.head) for e in f.outline] == [
        (3, 81, 1, "if(x)"),
        (21, 39, 2, "while(y)"),
        (41, 81, 1, "else if(z)"),
        (60, 81, 1, "else"),
        (62, 80, 2, "for(k in t)"),
    ]
    assert [(e.start, e.end, e.depth, e.head) for e in script.outline] == [
        (1, 82, 1, "function f()")
    ]


def block_script(block_lines: int, script_lines: int) -> bytes:
    """One `if` block of block_lines lines, then single-line statements up to
    script_lines lines."""
    block = "if(x)\n{\n" + "   a = 1;\n" * (block_lines - 3) + "}\n"
    return (block + "b = 2;\n" * (script_lines - block_lines)).encode()


def test_a_script_of_60_lines_has_no_outline_and_one_of_61_lines_has():
    assert parse_script(block_script(15, 60)).outline is None
    (block,) = parse_script(block_script(15, 61)).outline
    assert (block.start, block.end, block.depth, block.head) == (1, 15, 1, "if(x)")


def test_a_statement_of_14_lines_is_not_in_the_outline():
    assert parse_script(block_script(14, 61)).outline == ()


def test_a_statement_below_depth_3_is_not_in_the_outline():
    inner = "   a = 1;\n" * 15
    source = "".join(f"if(x{depth})\n{{\n" for depth in (1, 2, 3, 4))
    source += inner + "}\n" * 4 + "b = 2;\n" * 40
    outline = parse_script(source.encode()).outline
    assert [(e.depth, e.head) for e in outline] == [
        (1, "if(x1)"),
        (2, "if(x2)"),
        (3, "if(x3)"),
    ]


def test_a_head_is_cut_at_100_characters():
    condition = "x" * 120
    source = f"if({condition})\n{{\n" + "   a = 1;\n" * 15 + "}\n" + "b = 2;\n" * 50
    (block,) = parse_script(source.encode()).outline
    assert block.head == f"if({condition})"[:100]


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
