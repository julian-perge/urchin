# The top bar extractor's parsing and arithmetic, on AS and timelines built by
# hand, so no test needs the gitignored SWF. Running extract_top_bar twice
# checks the SWF side. The last tests check the committed record against the
# invariant that holds for all the battle art: rect times zoom is the PNG size.
from __future__ import annotations

import json

import pytest
from urchin_dev.swf import timeline
from urchin_dev.swf.extract import top_bar

LOAD_SCRIPT = """onClipEvent(load){
   this.inner.gotoAndStop("second");
   this.inner2._xscale = -100;
}
"""

BUFF_ROW = """   buffSpaceGF = 17;
   buffOffsetGF = 110;
   if(ukcb.teamSide == 1)
   {
      buffMultiGF = 1;
   }
   else
   {
      buffMultiGF = -1;
   }
   h = 0;
   var _loc3_;
   while(h < 7)
   {
      removeMovieClip(_root["p" + ukcb.playerID + "BAR"]["bshr" + h]);
"""

LIFE_BAR_LINES = """      _root["p" + PWLC + "BAR"].inner2.fB3.LBS._x = _root["p" + PWLC + "BAR"].inner2.fB._width * 1.2710000000000006 - 1;
         _root["p" + PWLC + "BAR"].inner2.lB3.LBS._x = _root["p" + PWLC + "BAR"].inner2.lB._width * 1.2710000000000006 - 1;
"""


def layer(character: int, matrix=timeline.IDENTITY, **changes) -> timeline.Layer:
    return timeline.Layer(character_id=character, matrix=matrix, **changes)


def test_a_load_script_names_the_inner_frame_and_the_mirror():
    assert top_bar.load_script_flags(LOAD_SCRIPT) == {
        "inner_frame": "second",
        "inner2_xscale": -100.0,
    }
    assert top_bar.load_script_flags("onClipEvent(load){}") == {
        "inner_frame": None,
        "inner2_xscale": None,
    }


def test_the_buff_row_constants_come_from_the_script():
    assert top_bar.buff_row_constants(BUFF_ROW) == {
        "offset": 110.0,
        "space": 17.0,
        "slots": 7,
        "player_side": 1,
        "enemy_side": -1,
    }


def test_a_buff_row_constant_set_twice_or_not_at_all_is_refused():
    with pytest.raises(ValueError, match="buffSpaceGF"):
        top_bar.buff_row_constants(BUFF_ROW.replace("buffSpaceGF = 17;", ""))
    with pytest.raises(ValueError, match="buffOffsetGF"):
        top_bar.buff_row_constants(BUFF_ROW + "buffOffsetGF = 5;")
    with pytest.raises(ValueError, match="loop"):
        top_bar.buff_row_constants(BUFF_ROW.replace("while(h < 7)", "while(h < i)"))
    with pytest.raises(ValueError, match="teamSide"):
        top_bar.buff_row_constants(BUFF_ROW.replace("teamSide == 1", "teamSide == 2"))


def test_the_smoother_factor_comes_from_the_two_lines_that_agree():
    assert top_bar.smoother_factors(LIFE_BAR_LINES) == {
        "x_factor": 1.2710000000000006,
        "x_offset": 1.0,
    }
    with pytest.raises(ValueError, match="2 formulas"):
        top_bar.smoother_factors(LIFE_BAR_LINES.replace("1.271", "1.5", 1))


# A bar clip holds the colour clip at x 2000 twips, and the colour clip holds
# one shape from -2000 to 2000, so the bar spans 0 to 4000 twips.
def _layers_of(character: int):
    return {
        10: {1: layer(11, (1.0, 0.0, 0.0, 1.0, 2000, -10))},
        11: {1: layer(12)},
    }.get(character)


def test_a_clips_width_is_the_union_of_what_its_first_frame_draws():
    shapes = {12: (-2000, -120, 2000, 120)}
    assert top_bar.content_width(10, _layers_of, shapes.__getitem__) == 4000
    scaled = {10: {1: layer(11, (0.5, 0.0, 0.0, 1.0, 100, 0))}, 11: {1: layer(12)}}
    assert top_bar.content_width(10, scaled.get, shapes.__getitem__) == 2000


def test_a_rotated_clip_has_no_width():
    rotated = {10: {1: layer(12, (1.0, 0.5, 0.0, 1.0, 0, 0))}}
    with pytest.raises(ValueError, match="skews"):
        top_bar.content_width(10, rotated.get, {12: (0, 0, 10, 10)}.__getitem__)


def _color_frame(add, shape=top_bar.LIFE_COLOR_SHAPE, mult=(0, 0, 0, 256), alpha_add=0):
    return {1: layer(shape, color_transform=(*mult, *add, alpha_add))}


def test_each_life_colour_is_the_add_of_its_frame():
    frames = [_color_frame((153, 0, 0)), _color_frame((116, 179, 53))]
    assert top_bar.life_colors(frames) == ["#990000", "#74b335"]


