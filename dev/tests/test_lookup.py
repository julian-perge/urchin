# These tests run lookup.py on the checked-in indexes and the tracked files,
# and on small records built by hand. Each expected value comes from a record
# or a source line, so a regenerated index does not need new numbers.
from __future__ import annotations

import json
import shutil
import subprocess
import sys

import pytest
from urchin_dev import REPO_ROOT, as_lookup
from urchin_dev.gd_index import OUT as GD_INDEX
from urchin_dev.lookup import lookup, main


@pytest.fixture(scope="module")
def as_records() -> list[dict]:
    return as_lookup.load()


@pytest.fixture(scope="module")
def gd_records() -> list[dict]:
    return [json.loads(line) for line in GD_INDEX.read_text().splitlines()]


def run(query: str, as_records, gd_records, **kwargs) -> tuple[int, str]:
    return lookup(query, as_records, gd_records, **kwargs)


def section(out: str, header: str) -> list[str]:
    """The indented lines under the first line that equals `header`."""
    lines = out.splitlines()
    rows = []
    for line in lines[lines.index(header) + 1 :]:
        if not line.startswith(" "):
            break
        rows.append(line)
    return rows


def gd_function(
    name: str,
    file: str,
    start: int = 1,
    end: int = 2,
    calls: list[dict] | None = None,
    connects: list[dict] | None = None,
    owner: str = "owner",
    params: list[str] | None = None,
) -> dict:
    return {
        "kind": "gd_function",
        "name": name,
        "owner": owner,
        "file": file,
        "start": start,
        "end": end,
        "params": params or [],
        "calls": calls or [],
        "connects": connects or [],
        "emits": [],
    }


def gd_script(file: str, lines: int = 10) -> dict:
    return {"kind": "gd_script", "file": file, "lines": lines, "signals": []}


def call(name: str, line: int, receiver: str | None = None) -> dict:
    return {"name": name, "line": line, "receiver": receiver}


def write_gd(root, file: str, lines: int = 10) -> None:
    path = root / file
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"line {n}\n" for n in range(1, lines + 1)))


def test_tick_buffs_prints_location_source_callers_and_calls(as_records, gd_records):
    code, out = run("tick_buffs", as_records, gd_records)
    assert code == 0
    (definition,) = [
        r
        for r in gd_records
        if r["kind"] == "gd_function" and r["name"] == "tick_buffs"
    ]
    span = f"{definition['file']}:{definition['start']}-{definition['end']}"
    assert span in out.splitlines()
    assert "source" in out.splitlines()
    first = (
        (REPO_ROOT / definition["file"])
        .read_text()
        .splitlines()[definition["start"] - 1]
    )
    assert f"{definition['start']:>5}  {first}" in out
    callers = section(out, "callers")
    assert any(
        row.startswith("  scripts/battle/battle_runner.gd:247  ") for row in callers
    )
    assert any("caster.tick_buffs" in row for row in callers)
    assert "calls" in out.splitlines()


def test_a_gdscript_only_name_prints_no_language_header(as_records, gd_records):
    _, out = run("tick_buffs", as_records, gd_records)
    assert "ActionScript" not in out
    assert "GDScript" not in out


def test_a_test_caller_has_kind_test_and_sorts_after_production_callers(
    as_records, gd_records
):
    _, out = run("tick_buffs", as_records, gd_records)
    kinds = [row.split()[-1] for row in section(out, "callers")]
    assert "test" in kinds
    assert kinds == sorted(kinds, key=lambda k: k == "test")


def test_a_long_function_prints_its_outline_and_source_on_request(
    as_records, gd_records
):
    long = next(r for r in gd_records if r.get("outline"))
    _, out = run(long["name"], as_records, gd_records, source=False)
    assert "outline" in out.splitlines()
    assert "source" not in out.splitlines()
    entry = long["outline"][0]
    assert f"{entry['start']}-{entry['end']}  {entry['head']}" in out
    _, forced = run(long["name"], as_records, gd_records, source=True)
    assert "source" in forced.splitlines()


def test_a_repo_path_lists_the_functions_of_the_script(as_records, gd_records):
    code, out = run("scripts/battle/combat_unit.gd", as_records, gd_records)
    assert code == 0
    assert "scripts/battle/combat_unit.gd:1-" in out
    inside = section(out, "functions")
    assert any(row.startswith("  tick_buffs(buffs_by_id") for row in inside)
    assert len(inside) == sum(
        r["kind"] == "gd_function" and r["file"] == "scripts/battle/combat_unit.gd"
        for r in gd_records
    )


def test_a_unique_end_of_a_repo_path_names_the_script(as_records, gd_records):
    code, out = run("combat_unit.gd", as_records, gd_records)
    assert code == 0
    assert "scripts/battle/combat_unit.gd:1-" in out


