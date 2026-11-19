# extract_krin_settings's reading of krinMelee's and krinBoltMake's settings, on
# the original's own committed ActionScript and on scripts written by hand, so
# no test needs the gitignored SWF.
from __future__ import annotations

import pytest
from urchin_dev.swf.extract import krin_settings


def test_the_original_sets_the_bolt_and_melee_numbers_of_frame_42():
    # The script writes krinBoltIncrease as 1.1500000000000001, which is the
    # double just above 1.15, and the port keeps that double.
    assert krin_settings.settings(krin_settings.SCRIPT.read_text()) == {
        "krinBodyMove": 10,
        "krinBoltIncrease": 1.1500000000000001,
        "krinBoltSpeed": 1,
        "krinBoltTime": 60,
        "krinMeleeAttackCD": 15,
        "krinMeleeAttackEndCD": 15,
    }


def test_a_setting_the_script_does_not_set_is_refused():
    script = "krinBoltTime = 60;\nkrinBoltSpeed = 1;\n"
    with pytest.raises(RuntimeError, match="krinBoltIncrease: 0 matches"):
        krin_settings.settings(script)


def test_a_setting_the_script_sets_twice_is_refused():
    # The port reads one value, so a second one would be lost without a word.
    script = "".join(f"{name} = 1;\n" for name in krin_settings.NAMES)
    script += "krinBoltTime = 30;\n"
    with pytest.raises(RuntimeError, match="krinBoltTime: 2 matches"):
        krin_settings.settings(script)


def test_a_setting_inside_a_function_is_not_read():
    # Only the frame's own top-level lines set _root's value once, when the
    # frame runs. An indented line runs only when its function is called.
    script = "".join(f"{name} = 1;\n" for name in krin_settings.NAMES)
    script += "function f()\n{\n   krinBoltTime = 30;\n}\n"
    assert krin_settings.settings(script)["krinBoltTime"] == 1


def test_the_original_writes_the_bolt_and_melee_literals_inside_its_functions():
    # krinMelee writes its coefficients, their cap and its home tolerance at
    # lines 102-117, and krinBoltMake writes its trail growth and miss bound at
    # lines 200-209.
    assert krin_settings.literals(krin_settings.SCRIPT.read_text()) == {
        "krinBoltMissX": 500,
        "krinBoltTrailGrowth": 8.3,
        "krinMeleeDashBase": 1.5,
        "krinMeleeDashSlope": 1.45,
        "krinMeleeHomeTolerance": 0.000001,
        "krinMeleeRunbackSlope": 1.45,
        "krinMeleeStepCap": 1,
    }


def _original_with(old: str, new: str) -> str:
    text = krin_settings.SCRIPT.read_text()
    assert old in text
    return text.replace(old, new, 1)


def test_two_trail_growth_lines_that_disagree_are_refused():
    # The port grows the trail by one number before and after the crossing, so
    # a second number would be lost without a word.
    script = _original_with("_xscale += 8.3", "_xscale += 9.3")
    with pytest.raises(
        RuntimeError, match="krinBoltTrailGrowth: the script writes 8.3 and 9.3"
    ):
        krin_settings.literals(script)


def test_a_miss_bound_that_differs_on_each_side_is_refused():
    script = _original_with("this._x < -500", "this._x < -400")
    with pytest.raises(
        RuntimeError, match="krinBoltMissX: the script writes 400 and 500"
    ):
        krin_settings.literals(script)


def test_a_cap_that_differs_from_the_value_it_sets_is_refused():
    script = _original_with("this.spdXCoEFFER = 1;", "this.spdXCoEFFER = 0.9;")
    with pytest.raises(
        RuntimeError, match="krinMeleeStepCap: the script writes 0.9 and 1"
    ):
        krin_settings.literals(script)


def test_a_literal_the_script_does_not_write_is_refused():
    script = _original_with(
        "this.relX * this.faceing <= 0.000001", "this.relX * this.faceing < 0.000001"
    )
    with pytest.raises(RuntimeError, match="krinMeleeHomeTolerance: 0 matches"):
        krin_settings.literals(script)


def test_one_number_written_two_ways_is_read_once():
    # The two lines of the cap agree when they write the same number, even as
    # different text.
    script = _original_with("this.spdXCoEFFER = 1;", "this.spdXCoEFFER = 1.0;")
    assert krin_settings.literals(script)["krinMeleeStepCap"] == 1
