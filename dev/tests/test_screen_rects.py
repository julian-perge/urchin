# The rect record's arithmetic on numbers built by hand, so no test needs the
# gitignored SWF. Running extract_screen_rects twice checks the SWF side.
from __future__ import annotations

import json
from dataclasses import replace

import pytest
from urchin_dev import REPO_ROOT
from urchin_dev.swf.extract import screen_rects
from urchin_dev.swf.swf_index import ButtonRecord, DropShadow, EditText, StyleSet

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


# The close X of KRINMENU's inventory frame, as extract_window_chrome records it.
CLOSE_X_CHROME = {
    "rect": [734.3, 29.675, 37.0, 36.5],
    "relative_to": "stage",
    "size": [148, 146],
    "zoom": 4.0,
}


def test_art_record_is_the_render_rect_and_the_png():
    entry = screen_rects.art_record("close_x", CLOSE_X_CHROME)
    assert entry == {
        "kind": "art",
        "rect": [734.3, 29.675, 37.0, 36.5],
        "texture": "res://assets/ui/window/close_x.png",
    }


def test_art_record_refuses_a_rect_measured_from_a_sprite():
    with pytest.raises(ValueError, match="sprite 2986"):
        screen_rects.art_record(
            "slot_inventory", {**CLOSE_X_CHROME, "relative_to": "sprite 2986"}
        )


def test_art_record_of_a_sprite_rect_adds_where_that_sprite_sits():
    gloss = {**CLOSE_X_CHROME, "rect": [-38.25, 10.85, 129.0, 18.75]}
    entry = screen_rects.art_record(
        "xp_gloss_victory",
        {**gloss, "relative_to": "sprite 3002"},
        {"sprite 3002": (147.6, 172.65)},
    )
    assert entry["rect"] == pytest.approx([109.35, 183.5, 129.0, 18.75])
    assert entry["texture"] == "res://assets/ui/window/xp_gloss_victory.png"


def test_art_record_refuses_a_sprite_rect_of_another_sprite():
    with pytest.raises(ValueError, match="sprite 2867"):
        screen_rects.art_record(
            "xp_bar",
            {**CLOSE_X_CHROME, "relative_to": "sprite 2867"},
            {"sprite 3002": (147.6, 172.65)},
        )


# The victory row's backing 3001: a solid black 3936 x 1664 twip shape around
# the row's centre.
def test_box_record_is_the_shape_through_the_placement_with_its_fill():
    entry = screen_rects.box_record(
        (-1968, -832, 1968, 832),
        (1.0, 0.0, 0.0, 1.0, 0, 0),
        (147.6, 172.65),
        (0, 0, 0, 255),
    )
    assert entry["kind"] == "box"
    assert entry["rect"] == pytest.approx([49.2, 131.05, 196.8, 83.2])
    assert entry["fill"] == "000000ff"


# The DropShadow on each victory row: black, blur 5, distance 5 at 45 degrees.
ROW_SHADOW = DropShadow(
    color=(0, 0, 0, 255),
    blur_x=5.0,
    blur_y=5.0,
    angle=45.0,
    distance=5.0,
    strength=1.0,
    inner=False,
    knockout=False,
)


def test_text_shadow_is_the_drop_shadow_offset_and_colour():
    assert screen_rects.text_shadow(ROW_SHADOW) == {
        "offset": pytest.approx([3.5355, 3.5355], abs=0.0001),
        "color": "000000ff",
        "blur": 5.0,
    }


def test_text_shadow_scales_the_alpha_by_the_strength():
    from dataclasses import replace as changed

    assert screen_rects.text_shadow(changed(ROW_SHADOW, strength=0.5))["color"] == "00000080"


@pytest.mark.parametrize(
    "change, message",
    [
        ({"inner": True}, "inner"),
        ({"knockout": True}, "knockout"),
        ({"blur_y": 4.0}, "two blur values"),
    ],
)
def test_text_shadow_refuses_a_shadow_a_label_cannot_draw(change, message):
    from dataclasses import replace as changed

    with pytest.raises(ValueError, match=message):
        screen_rects.text_shadow(changed(ROW_SHADOW, **change))


def test_one_solid_fill_refuses_a_shape_with_a_second_style_set():
    sets = [
        StyleSet(((0, 0, 0, 255),), (), frozenset({1}), {}),
        StyleSet(((102, 102, 102, 255),), (), frozenset({1}), {}),
    ]
    with pytest.raises(ValueError, match="3001 is not one solid fill"):
        screen_rects.one_solid_fill(sets, 3001)


def test_one_solid_fill_is_the_fill_of_a_plain_box():
    sets = [StyleSet(((0, 0, 0, 255),), (), frozenset({1}), {})]
    assert screen_rects.one_solid_fill(sets, 7) == (0, 0, 0, 255)


# The close button 2853: one record, drawn in the hit state only, of the
# 600 twip square shape 291. KRINMENU frame 1 places it at depth 1434.
CLOSE_HIT = ButtonRecord(frozenset({"hit"}), 291, 1, (1.0, 0.0, 0.0, 1.0, 0, 0))
CLOSE_MATRIX = (1.0, 0.0, 0.0, 1.0, 7062, -3494)
CLOSE_BOUNDS = (-300, -300, 300, 300)