def test_a_path_with_a_line_names_the_innermost_function(as_records, gd_records):
    long = next(r for r in gd_records if r.get("outline"))
    entry = long["outline"][0]
    line = entry["start"]
    code, out = run(f"{long['file']}:{line}", as_records, gd_records)
    assert code == 0
    assert f"{long['file']}:{long['start']}-{long['end']}" in out
    assert f"line {line} is in" in out.splitlines()
    assert f"  {entry['start']}-{entry['end']}  {entry['head']}" in out


def test_a_line_outside_every_function_names_the_script(as_records, gd_records):
    code, out = run("scripts/battle/combat_unit.gd:1", as_records, gd_records)
    assert code == 0
    assert "scripts/battle/combat_unit.gd:1-" in out


def test_a_line_past_the_end_of_a_script_exits_1(as_records, gd_records):
    code, out = run("scripts/battle/combat_unit.gd:99999", as_records, gd_records)
    assert code == 1
    assert "has" in out


def test_a_wrong_path_exits_1_and_prints_near_paths(as_records, gd_records):
    code, out = run("scripts/battle/combat_unt.gd", as_records, gd_records)
    assert code == 1
    assert "scripts/battle/combat_unit.gd" in out


def test_a_wrong_name_exits_1_and_prints_near_names_of_both_languages(tmp_path):
    gd = [gd_script("a.gd"), gd_function("apply_buff", "a.gd")]
    as_records = [
        {
            "kind": "script",
            "file": "frame_1/DoAction_1.as",
            "lines": 3,
            "owner": {},
            "calls": [],
            "writes": [],
            "reads": [],
        },
        {
            "kind": "function",
            "name": "applyBuf",
            "declared_as": "declaration",
            "file": "frame_1/DoAction_1.as",
            "start": 1,
            "end": 2,
            "params": [],
            "calls": [],
            "writes": [],
            "reads": [],
        },
    ]
    code, out = lookup("apply_buf", as_records, gd, root=tmp_path)
    assert code == 1
    assert out.splitlines()[0] == "no match for apply_buf"
    names = out.splitlines()
    assert any(row.startswith("  apply_buff") and "GDScript" in row for row in names)
    assert any(row.startswith("  applyBuf") and "ActionScript" in row for row in names)


def test_a_wrong_name_on_the_real_indexes_exits_1(as_records, gd_records):
    code, out = run("tick_buff", as_records, gd_records)
    assert code == 1
    assert "tick_buffs" in out


def test_a_caller_list_over_40_rows_is_cut_and_counted(tmp_path):
    write_gd(tmp_path, "a.gd", 100)
    callers = [
        gd_function(f"c{n:02}", "b.gd", n * 2 + 1, n * 2 + 2, [call("go", n * 2 + 1)])
        for n in range(45)
    ]
    gd = [gd_script("a.gd", 100), gd_script("b.gd", 100)]
    gd += [gd_function("go", "a.gd"), *callers]
    code, out = lookup("go", [], gd, root=tmp_path)
    assert code == 0
    rows = section(out, "callers")
    assert len(rows) == 41
    assert rows[-1] == "  ... 5 more callers"


def test_a_name_with_two_definitions_lists_the_callers_of_each_apart(tmp_path):
    write_gd(tmp_path, "a.gd")
    write_gd(tmp_path, "b.gd")
    gd = [
        gd_script("a.gd"),
        gd_function("go", "a.gd", 1, 2),
        gd_function("in_a", "a.gd", 3, 4, [call("go", 3)]),
        gd_script("b.gd"),
        gd_function("go", "b.gd", 1, 2),
        gd_function("in_b", "b.gd", 3, 4, [call("go", 3, "self")]),
        gd_script("c.gd"),
        gd_function("in_c", "c.gd", 3, 4, [call("go", 3, "x")]),
    ]
    code, out = lookup("go", [], gd, root=tmp_path)
    assert code == 0
    first, second = out.split("\n\n")
    assert first.splitlines()[1] == "a.gd:1-2"
    assert "  a.gd:3  in_a  go  call" in first
    assert "  b.gd:3  in_b" not in first
    assert "  c.gd:3  in_c  x.go  call" in first
    assert "  b.gd:3  in_b  self.go  call" in second
    assert "  a.gd:3  in_a" not in second
    assert "  c.gd:3  in_c  x.go  call" in second


