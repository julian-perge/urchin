# The rect record's arithmetic on numbers built by hand, so no test needs the
# gitignored SWF. Running extract_screen_rects twice checks the SWF side.
from __future__ import annotations

import json
from dataclasses import replace

import pytest
from urchin_dev import ACTION_SCRIPT, REPO_ROOT
from urchin_dev.swf import timeline
from urchin_dev.swf.extract import hotbar_icons, screen_rects
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
    # PanelRecipe.border_width has the same case in test/unit/test_panel_recipe.gd.
    assert screen_rects.border_width(3 * LINE, (0.6, 2.1)) == 5


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
        "align": "left",
    }


@pytest.mark.parametrize(
    ("align", "name"), [(0, "left"), (1, "right"), (2, "center"), (3, "justify")]
)
def test_text_record_holds_the_alignment_of_the_field(align, name):
    entry = screen_rects.text_record(
        field(align=align), (1.0, 0.0, 0.0, 1.0, 0, 0), ORIGIN
    )
    assert entry["align"] == name


# The face's crop box in clip 2978 is placed by the clip's own matrix, which
# scales (sprite 3002 places it at 1.653), so the record scales it too.
def test_face_record_is_the_crop_box_through_the_placement():
    entry = screen_rects.face_record(
        [1.0, 2.0, 28.0, 38.0], (2.0, 0.0, 0.0, 2.0, -100, 20), ORIGIN
    )
    assert entry == {"kind": "face", "rect": pytest.approx([397.5, 227.4, 56.0, 76.0])}


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


def rig(name: str, x_twips: int, y_twips: int, scale: float = 1.0) -> timeline.Layer:
    return timeline.Layer(
        character_id=2676, name=name, matrix=(scale, 0.0, 0.0, 1.0, x_twips, y_twips)
    )


# CHURCH's label frame of BATTLESCREEN (3435), which the battle frame places at
# (400, 294.5). The right-hand rigs are mirrored and sit at the mirrored x.
CHURCH_RIGS = {
    40: rig("player5", -3582, -1520),
    80: rig("player6", 3558, -1520, -1.0),
    120: rig("player1", -4782, 58),
    160: rig("player2", 4758, 58, -1.0),
    200: rig("player3", -3582, 1530),
    240: rig("player4", 3558, 1530, -1.0),
}
BATTLESCREEN_ORIGIN = (400.0, 294.5)


def test_fighter_marks_are_the_rig_placements_on_the_stage():
    marks = screen_rects.fighter_marks(BATTLESCREEN_ORIGIN, CHURCH_RIGS)
    assert marks == {
        "1": [160.9, 297.4],
        "2": [637.9, 297.4],
        "3": [220.9, 371.0],
        "4": [577.9, 371.0],
        "5": [220.9, 218.5],
        "6": [577.9, 218.5],
    }


def test_fighter_marks_ignore_the_hall_art_and_refuse_a_missing_slot():
    art = timeline.Layer(character_id=3400, name=None)
    without_five = {d: layer for d, layer in CHURCH_RIGS.items() if d != 40}
    with pytest.raises(ValueError, match="slots"):
        screen_rects.fighter_marks(BATTLESCREEN_ORIGIN, {**without_five, 1: art})
    assert screen_rects.fighter_marks(BATTLESCREEN_ORIGIN, {**CHURCH_RIGS, 1: art})


def test_fighter_marks_refuse_a_rig_with_another_name():
    with pytest.raises(ValueError, match="player7"):
        screen_rects.fighter_marks(
            BATTLESCREEN_ORIGIN, {**CHURCH_RIGS, 41: rig("player7", 0, 0)}
        )


def test_the_committed_record_holds_the_fighter_marks_of_every_hall():
    record = json.loads(screen_rects.RECORD.read_text())
    layout = json.loads(screen_rects.battle_screen.LAYOUT_JSON.read_text())
    assert set(record["fighter_marks"]) == set(layout["halls"])
    for marks in record["fighter_marks"].values():
        assert sorted(marks) == ["1", "2", "3", "4", "5", "6"]


def test_the_art_sources_hold_the_battle_top_panel():
    entry, folder = screen_rects.art_sources()["top_panel"]
    assert folder == screen_rects.BATTLE_TEXTURES
    assert entry["relative_to"] == "stage"
    assert [v * entry["zoom"] for v in entry["rect"][2:]] == pytest.approx(
        entry["size"]
    )


# The bottom bar's one shape 3315 strokes three boxes with one line. A path is
# counted from the top and then from the left, and it is the line's centre.
THREE_BOXES = [
    StyleSet(
        fills=(None,),
        lines=((20, (0, 0, 0, 255)),),
        used_fills=frozenset({1}),
        line_bounds={},
        paths=(
            (1351, -1084, 7702, 1084),
            (-1252, -1084, 1273, 1084),
            (-7701, -1084, -1349, 1084),
        ),
    )
]


def test_a_path_shape_is_the_nth_box_from_the_left_through_the_placement():
    entry = screen_rects.path_shape_record(
        THREE_BOXES, 2, (1.0, 0.0, 0.0, 1.0, 1, 0), (400.0, 508.0)
    )
    assert entry == {
        "kind": "shape",
        "rect": pytest.approx([467.6, 453.8, 317.55, 108.4], abs=0.01),
    }
    left = screen_rects.path_shape_record(THREE_BOXES, 0, timeline.IDENTITY, (0.0, 0.0))
    assert left["rect"][0] == pytest.approx(-385.05)


