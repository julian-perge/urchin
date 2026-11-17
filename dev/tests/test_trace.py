# Tests trace.py with probe files and Trace logs in a temporary folder, and
# with the goto Probe of dev/probes/. No SWF, ffdec or player is needed.
#
# The last tests check the committed Trace logs in references/traced_runs/.
# Each hub, hall and sky goto of a log must go to the label that battles.json
# or Krin.zoneName gives for the route, that label must be one the matching
# goto record of label_xref.json selects, and in a web log the clip must land
# on that label's frame. Every label and frame comes from those files and the
# tracked export, so the test reads no SWF and no XML dump.
from __future__ import annotations

import json
import re

import pytest
from urchin_dev import ACTION_SCRIPT, CONVERTED_JSON
from urchin_dev.swf.label_xref import load_value_sets
from urchin_dev.swf.trace import (
    HOOK_LINE,
    PROBES,
    TRACED_RUNS,
    DiffRecord,
    Goto,
    diff,
    diff_main,
    parse,
    play_flash,
    play_ruffle,
    preflight,
    read_probes,
    report,
    run_main,
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

# Three lines of references/traced_runs/web_ruffle.txt as Ruffle 0.7.1 wrote
# them: a prefix with colour codes, then the same tabs as a Flash line.
RUFFLE_LOG = (
    "\x1b[2m2026-11-17T07:10:00.045621Z\x1b[0m \x1b[32m INFO\x1b[0m"
    " \x1b[2mavm_trace\x1b[0m\x1b[2m:\x1b[0m HOOK\tinstalled\ttrue\n"
    "\x1b[2m2026-11-17T07:10:00.049162Z\x1b[0m \x1b[33m WARN\x1b[0m"
    " \x1b[2mruffle_core::avm1::fscommand\x1b[0m\x1b[2m:\x1b[0m"
    " Unhandled FSCommand: showMenu\n"
    "\x1b[2m2026-11-17T07:10:33.744921Z\x1b[0m \x1b[32m INFO\x1b[0m"
    " \x1b[2mavm_trace\x1b[0m\x1b[2m:\x1b[0m"
    " GOTO\tstop\t_level0.BATTLESCREEN\t145\t1\tJAIL\t15\n"
)


def test_parse_returns_one_record_for_each_goto_line_of_a_flash_log():
    assert parse(FLASH_LOG) == [
        Goto("stop", "_level0.__t", 1, 0, "1", 0),
        Goto("play", "_level0.BATTLESCREEN.instance12", 40, 3, "WHITE NOVEMBER", 17),
    ]


def test_parse_reads_a_goto_line_behind_a_ruffle_prefix():
    assert parse(RUFFLE_LOG) == [
        Goto("stop", "_level0.BATTLESCREEN", 145, 1, "JAIL", 15)
    ]


def test_parse_names_the_line_number_of_a_goto_line_with_a_missing_field():
    log = "HOOK\tinstalled\ttrue\nGOTO\tstop\t_level0.__t\t1\t0\t1\t0\nGOTO\tstop\t_level0.__t\t1\t0\t1\n"

    with pytest.raises(ValueError, match="line 3"):
        parse(log)


def test_parse_names_the_line_number_of_a_goto_line_with_a_frame_that_is_no_number():
    with pytest.raises(ValueError, match="line 1"):
        parse("GOTO\tstop\t_level0.__t\t1\tundefined\t1\t0\n")


def test_parse_reads_from_the_first_goto_mark_when_the_target_is_the_label_goto():
    assert parse("GOTO\tstop\t_level0.c\t5\t1\tGOTO\t1\n") == [
        Goto("stop", "_level0.c", 5, 1, "GOTO", 1)
    ]


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
        "GOTO\tstop\t_level0.b\t5\t1\tEND\t5\n"
        "GOTO\tplay\t_level0.a\t5\t2\tNONE\t2\n"
        "GOTO\tstop\t_level0.a\t9\t1\tEND\t4\n"
        "GOTO\tplay\t_level0.d\t3\t1\t2\t2\n"
        "GOTO\tplay\t_level0.a\t4\t1\tNONE\t1\n"
    )
    log_b.write_text("GOTO\tstop\t_level0.c\t7\t1\t3\t3\n")

    diff_main([str(log_a), str(log_b)])

    assert capsys.readouterr().out == (
        f"only in {log_a} (5):\n"
        "play\t_level0.a\t4\tNONE\tstayed\n"
        "play\t_level0.a\t5\tNONE\tstayed\n"
        "play\t_level0.d\t3\t2\tmoved\n"
        "stop\t_level0.a\t9\tEND\tmoved\n"
        "stop\t_level0.b\t5\tEND\tmoved\n"
        f"only in {log_b} (1):\n"
        "stop\t_level0.c\t7\t3\tmoved\n"
    )


