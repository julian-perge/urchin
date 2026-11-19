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
