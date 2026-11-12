# These tests run as_lookup.py on the checked-in index and the tracked export,
# on the tracked GDScript, and on small records and GDScript text built by hand.
# Each expected value comes from a record, an export line or a GDScript line,
# so a regenerated index or an edited comment does not need new numbers.
from __future__ import annotations

import re
import subprocess
import sys

import pytest
from urchin_dev import ACTION_SCRIPT, REPO_ROOT
from urchin_dev.as_lookup import (
    EXPORT,
    INDEX,
    Citation,
    load,
    lookup,
    main,
    read_citations,
    resolve,
    tracked_citations,
)
from urchin_dev.swf import as_index

EXECUTE_MOVE_FILE = "frame_42/DoAction_8.as"
CONDUCTOR = (
    "frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(enterFrame).as"
)


@pytest.fixture(scope="module")
def records() -> list[dict]:
    return load()


def function(records: list[dict], name: str) -> dict:
    (record,) = [r for r in records if r["kind"] == "function" and r["name"] == name]
    return record


def script(records: list[dict], file: str) -> dict:
    (record,) = [r for r in records if r["kind"] == "script" and r["file"] == file]
    return record


def location(record: dict) -> str:
    if record["kind"] == "script":
        return f"{EXPORT}/{record['file']}:1-{record['lines']}"
    return f"{EXPORT}/{record['file']}:{record['start']}-{record['end']}"


def numbered(file: str, line: int) -> str:
    text = (ACTION_SCRIPT / file).read_text().splitlines()[line - 1]
    return f"{line:>5}  {text}"


def section(out: str, header: str) -> list[str]:
    """The indented lines under the first line that equals `header`."""
    lines = out.splitlines()
    rows = []
    for line in lines[lines.index(header) + 1 :]:
        if not line.startswith(" "):
            break
        rows.append(line)
    return rows


def holders(record: dict, line: int) -> list[dict]:
    """The outline blocks that hold a line, one for each depth, found without
    the lookup's own walk: the last block of a depth that holds the line."""
    chain = []
    for depth in (1, 2, 3):
        held = [
            e
            for e in record["outline"]
            if e["depth"] == depth and e["start"] <= line <= e["end"]
        ]
        if not held:
            break
        chain.append(held[-1])
    return chain


def test_importing_the_lookup_loads_no_parser():
    code = (
        "import sys, urchin_dev.as_lookup;"
        "print([m for m in sys.modules if m.startswith('tree_sitter')])"
    )
    done = subprocess.run(
        [sys.executable, "-c", code], capture_output=True, text=True, check=True
    )
    assert done.stdout.strip() == "[]"


def test_the_lookup_reads_the_file_the_indexer_writes():
    assert INDEX == as_index.OUT
    assert f"{EXPORT}/" == "dev/source_files/action_script/"


def test_a_function_name_prints_its_location_outline_callers_and_globals(records):
    record = function(records, "executeMove")
    code, out = lookup("executeMove", records)
    assert code == 0
    assert out.splitlines()[:2] == [
        "function executeMove(IDKM, IDKM2, IDKC, IDKT)",
        f"{EXPORT}/{EXECUTE_MOVE_FILE}:1-250",
    ]
    assert section(out, "outline") == [
        f"{'  ' * e['depth']}{e['start']}-{e['end']}  {e['head']}"
        for e in record["outline"]
    ]
    assert "source" not in out.splitlines()

    sites = [
        c for c in script(records, CONDUCTOR)["calls"] if c["name"] == "executeMove"
    ]
    assert len(sites) == 2
    callers = section(out, "callers")
    for site in sites:
        row = f"  {EXPORT}/{CONDUCTOR}:{site['line']}  script  _root.executeMove"
        assert row in callers

    assert "  AVGNUMC  3" in section(out, "writes")
    assert "  _root.perKSuccess  21" in section(out, "writes")
    rows = section(out, "reads")
    read = ", ".join(row.strip().rstrip(",") for row in rows)
    assert read.split(", ") == record["reads"]
    assert 1 < len(rows) < len(record["reads"])
    assert max(len(row) for row in rows) <= 100
    assert len(rows[0]) + len(rows[1].strip()) > 100