def test_trace_diff_exits_1_and_names_a_log_that_does_not_exist(tmp_path):
    log_a = tmp_path / "a.txt"
    log_a.write_text(FLASH_LOG, newline="")
    absent = tmp_path / "absent.txt"

    with pytest.raises(SystemExit) as exit_info:
        diff_main([str(log_a), str(absent)])

    assert exit_info.value.code == f"error: no Trace log at {absent}."


def test_trace_diff_exits_1_and_names_the_log_and_the_line_of_a_bad_goto_line(tmp_path):
    log_a = tmp_path / "a.txt"
    log_b = tmp_path / "b.txt"
    log_a.write_text(FLASH_LOG, newline="")
    log_b.write_text("HOOK\tinstalled\ttrue\nGOTO\tstop\t_level0.c\t5\t1\tEND\n")

    with pytest.raises(SystemExit) as exit_info:
        diff_main([str(log_a), str(log_b)])

    assert str(exit_info.value.code).startswith(f"error: {log_b}: line 2: ")


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


def fake_player(path, body):
    """Write an executable shell script that stands in for a player binary."""
    path.write_text(f"#!/bin/sh\n{body}\n")
    path.chmod(0o755)
    return path


def test_preflight_stops_on_an_os_other_than_macos(tmp_path):
    binary = fake_player(tmp_path / "player", "exit 0")

    with pytest.raises(SystemExit) as stop:
        preflight("ruffle", platform="linux", binary=binary, mm_cfg=tmp_path / "mm.cfg")

    assert stop.value.code == "error: trace-run needs macOS. This OS is linux."


def test_preflight_stops_and_names_a_player_binary_that_does_not_exist(tmp_path):
    binary = tmp_path / "no_player"

    with pytest.raises(SystemExit) as stop:
        preflight(
            "ruffle", platform="darwin", binary=binary, mm_cfg=tmp_path / "mm.cfg"
        )

    assert stop.value.code == f"error: no ruffle player at {binary}. Set RUFFLE_BIN."


def test_preflight_stops_for_flash_when_mm_cfg_does_not_turn_the_trace_file_on(
    tmp_path,
):
    binary = fake_player(tmp_path / "player", "exit 0")
    mm_cfg = tmp_path / "mm.cfg"
    mm_cfg.write_text("ErrorReportingEnable=1\nTraceOutputFileEnable=0\n")

    with pytest.raises(SystemExit) as stop:
        preflight("flash", platform="darwin", binary=binary, mm_cfg=mm_cfg)

    assert stop.value.code == (
        f"error: {mm_cfg} does not have TraceOutputFileEnable=1, "
        "so the debug player writes no flashlog.txt. Add that line."
    )


def test_preflight_stops_for_flash_when_mm_cfg_does_not_exist(tmp_path):
    binary = fake_player(tmp_path / "player", "exit 0")

    with pytest.raises(SystemExit) as stop:
        preflight("flash", platform="darwin", binary=binary, mm_cfg=tmp_path / "mm.cfg")

    assert "does not have TraceOutputFileEnable=1" in stop.value.code


def test_preflight_passes_for_flash_with_the_trace_file_on_and_for_ruffle_with_no_mm_cfg(
    tmp_path,
):
    binary = fake_player(tmp_path / "player", "exit 0")
    mm_cfg = tmp_path / "mm.cfg"
    mm_cfg.write_text("ErrorReportingEnable=1\r\n TraceOutputFileEnable=1 \r\n")

    preflight("flash", platform="darwin", binary=binary, mm_cfg=mm_cfg)
    preflight("ruffle", platform="darwin", binary=binary, mm_cfg=tmp_path / "none")