def test_a_life_frame_that_is_not_a_flat_colour_is_refused():
    with pytest.raises(ValueError, match="flat colour"):
        top_bar.life_colors([_color_frame((1, 2, 3), mult=(256, 256, 256, 256))])
    with pytest.raises(ValueError, match="shape 54"):
        top_bar.life_colors([_color_frame((1, 2, 3), shape=99)])
    with pytest.raises(ValueError, match="2 layers"):
        top_bar.life_colors([{1: layer(54), 2: layer(54)}])


def test_a_smoother_frame_is_the_colour_clip_at_an_x_and_a_scale_or_nothing():
    clip = layer(
        top_bar.LIFE_COLOR_CLIP, (0.5, 0.0, 0.0, 1.0, 1000, 0), name="LCC", ratio=3
    )
    record = top_bar.smoother_record([{1: clip}, {}], {"dead": 2}, {2: "loss_end"})
    assert record == {
        "frames": 2,
        "labels": {"dead": 2},
        "scripts": {"2": "loss_end"},
        "shown": [
            {"frame": 1, "shown": True, "x": 50.0, "x_scale": 0.5, "ratio": 3},
            {"frame": 2, "shown": False},
        ],
    }


def test_a_smoother_frame_that_moves_the_clip_up_is_refused():
    clip = layer(top_bar.LIFE_COLOR_CLIP, (1.0, 0.0, 0.0, 1.0, 0, 20), name="LCC")
    with pytest.raises(ValueError, match="places LCC"):
        top_bar.smoother_record([{1: clip}], {}, {})


# The four frame scripts of LifeBarSmoother, as the AS has them.
LIFE_SMOOTHER_SCRIPTS = {
    18: 'if(deadNow == true)\n{\n   this.gotoAndPlay("dead");\n'
    '   _parent._parent._parent.inner.gotoAndStop("third");\n}\n'
    "else\n{\n   removeMovieClip(this);\n}",
    19: "LCC.gotoAndStop(stopper);",
    36: "_parent._parent.lB._width = wsaver;\nremoveMovieClip(this);",
    38: "if(_parent._parent._parent._alpha > 0)\n{\n"
    '   _parent._parent._parent._alpha -= 5;\n   this.gotoAndPlay("dead");\n}\n'
    "else\n{\n   _parent._parent._visible = false;\n   removeMovieClip(this);\n}",
}


def test_each_smoother_frame_script_is_given_its_role():
    assert top_bar.smoother_roles(LIFE_SMOOTHER_SCRIPTS) == {
        18: "loss_end",
        19: "gain_color",
        36: "gain_end",
        38: "death_fade",
    }
    assert top_bar.smoother_roles({19: "removeMovieClip(this);"}) == {19: "loss_end"}
    assert top_bar.smoother_roles({39: "_parent._parent.fB._width = wsaver;"}) == {
        39: "gain_end"
    }
    with pytest.raises(ValueError, match="frame 5"):
        top_bar.smoother_roles({5: "stop();"})


def test_the_death_clears_the_frame_before_its_script_and_fades_by_the_amount_it_takes_off():
    assert top_bar.death_record(LIFE_SMOOTHER_SCRIPTS) == {
        "clear_frame": 17,
        "fade_per_frame": 5,
    }
    with pytest.raises(ValueError, match="0 frames"):
        top_bar.death_record({19: "LCC.gotoAndStop(stopper);"})


RECORD = json.loads(top_bar.RECORD.read_text())


def test_every_art_rect_times_the_zoom_is_its_png_size():
    arts = [
        *RECORD["art"].values(),
        *RECORD["inner2"]["art"].values(),
        *(f["art"] for f in RECORD["inner"]["frames"].values() if f["art"]),
    ]
    assert len(arts) == 7
    for art in arts:
        assert [v * RECORD["zoom"] for v in art["rect"][2:]] == pytest.approx(
            art["size"]
        ), art["file"]
        assert (top_bar.OUT_DIR / art["file"]).is_file()


def test_the_life_fill_records_where_the_colour_clip_sits_in_its_bar():
    art = RECORD["art"]["life_fill"]
    x, y, w, h = art["rect"]
    # The clip draws shape 54, which is centred on the clip's origin.
    assert art["origin"] == pytest.approx([x + w / 2, y + h / 2])


def test_the_committed_record_holds_what_the_status_bar_reads():
    assert sorted(RECORD["placements"]) == [f"p{n}BAR" for n in range(1, 7)]
    mirrored = {n for n, p in RECORD["placements"].items() if p["inner2_xscale"]}
    assert mirrored == {"p2BAR", "p4BAR", "p6BAR"}
    assert RECORD["life_color_frames"] == len(RECORD["life_colors"]) == 101
    assert RECORD["bars"]["life"]["wsaver"] == pytest.approx(157.4, abs=0.01)
    assert RECORD["buff_row"]["slots"] == 7
    assert RECORD["shadow"]["distance"] == 3.0
    assert set(RECORD["smoothers"]) == set(top_bar.SMOOTHERS)
    assert RECORD["inner"]["frames"]["third"]["art"] is None