def test_calls_print_each_callee_with_its_location(records):
    record = function(records, "executeMove")
    calls = [c for c in record["calls"] if c["name"] == "perScript"]
    assert len(calls) > 1 and not any(c["receiver"] for c in calls)
    _, out = lookup("executeMove", records)
    lines = ", ".join(str(c["line"]) for c in calls)
    callee = location(function(records, "perScript"))
    assert f"  perScript  {lines}  {callee}" in section(out, "calls")
    through_root = [c for c in record["calls"] if c["receiver"] == "_root"]
    assert through_root
    rows = [row.split("  ")[1] for row in section(out, "calls")]
    assert f"_root.{through_root[0]['name']}" in rows


def test_a_function_of_120_lines_or_less_prints_its_source_lines(records):
    record = function(records, "lifeBarUpdate")
    assert record["end"] - record["start"] + 1 <= 120
    code, out = lookup("lifeBarUpdate", records)
    assert code == 0
    assert out.splitlines()[:2] == [
        "function lifeBarUpdate(PWLC), assigned to lifeBarUpdate",
        location(record),
    ]
    assert section(out, "source") == [
        numbered(EXECUTE_MOVE_FILE, line)
        for line in range(record["start"], record["end"] + 1)
    ]
    assert "outline" not in out.splitlines()


def test_a_name_that_is_a_function_and_a_global_prints_both(records):
    record = script(records, EXECUTE_MOVE_FILE)
    (write,) = [w for w in record["writes"] if w["name"] == "lifeBarUpdate"]
    _, out = lookup("lifeBarUpdate", records)
    lines = out.splitlines()
    assert "function lifeBarUpdate(PWLC), assigned to lifeBarUpdate" in lines
    assert "global lifeBarUpdate" in lines
    (line,) = write["lines"]
    assert f"  {EXPORT}/{EXECUTE_MOVE_FILE}:{line}  script" in section(out, "written")


def test_a_path_prints_the_script_and_the_functions_in_it(records):
    record = script(records, EXECUTE_MOVE_FILE)
    code, out = lookup(EXECUTE_MOVE_FILE, records)
    assert code == 0
    assert out.splitlines()[:2] == ["script", location(record)]
    inside = [
        r for r in records if r["kind"] == "function" and r["file"] == EXECUTE_MOVE_FILE
    ]
    assert len(inside) > 1
    assert section(out, "functions") == [
        f"  {r['name']}({', '.join(r['params'])})  {location(r)}" for r in inside
    ]
    assert "callers" not in out.splitlines()


def test_the_conductor_path_prints_its_event_and_its_outline(records):
    record = script(records, CONDUCTOR)
    code, out = lookup(CONDUCTOR, records)
    assert code == 0
    assert out.splitlines()[0] == "script onClipEvent(enterFrame)"
    first = record["outline"][0]
    assert (
        section(out, "outline")[0]
        == f"  {first['start']}-{first['end']}  {first['head']}"
    )
    assert len(section(out, "outline")) == len(record["outline"])


def test_a_unique_end_of_a_path_and_a_repo_path_name_the_same_script(records):
    whole = lookup(EXECUTE_MOVE_FILE, records)
    assert lookup("DoAction_8.as", records) == whole
    assert lookup(f"{EXPORT}/{EXECUTE_MOVE_FILE}", records) == whole


def test_an_end_of_more_than_one_path_is_no_match_and_says_so(records):
    files = [r["file"] for r in records if r["kind"] == "script"]
    ends = [f for f in files if f.endswith("/DoAction.as")]
    assert len(ends) > 1
    code, out = lookup("DoAction.as", records)
    assert code == 1
    assert out.splitlines()[0] == f"DoAction.as is the end of {len(ends)} paths:"
    assert out.splitlines()[1:] == [
        *(f"  {EXPORT}/{file}" for file in ends[:12]),
        f"  ... {len(ends) - 12} more paths",
    ]
    files = ["a/DoAction.as", "b/DoAction.as"]
    few = [{"kind": "script", "file": file} for file in files]
    assert lookup("DoAction.as", few)[1].splitlines()[1:] == [
        f"  {EXPORT}/a/DoAction.as",
        f"  {EXPORT}/b/DoAction.as",
    ]