def test_a_path_shape_refuses_a_path_it_does_not_have():
    with pytest.raises(ValueError, match="3 paths"):
        screen_rects.path_shape_record(THREE_BOXES, 3, timeline.IDENTITY, (0.0, 0.0))


# A status bar as extract_top_bar writes it, cut to one backing, one text field and
# one fill. The battle frame places the bar with a scale of 2 in x and 3 in y at
# (100, 10) px.
BAR_MATRIX = (2.0, 0.0, 0.0, 3.0, 2000, 200)
BAR = {
    "placements": {
        "p1BAR": {"inner_frame": None, "inner2_xscale": None},
        "p2BAR": {"inner_frame": "second", "inner2_xscale": -100.0},
    },
    "inner": {
        "frames": {
            "first": {
                "art": {
                    "file": "a.png",
                    "rect": [10.0, 1.0, 1.0, 5.0],
                    "size": [4, 20],
                },
                "fields": [
                    {
                        "variable": "lifeNow",
                        "rect": [20.0, 2.0, 30.0, 12.0],
                        "font_size": 9.0,
                        "color": "ffffffff",
                        "align": "right",
                    }
                ],
            },
            "second": {
                "art": {
                    "file": "b.png",
                    "rect": [-11.0, 1.0, 1.0, 5.0],
                    "size": [4, 20],
                },
                "fields": [],
            },
        }
    },
    "inner2": {"art": {}},
    "bars": {"life": {"art": "life_fill", "scale_x": 0.5, "x": -100.0, "y": -5.0}},
    "art": {
        "life_fill": {
            "file": "f.png",
            "rect": [0.0, -6.0, 200.0, 12.0],
            "size": [800, 48],
        }
    },
    "shadow": {
        "angle": 90.0,
        "distance": 3.0,
        "strength": 0.5,
        "color": "000000ff",
        "blur_x": 5.0,
    },
}


def test_a_bar_art_part_goes_through_the_placement_with_a_zoom_for_each_axis():
    entry = screen_rects.bar_part_record("backing", BAR_MATRIX, BAR, "p1BAR")
    assert entry == {
        "kind": "art",
        "rect": [120.0, 13.0, 2.0, 15.0],
        "texture": "res://assets/ui/battle/top_bar/a.png",
        "size": [4, 20],
        "zoom": [2.0, 20 / 15],
    }


def test_a_right_hand_bar_takes_its_second_frame_and_mirrors_inner2():
    backing = screen_rects.bar_part_record("backing", BAR_MATRIX, BAR, "p2BAR")
    assert backing["texture"].endswith("/b.png")
    fill = screen_rects.bar_part_record("fill:life", BAR_MATRIX, BAR, "p2BAR")
    # The fill is 100 px wide from x -100 in inner2, so it runs from 0 to 100
    # once mirrored. Through the placement, that is x 100 + 2 * 0, 200 px wide.
    assert fill["rect"] == pytest.approx([100.0, 10.0 + 3 * -11.0, 200.0, 36.0])
    unmirrored = screen_rects.bar_part_record("fill:life", BAR_MATRIX, BAR, "p1BAR")
    assert unmirrored["rect"][0] == pytest.approx(100.0 + 2 * -100.0)


def test_a_bar_text_part_is_placed_with_the_shadow_scaled_and_its_strength_in_the_alpha():
    entry = screen_rects.bar_part_record("text:lifeNow", BAR_MATRIX, BAR, "p1BAR")
    assert entry["rect"] == [140.0, 16.0, 60.0, 36.0]
    assert entry["font_size"] == 9.0
    assert entry["shadow"]["color"] == "00000080"
    assert entry["shadow"]["offset"] == pytest.approx([0.0, 9.0])


def test_a_bar_part_that_is_not_one_is_refused():
    with pytest.raises(ValueError, match="unknown bar part"):
        screen_rects.bar_part_record("nothing", BAR_MATRIX, BAR, "p1BAR")
    with pytest.raises(ValueError, match="placed with"):
        screen_rects.bar_part_record(
            "backing", (1.0, 0.5, 0.0, 1.0, 0, 0), BAR, "p1BAR"
        )


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
        "size": [148, 146],
        "zoom": 4.0,
    }


def test_art_record_names_the_png_in_the_folder_it_is_given():
    entry = screen_rects.art_record(
        "logo", CLOSE_X_CHROME, textures=screen_rects.MENU_TEXTURES
    )
    assert entry["texture"] == "res://assets/ui/menu/logo.png"


def test_the_art_sources_hold_the_window_chrome_and_the_menu_art():
    sources = screen_rects.art_sources()
    chrome, chrome_folder = sources["close_x"]
    assert chrome_folder == screen_rects.CHROME_TEXTURES
    assert chrome["relative_to"] == "stage"
    for name in ("logo", "start_background"):
        entry, folder = sources[name]
        assert folder == screen_rects.MENU_TEXTURES
        # extract_start_screens measures both from the Stage and writes no
        # relative_to, so art_sources adds it.
        assert entry["relative_to"] == "stage"
        assert set(entry) == {"rect", "relative_to", "size", "zoom"}


def test_the_art_sources_hold_the_bottom_bar_and_the_hotbar_icons():
    sources = screen_rects.art_sources()
    bar, bar_folder = sources["bottom_bar"]
    assert bar_folder == screen_rects.BATTLE_TEXTURES
    assert bar["relative_to"] == "stage"
    assert [v * bar["zoom"] for v in bar["rect"][2:]] == pytest.approx(bar["size"])
    for name in hotbar_icons.ICONS:
        entry, folder = sources[name]
        assert folder == screen_rects.HOTBAR_TEXTURES
        assert set(entry) == {"rect", "relative_to", "size", "zoom"}
        assert entry["relative_to"] == "stage"