def test_hit_record_is_the_hit_shape_through_the_placement():
    entry = screen_rects.hit_record([CLOSE_HIT], CLOSE_BOUNDS, CLOSE_MATRIX, ORIGIN)
    assert entry["kind"] == "hit"
    assert entry["rect"] == pytest.approx([738.6, 32.7, 30.0, 30.0])


@pytest.mark.parametrize(
    "records, message",
    [
        ([CLOSE_HIT, CLOSE_HIT], "draws"),
        ([replace(CLOSE_HIT, states=frozenset({"up", "hit"}))], "draws"),
        ([replace(CLOSE_HIT, matrix=(1.0, 0.0, 0.0, 1.0, 20, 0))], "moves"),
    ],
)
def test_hit_record_refuses_a_button_that_is_more_than_a_hit_square(records, message):
    with pytest.raises(ValueError, match=message):
        screen_rects.hit_record(records, CLOSE_BOUNDS, CLOSE_MATRIX, ORIGIN)


# The Abilities window's top plus button 3068. Shape 3065 is the black plate of
# the up state, under the gradient 3064. Shapes 3066 and 3067 draw only on
# hover, press and hit. KRINMENU frame 25 places the button at depth 668.
PLUS_RECORDS = [
    ButtonRecord(frozenset({"up", "over", "down"}), 3064, 1, (1.0, 0.0, 0.0, 1.0, 0, 0)),
    ButtonRecord(frozenset({"up"}), 3065, 2, (1.0, 0.0, 0.0, 1.0, 0, 0)),
    ButtonRecord(frozenset({"over", "down", "hit"}), 3066, 3, (1.0, 0.0, 0.0, 1.0, 0, 0)),
    ButtonRecord(frozenset({"hit"}), 3067, 4, (1.0, 0.0, 0.0, 1.0, 0, 0)),
]
PLUS_BOUNDS = {
    3064: (-431, -154, 431, 155),
    3065: (-441, -164, 441, 165),
    3066: (-451, -174, 451, 175),
    3067: (-441, -164, 441, 165),
}
PLUS_MATRIX = (1.0, 0.0, 0.0, 1.0, -1358, 2501)


def test_button_record_is_the_up_state_through_the_placement():
    entry = screen_rects.button_record(PLUS_RECORDS, PLUS_BOUNDS, PLUS_MATRIX, ORIGIN)
    assert entry["kind"] == "button"
    assert entry["rect"] == pytest.approx([310.55, 339.25, 44.1, 16.45])


def test_button_record_refuses_a_moved_up_state_record():
    moved = [replace(PLUS_RECORDS[1], matrix=(1.0, 0.0, 0.0, 1.0, 20, 0))]
    with pytest.raises(ValueError, match="moves"):
        screen_rects.button_record(moved, PLUS_BOUNDS, PLUS_MATRIX, ORIGIN)


def test_button_record_refuses_a_button_with_no_up_state():
    with pytest.raises(ValueError, match="up state"):
        screen_rects.button_record(PLUS_RECORDS[2:], PLUS_BOUNDS, PLUS_MATRIX, ORIGIN)


# The clip reader (3059) at depth 675 of KRINMENU frame 25. Its first frame
# places the tip field at depth 1.
def test_inner_origin_adds_the_sprite_placement_to_the_origin():
    inner = screen_rects.inner_origin((1.0, 0.0, 0.0, 1.0, 0, -17), ORIGIN)
    assert inner == pytest.approx((400.5, 221.55))


def test_inner_origin_refuses_a_scaled_sprite():
    with pytest.raises(ValueError, match="scale"):
        screen_rects.inner_origin((1.041, 0.0, 0.0, 1.0, 0, 0), ORIGIN)


# The Abilities window's tip field 3037: 12 px text with 2 px of leading, which
# wraps. Flash puts its lines 12 + 2 px apart.
def test_text_record_of_a_wrapping_field_holds_its_line_pitch():
    tip = field(font_height=240, leading=40, multiline=True, word_wrap=True)
    entry = screen_rects.text_record(tip, (1.0, 0.0, 0.0, 1.0, 0, 0), ORIGIN)
    assert entry["line_pitch"] == 14.0


def test_text_record_of_a_one_line_field_holds_no_line_pitch():
    entry = screen_rects.text_record(field(), (1.0, 0.0, 0.0, 1.0, 0, 0), ORIGIN)
    assert "line_pitch" not in entry


# A multiline field that the game fills breaks its lines at line breaks, with
# no wrapping, and its lines are as far apart as those of a field that wraps.
def test_text_record_of_a_multiline_field_with_no_wrap_holds_its_line_pitch():
    filled = field(font_height=240, leading=40, multiline=True)
    entry = screen_rects.text_record(filled, (1.0, 0.0, 0.0, 1.0, 0, 0), ORIGIN)
    assert entry["line_pitch"] == 14.0


def test_text_record_of_one_line_of_static_text_holds_no_line_pitch():
    static = field(multiline=True, variable_name=None, initial_text="SKIP\r")
    entry = screen_rects.text_record(static, (1.0, 0.0, 0.0, 1.0, 0, 0), ORIGIN)
    assert "line_pitch" not in entry


@pytest.mark.parametrize(
    ("depth", "instance"), [(None, None), (7, "itemSlot0")], ids=["neither", "both"]
)
def test_a_piece_needs_exactly_one_of_a_depth_and_an_instance_name(depth, instance):
    with pytest.raises(ValueError, match="not both or neither"):
        screen_rects.Piece("art", depth, art="slot_inventory", instance=instance)