def test_a_path_that_names_no_file_prints_the_nearest_paths(records):
    code, out = lookup("frame_42/DoAction_88.as", records)
    assert code == 1
    assert out.splitlines()[0] == "no export file is frame_42/DoAction_88.as"
    assert f"  {EXPORT}/{EXECUTE_MOVE_FILE}" in section(out, "nearest paths")


def test_the_nearest_paths_of_a_short_end_compare_ends_of_that_length(tmp_path):
    files = {
        "DefineSprite_100_long_name_of_a_clip/frame_1/DoAction.as": "a = 1;\n",
        "frame_1/Other.as": "a = 1;\n",
    }
    built = as_index.build(write_export(tmp_path, files))
    code, out = lookup("DoActoin.as", built, export=tmp_path)
    assert code == 1
    assert section(out, "nearest paths") == [
        f"  {EXPORT}/DefineSprite_100_long_name_of_a_clip/frame_1/DoAction.as"
    ]


def test_a_path_with_a_line_prints_the_function_and_the_blocks_that_hold_it(records):
    record = function(records, "executeMove")
    chain = holders(record, 82)
    assert len(chain) == 3
    code, out = lookup(f"{EXECUTE_MOVE_FILE}:82", records)
    assert code == 0
    assert out.splitlines()[:2] == [
        "function executeMove(IDKM, IDKM2, IDKC, IDKT)",
        location(record),
    ]
    assert section(out, "line 82 is in") == [
        f"{'  ' * e['depth']}{e['start']}-{e['end']}  {e['head']}" for e in chain
    ]
    block = chain[-1]
    assert block["end"] - block["start"] + 1 <= 120
    assert section(out, "source") == [
        numbered(EXECUTE_MOVE_FILE, line)
        for line in range(block["start"], block["end"] + 1)
    ]


def test_a_line_in_a_block_of_more_than_120_lines_prints_the_block_alone(records):
    record = function(records, "executeMove")
    block = next(e for e in record["outline"] if e["end"] - e["start"] + 1 > 120)
    assert holders(record, block["start"]) == [block]
    query = f"{EXECUTE_MOVE_FILE}:{block['start']}"
    _, out = lookup(query, records)
    assert "source" not in out.splitlines()
    assert "outline" not in out.splitlines()
    _, out = lookup(query, records, source=True)
    assert len(section(out, "source")) == block["end"] - block["start"] + 1


def test_a_line_outside_every_function_prints_the_script(records):
    record = script(records, EXECUTE_MOVE_FILE)
    inside = [
        r for r in records if r["kind"] == "function" and r["file"] == EXECUTE_MOVE_FILE
    ]
    line = next(
        n
        for n in range(1, record["lines"] + 1)
        if not any(r["start"] <= n <= r["end"] for r in inside)
    )
    code, out = lookup(f"{EXECUTE_MOVE_FILE}:{line}", records)
    assert code == 0
    assert out.splitlines()[:2] == ["script", location(record)]


def test_a_line_past_the_end_of_the_file_is_no_match(records):
    lines = script(records, EXECUTE_MOVE_FILE)["lines"]
    code, out = lookup(f"{EXECUTE_MOVE_FILE}:{lines + 1}", records)
    assert code == 1
    assert out == f"{EXPORT}/{EXECUTE_MOVE_FILE} has {lines} lines"
    assert lookup(f"{EXECUTE_MOVE_FILE}:{lines}", records)[0] == 0
    assert lookup(f"{EXECUTE_MOVE_FILE}:1", records)[0] == 0
    assert lookup(f"{EXECUTE_MOVE_FILE}:0", records)[0] == 1


def test_a_last_segment_prints_the_writers_with_lines_and_the_readers(records):
    name = "_root.perKSuccess"
    writers = [
        (r, w["lines"]) for r in records for w in r["writes"] if w["name"] == name
    ]
    readers = [r for r in records if name in r["reads"]]
    assert len(writers) > 1 and readers
    code, out = lookup("perKSuccess", records)
    assert code == 0
    assert out.splitlines()[0] == f"global {name}"
    assert section(out, "written") == [
        f"  {EXPORT}/{r['file']}:{line}  {r.get('name', 'script')}"
        for r, lines in writers
        for line in lines
    ]
    assert section(out, "read") == [
        f"  {location(r)}  {r.get('name', 'script')}" for r in readers
    ]


