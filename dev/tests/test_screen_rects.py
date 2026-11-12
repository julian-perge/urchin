# The rect record's arithmetic on numbers built by hand, so no test needs the
# gitignored SWF. Running extract_screen_rects twice checks the SWF side.
from __future__ import annotations

import json
from dataclasses import replace

import pytest
from urchin_dev import REPO_ROOT
from urchin_dev.swf.extract import screen_rects
from urchin_dev.swf.swf_index import DropShadow, EditText

ORIGIN = (400.5, 222.4)
# The victory frame's left Panel: KRINMENU frame 9 places sprite 2990 at depth
# 11 with this matrix, and the sprite's shape 2989 has these ShapeBounds and a
# 20 twip line.
LEFT_PANEL_MATRIX = (0.894195556640625, 0.0, 0.0, 1.22491455078125, -5061, 443)
LEFT_PANEL_BOUNDS = (-2490, -2671, 2491, 2672)
LINE = 20


def shadow(**changes) -> DropShadow:
    base = DropShadow(
        color=(0, 0, 0, 255),
        blur_x=5.0,
        blur_y=5.0,
        angle=45.0,
        distance=5.0,
        strength=1.0,
        inner=True,
        knockout=False,
    )
    return replace(base, **changes)


def field(**changes) -> EditText:
    base = EditText(
        bounds=(-40, -40, 4223, 340),
        font_id=1,
        font_height=260,
        color=(94, 94, 94, 255),
        align=0,
        left_margin=0,
        right_margin=0,
        indent=0,
        leading=0,
        multiline=False,
        word_wrap=False,
        html=False,
        variable_name="vbbc1",
        initial_text=None,
    )
    return replace(base, **changes)


def test_stage_rect_scales_then_translates_then_adds_the_origin():
    rect = screen_rects.stage_rect(
        (-20, -40, 20, 40), (2.0, 0.0, 0.0, 0.5, 100, 200), ORIGIN
    )
    assert rect == pytest.approx((400.5 + 5 - 2, 222.4 + 10 - 1, 4.0, 2.0))


def test_stage_rect_refuses_a_rotation():
    with pytest.raises(ValueError, match="rotat"):
        screen_rects.stage_rect((0, 0, 20, 20), (1.0, 0.1, 0.0, 1.0, 0, 0), ORIGIN)


def test_fill_rect_is_shapebounds_shrunk_by_half_the_scaled_line():
    # The issue's measurement: passing ShapeBounds puts each side of this
    # Panel 0.45 px out on x and 0.61 px out on y.
    outer = screen_rects.stage_rect(LEFT_PANEL_BOUNDS, LEFT_PANEL_MATRIX, ORIGIN)
    fill = screen_rects.fill_rect(LEFT_PANEL_BOUNDS, LINE, LEFT_PANEL_MATRIX, ORIGIN)
    assert fill[0] - outer[0] == pytest.approx(0.5 * 0.894195556640625)
    assert fill[1] - outer[1] == pytest.approx(0.5 * 1.22491455078125)
    assert outer[2] - fill[2] == pytest.approx(0.894195556640625)
    assert outer[3] - fill[3] == pytest.approx(1.22491455078125)


def test_border_is_the_line_times_the_rounded_mean_scale():
    assert screen_rects.border_width(LINE, (0.6, 2.1)) == 2
    assert screen_rects.border_width(LINE, (0.894, 1.225)) == 1
    assert screen_rects.border_width(2 * LINE, (1.0, 1.0)) == 2


def test_panel_record_grows_the_fill_rect_by_half_the_border():
    entry = screen_rects.panel_record(
        bounds=LEFT_PANEL_BOUNDS,
        line_width=LINE,
        matrix=LEFT_PANEL_MATRIX,
        origin=ORIGIN,
        fill=(55, 55, 55, 255),
        line=(0, 0, 0, 255),
        shadow=shadow(),
    )
    fill = screen_rects.fill_rect(LEFT_PANEL_BOUNDS, LINE, LEFT_PANEL_MATRIX, ORIGIN)
    assert entry["kind"] == "panel"
    assert entry["border"] == 1
    assert entry["rect"] == pytest.approx(
        [fill[0] - 0.5, fill[1] - 0.5, fill[2] + 1, fill[3] + 1], abs=1e-4
    )
    assert entry["fill"] == "373737ff"
    assert entry["line"] == "000000ff"
    assert entry["shadow"] == {"angle": 45.0, "blur": 5.0, "distance": 5.0}


@pytest.mark.parametrize(
    "change, message",
    [
        ({"inner": False}, "inner"),
        ({"knockout": True}, "knockout"),
        ({"blur_y": 4.0}, "blur"),
        ({"color": (0, 0, 0, 128)}, "colour"),
        ({"strength": 2.0}, "strength"),
    ],
)
def test_panel_record_refuses_a_shadow_the_shared_material_cannot_draw(change, message):
    with pytest.raises(ValueError, match=message):
        screen_rects.panel_record(
            bounds=LEFT_PANEL_BOUNDS,
            line_width=LINE,
            matrix=LEFT_PANEL_MATRIX,
            origin=ORIGIN,
            fill=(55, 55, 55, 255),
            line=(0, 0, 0, 255),
            shadow=shadow(**change),
        )


def test_text_record_is_the_field_inside_its_gutter_with_its_size_and_colour():
    entry = screen_rects.text_record(
        field(), (1.0, 0.0, 0.0, 1.0, -7144, -2666), ORIGIN
    )
    assert entry == {
        "kind": "text",
        "rect": pytest.approx([43.3, 89.1, 209.15, 15.0]),
        "font_size": 13.0,
        "color": "5e5e5eff",
    }


def test_text_record_refuses_a_scaled_field():
    with pytest.raises(ValueError, match="scale"):
        screen_rects.text_record(field(), (1.5, 0.0, 0.0, 1.0, 0, 0), ORIGIN)


def test_every_configured_scene_is_a_committed_scene():
    for scene in screen_rects.SCENES:
        assert scene.startswith("res://")
        assert (REPO_ROOT / scene.removeprefix("res://")).is_file(), scene


def test_the_committed_record_holds_every_configured_scene_and_piece():
    record = json.loads(screen_rects.RECORD.read_text())
    assert set(record["scenes"]) == set(screen_rects.SCENES)
    for path, scene in screen_rects.SCENES.items():
        assert set(record["scenes"][path]["pieces"]) == set(scene.pieces)
        assert record["scenes"][path]["port_only"] == list(scene.port_only)
