# These tests run as_citations.py on GDScript text built by hand, against a
# small table of export files, and then on every tracked .gd file against the
# checked-in index.
from __future__ import annotations

from urchin_dev.as_lookup import load, read_citations, tracked_citations
from urchin_dev.checks.as_citations import failures, line_counts, main

LINES = {
    "frame_1/DoAction.as": 7,
    "DefineSprite_1_a/frame_2/DoAction.as": 3,
    "DefineSprite_2_b/frame_2/DoAction.as": 3,
    "DefineSprite_2_b/frame_3/DoAction.as": 40,
}


def failed(comment: str) -> list[str]:
    return failures(read_citations(comment, "scripts/x.gd"), LINES)


def test_a_citation_of_a_line_in_one_export_file_passes():
    assert failed("# frame_1/DoAction.as:7") == []
    assert failed("# frame_1/DoAction.as:1-7") == []
    assert failed("# frame_1/DoAction.as") == []
    assert failed("# frame_3/DoAction.as:12, 40") == []
    assert failed("# DefineSprite_2_b/frame_2/DoAction.as:3") == []


def test_a_path_that_names_no_export_file_fails():
    assert failed("# frame_9/DoAction.as:1") == [
        "scripts/x.gd:1: frame_9/DoAction.as:1 names no export file"
    ]
    assert failed("# frame_9/DoAction.as") == [
        "scripts/x.gd:1: frame_9/DoAction.as names no export file"
    ]


def test_a_path_that_ends_more_than_one_export_file_fails_and_names_them():
    ends = "DefineSprite_1_a/frame_2/DoAction.as, DefineSprite_2_b/frame_2/DoAction.as"
    assert failed("# frame_2/DoAction.as:1") == [
        f"scripts/x.gd:1: frame_2/DoAction.as:1 is the end of 2 export files: {ends}"
    ]


def test_a_line_past_the_end_of_the_file_fails():
    has = "and frame_1/DoAction.as has 7 lines"
    assert failed("# frame_1/DoAction.as:8") == [
        f"scripts/x.gd:1: frame_1/DoAction.as:8 names line 8, {has}"
    ]
    assert failed("# frame_1/DoAction.as:5-9") == [
        f"scripts/x.gd:1: frame_1/DoAction.as:5-9 names line 9, {has}"
    ]
    has = "and DefineSprite_2_b/frame_3/DoAction.as has 40 lines"
    assert failed("# frame_3/DoAction.as:12, 41") == [
        f"scripts/x.gd:1: frame_3/DoAction.as:12, 41 names line 41, {has}"
    ]


def test_each_failure_names_the_line_of_its_comment():
    text = (
        "extends Node\n# frame_1/DoAction.as:2\n\nvar x := 1  # frame_9/DoAction.as\n"
    )
    assert failures(read_citations(text, "scripts/y.gd"), LINES) == [
        "scripts/y.gd:4: frame_9/DoAction.as names no export file"
    ]


def test_line_counts_come_from_the_script_records():
    records = load()
    counts = line_counts(records)
    scripts = [r for r in records if r["kind"] == "script"]
    assert len(counts) == len(scripts) > 800
    assert all(counts[r["file"]] == r["lines"] for r in scripts)


def test_every_citation_in_the_tracked_gd_files_passes():
    cited = tracked_citations()
    assert len(cited) > 300
    assert failures(cited, line_counts(load())) == []


def test_main_with_no_file_checks_the_tracked_gd_files(capsys):
    assert main([]) == 0
    assert capsys.readouterr().err == ""


def test_main_checks_the_files_it_is_given_and_prints_each_failure(tmp_path, capsys):
    good = tmp_path / "good.gd"
    good.write_text("# frame_42/DoAction_8.as:82\n")
    bad = tmp_path / "bad.gd"
    bad.write_text("# frame_42/DoAction_8.as:82\n# frame_42/DoAction_88.as:1\n")
    assert main([str(good)]) == 0
    assert capsys.readouterr().err == ""
    assert main([str(good), str(bad)]) == 1
    printed = capsys.readouterr().err.splitlines()
    assert printed[0] == f"{bad}:2: frame_42/DoAction_88.as:1 names no export file"
    assert "uv run as_lookup" in printed[-1]
    assert len(printed) == 2