def test_a_full_path_matches_only_that_name(records):
    code, out = lookup("_root.Krin.zoneName", records)
    assert code == 0
    assert [line for line in out.splitlines() if line.startswith("global ")] == [
        "global _root.Krin.zoneName"
    ]
    _, both = lookup("zoneName", records)
    assert [line for line in both.splitlines() if line.startswith("global ")] == [
        "global Krin.zoneName",
        "global _root.Krin.zoneName",
    ]


def test_a_name_with_no_exact_match_is_matched_without_case_with_a_note(records):
    exact = lookup("executeMove", records)
    code, out = lookup("EXECUTEMOVE", records)
    assert code == 0
    note = "no exact match for EXECUTEMOVE, so this is a match without case"
    assert out == note + "\n\n" + exact[1]
    assert "without case" not in exact[1]


def test_a_name_with_no_match_prints_the_nearest_names(records):
    code, out = lookup("executeMoov", records)
    assert code == 1
    assert out.splitlines()[0] == "no match for executeMoov"
    assert "  executeMove" in section(out, "nearest names")


def test_source_forces_the_lines_of_a_long_function(records):
    record = function(records, "executeMove")
    _, out = lookup("executeMove", records, source=True)
    assert section(out, "source") == [
        numbered(EXECUTE_MOVE_FILE, line)
        for line in range(record["start"], record["end"] + 1)
    ]
    assert "outline" not in out.splitlines()


def test_no_source_leaves_the_lines_out_and_prints_the_outline(records):
    record = function(records, "lifeBarUpdate")
    _, out = lookup("lifeBarUpdate", records, source=False)
    assert "source" not in out.splitlines()
    assert len(section(out, "outline")) == len(record["outline"]) > 0


def test_a_name_written_on_many_lines_prints_12_lines_and_the_count(records):
    record = max(
        (r for r in records if r["kind"] == "script"),
        key=lambda r: max((len(w["lines"]) for w in r["writes"]), default=0),
    )
    write = max(record["writes"], key=lambda w: len(w["lines"]))
    assert len(write["lines"]) > 12
    _, out = lookup(record["file"], records)
    shown = ", ".join(str(line) for line in write["lines"][:12])
    row = f"  {write['name']}  {shown} ... ({len(write['lines'])} lines)"
    assert row in section(out, "writes")

    _, out = lookup(write["name"], records)
    written = section(out, "written")
    assert len([row for row in written if row.endswith("  script")]) == 12
    more = f"  ... {len(write['lines']) - 12} more lines in {EXPORT}/{record['file']}"
    assert more in written


def test_main_prints_the_answer_and_returns_the_exit_code(capsys):
    cited = tracked_citations()
    assert main(["executeMove"]) == 0
    answer = lookup("executeMove", load(), citations=cited)[1]
    assert capsys.readouterr().out == answer + "\n"
    assert section(answer, "ports") != ["  none"]
    assert main(["executeMoov"]) == 1
    assert capsys.readouterr().out.startswith("no match for executeMoov\n")


def test_main_passes_the_source_flags_and_joins_a_path_with_spaces(capsys):
    records = load()
    cited = tracked_citations()

    def answer(query: str, source: bool | None = None) -> str:
        return lookup(query, records, source=source, citations=cited)[1] + "\n"

    assert main(["--source", "executeMove"]) == 0
    assert capsys.readouterr().out == answer("executeMove", True)
    assert main(["--no-source", "lifeBarUpdate"]) == 0
    assert capsys.readouterr().out == answer("lifeBarUpdate", False)
    assert main(CONDUCTOR.split(" ")) == 0
    assert capsys.readouterr().out == answer(CONDUCTOR)


FILES = ["a/DoAction.as", "b/DoAction.as", "b/c/Other.as"]


def test_resolve_finds_one_file_no_file_or_more_than_one_file():
    assert resolve("b/DoAction.as", FILES) == ["b/DoAction.as"]
    assert resolve("c/Other.as", FILES) == ["b/c/Other.as"]
    assert resolve("Other.as", FILES) == ["b/c/Other.as"]
    assert resolve("x/Other.as", FILES) == []
    assert resolve("DoAction.as", FILES) == ["a/DoAction.as", "b/DoAction.as"]


