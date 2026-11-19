# Checks the committed gd_index.jsonl against the tracked .gd files. Neither the
# SWF nor Godot is read, since both are absent from a fresh checkout.
from __future__ import annotations

import json
import re
import subprocess

import pytest
import tree_sitter_gdscript
from tree_sitter import Language, Parser
from urchin_dev import REPO_ROOT
from urchin_dev.gd_index import OUT, build, dumps, index_sources, tracked_gd_files

_FUNC_LINE = re.compile(r"^\s*(static\s+)?func\s", re.MULTILINE)


@pytest.fixture(scope="module")
def built() -> list[dict]:
    return build()


@pytest.fixture(scope="module")
def records() -> list[dict]:
    return [json.loads(line) for line in OUT.read_text().splitlines()]


def git_files() -> list[str]:
    """The tracked .gd files, found without the builder's own file list."""
    out = subprocess.run(
        ["git", "ls-files", "-z", "--", "scripts/*.gd", "test/*.gd", "dev/*.gd"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return sorted(out.split("\0")[:-1])


def source_lines(file: str) -> list[str]:
    return (REPO_ROOT / file).read_text().splitlines()


def sample(source: str) -> list[dict]:
    return index_sources({"scripts/sample.gd": source.encode()})


def functions(records: list[dict], name: str | None = None) -> list[dict]:
    return [
        r
        for r in records
        if r["kind"] == "gd_function" and (name is None or r["name"] == name)
    ]


def invariant_failures(records: list[dict], lines_of) -> list[str]:
    """Every way a record disagrees with the source lines it points at.
    `lines_of` maps a record's file to that file's lines."""
    failures = []
    for record in records:
        lines = lines_of(record["file"])
        where = record["file"]
        if record["kind"] == "gd_script":
            if record["lines"] != len(lines):
                failures.append(f"{where}: lines {record['lines']} != {len(lines)}")
            for held in record["strings"]:
                for line in held["lines"]:
                    if (
                        not 1 <= line <= len(lines)
                        or held["value"] not in lines[line - 1]
                    ):
                        failures.append(f"{where}: no string {held['value']} on {line}")
            for signal in record["signals"]:
                line = signal["line"]
                if not 1 <= line <= len(lines) or "signal" not in lines[line - 1]:
                    failures.append(f"{where}: no signal on line {line}")
            continue
        start, end = record["start"], record["end"]
        where = f"{where}:{start}-{end} {record['name']}"
        if not 1 <= start <= end <= len(lines):
            failures.append(f"{where}: range outside the file")
            continue
        first = lines[start - 1]
        if "func" not in first or record["name"] not in first:
            failures.append(f"{where}: first line is not the func line")
        if not lines[end - 1].strip():
            failures.append(f"{where}: last line is blank")
        for call in record["calls"]:
            line = call["line"]
            if not start <= line <= end:
                failures.append(f"{where}: call on line {line} is outside the range")
            elif call["name"] + "(" not in lines[line - 1]:
                failures.append(f"{where}: no call of {call['name']} on line {line}")
        for connect in record["connects"]:
            line = connect["line"]
            if not start <= line <= end or "connect" not in lines[line - 1]:
                failures.append(f"{where}: no connect on line {line}")
        for emit in record["emits"]:
            line = emit["line"]
            if not start <= line <= end or "emit" not in lines[line - 1]:
                failures.append(f"{where}: no emit on line {line}")
        for held in record["strings"]:
            for line in held["lines"]:
                if not start <= line <= end or held["value"] not in lines[line - 1]:
                    failures.append(f"{where}: no string {held['value']} on {line}")
        for entry in record.get("outline", []):
            if not start <= entry["start"] <= entry["end"] <= end:
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
    assert dumps(build()) == dumps(built)


def test_records_are_sorted_by_file_then_start(records):
    keys = [(r["file"], r.get("start", 0)) for r in records]
    assert keys == sorted(keys)


def test_each_line_has_sorted_keys_and_no_spaces(records):
    for line, record in zip(OUT.read_text().splitlines(), records, strict=True):
        assert line == json.dumps(record, sort_keys=True, separators=(",", ":"))


def test_the_builder_lists_the_tracked_files_and_leaves_out_addons():
    files = tracked_gd_files()
    assert files == git_files()
    assert files
    assert not any(f.startswith("addons/") for f in files)


def test_every_tracked_file_parses_and_has_one_script_record(records):
    parser = Parser(Language(tree_sitter_gdscript.language()))
    files = git_files()
    for file in files:
        assert not parser.parse((REPO_ROOT / file).read_bytes()).root_node.has_error
    indexed = [r["file"] for r in records if r["kind"] == "gd_script"]
    assert indexed == files


def test_a_file_that_does_not_parse_is_an_error():
    with pytest.raises(ValueError, match="does not parse"):
        index_sources({"scripts/bad.gd": b"func (:\n"})


def test_every_record_agrees_with_its_source_lines(records):
    assert invariant_failures(records, source_lines) == []


def test_a_moved_func_line_fails_an_invariant(records, tmp_path):
    victim = next(r for r in functions(records) if r["start"] > 1)
    file = victim["file"]
    lines = source_lines(file)
    moved = list(lines)
    moved.insert(victim["start"] - 1, "")

    def lines_of(name: str) -> list[str]:
        return moved if name == file else source_lines(name)

    assert invariant_failures(records, lines_of) != []


def test_the_function_count_equals_a_regex_count_of_func_lines(records):
    counted = sum(
        len(_FUNC_LINE.findall((REPO_ROOT / f).read_text())) for f in git_files()
    )
    assert counted > 0
    assert len(functions(records)) == counted


def test_tick_buffs_is_in_combat_unit_and_has_a_caller_in_battle_runner(records):
    (definition,) = [
        r
        for r in functions(records, "tick_buffs")
        if r["file"] == "scripts/battle/combat_unit.gd"
    ]
    assert definition["owner"] == "CombatUnit"
    callers = [
        (r["file"], c["line"])
        for r in functions(records)
        for c in r["calls"]
        if c["name"] == "tick_buffs"
    ]
    call_line = 1 + (
        REPO_ROOT / "scripts/battle/battle_runner.gd"
    ).read_text().splitlines().index(
        "\t\tvar tick: BuffTick = caster.tick_buffs(buffs_by_id)"
    )
    assert ("scripts/battle/battle_runner.gd", call_line) in callers


def test_a_voice_cue_connect_is_recorded_with_its_target(records):
    connects = [
        c
        for r in functions(records)
        if r["file"] == "scripts/battle/battle_scene.gd"
        for c in r["connects"]
        if c["signal"] == "voice_cue"
    ]
    assert any(c["target"] == "AudioManagerAuto.voice" for c in connects)


def test_a_function_record_holds_its_owner_range_and_params():
    records = sample(
        "class_name Foo\n"
        "extends Node\n"
        "\n"
        "class Inner:\n"
        "\tfunc ping(x):\n"
        "\t\treturn x\n"
        "\n"
        "static func make(a: int, b := 2, c = 3) -> Foo:\n"
        "\treturn Foo.new()\n"
        "\n"
        "func last():\n"
        "\tpass\n"
    )
    ping, make, last = functions(records)
    assert (ping["owner"], ping["start"], ping["end"]) == ("Inner", 5, 6)
    assert (make["owner"], make["start"], make["end"]) == ("Foo", 8, 9)
    assert make["params"] == ["a", "b", "c"]
    assert (last["name"], last["start"], last["end"]) == ("last", 11, 12)


def test_a_file_without_class_name_is_owned_by_its_stem():
    records = sample("func go():\n\tpass\n")
    assert functions(records)[0]["owner"] == "sample"


def test_a_script_record_holds_class_name_extends_and_signals():
    records = sample(
        "class_name Foo\nextends Node\nsignal done(a, b: int)\nsignal quiet\n"
    )
    script = records[0]
    assert script["kind"] == "gd_script"
    assert script["file"] == "scripts/sample.gd"
    assert script["class_name"] == "Foo"
    assert script["extends"] == "Node"
    assert script["signals"] == [
        {"name": "done", "line": 3, "params": ["a", "b"]},
        {"name": "quiet", "line": 4, "params": []},
    ]


def test_a_script_with_no_class_name_or_extends_omits_those_keys():
    script = sample("func go():\n\tpass\n")[0]
    assert "class_name" not in script
    assert "extends" not in script


def test_calls_keep_only_names_that_a_function_defines_and_hold_the_receiver():
    records = sample(
        "func helper(x):\n"
        "\tpass\n"
        "\n"
        "func run(unit):\n"
        "\thelper(1)\n"
        "\tself.helper(2)\n"
        "\tunit.a.helper(3)\n"
        "\tget_node('x').helper(4)\n"
        "\tprint('not defined')\n"
        "\tvar f = func(): helper(5)\n"
    )
    run = functions(records, "run")[0]
    assert run["calls"] == [
        {"name": "helper", "line": 5, "receiver": None},
        {"name": "helper", "line": 6, "receiver": "self"},
        {"name": "helper", "line": 7, "receiver": "unit.a"},
        {"name": "helper", "line": 8, "receiver": "get_node('x')"},
        {"name": "helper", "line": 10, "receiver": None},
    ]


def test_connects_hold_the_signal_receiver_and_target():
    records = sample(
        "func _on_died():\n"
        "\tpass\n"
        "\n"
        "func run(unit):\n"
        "\tunit.died.connect(_on_died.bind(1))\n"
        "\tdone.connect(_on_died)\n"
        "\tbtn.pressed.connect(func(): print('x'))\n"
        "\tconnect('done', _on_died)\n"
    )
    assert functions(records, "run")[0]["connects"] == [
        {"signal": "died", "line": 5, "receiver": "unit", "target": "_on_died.bind(1)"},
        {"signal": "done", "line": 6, "receiver": None, "target": "_on_died"},
        {
            "signal": "pressed",
            "line": 7,
            "receiver": "btn",
            "target": "func(): print('x')",
        },
        {"signal": "done", "line": 8, "receiver": None, "target": "_on_died"},
    ]


def test_emits_hold_the_signal_name():
    records = sample(
        "func run():\n"
        "\tdone.emit(1, 2)\n"
        "\tunit.died.emit()\n"
        "\temit_signal('done', 1)\n"
        "\tunit.emit_signal('died')\n"
    )
    assert functions(records, "run")[0]["emits"] == [
        {"signal": "done", "line": 2},
        {"signal": "died", "line": 3},
        {"signal": "done", "line": 4},
        {"signal": "died", "line": 5},
    ]


def test_a_lambda_call_belongs_to_the_function_that_holds_the_lambda():
    records = sample(
        "func helper():\n\tpass\n\nfunc run():\n\tvar f = func():\n\t\thelper()\n"
    )
    assert len(functions(records)) == 2
    assert [c["line"] for c in functions(records, "run")[0]["calls"]] == [6]


def test_a_short_function_has_no_outline():
    records = sample("func go():\n\tpass\n")
    assert "outline" not in functions(records)[0]


def test_a_long_function_has_an_outline_of_its_big_statements():
    body = "".join(f"\t\tpass # {i}\n" for i in range(16))
    source = (
        "func go(x):\n"
        "\tif x:\n"
        + body
        + "\telif x == 2:\n"
        + body
        + "\telse:\n"
        + body
        + "".join(f"\tpass # {i}\n" for i in range(10))
    )
    (function,) = functions(sample(source))
    heads = [(b["head"], b["depth"]) for b in function["outline"]]
    assert heads == [("if x:", 1), ("elif x == 2:", 1), ("else:", 1)]
    first = function["outline"][0]
    assert (first["start"], first["end"]) == (2, 52)


def test_a_constructor_is_a_function_named_init():
    records = sample("func _init(a) -> void:\n\tpass\n")
    (init,) = functions(records)
    assert (init["name"], init["params"], init["start"]) == ("_init", ["a"], 1)


def test_strings_are_the_name_like_literals_of_a_function_with_their_lines():
    records = sample(
        'const TOP = "top_level"\n'
        "\n"
        "func go():\n"
        '\tprint("Angry_Dux")\n'
        '\tvar d = {"Angry_Dux": 1, "ab": 2, "two words": 3, "": 4}\n'
        '\tvar n = &"sn_name"\n'
        '\tvar f = func(): print("in_lambda")\n'
        "\n"
        "func other():\n"
        "\tpass\n"
    )
    script, go, other = records
    assert script["strings"] == [{"value": "top_level", "lines": [1]}]
    assert go["strings"] == [
        {"value": "Angry_Dux", "lines": [4, 5]},
        {"value": "in_lambda", "lines": [7]},
        {"value": "sn_name", "lines": [6]},
    ]
    assert other["strings"] == []


def test_the_real_index_finds_angry_dux_on_line_40_of_battle_scene(records):
    lines = [
        line
        for r in records
        if r["file"] == "scripts/battle/battle_scene.gd"
        for held in r["strings"]
        if held["value"] == "Angry_Dux"
        for line in held["lines"]
    ]
    assert 40 in lines
