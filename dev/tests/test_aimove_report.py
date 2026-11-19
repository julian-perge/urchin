# Tests aimove_report.py with AIMOVE lines written here, and checks the
# committed AIMOVE logs in references/traced_runs/. No SWF or player is needed.
from __future__ import annotations

import pytest
from urchin_dev.swf.aimove_report import Outcome, count, main, outcome, parse
from urchin_dev.swf.trace import TRACED_RUNS

ENTRY = "fc=80\tpfc=2\tfm=false\tnlk=4\tae=[6 4 2]\tcf1=1\tD=1,1,0"


def line(number, caster, absolute, real, replays, battle="212"):
    groups = {
        "none": real,
        "all": real,
        "focus": real,
        "fmove": real,
        "darr": real,
        "alive": real,
        "lock": real,
    }
    groups.update(replays)
    tail = "\t".join(f"{key}={value}" for key, value in groups.items())
    return f"INFO avm_trace: AIMOVE\t{number}\t{battle}\t2\t{caster}\t6\t{str(absolute).lower()}\t{ENTRY}\treal={real}\t{tail}"


def test_parse_reads_the_fields_by_key():
    calls = parse("noise\n" + line(9, "4", True, "550>6>h6", {}))
    assert len(calls) == 1
    assert calls[0].caster == "4"
    assert calls[0].absolute
    assert calls[0].fields["ae"] == "[6 4 2]"
    assert calls[0].fields["real"] == "550>6>h6"


def test_outcome_maps_the_fallback_to_the_caster_and_drops_the_false_key():
    assert outcome("550>undefined>hfalse", "4") == Outcome("550", "4", "")
    assert outcome("532>1>", "2") == Outcome("532", "1", "")


def test_a_call_that_the_stale_lists_retarget_counts_as_changed():
    text = "\n".join(
        [
            line(1, "6", False, "548>1>", {}),
            line(
                2,
                "4",
                True,
                "550>6>h6",
                {"all": "550>undefined>hfalse", "darr": "550>4>hfalse"},
            ),
        ]
    )
    counts = count(parse(text))["212"]
    assert counts["calls"] == 2
    assert counts["changed"] == 1
    assert counts["changed_target"] == 1
    assert counts["by_darr"] == 1
    assert counts["lists_from_other_unit"] == 1
    assert counts["fallback"] == 0


def test_a_fallback_onto_the_caster_matches_the_port():
    replays = {"all": "531>undefined>", "alive": "531>undefined>"}
    counts = count(parse(line(1, "2", True, "531>2>", replays, battle="109")))["109"]
    assert counts["fallback"] == 1
    assert counts["fallback_not_caster"] == 0
    assert counts["changed"] == 0


def test_a_fallback_onto_another_slot_is_a_change():
    replays = {"all": "531>undefined>", "alive": "531>undefined>"}
    counts = count(parse(line(1, "2", True, "531>4>", replays)))["212"]
    assert counts["fallback_not_caster"] == 1
    assert counts["changed"] == 1
    assert counts["by_alive"] == 1


def test_a_replay_that_differs_from_the_real_call_is_counted():
    counts = count(parse(line(1, "2", True, "531>2>", {"none": "531>3>"})))["212"]
    assert counts["replay_mismatch"] == 1


def test_main_needs_a_log(tmp_path):
    with pytest.raises(SystemExit):
        main([])
    with pytest.raises(SystemExit):
        main([str(tmp_path / "missing.txt")])


@pytest.mark.parametrize(
    ("name", "changed"),
    [("aimove_web_ruffle.txt", {"212": 8}), ("aimove_web_flash.txt", {"212": 8})],
)
def test_the_committed_logs_give_the_changed_calls_in_decoded_algorithms(name, changed):
    # DECODED_ALGORITHMS.md, "Left-behind globals in AImoveAdder", cites these
    # counts, and every changed call there is the Medic's Med Buff 1 target.
    counts = count(parse((TRACED_RUNS / name).read_text(encoding="utf-8")))
    assert {
        battle: c["changed"] for battle, c in counts.items() if c["changed"]
    } == changed
    assert all(c["changed"] == c["changed_target"] for c in counts.values())


@pytest.mark.parametrize("name", ["aimove_web_ruffle.txt", "aimove_web_flash.txt"])
def test_every_committed_replay_with_nothing_reset_matches_the_real_call(name):
    calls = parse((TRACED_RUNS / name).read_text(encoding="utf-8"))
    assert calls
    assert all(counts["replay_mismatch"] == 0 for counts in count(calls).values())