def test_resolve_matches_whole_components_only():
    assert resolve("Action.as", FILES) == []
    assert resolve("/Other.as", FILES) == []


def write_export(root, files: dict[str, str]):
    for file, text in files.items():
        (root / file).parent.mkdir(parents=True, exist_ok=True)
        (root / file).write_text(text)
    return root


def test_callers_name_the_function_or_script_and_the_receiver(tmp_path):
    files = {
        "frame_1/DoAction.as": (
            "function hit(a)\n{\n   return a;\n}\n"
            "function swing()\n{\n   hit(1);\n}\n_root.hit(2);\n"
        )
    }
    built = as_index.build(write_export(tmp_path, files))
    code, out = lookup("hit", built, export=tmp_path)
    assert code == 0
    prefix = f"  {EXPORT}/frame_1/DoAction.as"
    assert section(out, "callers") == [
        f"{prefix}:7  swing  hit",
        f"{prefix}:9  script  _root.hit",
    ]
    assert section(out, "calls") == ["  none"]
    assert section(out, "writes") == ["  none"]
    assert section(out, "reads") == ["  none"]
    assert section(out, "source") == [
        "    1  function hit(a)",
        "    2  {",
        "    3     return a;",
        "    4  }",
    ]


def test_a_function_of_more_than_120_lines_prints_no_source_lines(tmp_path):
    def function_of(name: str, lines: int) -> str:
        return f"function {name}()\n{{\n" + "   x = 1;\n" * (lines - 3) + "}\n"

    files = {"frame_1/DoAction.as": function_of("f", 120) + function_of("g", 121)}
    built = as_index.build(write_export(tmp_path, files))
    _, out = lookup("f", built, export=tmp_path)
    assert len(section(out, "source")) == 120
    _, out = lookup("g", built, export=tmp_path)
    assert "source" not in out.splitlines()
    _, out = lookup("g", built, source=True, export=tmp_path)
    assert len(section(out, "source")) == 121


def test_a_line_in_a_nested_function_prints_the_innermost_function(tmp_path):
    files = {
        "frame_1/DoAction.as": (
            "function outer()\n{\n   function inner()\n   {\n      x = 1;\n   }\n}\n"
        )
    }
    built = as_index.build(write_export(tmp_path, files))
    _, out = lookup("frame_1/DoAction.as:5", built, export=tmp_path)
    assert out.splitlines()[0] == "function inner()"
    assert "line 5 is in no outline block" in out.splitlines()
    _, out = lookup("frame_1/DoAction.as:2", built, export=tmp_path)
    assert out.splitlines()[0] == "function outer()"


GD = """\
## Ported from frame_1/DoAction.as.
extends Node

# The cap comes from frame_42/DoAction_8.as:82.
const CAP := 5


# Rolls the hit (frame_42/DoAction_8.as:40-64).
# The second line of the block has no citation.
func roll() -> int:
	var x := 1  # frame_42/DoAction_8.as:188, 261
	# DefineSprite_12_bar/frame_4/DoAction.as:3-5, 9
	return x


var after := 0  # frame_3/DoAction.as

# A blank line parts this comment from the func: frame_5/DoAction.as:6

func apart() -> void:
	pass


class Inner:
	# frame_7/DoAction.as:2
	func inside() -> void:
		pass

	static func other() -> void:
		pass  # frame_8/DoAction.as:1; frame_9/DoAction.as:4-5
"""


def gd_line(text: str, part: str) -> tuple[int, str]:
    """The number and the stripped text of the one line that holds `part`."""
    ((number, line),) = [
        (number, line.strip())
        for number, line in enumerate(text.splitlines(), 1)
        if part in line
    ]
    return number, line


def cite(part: str, function: str | None, path: str, *lines: tuple[int, int]):
    number, comment = gd_line(GD, part)
    return Citation("scripts/x.gd", number, function, path, lines, comment)


