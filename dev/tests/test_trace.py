# Tests trace.py with probe files and Trace logs in a temporary folder, and
# with the goto Probe of dev/probes/. No SWF, ffdec or player is needed.
from __future__ import annotations

import re

import pytest
from urchin_dev.swf.trace import (
    PROBES,
    DiffRecord,
    Goto,
    diff,
    diff_main,
    parse,
    read_probes,
    with_probes,
)


def test_with_probes_puts_the_probes_first_in_name_order_and_keeps_the_frame_script(
    tmp_path,
):
    (tmp_path / "b_second.as").write_text("trace(2);")
    (tmp_path / "a_first.as").write_text("trace(1);\n\n")
    (tmp_path / "notes.txt").write_text("not a probe")
    frame_script = "var x = 1;\r\nStage.showMenu = false();\r\n"

    result = with_probes(frame_script, read_probes(tmp_path))

    assert result.endswith(frame_script)
    assert result.removesuffix(frame_script) == "trace(1);\ntrace(2);\n"


FLASH_LOG = (
    "Warning: false is not a function\r\n"
    "HOOK\tinstalled\ttrue\r\n"
    "GOTO\tstop\t_level0.__t\t1\t0\t1\t0\r\n"
    "swf Bridge Made: [object Object]\r\n"
    "GOTO\tplay\t_level0.BATTLESCREEN.instance12\t40\t3\tWHITE NOVEMBER\t17\r\n"
)

# A guess at Ruffle's stderr: a prefix, then the same tabs. The first Ruffle
# log replaces these lines.
RUFFLE_LOG = (
    "2026-11-16T10:00:00Z  INFO avm_trace: HOOK\tinstalled\ttrue\n"
    "2026-11-16T10:00:01Z  INFO avm_trace: GOTO\tstop\t_level0.__t\t1\t1\t1\t1\n"
    "2026-11-16T10:00:02Z  WARN ruffle_core: GOTO is not followed by a tab here\n"
)


def test_parse_returns_one_record_for_each_goto_line_of_a_flash_log():
    assert parse(FLASH_LOG) == [
        Goto("stop", "_level0.__t", 1, 0, "1", 0),
        Goto("play", "_level0.BATTLESCREEN.instance12", 40, 3, "WHITE NOVEMBER", 17),
    ]


def test_parse_reads_a_goto_line_behind_a_ruffle_prefix():
    assert parse(RUFFLE_LOG) == [Goto("stop", "_level0.__t", 1, 1, "1", 1)]


def test_parse_names_the_line_number_of_a_goto_line_with_a_missing_field():
    log = "HOOK\tinstalled\ttrue\nGOTO\tstop\t_level0.__t\t1\t0\t1\t0\nGOTO\tstop\t_level0.__t\t1\t0\t1\n"

    with pytest.raises(ValueError, match="line 3"):
        parse(log)


def test_parse_names_the_line_number_of_a_goto_line_with_a_frame_that_is_no_number():
    with pytest.raises(ValueError, match="line 1"):
        parse("GOTO\tstop\t_level0.__t\t1\tundefined\t1\t0\n")


def test_diff_ignores_the_order_and_the_count_of_the_gotos():
    hall = Goto("stop", "_level0.BATTLESCREEN", 20, 1, "JAIL", 15)
    hub = Goto("stop", "_level0.KrinScreen", 9, 1, "PRISON", 1)

    assert diff([hall, hub, hall], [hub, hall]) == ([], [])


def test_diff_shows_a_goto_of_one_log_on_that_side_only():
    hall = Goto("stop", "_level0.BATTLESCREEN", 20, 1, "JAIL", 15)
    hub = Goto("stop", "_level0.KrinScreen", 9, 1, "PRISON", 1)
    sky = Goto("stop", "_level0.instance3", 18, 1, "JAIL", 14)

    assert diff([hall, hub], [sky, hall]) == (
        [DiffRecord("stop", "_level0.KrinScreen", 9, "PRISON", False)],
        [DiffRecord("stop", "_level0.instance3", 18, "JAIL", True)],
    )


def test_diff_marks_a_goto_as_moved_when_one_occurrence_of_several_changed_the_frame():
    stayed = Goto("stop", "_level0.BATTLESCREEN", 20, 15, "JAIL", 15)
    moved = Goto("stop", "_level0.BATTLESCREEN", 20, 1, "JAIL", 15)

    assert diff([stayed, moved, stayed], [stayed]) == (
        [DiffRecord("stop", "_level0.BATTLESCREEN", 20, "JAIL", True)],
        [DiffRecord("stop", "_level0.BATTLESCREEN", 20, "JAIL", False)],
    )


def test_trace_diff_prints_no_record_for_the_same_gotos_in_another_order_and_count(
    tmp_path, capsys
):
    log_a = tmp_path / "a.txt"
    log_b = tmp_path / "b.txt"
    log_a.write_text(FLASH_LOG + "GOTO\tstop\t_level0.__t\t1\t0\t1\t0\r\n", newline="")
    log_b.write_text("".join(reversed(FLASH_LOG.splitlines(keepends=True))), newline="")

    diff_main([str(log_a), str(log_b)])

    assert capsys.readouterr().out == f"only in {log_a} (0):\nonly in {log_b} (0):\n"


def test_trace_diff_prints_the_records_of_each_side_sorted(tmp_path, capsys):
    log_a = tmp_path / "a.txt"
    log_b = tmp_path / "b.txt"
    log_a.write_text(
        "GOTO\tstop\t_level0.b\t5\t1\tEND\t5\nGOTO\tplay\t_level0.a\t5\t2\tNONE\t2\n"
    )
    log_b.write_text("GOTO\tstop\t_level0.c\t7\t1\t3\t3\n")

    diff_main([str(log_a), str(log_b)])

    assert capsys.readouterr().out == (
        f"only in {log_a} (2):\n"
        "play\t_level0.a\t5\tNONE\tstayed\n"
        "stop\t_level0.b\t5\tEND\tmoved\n"
        f"only in {log_b} (1):\n"
        "stop\t_level0.c\t7\t3\tmoved\n"
    )


def test_the_goto_probe_traces_its_fields_in_the_order_parse_reads():
    probe = (PROBES / "goto.as").read_text(encoding="utf-8")
    call = re.search(r'trace\("GOTO\\t" \+ (.+)\);', probe)
    values = {
        "kind": "stop",
        "mc": "_level0.clip",
        "mc._totalframes": "7",
        "from": "3",
        "target": "LABEL",
        "mc._currentframe": "5",
    }
    line = "GOTO\t" + "\t".join(
        values[expression] for expression in call.group(1).split(' + "\\t" + ')
    )

    assert parse(line) == [Goto("stop", "_level0.clip", 7, 3, "LABEL", 5)]