def test_a_connect_target_is_a_caller_of_kind_connect(tmp_path):
    write_gd(tmp_path, "a.gd")
    connects = [
        {"signal": "died", "line": 5, "receiver": "unit", "target": "_on_died.bind(1)"},
        {"signal": "voice", "line": 6, "receiver": "x", "target": "Audio.voice"},
        {"signal": "done", "line": 7, "receiver": None, "target": "func(): pass"},
    ]
    gd = [
        gd_script("a.gd"),
        gd_function("_on_died", "a.gd", 1, 2),
        gd_function("voice", "a.gd", 3, 4),
        gd_function("setup", "a.gd", 5, 8, connects=connects),
    ]
    _, died = lookup("_on_died", [], gd, root=tmp_path)
    assert "  a.gd:5  setup  unit.died -> _on_died  connect" in died
    _, voice = lookup("voice", [], gd, root=tmp_path)
    assert "  a.gd:6  setup  x.voice -> Audio.voice  connect" in voice


def test_calls_list_each_callee_with_its_location(tmp_path):
    write_gd(tmp_path, "a.gd")
    gd = [
        gd_script("a.gd"),
        gd_function("helper", "a.gd", 1, 2),
        gd_function(
            "run", "a.gd", 3, 6, [call("helper", 4, "self"), call("helper", 5)]
        ),
    ]
    _, out = lookup("run", [], gd, root=tmp_path)
    rows = section(out, "calls")
    assert "  self.helper  4  a.gd:1-2" in rows
    assert "  helper  5  a.gd:1-2" in rows


def test_a_name_without_exact_case_matches_without_case(tmp_path):
    write_gd(tmp_path, "a.gd")
    gd = [gd_script("a.gd"), gd_function("Go", "a.gd", 1, 2)]
    code, out = lookup("go", [], gd, root=tmp_path)
    assert code == 0
    assert out.startswith("no exact match for go, so this is a match without case")


def test_a_name_in_both_languages_prints_one_section_for_each(tmp_path):
    write_gd(tmp_path, "a.gd")
    export = tmp_path / "export"
    (export / "frame_1").mkdir(parents=True)
    (export / "frame_1/DoAction_1.as").write_text("a\nb\nc\n")
    gd = [gd_script("a.gd"), gd_function("go", "a.gd", 1, 2)]
    as_records = [
        {
            "kind": "script",
            "file": "frame_1/DoAction_1.as",
            "lines": 3,
            "owner": {},
            "calls": [],
            "writes": [],
            "reads": [],
        },
        {
            "kind": "function",
            "name": "go",
            "declared_as": "declaration",
            "file": "frame_1/DoAction_1.as",
            "start": 1,
            "end": 2,
            "params": [],
            "calls": [],
            "writes": [],
            "reads": [],
        },
    ]
    code, out = lookup("go", as_records, gd, root=tmp_path, export=export)
    assert code == 0
    lines = out.splitlines()
    assert lines.index("GDScript") < lines.index("ActionScript")
    assert "a.gd:1-2" in lines
    assert any(line.endswith("frame_1/DoAction_1.as:1-2") for line in lines)


def test_a_path_that_ends_in_as_is_answered_by_as_lookup(as_records, gd_records):
    path = "frame_42/DoAction_8.as"
    assert run(path, as_records, gd_records) == as_lookup.lookup(path, as_records)


def test_an_actionscript_query_prints_the_bytes_as_lookup_prints(
    as_records, gd_records
):
    assert not any(
        r["kind"] == "gd_function" and r["name"] == "executeMove" for r in gd_records
    )
    old = as_lookup.lookup(
        "executeMove", as_records, citations=as_lookup.tracked_citations()
    )
    new = run(
        "executeMove", as_records, gd_records, citations=as_lookup.tracked_citations()
    )
    assert new == old


def test_main_exits_0_on_a_match_and_1_on_none(capsys):
    assert main(["tick_buffs"]) == 0
    assert "scripts/battle/combat_unit.gd" in capsys.readouterr().out
    assert main(["no_such_name_zzz"]) == 1
    assert "no match for no_such_name_zzz" in capsys.readouterr().out


def test_just_as_lookup_prints_the_same_bytes_as_just_lookup():
    if shutil.which("just") is None:
        pytest.skip("just is not on PATH")

    def printed(recipe: str) -> bytes:
        return subprocess.run(
            ["just", recipe, "executeMove"],
            cwd=REPO_ROOT,
            capture_output=True,
            check=True,
        ).stdout

    assert printed("as-lookup") == printed("lookup")


def test_lookup_imports_no_parser():
    code = (
        "import sys, urchin_dev.lookup;"
        "bad = sorted(m for m in sys.modules if m.startswith('tree_sitter'));"
        "assert not bad, bad"
    )
    result = subprocess.run(
        [sys.executable, "-c", code], capture_output=True, text=True
    )
    assert result.returncode == 0, result.stderr
