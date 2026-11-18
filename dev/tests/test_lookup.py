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
    kwargs.setdefault("facts", as_lookup.tracked_facts())
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
        "strings": [],
    }


def gd_script(file: str, lines: int = 10) -> dict:
    return {
        "kind": "gd_script",
        "file": file,
        "lines": lines,
        "signals": [],
        "strings": [],
    }


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
    facts = as_lookup.tracked_facts()
    assert run(path, as_records, gd_records) == as_lookup.lookup(
        path, as_records, facts=facts
    )


def test_an_actionscript_query_prints_the_bytes_as_lookup_prints(
    as_records, gd_records
):
    assert not any(
        r["kind"] == "gd_function" and r["name"] == "executeMove" for r in gd_records
    )
    old = as_lookup.lookup(
        "executeMove",
        as_records,
        citations=as_lookup.tracked_citations(),
        facts=as_lookup.tracked_facts(),
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
        # The flag checks that the alias passes each argument on as it is.
        return subprocess.run(
            ["just", recipe, "executeMove", "--no-source"],
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


def as_function(name: str, file: str, start: int, end: int) -> dict:
    return {
        "kind": "function",
        "name": name,
        "declared_as": "declaration",
        "file": file,
        "start": start,
        "end": end,
        "params": [],
        "calls": [],
        "writes": [],
        "reads": [],
        "strings": [],
    }


def as_script(file: str, lines: int) -> dict:
    return {
        "kind": "script",
        "file": file,
        "lines": lines,
        "owner": {},
        "calls": [],
        "writes": [],
        "reads": [],
        "strings": [],
    }


def test_a_signal_name_prints_its_declaration_connects_and_emits(
    as_records, gd_records
):
    code, out = run("proceed_pressed", as_records, gd_records)
    assert code == 0
    assert "signal proceed_pressed" in out.splitlines()
    declared = section(out, "declared")
    assert any(
        row.startswith("  scripts/battle/victory_screen.gd:13  ") for row in declared
    )
    connects = section(out, "connects")
    assert any(
        row.startswith("  scripts/battle/battle_scene.gd:985  ")
        and "victory.proceed_pressed -> _on_victory_proceed" in row
        for row in connects
    )
    emits = section(out, "emits")
    assert any(
        row.startswith("  scripts/battle/victory_screen.gd:46  ") for row in emits
    )


def test_a_voice_cue_connect_names_its_target(as_records, gd_records):
    _, out = run("voice_cue", as_records, gd_records)
    assert any(
        row.startswith("  scripts/battle/battle_scene.gd:368  ")
        and "presenter.voice_cue -> AudioManagerAuto.voice" in row
        for row in section(out, "connects")
    )


def test_a_signal_that_has_a_function_of_the_same_name_prints_both(tmp_path):
    write_gd(tmp_path, "a.gd")
    script = gd_script("a.gd")
    script["signals"] = [{"name": "done", "line": 1, "params": ["x"]}]
    gd = [script, gd_function("done", "a.gd", 2, 3)]
    code, out = lookup("done", [], gd, root=tmp_path)
    assert code == 0
    assert "function owner.done()" in out.splitlines()
    assert "signal done" in out.splitlines()
    assert "  a.gd:1  done(x)" in section(out, "declared")


def test_a_function_answer_lists_the_signals_it_connects_and_emits(tmp_path):
    write_gd(tmp_path, "a.gd")
    record = gd_function(
        "setup",
        "a.gd",
        1,
        8,
        connects=[
            {"signal": "died", "line": 2, "receiver": "unit", "target": "_on_died"}
        ],
    )
    record["emits"] = [{"signal": "ready", "line": 5}]
    code, out = lookup("setup", [], [gd_script("a.gd"), record], root=tmp_path)
    assert code == 0
    assert section(out, "signals") == [
        "  connects  unit.died -> _on_died  2",
        "  emits  ready  5",
    ]


def test_a_function_with_no_signals_prints_none(tmp_path):
    write_gd(tmp_path, "a.gd")
    gd = [gd_script("a.gd"), gd_function("go", "a.gd", 1, 2)]
    _, out = lookup("go", [], gd, root=tmp_path)
    assert section(out, "signals") == ["  none"]


PORT_COMMENTS = (
    "# frame_1/DoAction_1.as:82\n"
    "func a():\n"
    "\tpass\n"
    "\n"
    "# The conductor, frame_1/DoAction_1.as:40-64.\n"
    "# More text.\n"
    "func b():\n"
    "\t# frame_1/DoAction_1.as:188, 261\n"
    "\tpass\n"
    "\n"
    "func c():\n"
    "\tpass\n"
)


def port_fixture(tmp_path):
    (tmp_path / "scripts").mkdir(exist_ok=True)
    (tmp_path / "scripts/p.gd").write_text(PORT_COMMENTS)
    gd = [
        gd_script("scripts/p.gd", 12),
        gd_function("a", "scripts/p.gd", 2, 3),
        gd_function("b", "scripts/p.gd", 7, 9),
        gd_function("c", "scripts/p.gd", 11, 12),
    ]
    as_records = [
        as_script("frame_1/DoAction_1.as", 300),
        as_function("one", "frame_1/DoAction_1.as", 80, 90),
        as_function("two", "frame_1/DoAction_1.as", 30, 70),
        as_function("three", "frame_1/DoAction_1.as", 180, 200),
        as_function("four", "frame_1/DoAction_1.as", 250, 280),
    ]
    citations = as_lookup.read_citations(PORT_COMMENTS, "scripts/p.gd")
    return as_records, gd, citations


def ports(tmp_path, name: str) -> list[str]:
    as_records, gd, citations = port_fixture(tmp_path)
    code, out = lookup(name, as_records, gd, root=tmp_path, citations=citations)
    assert code == 0
    return section(out, "ports")


def test_a_comment_above_a_func_is_a_port_of_that_func(tmp_path):
    rows = ports(tmp_path, "a")
    assert len(rows) == 1
    assert "one" in rows[0]
    assert "frame_1/DoAction_1.as:82" in rows[0]
    assert "scripts/p.gd:1" in rows[0]


def test_a_comment_block_above_a_func_and_a_comment_inside_it_both_count(tmp_path):
    rows = ports(tmp_path, "b")
    assert len(rows) == 3
    holders = [row.split()[1] for row in rows]
    assert holders == ["two", "three", "four"]
    assert "frame_1/DoAction_1.as:40-64" in rows[0]


def test_a_func_with_no_citation_has_no_ports(tmp_path):
    assert ports(tmp_path, "c") == ["  none"]


def test_a_cited_range_outside_every_function_names_the_script(tmp_path):
    as_records, gd, citations = port_fixture(tmp_path)
    as_records = as_records[:1]
    _, out = lookup("a", as_records, gd, root=tmp_path, citations=citations)
    assert section(out, "ports")[0].split()[1] == "script"


def test_the_actionscript_answer_still_lists_the_gdscript_ports(tmp_path):
    as_records, gd, citations = port_fixture(tmp_path)
    export = tmp_path / "export/frame_1"
    export.mkdir(parents=True, exist_ok=True)
    (export / "DoAction_1.as").write_text("x\n" * 300)
    code, out = lookup(
        "one",
        as_records,
        gd,
        root=tmp_path,
        export=tmp_path / "export",
        citations=citations,
    )
    assert code == 0
    assert any(row.startswith("  scripts/p.gd:1  a") for row in section(out, "ports"))


FACTS = (
    "# Decoded\n"
    "\n"
    "## Melee run (frame_1/DoAction_1.as)\n"
    "\n"
    "Implemented in `scripts/p.gd` (`a`, `_other`). The dash is\n"
    "`frame_1/DoAction_1.as:40-64`.\n"
    "\n"
    "## Other thing\n"
    "\n"
    "Cites `frame_1/DoAction_1.as:200-210`.\n"
    "\n"
    "Names `scripts/p.gd` but not the func: `zzz`.\n"
    "\n"
    "```\n"
    "## not a heading\n"
    "```\n"
    "\n"
    "## No line\n"
    "\n"
    "See frame_1/DoAction_1.as for the whole script.\n"
)
MELEE = "  DECODED_ALGORITHMS.md:3  Melee run (frame_1/DoAction_1.as)"
OTHER = "  DECODED_ALGORITHMS.md:8  Other thing"
NO_LINE = "  DECODED_ALGORITHMS.md:18  No line"


def facts_of(tmp_path, query: str, text: str | None = FACTS) -> list[str]:
    as_records, gd, citations = port_fixture(tmp_path)
    if text is not None:
        (tmp_path / "DECODED_ALGORITHMS.md").write_text(text)
    export = tmp_path / "export/frame_1"
    export.mkdir(parents=True, exist_ok=True)
    (export / "DoAction_1.as").write_text("x\n" * 300)
    code, out = lookup(
        query,
        as_records,
        gd,
        root=tmp_path,
        export=tmp_path / "export",
        citations=citations,
        facts=as_lookup.tracked_facts(tmp_path),
    )
    assert code == 0
    return section(out, "facts") if "facts" in out.splitlines() else []


def test_a_fact_whose_cited_range_overlaps_an_as_function_is_linked(tmp_path):
    assert facts_of(tmp_path, "two") == [MELEE]


def test_a_fact_that_cites_a_range_outside_the_function_is_not_linked(tmp_path):
    assert facts_of(tmp_path, "one") == []
    assert facts_of(tmp_path, "three") == [OTHER]


def test_an_answer_with_no_linked_section_prints_no_facts_section(tmp_path):
    as_records, gd, _ = port_fixture(tmp_path)
    export = tmp_path / "export/frame_1"
    export.mkdir(parents=True, exist_ok=True)
    (export / "DoAction_1.as").write_text("x\n" * 300)
    _, out = lookup("four", as_records, gd, root=tmp_path, export=tmp_path / "export")
    assert "facts" not in out.splitlines()


def test_a_citation_with_no_line_part_links_the_script_only(tmp_path):
    assert NO_LINE not in facts_of(tmp_path, "two")
    assert facts_of(tmp_path, "frame_1/DoAction_1.as") == [MELEE, OTHER, NO_LINE]


def test_a_fact_that_names_the_gd_path_and_func_in_backticks_is_linked(tmp_path):
    assert facts_of(tmp_path, "a") == [MELEE]


def test_a_fact_that_names_only_the_path_links_the_script_and_not_each_func(tmp_path):
    assert facts_of(tmp_path, "c") == []
    assert facts_of(tmp_path, "scripts/p.gd") == [MELEE, OTHER]


def test_a_gd_function_is_linked_to_facts_through_the_ranges_it_cites(tmp_path):
    assert facts_of(tmp_path, "b") == [MELEE]


def test_a_heading_inside_a_code_fence_is_not_a_fact(tmp_path):
    rows = facts_of(tmp_path, "frame_1/DoAction_1.as")
    assert not any("not a heading" in row for row in rows)


def test_a_missing_facts_file_prints_no_facts_section(tmp_path):
    assert facts_of(tmp_path, "two", text=None) == []


def test_known_gaps_and_research_notes_are_not_read(tmp_path):
    (tmp_path / "KNOWN_GAPS.md").write_text(FACTS)
    (tmp_path / "docs/research").mkdir(parents=True)
    (tmp_path / "docs/research/note.md").write_text(FACTS)
    assert facts_of(tmp_path, "two", text=None) == []


def test_krin_melee_and_play_melee_print_the_krin_melee_section(as_records, gd_records):
    heading = next(
        line
        for line in (REPO_ROOT / "DECODED_ALGORITHMS.md").read_text().splitlines()
        if line.startswith("## krinMelee")
    )
    for query in ("krinMelee", "play_melee"):
        _, out = run(query, as_records, gd_records)
        rows = section(out, "facts")
        assert any(
            row.startswith("  DECODED_ALGORITHMS.md:")
            and row.endswith(heading.removeprefix("## "))
            for row in rows
        ), query


def test_a_fact_prints_its_heading_and_never_its_text(as_records, gd_records):
    _, out = run("krinMelee", as_records, gd_records)
    assert "Constants (frame 42 globals)" not in out


def test_a_string_value_prints_the_as_line_and_the_gd_line(as_records, gd_records):
    code, out = run("Angry_Dux", as_records, gd_records)
    assert code == 0
    gd_part, as_part = out.split("\nActionScript\n")
    assert gd_part.startswith("GDScript\nstring Angry_Dux\n")
    assert any(
        row.startswith("  scripts/battle/battle_scene.gd:40  ")
        for row in gd_part.splitlines()
    )
    assert any(
        row.startswith("  dev/source_files/action_script/frame_42/DoAction_8.as:38  ")
        for row in as_part.splitlines()
    )


def test_a_string_row_names_the_function_that_holds_the_literal(tmp_path):
    write_gd(tmp_path, "a.gd")
    script = gd_script("a.gd")
    script["strings"] = [{"value": "top_level", "lines": [1]}]
    record = gd_function("go", "a.gd", 2, 4)
    record["strings"] = [{"value": "top_level", "lines": [3, 4]}]
    code, out = lookup("top_level", [], [script, record], root=tmp_path)
    assert code == 0
    assert section(out, "string top_level") == [
        "  a.gd:1  script",
        "  a.gd:3  go",
        "  a.gd:4  go",
    ]


def test_a_string_matches_without_case_when_no_exact_match_exists(tmp_path):
    write_gd(tmp_path, "a.gd")
    record = gd_function("go", "a.gd", 2, 4)
    record["strings"] = [{"value": "Angry_Dux", "lines": [3]}]
    code, out = lookup("angry_dux", [], [gd_script("a.gd"), record], root=tmp_path)
    assert code == 0
    assert out.startswith("no exact match for angry_dux, so this is a match")
    assert "  a.gd:3  go" in out


def test_an_exact_string_wins_over_a_string_without_case(tmp_path):
    write_gd(tmp_path, "a.gd")
    record = gd_function("go", "a.gd", 2, 4)
    record["strings"] = [
        {"value": "Angry_Dux", "lines": [3]},
        {"value": "angry_dux", "lines": [4]},
    ]
    _, out = lookup("angry_dux", [], [gd_script("a.gd"), record], root=tmp_path)
    assert "a.gd:4" in out
    assert "a.gd:3" not in out
    assert "no exact match" not in out


def test_a_query_with_a_name_match_and_a_string_match_prints_both(tmp_path):
    write_gd(tmp_path, "a.gd")
    named = gd_function("shared", "a.gd", 2, 3)
    holder = gd_function("holder", "a.gd", 4, 5)
    holder["strings"] = [{"value": "shared", "lines": [5]}]
    gd = [gd_script("a.gd"), named, holder]
    code, out = lookup("shared", [], gd, root=tmp_path)
    assert code == 0
    assert "function owner.shared()" in out.splitlines()
    assert section(out, "string shared") == ["  a.gd:5  holder"]


def test_an_exact_name_in_one_language_hides_a_string_without_case(tmp_path):
    write_gd(tmp_path, "a.gd")
    named = gd_function("Shared", "a.gd", 2, 3)
    holder = gd_function("holder", "a.gd", 4, 5)
    holder["strings"] = [{"value": "shared", "lines": [5]}]
    gd = [gd_script("a.gd"), named, holder]
    _, out = lookup("Shared", [], gd, root=tmp_path)
    assert "string" not in out.replace("source", "")


def test_a_string_in_only_the_actionscript_prints_without_a_language_header(tmp_path):
    export = tmp_path / "export/frame_1"
    export.mkdir(parents=True)
    (export / "DoAction_1.as").write_text("a\nb\nc\n")
    as_script_record = as_script("frame_1/DoAction_1.as", 3)
    holder = as_function("go", "frame_1/DoAction_1.as", 1, 2)
    holder["strings"] = [{"value": "snd_boom", "lines": [2]}]
    code, out = lookup("snd_boom", [as_script_record, holder], [], root=tmp_path)
    assert code == 0
    assert out == (
        "string snd_boom\n  dev/source_files/action_script/frame_1/DoAction_1.as:2  go"
    )


def test_a_string_list_over_40_rows_is_cut_and_counted(tmp_path):
    record = gd_function("go", "a.gd", 1, 100)
    record["strings"] = [{"value": "many_rows", "lines": list(range(1, 46))}]
    _, out = lookup("many_rows", [], [gd_script("a.gd", 100), record], root=tmp_path)
    rows = section(out, "string many_rows")
    assert len(rows) == 41
    assert rows[-1] == "  ... 5 more lines"