# extract_window_chrome renders the hotbar square where depth 126 places it,
# and depth 128 places the same art 964 twips to the right.
def test_art_rendered_at_another_placement_moves_by_the_difference():
    square = {**CLOSE_X_CHROME, "rect": [25.0, 467.25, 53.75, 54.0]}
    moved = screen_rects.moved_art(
        square, (0.67, 0.0, 0.0, 0.67, 1997, 9878), (0.67, 0.0, 0.0, 0.67, 1033, 9878)
    )
    assert moved["rect"] == pytest.approx([73.2, 467.25, 53.75, 54.0])
    assert moved["size"] == square["size"]


def test_art_rendered_at_another_scale_is_refused():
    with pytest.raises(ValueError, match="scale"):
        screen_rects.moved_art(
            CLOSE_X_CHROME,
            (0.81, 0.0, 0.0, 0.81, 1997, 9878),
            (0.67, 0.0, 0.0, 0.67, 1033, 9878),
        )


def test_art_rendered_from_a_sprite_cannot_be_moved():
    with pytest.raises(ValueError, match="sprite 2986"):
        screen_rects.moved_art(
            {**CLOSE_X_CHROME, "relative_to": "sprite 2986"},
            (1.0, 0.0, 0.0, 1.0, 20, 0),
            (1.0, 0.0, 0.0, 1.0, 0, 0),
        )


# The zone fill's shape 3146 is 5028 by 281 twips, and the bar's sprite places
# it at its own origin.
def test_a_shape_record_is_the_shape_bounds_through_the_placement():
    entry = screen_rects.shape_record(
        (0, 0, 5028, 281), (1.0, 0.0, 0.0, 1.0, 94, 105), (500.0, 510.0)
    )
    assert entry == {"kind": "shape", "rect": [504.7, 515.25, 251.4, 14.05]}


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


def test_shared_slot_art_uses_the_equip_placement_not_the_grid_placement(monkeypatch):
    from types import SimpleNamespace

    equip = SimpleNamespace(
        character_id=2984, matrix=(1.0, 0.0, 0.0, 1.0, -6366, -1005)
    )
    grid = SimpleNamespace(character_id=2986, matrix=(1.0, 0.0, 0.0, 1.0, 2652, -1885))
    monkeypatch.setattr(screen_rects, "origin_of", lambda *_: ORIGIN)
    monkeypatch.setattr(screen_rects.timeline, "frame_of", lambda *_: 1)
    monkeypatch.setattr(
        screen_rects.timeline, "frames", lambda *_: [{828: equip, 30: grid}]
    )
    monkeypatch.setattr(
        screen_rects,
        "art_sources",
        lambda: {
            "slot_inventory": (
                {
                    "relative_to": "sprite 2986",
                    "rect": [-15.5, -15.5, 31.0, 31.0],
                    "size": [124, 124],
                    "zoom": 4,
                },
                screen_rects.CHROME_TEXTURES,
            )
        },
    )
    scene = screen_rects.Scene(
        3142,
        "inventory",
        {
            "EquipSlot": screen_rects.Piece(
                "art", 828, art="slot_inventory", rendered_at=30
            )
        },
    )
    piece = screen_rects.scene_record(None, scene)["pieces"]["EquipSlot"]
    assert piece["rect"] == pytest.approx([66.7, 156.65, 31.0, 31.0])


def scaled_slot_record(monkeypatch, scale_x, scale_y=None):
    """-> the record of an equip slot that the frame places at depth 828 with
    the scale `scale_x` by `scale_y`, drawn with the art of the grid slot."""
    from types import SimpleNamespace

    equip = SimpleNamespace(
        character_id=2984, matrix=(scale_x, 0.0, 0.0, scale_y or scale_x, -6366, -1005)
    )
    grid = SimpleNamespace(character_id=2986, matrix=(1.0, 0.0, 0.0, 1.0, 2652, -1885))
    monkeypatch.setattr(screen_rects, "origin_of", lambda *_: ORIGIN)
    monkeypatch.setattr(screen_rects.timeline, "frame_of", lambda *_: 1)
    monkeypatch.setattr(
        screen_rects.timeline, "frames", lambda *_: [{828: equip, 30: grid}]
    )
    monkeypatch.setattr(
        screen_rects,
        "art_sources",
        lambda: {
            "slot_inventory": (
                {
                    "relative_to": "sprite 2986",
                    "rect": [-15.5, -15.5, 31.0, 31.0],
                    "size": [124, 124],
                    "zoom": 4,
                },
                screen_rects.CHROME_TEXTURES,
            )
        },
    )
    scene = screen_rects.Scene(
        3142,
        "shop",
        {
            "EquipSlot": screen_rects.Piece(
                "art", 828, art="slot_inventory", rendered_at=30
            )
        },
    )
    return screen_rects.scene_record(None, scene)["pieces"]["EquipSlot"]


# The shop frame scales its equip slots to 0.86. The art, its baked shadow and
# its highlight scale with the clip, so the rect is the art's rect times the
# scale from the slot's placement, and the PNG shows that many pixels for each
# Stage px less.
def test_shared_slot_art_at_another_scale_is_scaled_from_the_equip_placement(
    monkeypatch,
):
    piece = scaled_slot_record(monkeypatch, 0.86)
    assert piece["rect"] == pytest.approx(
        [400.5 - 318.3 - 15.5 * 0.86, 222.4 - 50.25 - 15.5 * 0.86, 26.66, 26.66]
    )
    assert piece["size"] == [124, 124]