def test_a_citation_has_a_path_an_optional_line_part_and_the_func_that_holds_it():
    assert read_citations(GD, "scripts/x.gd") == [
        cite("Ported from", None, "frame_1/DoAction.as"),
        cite("The cap", None, "frame_42/DoAction_8.as", (82, 82)),
        cite("Rolls the hit", "roll", "frame_42/DoAction_8.as", (40, 64)),
        cite("var x", "roll", "frame_42/DoAction_8.as", (188, 188), (261, 261)),
        cite(
            "_bar/", "roll", "DefineSprite_12_bar/frame_4/DoAction.as", (3, 5), (9, 9)
        ),
        cite("var after", None, "frame_3/DoAction.as"),
        cite("A blank line", None, "frame_5/DoAction.as", (6, 6)),
        cite("frame_7", "inside", "frame_7/DoAction.as", (2, 2)),
        cite("frame_8", "other", "frame_8/DoAction.as", (1, 1)),
        cite("frame_8", "other", "frame_9/DoAction.as", (4, 5)),
    ]


def test_a_signature_on_more_than_one_line_does_not_end_its_func():
    text = "func wide(\n\ta: int,\n) -> int:\n\treturn a  # frame_1/DoAction.as:1\n"
    (cited,) = read_citations(text, "x.gd")
    assert cited.function == "wide"


def test_every_export_path_is_read_back_from_a_comment(records):
    files = [r["file"] for r in records if r["kind"] == "script"]
    assert len(files) > 800
    for file in files:
        comment = f"# see ({file}:7-9, 12) for the rule"
        assert read_citations(comment, "x.gd") == [
            Citation("x.gd", 1, None, file, ((7, 9), (12, 12)), comment)
        ], file


def test_text_outside_a_comment_and_a_bare_file_name_are_no_citation():
    assert read_citations('var path := "frame_1/DoAction.as:5"', "x.gd") == []
    assert read_citations("# DoAction.as:5 and frame217/DoAction.as:5", "x.gd") == []
    assert read_citations("# _data.asset_library and frame_1/x.assets", "x.gd") == []
    assert read_citations("# keyframe_1/DoAction.as:5", "x.gd") == []


def test_a_deeper_comment_directly_above_a_func_stays_in_the_func_before_it():
    text = "func a():\n\tpass\n\t# frame_1/DoAction.as:1\nfunc b():\n\tpass\n"
    (cited,) = read_citations(text, "x.gd")
    assert cited.function == "a"


def test_tracked_citations_reads_the_tracked_gd_files_and_no_other_file(tmp_path):
    (tmp_path / "scripts").mkdir()
    (tmp_path / "scripts/in.gd").write_text("# frame_1/DoAction.as:2\n")
    (tmp_path / "scripts/out.gd").write_text("# frame_2/DoAction.as:2\n")
    (tmp_path / "notes.md").write_text("# frame_3/DoAction.as:2\n")
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(
        ["git", "add", "scripts/in.gd", "notes.md"], cwd=tmp_path, check=True
    )
    assert tracked_citations(tmp_path) == [
        Citation(
            "scripts/in.gd",
            1,
            None,
            "frame_1/DoAction.as",
            ((2, 2),),
            "# frame_1/DoAction.as:2",
        )
    ]


PORT = """\
# The whole script: frame_1/DoAction.as

func port() -> void:
	pass  # frame_1/DoAction.as:3
	# frame_1/DoAction.as:4-5
	# frame_1/DoAction.as:9, 2
	# frame_1/DoAction.as:99
	# frame_9/DoAction.as:1
"""
HIT = (
    "function hit(a)\n{\n   return a;\n}\n"
    "function swing()\n{\n   hit(1);\n}\n_root.hit(2);\n"
)


def port_row(part: str, function: str = "port") -> str:
    number, comment = gd_line(PORT, part)
    return f"  scripts/x.gd:{number}  {function}  {comment}"


def test_ports_print_the_citations_of_the_lines_of_a_record(tmp_path):
    built = as_index.build(write_export(tmp_path, {"frame_1/DoAction.as": HIT}))
    cited = read_citations(PORT, "scripts/x.gd")
    _, out = lookup("hit", built, export=tmp_path, citations=cited)
    assert section(out, "ports") == [
        port_row(":3"),
        port_row(":4-5"),
        port_row(":9, 2"),
    ]
    assert out.splitlines().index("ports") > out.splitlines().index("reads")
    _, out = lookup("swing", built, export=tmp_path, citations=cited)
    assert section(out, "ports") == [port_row(":4-5")]


