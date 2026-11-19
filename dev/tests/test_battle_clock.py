"""The battle clock's hands, as extract_battle_screen reads them from the
ActionScript export. These read the scripts in dev/source_files and never the
SWF."""

from __future__ import annotations

import pytest
from urchin_dev.swf.extract import battle_screen

HAND_2 = """onClipEvent(enterFrame){
   this._rotation = -180 + 180 * (_root.BattleTimeNow / (_root.BattleTimeLimit / 2));
   if(this._rotation >= 0)
   {
      _rotation = 0;
   }
}"""


def test_each_hand_clamps_the_other_way():
    assert battle_screen.hand_clamps() == {2: ">=", 6: "<"}


def test_hand_clamp_refuses_a_script_with_another_angle():
    with pytest.raises(RuntimeError, match="not the angle"):
        battle_screen.hand_clamp(HAND_2.replace("-180 +", "-90 +"))


# A Traced run in Flash Player 14 set BattleTimeNow to these values with
# BattleTimeLimit 120 and traced each hand's _rotation.
@pytest.mark.parametrize(
    ("time_now", "depth_2", "depth_6"),
    [
        (0, -180.0, 0.0),
        (30, -90.0, 0.0),
        (60, 0.0, 0.0),
        (90, 0.0, 90.0),
        (120, 0.0, 180.0),
    ],
)
def test_hand_rotation_is_what_flash_player_traced(time_now, depth_2, depth_6):
    assert battle_screen.hand_rotation(">=", time_now, 120) == depth_2
    assert battle_screen.hand_rotation("<", time_now, 120) == depth_6


def test_time_limit_is_read_from_the_battle_frame():
    script = battle_screen.TIME_LIMIT_SCRIPT.read_text("utf-8")
    assert battle_screen.time_limit(script) == 120


def test_time_limit_refuses_a_script_that_never_sets_it():
    with pytest.raises(RuntimeError, match="0 times"):
        battle_screen.time_limit("BattleTimeNow = 0;")


def test_pick_delay_is_read_from_the_pick_and_the_pass():
    scripts = [path.read_text("utf-8") for path in battle_screen.PICK_SCRIPTS]
    assert battle_screen.pick_delay(scripts) == 5


def test_pick_delay_refuses_a_script_that_never_sets_it():
    with pytest.raises(RuntimeError, match="set BattleTimeNow"):
        battle_screen.pick_delay(
            ["_root.BattleTimeNow = _root.BattleTimeLimit - 5;", "x = 1;"]
        )


def test_pick_delay_refuses_a_pick_and_a_pass_that_disagree():
    with pytest.raises(RuntimeError, match="set BattleTimeNow"):
        battle_screen.pick_delay(
            [
                "_root.BattleTimeNow = _root.BattleTimeLimit - 5;",
                "_root.BattleTimeNow = _root.BattleTimeLimit - 4;",
            ]
        )