def test_scaled_slot_art_keeps_the_rect_times_zoom_equal_to_the_png_size(monkeypatch):
    piece = scaled_slot_record(monkeypatch, 0.86)
    assert [v * piece["zoom"] for v in piece["rect"][2:]] == pytest.approx(
        piece["size"], abs=0.01
    )


def test_shared_slot_art_refuses_a_placement_that_scales_x_and_y_differently(
    monkeypatch,
):
    with pytest.raises(ValueError, match="same scale"):
        scaled_slot_record(monkeypatch, 0.86, 0.9)


def test_art_record_scales_a_sprite_rect_and_leaves_a_stage_rect_alone():
    slot = {
        "relative_to": "sprite 2986",
        "rect": [-15.5, -15.5, 31.0, 31.0],
        "size": [124, 124],
        "zoom": 4,
    }
    entry = screen_rects.art_record(
        "slot_inventory", slot, {"sprite 2986": (10.0, 20.0)}, scale=0.5
    )
    assert entry["rect"] == [2.25, 12.25, 15.5, 15.5]
    assert entry["zoom"] == 8
    with pytest.raises(ValueError, match="Stage"):
        screen_rects.art_record("close_x", CLOSE_X_CHROME, scale=0.5)


HOTBAR_SQUARE_SOURCE = {
    "hotbar_square": (
        {
            "relative_to": "stage",
            "rect": [25.0, 467.25, 53.75, 54.0],
            "size": [269, 270],
            "zoom": 5,
        },
        screen_rects.CHROME_TEXTURES,
    )
}


def steam_scene_record(monkeypatch, web_matrix, steam_matrix):
    """-> the record of one hotbar square that the web build places at depth
    126 with `web_matrix` and the Steam build at depth 157 with `steam_matrix`."""
    from types import SimpleNamespace

    frames = {
        "web": [{126: SimpleNamespace(character_id=3185, matrix=web_matrix)}],
        "steam": [{157: SimpleNamespace(character_id=2910, matrix=steam_matrix)}],
    }
    monkeypatch.setattr(screen_rects.timeline, "frame_of", lambda *_: 1)
    monkeypatch.setattr(screen_rects.timeline, "frames", lambda index, _: frames[index])
    monkeypatch.setattr(screen_rects, "art_sources", lambda: HOTBAR_SQUARE_SOURCE)
    scene = screen_rects.Scene(
        0,
        "Navigation",
        {"Square": screen_rects.Piece("art", 126, art="hotbar_square", steam=157)},
    )
    return screen_rects.scene_record("web", scene, "steam")["pieces"]["Square"]


# The Steam build places the six hotbar squares 260 twips under the web
# build's, and the port puts them where the Steam build does.
def test_a_piece_with_a_steam_placement_sits_where_the_steam_build_places_it(
    monkeypatch,
):
    piece = steam_scene_record(
        monkeypatch,
        (0.67, 0.0, 0.0, 0.67, 1033, 9878),
        (0.67, 0.0, 0.0, 0.67, 1033, 10138),
    )
    assert piece["rect"] == pytest.approx([25.0, 480.25, 53.75, 54.0])


def test_a_steam_placement_with_another_scale_is_refused(monkeypatch):
    with pytest.raises(ValueError, match="scale"):
        steam_scene_record(
            monkeypatch,
            (0.67, 0.0, 0.0, 0.67, 1033, 9878),
            (0.81, 0.0, 0.0, 0.81, 1033, 10138),
        )


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

    assert (
        screen_rects.text_shadow(changed(ROW_SHADOW, strength=0.5))["color"]
        == "00000080"
    )


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


def test_outline_record_has_a_stroke_and_no_fill_or_shadow():
    styles = [StyleSet((), ((20, (51, 51, 51, 255)),), frozenset(), {})]
    entry = screen_rects.outline_record(
        (-100, -200, 100, 200), (1.0, 0.0, 0.0, 1.0, 0, 0), ORIGIN, styles
    )
    assert entry == {
        "kind": "outline",
        "rect": [395.5, 212.4, 10.0, 20.0],
        "line": "333333ff",
        "border": 1,
    }


def test_outline_record_of_a_path_is_its_box_grown_by_half_the_line():
    # Two stacked boxes drawn with one 20 twip line. Each box's rect is its
    # edges grown by 10 twips, so the two cover the shape's bounds.
    styles = [
        StyleSet(
            (),
            ((20, (51, 51, 51, 255)),),
            frozenset(),
            {},
            ((-90, 10, 90, 190), (-90, -190, 90, -10)),
        )
    ]
    matrix = (1.0, 0.0, 0.0, 1.0, 0, 0)
    bounds = (-100, -200, 100, 200)
    first = screen_rects.outline_record(bounds, matrix, ORIGIN, styles, 0)
    second = screen_rects.outline_record(bounds, matrix, ORIGIN, styles, 1)
    assert first["rect"] == [395.5, 212.4, 10.0, 10.0]
    assert second["rect"] == [395.5, 222.4, 10.0, 10.0]
    assert first["border"] == second["border"] == 1


def test_outline_record_refuses_paths_that_do_not_cover_the_shape():
    styles = [
        StyleSet(
            (), ((20, (51, 51, 51, 255)),), frozenset(), {}, ((-90, -190, 90, -10),)
        )
    ]
    with pytest.raises(ValueError, match="paths cover"):
        screen_rects.outline_record(
            (-100, -200, 100, 200), (1.0, 0.0, 0.0, 1.0, 0, 0), ORIGIN, styles, 0
        )