def test_a_citation_with_no_line_is_a_port_of_the_script_alone(tmp_path):
    built = as_index.build(write_export(tmp_path, {"frame_1/DoAction.as": HIT}))
    cited = read_citations(PORT, "scripts/x.gd")
    _, out = lookup("frame_1/DoAction.as", built, export=tmp_path, citations=cited)
    assert section(out, "ports") == [
        port_row("The whole script", "file"),
        port_row(":3"),
        port_row(":4-5"),
        port_row(":9, 2"),
    ]


def test_a_record_with_no_citation_prints_none(tmp_path):
    built = as_index.build(write_export(tmp_path, {"frame_1/DoAction.as": HIT}))
    _, out = lookup("hit", built, export=tmp_path)
    assert section(out, "ports") == ["  none"]


def test_a_citation_is_a_port_only_when_its_path_names_one_file(tmp_path):
    files = {
        "DefineSprite_1_a/frame_2/DoAction.as": "a = 1;\n",
        "DefineSprite_2_b/frame_2/DoAction.as": "a = 1;\n",
        "DefineSprite_2_b/frame_3/DoAction.as": "a = 1;\n",
    }
    built = as_index.build(write_export(tmp_path, files))
    text = "# frame_2/DoAction.as:1\n\n# frame_3/DoAction.as:1\n"
    cited = read_citations(text, "scripts/x.gd")
    for file in files:
        _, out = lookup(file, built, export=tmp_path, citations=cited)
        expected = ["  none"]
        if "frame_3" in file:
            expected = ["  scripts/x.gd:3  file  # frame_3/DoAction.as:1"]
        assert section(out, "ports") == expected, file


def tracked_lines() -> list[tuple[str, int, str]]:
    """Every line of every tracked .gd file, found without the reader."""
    listed = subprocess.run(
        ["git", "ls-files", "*.gd"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return [
        (gd, number, line)
        for gd in listed.stdout.splitlines()
        for number, line in enumerate((REPO_ROOT / gd).read_text().splitlines(), 1)
    ]


FIRST_RANGE = re.compile(r"#.*frame_42/DoAction_8\.as:(\d+)(?:-(\d+))?")


def first_ranges() -> list[tuple[str, int, int, int]]:
    """The first cited range of each tracked line that cites the file of
    executeMove with a line."""
    found = []
    for gd, number, line in tracked_lines():
        cited = FIRST_RANGE.search(line)
        if cited:
            start = int(cited[1])
            found.append((gd, number, start, int(cited[2] or start)))
    return found


def test_executemove_prints_the_tracked_citations_of_its_lines(records):
    record = function(records, "executeMove")
    _, out = lookup("executeMove", records, citations=tracked_citations())
    ports = section(out, "ports")
    assert out.splitlines().index("ports") > out.splitlines().index("reads")
    inside = [
        f"  {gd}:{number}  "
        for gd, number, start, end in first_ranges()
        if start <= record["end"] and end >= record["start"]
    ]
    assert len(inside) > 5
    for prefix in inside:
        assert any(row.startswith(prefix) for row in ports), prefix
    outside = [
        f"  {gd}:{number}  "
        for gd, number, start, end in first_ranges()
        if start > record["end"]
    ]
    assert outside
    for prefix in outside:
        assert not any(row.startswith(prefix) for row in ports), prefix


def test_a_line_query_prints_the_ports_of_its_block(records):
    block = holders(function(records, "executeMove"), 82)[-1]
    query = f"{EXECUTE_MOVE_FILE}:82"
    _, out = lookup(query, records, citations=tracked_citations())
    ports = section(out, "ports")
    ranges = first_ranges()
    inside = [r for r in ranges if r[2] <= block["end"] and r[3] >= block["start"]]
    before = [r for r in ranges if r[3] < block["start"]]
    assert inside and before
    for gd, number, _, _ in inside:
        assert any(row.startswith(f"  {gd}:{number}  ") for row in ports)
    for gd, number, _, _ in before:
        assert not any(row.startswith(f"  {gd}:{number}  ") for row in ports)
