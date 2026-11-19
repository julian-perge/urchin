# extract_hint_steps's reading of the hint box's scripts, on plain data, so no
# test needs the gitignored SWF.
from __future__ import annotations

import pytest
from urchin_dev.swf.extract import hint_steps
from urchin_dev.swf.extract.hint_steps import Jump

# The labels of DefineSprite 3059 and the frame scripts that jump back to them.
LABELS = {"stable": 1, "level": 7, "part1": 12, "part2": 56, "part3": 107, "part4": 151}
JUMPS = {55: Jump("part1", True), 106: Jump("part2", True), 150: Jump("part3", True)}


def test_a_label_that_jumps_back_to_itself_loops_up_to_that_script():
    shown = hint_steps.label_frames(LABELS, JUMPS, 163)
    assert shown["part1"] == list(range(12, 55))
    assert shown["part2"] == list(range(56, 106))
    assert shown["part3"] == list(range(107, 150))


def test_a_label_with_no_jump_back_holds_still_on_its_frame():
    shown = hint_steps.label_frames(LABELS, JUMPS, 163)
    assert shown["stable"] == [1]
    assert shown["level"] == [7]
    assert shown["part4"] == [151]


@pytest.mark.parametrize(
    "jump, refusal",
    [
        (Jump("part2", True), "jumps to 'part2' and plays"),
        (Jump("part1", False), "jumps to 'part1', where"),
    ],
    ids=["a jump to another label", "a jump back without play()"],
)
def test_a_label_that_does_not_loop_back_to_itself_is_refused(jump, refusal):
    with pytest.raises(RuntimeError, match=refusal):
        hint_steps.label_frames(LABELS, {**JUMPS, 55: jump}, 163)


def test_a_step_reads_its_reader_and_clicker_menu_indices():
    assert hint_steps.step_strings(["reader", "clicker"], [8, 11]) == (8, 11)


@pytest.mark.parametrize(
    "targets, numbers",
    [
        (["clicker", "reader"], [8, 11]),
        (["reader"], [8]),
        (["reader", "clicker"], [8, 11, 2]),
    ],
    ids=["the wrong order", "no clicker", "a third number"],
)
def test_a_step_script_that_sets_anything_else_is_refused(targets, numbers):
    with pytest.raises(RuntimeError, match="where a step sets reader and then clicker"):
        hint_steps.step_strings(targets, numbers)


def test_a_step_index_that_is_no_whole_number_is_refused():
    with pytest.raises(RuntimeError, match="not MENU indices"):
        hint_steps.step_strings(["reader", "clicker"], [8.5, 11])


def test_the_resting_frame_reads_its_first_tip_and_the_tip_count():
    assert hint_steps.tip_strings(["picker", "reader"], [43, 4]) == (43, 4)


def test_a_resting_frame_that_does_not_pick_a_tip_is_refused():
    with pytest.raises(RuntimeError, match="sets it to MENU|sets reader to MENU"):
        hint_steps.tip_strings(["picker"], [43, 4])
