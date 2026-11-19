# extract_fade_steps's reading of the fades' scripts, on the original's own
# committed ActionScript and on scripts written by hand, so no test needs the
# gitignored SWF.
from __future__ import annotations

import pytest
from urchin_dev.swf.extract import fade_steps


def test_the_six_hover_rings_step_up_by_20_and_down_by_5():
    scripts = [
        (d / fade_steps.ENTER_FRAME).read_text() for d in fade_steps.RING_SCRIPTS
    ]
    assert len(scripts) == 6
    assert fade_steps.ring_steps(scripts) == {"fade_in_step": 20, "fade_out_step": 5}


def test_a_ring_that_steps_differently_is_refused():
    # The port runs one fade for every fighter, so a ring with its own step
    # would be lost without a word.
    same = "_alpha = _alpha + 20;\n_alpha = _alpha - 5;\n"
    other = "_alpha = _alpha + 20;\n_alpha = _alpha - 10;\n"
    with pytest.raises(RuntimeError, match="differently"):
        fade_steps.ring_steps([same, other])


def test_the_radial_menu_steps_by_50_and_10_and_covers_at_75_then_85():
    numbers = fade_steps.radial_steps(fade_steps.RADIAL_SCRIPT.read_text())
    assert numbers == {
        "cover_percent": 85,
        "cover_percent_fading_in": 75,
        "fade_in_step": 50,
        "fade_out_step": 10,
    }


def test_a_radial_menu_with_two_cover_alphas_after_the_fade_in_is_refused():
    # The port shows one cover alpha once the menu is in.
    script = (
        "bfilter._alpha = 75;\n_alpha = _alpha + 50;\nbfilter._alpha = 85;\n"
        "_alpha = _alpha - 10;\nbfilter._alpha = 90;\n"
    )
    with pytest.raises(RuntimeError, match=r"\[85, 90\] after"):
        fade_steps.radial_steps(script)


def test_the_bolt_steps_up_by_10():
    assert fade_steps.bolt_step(fade_steps.BOLT_SCRIPT.read_text()) == {
        "fade_in_step": 10
    }


def test_the_cutscene_black_steps_by_5():
    assert fade_steps.cutscene_step(fade_steps.CUTSCENE_SCRIPT.read_text()) == {
        "fade_step": 5
    }


def test_a_cutscene_fade_back_to_black_with_another_step_is_refused():
    # The port records one step, so a second one would be lost without a word.
    script = "_alpha = _alpha - 5;\n_alpha = _alpha + 10;\n"
    with pytest.raises(RuntimeError, match="down by 5 and up by 10"):
        fade_steps.cutscene_step(script)


def test_a_talent_node_with_no_point_is_covered_at_80():
    assert fade_steps.talent_cover(fade_steps.TALENT_SCRIPT.read_text()) == {
        "cover_percent": 80
    }


def test_a_script_with_no_step_is_refused():
    with pytest.raises(RuntimeError, match="0 matches"):
        fade_steps.bolt_step("this._alpha = 100;\n")