def test_play_flash_gives_the_player_the_traced_copy_and_saves_its_flashlog(tmp_path):
    flashlog = tmp_path / "Logs" / "flashlog.txt"
    flashlog.parent.mkdir()
    flashlog.write_bytes(b"the log of an older launch\r\n")
    traced = tmp_path / "traced" / "sonny-2-2900.swf"
    binary = fake_player(
        tmp_path / "player", f"printf 'opened %s\\r\\n' \"$1\" > '{flashlog}'"
    )
    dest = tmp_path / "runs" / "web_flash.txt"
    dest.parent.mkdir()
    dest.write_text("the log of an older run")

    play_flash(binary, traced, flashlog, dest)

    assert dest.read_bytes() == f"opened {traced}\r\n".encode()


def test_play_flash_stops_when_the_player_wrote_no_flashlog(tmp_path):
    flashlog = tmp_path / "flashlog.txt"
    flashlog.write_text("the log of an older launch")
    binary = fake_player(tmp_path / "player", "exit 0")
    dest = tmp_path / "web_flash.txt"

    with pytest.raises(SystemExit) as stop:
        play_flash(binary, tmp_path / "x.swf", flashlog, dest)

    assert stop.value.code == f"error: the player wrote no log at {flashlog}."
    assert not dest.exists()


def test_play_flash_saves_the_log_of_a_player_that_was_killed(tmp_path):
    flashlog = tmp_path / "flashlog.txt"
    binary = fake_player(tmp_path / "player", f"echo HOOK > '{flashlog}'; kill -9 $$")
    dest = tmp_path / "web_flash.txt"

    play_flash(binary, tmp_path / "x.swf", flashlog, dest)

    assert dest.read_text() == "HOOK\n"


def test_play_ruffle_opens_a_copy_in_the_container_and_saves_its_stdout_and_stderr(
    tmp_path,
):
    traced = tmp_path / "traced" / "SONNY2.swf"
    traced.parent.mkdir()
    traced.write_bytes(b"swf bytes")
    container = tmp_path / "Data" / "urchin_traced"
    binary = fake_player(
        tmp_path / "player",
        'echo "INFO avm_trace: on stdout"; echo "opened $1 with $(cat "$1")" >&2; exit 3',
    )
    dest = tmp_path / "steam_ruffle.txt"
    dest.write_text("the log of an older run, which is longer than the new one" * 9)

    play_ruffle(binary, traced, container, dest)

    assert dest.read_text() == (
        f"INFO avm_trace: on stdout\nopened {container / 'SONNY2.swf'} with swf bytes\n"
    )


def test_report_prints_the_number_of_goto_lines(tmp_path, capsys):
    log = tmp_path / "web_flash.txt"
    log.write_bytes(FLASH_LOG.encode())

    report(log)

    assert capsys.readouterr().out == f"{log}: 2 GOTO lines\n"


def test_report_reads_the_hook_line_behind_a_ruffle_prefix(tmp_path, capsys):
    log = tmp_path / "web_ruffle.txt"
    log.write_text("2026-11-17 INFO avm_trace: HOOK\tinstalled\ttrue\n")

    report(log)

    assert capsys.readouterr().out == f"{log}: 0 GOTO lines\n"


@pytest.mark.parametrize(
    "hook_line", ["", "HOOK\tinstalled\tfalse\r\n", "HOOK installed true\r\n"]
)
def test_report_prints_the_count_then_exits_1_for_a_log_with_no_hook_line(
    tmp_path, capsys, hook_line
):
    log = tmp_path / "web_flash.txt"
    log.write_text(hook_line + "GOTO\tstop\t_level0.__t\t1\t0\t1\t0\r\n")

    with pytest.raises(SystemExit) as stop:
        report(log)

    assert capsys.readouterr().out == f"{log}: 1 GOTO lines\n"
    assert stop.value.code == (
        f"error: {log} has no HOOK<tab>installed<tab>true line, "
        "so the goto Probe did not install."
    )


@pytest.mark.parametrize(
    "args",
    [[], ["web"], ["web", "vlc"], ["zip", "flash"], ["web", "flash", "--tutorial"]],
)
def test_trace_run_exits_with_its_usage_for_wrong_arguments(args):
    with pytest.raises(SystemExit) as stop:
        run_main(args)

    assert stop.value.code == "usage: trace_run <web|steam> <flash|ruffle>"


# The route of each Traced run: the battles it fights, in order, and the zone
# of the hub it ends on. spec/5-trace-the-original.md gives the route.
RUNS = {
    "web_flash": (2, 100),
    "steam_flash": (2, 100),
    "web_ruffle": (100,),
    "steam_ruffle": (100,),
}
HUB_ZONE = 1