def test_outline_record_refuses_a_shape_with_fill():
    with pytest.raises(ValueError, match="outline"):
        screen_rects.outline_record(
            (0, 0, 100, 100), (1.0, 0.0, 0.0, 1.0, 0, 0), ORIGIN, [panel_styles()]
        )


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


# The Abilities window's top plus button 3068. Shape 3065 is the black plus
# glyph and its outline, at depth 2 over the gradient 3064, in the up state.
# Shapes 3066 and 3067 draw only on hover, press and hit. KRINMENU frame 25
# places the button at depth 668.
PLUS_RECORDS = [
    ButtonRecord(
        frozenset({"up", "over", "down"}), 3064, 1, (1.0, 0.0, 0.0, 1.0, 0, 0)
    ),
    ButtonRecord(frozenset({"up"}), 3065, 2, (1.0, 0.0, 0.0, 1.0, 0, 0)),
    ButtonRecord(
        frozenset({"over", "down", "hit"}), 3066, 3, (1.0, 0.0, 0.0, 1.0, 0, 0)
    ),
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
    entry = screen_rects.button_record(
        3068, PLUS_RECORDS, PLUS_BOUNDS, PLUS_MATRIX, ORIGIN
    )
    assert entry["kind"] == "button"
    assert entry["rect"] == pytest.approx([310.55, 339.25, 44.1, 16.45])


# A hotbar square is a button whose one record scales and moves shape 3119
# inside the button, and the hub frame then scales the button.
def test_button_record_places_the_shape_with_its_record_before_the_placement():
    records = [
        ButtonRecord(
            frozenset({"up", "over", "down", "hit"}),
            3119,
            1,
            (0.5, 0.0, 0.0, 0.25, -600, -400),
        )
    ]
    entry = screen_rects.button_record(
        3068,
        records,
        {3119: (0, 0, 2000, 4000)},
        (2.0, 0.0, 0.0, 2.0, 1000, 2000),
        (0, 0),
    )
    assert entry["rect"] == pytest.approx([-10.0, 60.0, 100.0, 100.0])


def test_button_record_refuses_a_rotated_up_state_record():
    turned = [replace(PLUS_RECORDS[1], matrix=(1.0, 0.1, 0.0, 1.0, 0, 0))]
    with pytest.raises(ValueError, match="rotat"):
        screen_rects.button_record(3068, turned, PLUS_BOUNDS, PLUS_MATRIX, ORIGIN)


def test_button_record_refuses_a_button_with_no_up_state():
    with pytest.raises(ValueError, match="up state"):
        screen_rects.button_record(
            3068, PLUS_RECORDS[2:], PLUS_BOUNDS, PLUS_MATRIX, ORIGIN
        )


def test_button_record_refuses_a_sprite_in_the_up_state():
    # The clip reader 3059 is a sprite, so it has no ShapeBounds.
    records = [PLUS_RECORDS[0], replace(PLUS_RECORDS[1], character_id=3059)]
    with pytest.raises(ValueError, match="3068.*3059"):
        screen_rects.button_record(3068, records, PLUS_BOUNDS, PLUS_MATRIX, ORIGIN)


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


# A field that wraps shows more than one line even when it is not multiline.
# This test pins the word_wrap arm of the pitch condition, which the multiline
# wrapping field above does not cover.
def test_text_record_of_a_wrapping_field_with_no_multiline_holds_its_line_pitch():
    wrapping = field(font_height=240, leading=40, multiline=False, word_wrap=True)
    entry = screen_rects.text_record(wrapping, (1.0, 0.0, 0.0, 1.0, 0, 0), ORIGIN)
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


def test_an_art_piece_needs_the_name_of_its_art():
    with pytest.raises(ValueError, match="needs the name of its art"):
        screen_rects.Piece("art", 7)


def test_an_art_set_piece_needs_the_name_of_its_set():
    with pytest.raises(ValueError, match="needs the name of its art"):
        screen_rects.Piece("art_set", 7)


def test_the_clock_ring_set_lists_every_render_of_both_frames():
    crop, textures = screen_rects.art_set_sources()["clock_ring"]
    assert crop["relative_to"] == "stage"
    assert len(textures) == 2 * 121
    assert textures[0] == "res://assets/ui/battle/clock/enemy_000.png"
    assert textures[-1] == "res://assets/ui/battle/clock/friend_120.png"


# A Panel's shape is one solid fill and one stroked line in one style set. 2989
# is the victory frame's left Panel: a 20 twip black line round a #373737 fill.
PANEL_FILL = (55, 55, 55, 255)
PANEL_LINE = (20, (0, 0, 0, 255))


def panel_styles(**changes) -> StyleSet:
    base = StyleSet(
        (PANEL_FILL,), (PANEL_LINE,), frozenset({1}), {1: (-2490, -2671, 2491, 2672)}
    )
    return replace(base, **changes)


def test_one_fill_and_line_is_the_fill_and_the_line_of_a_plain_panel():
    assert screen_rects.one_fill_and_line([panel_styles()], 2989) == (
        PANEL_FILL,
        PANEL_LINE,
    )


@pytest.mark.parametrize(
    ("sets", "message"),
    [
        ([panel_styles(), panel_styles()], "2 style sets"),
        ([panel_styles(used_fills=frozenset({2}))], "fill 1"),
        ([panel_styles(used_fills=frozenset({1, 2}))], "fill 1"),
        ([panel_styles(fills=(None,))], "solid"),
        ([panel_styles(lines=(), line_bounds={})], "one line"),
        ([panel_styles(lines=(PANEL_LINE, PANEL_LINE))], "one line"),
    ],
)
def test_one_fill_and_line_refuses_a_shape_that_is_not_one_fill_and_one_line(
    sets, message
):
    with pytest.raises(ValueError, match=message):
        screen_rects.one_fill_and_line(sets, 2989)


# The euro sign is static text of one line: edit text 2861, "€" and a paragraph
# mark. A Label that shows it has to show the same character.
def test_text_record_of_one_line_of_static_text_holds_its_text_without_the_paragraph_mark():
    static = field(multiline=True, variable_name=None, initial_text="€\r")
    entry = screen_rects.text_record(static, (1.0, 0.0, 0.0, 1.0, 0, 0), ORIGIN)
    assert entry["text"] == "€"


def test_text_record_of_a_field_the_game_fills_holds_no_text():
    entry = screen_rects.text_record(field(), (1.0, 0.0, 0.0, 1.0, 0, 0), ORIGIN)
    assert "text" not in entry


# The info spots of zones 1 to 5: each button's press script calls
# krinNavHideUI(n) with the n that ZONE_SPOTS names it by. Neither the depth nor
# the button id runs in the order of n, so a typed pair that is off by one
# would still pass the rect test, which reads the record the pair builds.
def test_each_info_spot_names_the_number_its_button_press_shows():
    shown = {}
    for zone, spots in enumerate(screen_rects.ZONE_SPOTS, 1):
        for n, (_depth, button) in spots.items():
            script = (
                ACTION_SCRIPT
                / f"DefineButton2_{button}"
                / "BUTTONCONDACTION on(press).as"
            ).read_text()
            assert script.split() == [
                "on(press){",
                f"_root.krinNavHideUI({n});",
                "}",
            ], f"zone {zone} spot {n}, button {button}"
            shown[n] = zone
    assert sorted(shown) == list(range(1, 21))
    assert [n for n, zone in shown.items() if zone > 5] == []


DOLL_SCRIPT = """
dollPartsArray = new Array();
dollPartsArray = ["head","arm1","weapon1"];
dollPartsCores = new Array();
dollPartsCores = [0,1,5];
dollPartsCores2 = new Array();
dollPartsCores2 = ["HEAD","ARM","WEAPON"];
"""
DOLL_PARTS = [("head", "HEAD"), ("arm1", "ARM"), ("weapon1", "WEAPON")]
# The rig's stand pose: [a, b, c, d, tx, ty] in px for each part.
DOLL_RIG = {
    "head": [1.0, 0.0, 0.0, 1.0, 5.0, -34.0],
    "arm1": [0.8, 0.4, -0.4, 0.8, -7.0, -20.0],
    "weapon1": [0.9, 0.5, -0.5, 0.9, 9.0, -19.0],
}
DOLL_OFFSETS = {
    "M_SHEAD_ONE": {"x": -10.0, "y": -20.0, "w": 20.0, "h": 24.0},
    "HAIR_ONE": {"x": -12.0, "y": -30.0, "w": 24.0, "h": 20.0},
    "M_SARM_ONE": {"x": 0.0, "y": 0.0, "w": 10.0, "h": 30.0},
}


def mirrored_doll(scale, x0, y0, rig=DOLL_RIG):
    """-> the layers of a frame that places the rig mirrored and scaled by
    `scale`, with its origin at (x0, y0) px: each part, its _f twin and the
    ground shadow."""
    layers = {}
    depth = 912
    layers[depth] = timeline.Layer(143)
    for suffix in ("", "_f"):
        for name, (a, b, c, d, tx, ty) in rig.items():
            depth += 1
            layers[depth] = timeline.Layer(
                121,
                name + suffix,
                (-scale * a, scale * b, -scale * c, scale * d,
                 round((x0 - scale * tx) * 20), round((y0 + scale * ty) * 20)),
            )  # fmt: skip
    return layers


def test_the_doll_parts_are_read_in_the_order_of_the_scripts_array():
    assert screen_rects.doll_parts(DOLL_SCRIPT) == DOLL_PARTS


def test_a_doll_script_with_another_count_of_codes_is_refused():
    changed = DOLL_SCRIPT.replace('["HEAD","ARM","WEAPON"]', '["HEAD","ARM"]')
    with pytest.raises(ValueError, match="art codes"):
        screen_rects.doll_parts(changed)


def test_a_doll_script_that_fills_an_array_twice_is_refused():
    with pytest.raises(ValueError, match="dollPartsArray"):
        screen_rects.doll_parts(DOLL_SCRIPT + DOLL_SCRIPT)


def test_the_doll_record_is_the_rigs_stand_pose_mirrored_and_scaled_to_the_placements():
    record = screen_rects.doll_record(
        mirrored_doll(1.5, -200.0, -10.0), DOLL_PARTS, DOLL_RIG, DOLL_OFFSETS, ORIGIN
    )
    assert record["kind"] == "doll"
    assert record["scale"] == [-1.5, 1.5]
    assert record["position"] == pytest.approx([400.5 - 200.0, 222.4 - 10.0])
    assert record["look"] == {"gender": "M", "skin": "ONE", "hair": "ONE"}


def test_the_doll_rect_is_the_union_of_the_art_under_the_male_placements():
    record = screen_rects.doll_record(
        mirrored_doll(1.5, -200.0, -10.0), DOLL_PARTS, DOLL_RIG, DOLL_OFFSETS, ORIGIN
    )
    # The weapon has no skin art, and the head holds the skin and the hair. The
    # head's matrix is the rig's mirrored, so its art spans x from -12 to 12 and
    # y from -30 to 4, each times 1.5, around the head's placed origin.
    head_x = 400.5 - 200.0 - 1.5 * 5.0
    head_y = 222.4 - 10.0 + 1.5 * -34.0
    arm = placed_box(DOLL_RIG["arm1"], "M_SARM_ONE", (-200.0, -10.0))
    left = min(head_x - 1.5 * 12.0, arm[0])
    top = min(head_y - 1.5 * 30.0, arm[1])
    right = max(head_x + 1.5 * 12.0, arm[2])
    bottom = max(head_y + 1.5 * 4.0, arm[3])
    x, y, w, h = record["rect"]
    assert (x, y, x + w, y + h) == pytest.approx((left, top, right, bottom), abs=0.01)


def placed_box(rig, key, at):
    """-> (left, top, right, bottom) of the art `key` under the mirrored
    placement of one rig matrix, with the doll at `at` and scale 1.5."""
    a, b, c, d, tx, ty = rig
    box = DOLL_OFFSETS[key]
    xs, ys = [], []
    for x, y in (
        (box["x"], box["y"]),
        (box["x"] + box["w"], box["y"]),
        (box["x"], box["y"] + box["h"]),
        (box["x"] + box["w"], box["y"] + box["h"]),
    ):
        xs.append(ORIGIN[0] + at[0] + -1.5 * (a * x + c * y + tx))
        ys.append(ORIGIN[1] + at[1] + 1.5 * (b * x + d * y + ty))
    return min(xs), min(ys), max(xs), max(ys)


def test_a_part_with_the_rigs_rotation_but_another_scale_is_refused():
    layers = mirrored_doll(1.5, -200.0, -10.0)
    arm = layers[914]
    assert arm.name == "arm1"
    layers[914] = replace(arm, matrix=(arm.matrix[0] * 1.5, *arm.matrix[1:]))
    with pytest.raises(ValueError, match="arm1 is not the rig's stand pose"):
        screen_rects.doll_record(layers, DOLL_PARTS, DOLL_RIG, DOLL_OFFSETS, ORIGIN)


def test_one_part_origin_off_the_pose_does_not_move_the_doll():
    layers = mirrored_doll(1.5, -200.0, -10.0)
    arm = layers[914]
    layers[914] = replace(
        arm, matrix=(*arm.matrix[:4], arm.matrix[4] + 20, arm.matrix[5] - 20)
    )
    record = screen_rects.doll_record(
        layers, DOLL_PARTS, DOLL_RIG, DOLL_OFFSETS, ORIGIN
    )
    assert record["position"] == pytest.approx([400.5 - 200.0, 222.4 - 10.0])


def test_a_frame_with_no_female_set_gives_the_same_doll():
    full = mirrored_doll(1.5, -200.0, -10.0)
    male_only = {
        depth: layer
        for depth, layer in full.items()
        if not (layer.name or "").endswith("_f")
    }
    assert len(male_only) == 4
    record = screen_rects.doll_record(
        male_only, DOLL_PARTS, DOLL_RIG, DOLL_OFFSETS, ORIGIN, female_set=False
    )
    assert record == screen_rects.doll_record(
        full, DOLL_PARTS, DOLL_RIG, DOLL_OFFSETS, ORIGIN
    )


def test_a_frame_that_places_the_female_set_is_refused_when_none_is_expected():
    with pytest.raises(ValueError, match="7 doll clips, not 4"):
        screen_rects.doll_record(
            mirrored_doll(1.5, -200.0, -10.0),
            DOLL_PARTS,
            DOLL_RIG,
            DOLL_OFFSETS,
            ORIGIN,
            female_set=False,
        )


def test_a_frame_with_another_count_of_doll_clips_is_refused():
    layers = mirrored_doll(1.5, -200.0, -10.0)
    del layers[912]
    with pytest.raises(ValueError, match="6 doll clips, not 7"):
        screen_rects.doll_record(layers, DOLL_PARTS, DOLL_RIG, DOLL_OFFSETS, ORIGIN)


# The element bar block (sprite 2877) holds each layer of a bar as a sprite
# that holds a sprite that holds the shape, each placed with its own matrix.
# These are the matrices the web build uses for bar 0's dim layer (2873, 2871,
# shape 2870) and its track (2876, 2875, shape 333).
def _bar_chain(monkeypatch):
    from types import SimpleNamespace

    def layer(character_id, matrix):
        return SimpleNamespace(character_id=character_id, matrix=matrix)

    held = {
        2873: [layer(2871, (1.0, 0.0, 0.0, 1.0, 0, -680))],
        2871: [
            layer(2870, (0.0206451416015625, 0.0, 0.0, 0.2266693115234375, -110, -680))
        ],
        2876: [layer(2875, (1.0, 0.0, 0.0, 1.0, 0, 0))],
        2875: [
            layer(333, (0.0213775634765625, 0.0, 0.0, 0.1876983642578125, -141, -798))
        ],
    }
    monkeypatch.setattr(
        screen_rects.timeline,
        "frames",
        lambda _index, owner: [dict(enumerate(held[owner]))],
    )
    kinds = {2873: "sprite", 2871: "sprite", 2876: "sprite", 2875: "sprite"}
    monkeypatch.setattr(
        screen_rects, "character_kind", lambda _index, cid: kinds.get(cid, "shape")
    )
    return layer


def test_a_shape_inside_nested_sprites_is_placed_through_every_matrix(monkeypatch):
    layer = _bar_chain(monkeypatch)
    placed = layer(2873, (1.0, 0.0, 0.0, 1.0, -1260, 675))
    shape, matrix = screen_rects.through_sprites(None, placed)
    assert shape == 2870
    # The two sprites only move the shape, so its own scale stays and the
    # translations add: -1260 + 0 + -110 and 675 + -680 + -680.
    assert matrix == pytest.approx(
        (0.0206451416015625, 0.0, 0.0, 0.2266693115234375, -1370, -685)
    )
    rect = screen_rects.stage_rect((0, 0, 10660, 6000), matrix, (400.5, 256.0))
    assert rect == pytest.approx((332.0, 221.75, 11.0, 68.0), abs=0.01)


def test_a_scaled_sprite_scales_the_translation_of_the_shape_inside_it(monkeypatch):
    layer = _bar_chain(monkeypatch)
    placed = layer(2873, (2.0, 0.0, 0.0, 3.0, 10, 20))
    _shape, matrix = screen_rects.through_sprites(None, placed)
    assert matrix[:4] == pytest.approx(
        (2.0 * 0.0206451416015625, 0.0, 0.0, 3.0 * 0.2266693115234375)
    )
    # The inner translation (0, -680) and then (-110, -680) are scaled by the
    # outer matrix: 2 * -110 + 10 and 3 * (-680 + -680) + 20.
    assert matrix[4:] == pytest.approx((-210, -4060))


def test_the_track_is_a_black_13_by_70_box_through_two_sprites(monkeypatch):
    layer = _bar_chain(monkeypatch)
    placed = layer(2876, (1.0, 0.0, 0.0, 1.0, -1260, 0))
    shape, matrix = screen_rects.through_sprites(None, placed)
    assert shape == 333
    rect = screen_rects.stage_rect((534, 521, 12694, 7980), matrix, (400.5, 256.0))
    assert rect == pytest.approx((331.0, 221.0, 13.0, 70.0), abs=0.05)


def test_a_sprite_that_holds_two_things_is_refused(monkeypatch):
    layer = _bar_chain(monkeypatch)
    held = screen_rects.timeline.frames
    monkeypatch.setattr(
        screen_rects.timeline,
        "frames",
        lambda index, owner: [
            {**held(index, owner)[0], 9: layer(2870, (1.0, 0.0, 0.0, 1.0, 0, 0))}
        ],
    )
    with pytest.raises(ValueError, match="2873"):
        screen_rects.through_sprites(None, layer(2873, (1.0, 0.0, 0.0, 1.0, 0, 0)))


def test_a_rotated_sprite_in_the_chain_is_refused(monkeypatch):
    layer = _bar_chain(monkeypatch)
    with pytest.raises(ValueError, match="rotates or skews"):
        screen_rects.through_sprites(None, layer(2873, (1.0, 0.5, 0.0, 1.0, 0, 0)))


def test_art_set_record_is_the_crop_and_the_list_of_pngs():
    crop = {
        "rect": [54.525, 99.2, 187.25, 141.25],
        "relative_to": "stage",
        "size": [749, 565],
        "zoom": 4.0,
    }
    textures = ["res://store/shop0.png", "res://store/shop1.png"]
    assert screen_rects.art_set_record(crop, textures) == {
        "kind": "art_set",
        "rect": [54.525, 99.2, 187.25, 141.25],
        "textures": textures,
        "size": [749, 565],
        "zoom": 4.0,
    }


def test_art_set_record_refuses_a_crop_measured_from_a_sprite():
    crop = {
        "rect": [0, 0, 1, 1],
        "relative_to": "sprite 3036",
        "size": [4, 4],
        "zoom": 4.0,
    }
    with pytest.raises(ValueError, match="sprite 3036"):
        screen_rects.art_set_record(crop, ["a.png"])


def test_art_set_record_refuses_an_empty_list():
    crop = {"rect": [0, 0, 1, 1], "relative_to": "stage", "size": [4, 4], "zoom": 4.0}
    with pytest.raises(ValueError, match="at least one"):
        screen_rects.art_set_record(crop, [])


# The skills frame places the ring 'selector' at (4602, -1004) twips with a
# scale of 1.0383, and the ring places thing0 at (0, -49.2) px.
SELECTOR_MATRIX = (1.0383, 0.0, 0.0, 1.0383, 4602, -1004)
THING0_MATRIX = (1.0, 0.0, 0.0, 1.0, 0, -984)
IDENTITY = (1.0, 0.0, 0.0, 1.0, 0, 0)


def test_centre_record_scales_the_childs_translation_by_the_holder():
    record = screen_rects.centre_record(SELECTOR_MATRIX, THING0_MATRIX, ORIGIN, None)
    assert record["kind"] == "centre"
    assert record["position"] == pytest.approx(
        [400.5 + 230.1, 222.4 - 50.2 - 1.0383 * 49.2], abs=0.0001
    )
    assert "shadow" not in record


def test_centre_record_holds_the_holders_drop_shadow_with_its_blur():
    drop = shadow(inner=False, blur_x=6.0, blur_y=6.0, distance=4.0, strength=0.5)
    record = screen_rects.centre_record(IDENTITY, IDENTITY, ORIGIN, drop)
    assert record["shadow"] == {
        "offset": [2.8284, 2.8284],
        "color": "00000080",
        "blur": 6.0,
    }


@pytest.mark.parametrize("rotated", ["holder", "child"])
def test_centre_record_refuses_a_rotation(rotated):
    turned = (1.0, 0.5, 0.0, 1.0, 0, 0)
    holder, child = (turned, IDENTITY) if rotated == "holder" else (IDENTITY, turned)
    with pytest.raises(ValueError, match="rotates or skews"):
        screen_rects.centre_record(holder, child, ORIGIN, None)


def test_a_centre_piece_needs_the_name_of_its_child():
    with pytest.raises(ValueError, match="inner_instance"):
        screen_rects.Piece("centre", None, instance="selector")
