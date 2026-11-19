# convert_starting_state's reading of equipArray0 and StatSets0. The samples
# copy the statement shapes of frame_42/DoAction_17.as and frame_180/DoAction.as
# with other numbers, so a test passes only when the parser reads each number
# from its own statement.
from __future__ import annotations

import pytest
from urchin_dev.convert import starting_state

SAMPLE = """Krin.NameSets[0] = "Sonny";
Krin.equipArray0 = [0,12,0,3,9,6,0];
Krin.StatSets0 = [1,2,3,4,0];
Krin.equipArray1 = [38,34,36,35,37,39,0];
Krin.StatSets1 = [9,12,11,9,0];
"""


def test_reads_only_sonnys_gear_and_allocation():
    state = starting_state.parse_state(SAMPLE, "frame_x/DoAction.as")
    assert state == {
        "source": "frame_x/DoAction.as",
        "equip": [0, 12, 0, 3, 9, 6, 0],
        "stat_allocation": [1, 2, 3, 4, 0],
    }


def test_refuses_a_script_that_sets_the_gear_twice():
    with pytest.raises(ValueError, match="2 statements set Krin.equipArray0"):
        starting_state.parse_state(
            SAMPLE + "Krin.equipArray0 = [0,0,0,0,0,0,0];\n", "x"
        )


def test_refuses_a_script_with_no_allocation():
    with pytest.raises(ValueError, match="0 statements set Krin.StatSets0"):
        starting_state.parse_state(SAMPLE.replace("Krin.StatSets0", "Krin.Other"), "x")


def test_refuses_gear_of_the_wrong_length():
    with pytest.raises(ValueError, match="6 entries, not 7"):
        starting_state.parse_state(
            SAMPLE.replace("[0,12,0,3,9,6,0]", "[0,12,0,3,9,6]"), "x"
        )


def test_reads_both_frames(tmp_path):
    for path in starting_state.SOURCES.values():
        (tmp_path / path).parent.mkdir(parents=True, exist_ok=True)
        (tmp_path / path).write_text(SAMPLE, encoding="utf-8")
    state = starting_state.convert(tmp_path)
    assert list(state) == ["before_story", "story"]
    assert state["story"]["source"] == "frame_180/DoAction.as"