# A run whose Trace log is not committed, with the URL of the #5 comment that
# records where the run stopped. Add a run here only when that comment exists.
MISSING: dict[str, str] = {}
MISSING_COMMENT = re.compile(
    r"https://github\.com/julian-perge/urchin/issues/5#issuecomment-\d+"
)

HALL_CLIP = "_level0.BATTLESCREEN"
HUB_CLIP = "_level0.KrinScreen"
# The sky clip has no instance name, so the player names it instanceN.
SKY_CLIP = re.compile(r"_level0\.instance\d+")


@pytest.fixture(scope="module")
def xref():
    return json.loads((CONVERTED_JSON / "label_xref.json").read_text())


@pytest.fixture(scope="module")
def route_labels():
    """-> {value set name: {battle id or zone index: label}}."""
    values = load_value_sets(ACTION_SCRIPT, CONVERTED_JSON / "battles.json")
    return {
        name: dict(values[name])
        for name in ("zone_background", "sky_background", "zone_name")
    }


def folded(labels):
    return [label.casefold() for label in labels]


def read_log(run):
    log = TRACED_RUNS / f"{run}.txt"
    if not log.is_file():
        assert run in MISSING, f"no Trace log at {log}, and MISSING does not list {run}"
        pytest.skip(f"{run} is in MISSING: {MISSING[run]}")
    return log.read_text(encoding="utf-8")


def route_gotos(gotos, xref):
    """-> {value set name: the gotos of the log that select from it, in order}."""
    sky_sprite = xref["value_sets"]["sky_background"]["sprite"]
    sky_labels = {
        label["label"].casefold()
        for label in xref["labels"]
        if label["sprite"] == sky_sprite
    }
    return {
        "zone_background": [goto for goto in gotos if goto.clip == HALL_CLIP],
        "sky_background": [
            goto
            for goto in gotos
            if goto.kind == "stop"
            and SKY_CLIP.fullmatch(goto.clip)
            and goto.target.casefold() in sky_labels
        ],
        "zone_name": [goto for goto in gotos if goto.clip == HUB_CLIP],
    }


def test_every_missing_trace_log_names_a_run_and_its_comment_on_issue_5():
    for run, url in MISSING.items():
        assert run in RUNS
        assert MISSING_COMMENT.fullmatch(url), f"{run}: {url}"


@pytest.mark.parametrize("run", RUNS)
def test_the_trace_log_has_the_hook_line(run):
    lines = read_log(run).splitlines()

    assert any(HOOK_LINE in line for line in lines), f"{run} has no HOOK line"


@pytest.mark.parametrize("run", RUNS)
def test_the_hall_and_sky_gotos_go_to_the_labels_of_the_run_battles(
    run, xref, route_labels
):
    gotos = route_gotos(parse(read_log(run)), xref)

    for name in ("zone_background", "sky_background"):
        expected = [route_labels[name][battle] for battle in RUNS[run]]
        assert folded(goto.target for goto in gotos[name]) == folded(expected), name


@pytest.mark.parametrize("run", RUNS)
def test_every_hub_goto_goes_to_the_name_of_the_hub_zone(run, xref, route_labels):
    hub = route_gotos(parse(read_log(run)), xref)["zone_name"]

    assert hub
    assert set(folded(goto.target for goto in hub)) == {
        route_labels["zone_name"][HUB_ZONE].casefold()
    }


@pytest.mark.parametrize("run", RUNS)
def test_each_route_target_is_selected_by_the_goto_record_of_its_value_set(run, xref):
    for name, gotos in route_gotos(parse(read_log(run)), xref).items():
        (record,) = [goto for goto in xref["gotos"] if goto.get("via") == name]
        selects = set(folded(label for _sprite, label in record["selects"]))
        for goto in gotos:
            assert goto.target.casefold() in selects, (name, goto)


@pytest.mark.parametrize("run", [run for run in RUNS if run.startswith("web_")])
def test_each_route_goto_of_a_web_log_lands_on_the_frame_of_its_label(run, xref):
    for name, gotos in route_gotos(parse(read_log(run)), xref).items():
        sprite = xref["value_sets"][name]["sprite"]
        frames = {
            label["label"].casefold(): label["frame"]
            for label in xref["labels"]
            if label["sprite"] == sprite
        }
        for goto in gotos:
            assert goto.after == frames[goto.target.casefold()], (name, goto)
