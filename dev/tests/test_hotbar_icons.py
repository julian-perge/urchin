# Checks the committed hotbar icons against the record extract_hotbar_icons
# wrote next to them, and the extractor's filter decoding, hover ranges and job
# list on bytes and timelines built by hand, so these tests never read the SWF
# or run ffdec. The extractor's own renders are checked by running it twice
# (see #218).
from __future__ import annotations

import json
import math
import struct
from types import SimpleNamespace

import pytest
from PIL import Image
from urchin_dev.swf import render, timeline
from urchin_dev.swf.extract import hotbar_icons

RECORD = json.loads(hotbar_icons.RECORD.read_text())

# The hover Glow colours at the end of START, from the table in
# spec/107-hub.md (The hotbar). The spec left World Map's GradientGlow
# undecoded, so it is not here.
SPEC_GLOWS = {
    "inventory": ["#ff66ff"],
    "abilities": ["#66ff66", "#33ff00"],
    "save": ["#00ccff", "#0099ff"],
    "options": ["#ffcc00"],
    "respec": ["#ff66ff", "#6633ff"],
    "achievements": ["#ff9900", "#ff3300"],
}
WORLD_MAP_STOPS = [
    {"alpha": 0, "color": "#00ff00", "ratio": 0},
    {"alpha": 255, "color": "#00ffff", "ratio": 255},
]

# Each icon shape's box on the stage in design px, (x, y, w, h), from the same
# table. The icon is drawn with no Glow, so its rect is this box to the pixel
# the render rounds to.
SHAPE_BOXES = {
    "inventory": (36.73, 479.26, 28.78, 28.62),
    "abilities": (85.94, 478.44, 25.56, 31.01),
    "save": (139.13, 479.39, 20.23, 28.70),
    "options": (183.33, 479.25, 29.15, 29.61),
    "respec": (233.76, 481.16, 24.78, 24.78),
    "achievements": (283.06, 482.40, 24.57, 25.73),
    "world_map": (384.45, 492.75, 31.80, 31.80),
}
EDGE = 0.5


def glow(
    red: int,
    green: int,
    blue: int,
    *,
    alpha: int = 255,
    blurs: tuple[int, int] = (13, 13),
    flags: int = 0x21,
) -> bytes:
    """A Glow filter record: its id, the colour, two blurs in px, the strength
    396/256 and the flags. Flags 0x21 are an outer Glow under the icon with
    one blur pass."""
    fixed = struct.pack("<iih", blurs[0] << 16, blurs[1] << 16, 396)
    return bytes([2, red, green, blue, alpha]) + fixed + bytes([flags])


def gradient_glow(*stops: tuple[int, int, int, int, int], distance: int = 0) -> bytes:
    """A GradientGlow filter record from (red, green, blue, alpha, ratio)
    stops: its id, the count, every colour, every ratio, then two blurs of 17
    px, the angle, the distance in px, the strength 465/256 and the flags."""
    colours = b"".join(bytes(stop[:4]) for stop in stops)
    ratios = bytes(stop[4] for stop in stops)
    fixed = struct.pack("<iiiih", 17 << 16, 17 << 16, 0, distance << 16, 465)
    return bytes([4, len(stops)]) + colours + ratios + fixed + bytes([0x21])


def held(name: str) -> list[dict]:
    """-> the Glows of the frame the clip holds while the pointer is on the
    button, the last frame of START."""
    return RECORD["icons"][name]["frames"][RECORD["hover"]["start"][1] - 1]


def test_every_icon_the_extractor_renders_is_in_the_record():
    assert sorted(RECORD["icons"]) == sorted(hotbar_icons.ICONS)


def test_every_icon_is_a_png_whose_pixels_are_its_rect_times_the_zoom():
    for name, icon in RECORD["icons"].items():
        with Image.open(hotbar_icons.OUT_DIR / f"{name}.png") as image:
            size = image.size
        _x, _y, width, height = icon["rect"]
        assert icon["zoom"] == hotbar_icons.ZOOM == 5.0, name
        assert math.isclose(width * icon["zoom"], size[0], abs_tol=1e-6), name
        assert math.isclose(height * icon["zoom"], size[1], abs_tol=1e-6), name


@pytest.mark.parametrize("name", sorted(SHAPE_BOXES))
def test_an_icon_sits_on_its_shape_box_with_no_glow_around_it(name):
    assert RECORD["icons"][name]["rect"] == pytest.approx(SHAPE_BOXES[name], abs=EDGE)


@pytest.mark.parametrize("name", sorted(SHAPE_BOXES))
def test_an_icon_is_drawn_in_white_only(name):
    with Image.open(hotbar_icons.OUT_DIR / f"{name}.png") as image:
        colours = image.convert("RGBA").getcolors(maxcolors=1 << 20)
    assert {colour[:3] for _count, colour in colours if colour[3]} == {(255, 255, 255)}


def test_the_held_frame_holds_the_glow_colours_of_the_specs_table():
    assert {
        name: [glow["color"] for glow in held(name)] for name in SPEC_GLOWS
    } == SPEC_GLOWS


def test_the_held_frame_of_the_world_map_holds_both_stops_of_its_gradient():
    assert held("world_map") == [
        {"blur": 17.0, "gradient": WORLD_MAP_STOPS, "inner": False, "strength": 1.8164}
    ]
    others = [glow for name in SPEC_GLOWS for glow in held(name)]
    assert all("gradient" not in glow for glow in others)


def test_the_held_frame_holds_the_blur_the_strength_and_the_side_of_each_glow():
    assert held("inventory") == [
        {"blur": 13.0, "color": "#ff66ff", "inner": False, "strength": 1.5469}
    ]
    assert held("achievements") == [
        {"blur": 7.0, "color": "#ff9900", "inner": True, "strength": 1.0},
        {"blur": 13.0, "color": "#ff3300", "inner": False, "strength": 1.5469},
    ]


def test_every_icon_holds_the_glows_of_each_frame_of_both_runs():
    last = RECORD["hover"]["stop"][1]
    for name, icon in RECORD["icons"].items():
        assert len(icon["frames"]) == last, name


def test_every_glow_has_no_strength_at_rest_and_at_the_end_of_stop():
    for name, icon in RECORD["icons"].items():
        for frame in (icon["frames"][0], icon["frames"][-1]):
            assert [glow["strength"] for glow in frame] == [0.0] * len(frame), name


def test_the_record_holds_both_hover_ranges_and_the_frame_rate():
    assert RECORD["hover"] == {"frame_rate": 30.0, "start": [2, 7], "stop": [8, 27]}


def test_glow_filters_give_their_values_in_filter_order():
    records = (glow(0x66, 0xFF, 0x66, blurs=(5, 5), flags=0xA1), glow(0x33, 0xFF, 0))
    assert hotbar_icons.glow_record(records) == [
        {"blur": 5.0, "color": "#66ff66", "inner": True, "strength": 1.5469},
        {"blur": 13.0, "color": "#33ff00", "inner": False, "strength": 1.5469},
    ]


def test_a_gradient_glow_gives_every_stop_lowest_ratio_first():
    record = gradient_glow((0, 255, 255, 255, 255), (0, 255, 0, 0, 0))
    assert hotbar_icons.glow_record((record,)) == [
        {"blur": 17.0, "gradient": WORLD_MAP_STOPS, "inner": False, "strength": 1.8164}
    ]


@pytest.mark.parametrize(
    ("record", "message"),
    [
        (glow(1, 2, 3, alpha=128), "alpha"),
        (glow(1, 2, 3, blurs=(13, 5)), "differ"),
        (glow(1, 2, 3, flags=0x61), "knock"),
        (glow(1, 2, 3, flags=0x01), "knock"),
        (glow(1, 2, 3, flags=0x22), "one blur pass"),
        (gradient_glow((0, 0, 0, 0, 0), (0, 0, 0, 255, 128)), "0 and 255"),
        (gradient_glow((0, 0, 0, 0, 0), (0, 0, 0, 255, 255), distance=4), "distance"),
    ],
)
def test_a_glow_the_shader_does_not_draw_is_refused(record, message):
    with pytest.raises(ValueError, match=message):
        hotbar_icons.glow_values(record)


@pytest.mark.parametrize(
    "records",
    [
        (),
        (bytes([0]) + bytes(23),),
        (glow(1, 2, 3), gradient_glow((0, 0, 0, 0, 0))),
        (gradient_glow((0, 0, 0, 0, 0)), gradient_glow((0, 0, 0, 0, 0))),
    ],
)
def test_any_other_filter_list_is_refused(records):
    with pytest.raises(ValueError):
        hotbar_icons.glow_record(records)


def stub_stops(monkeypatch, labels, stops):
    monkeypatch.setattr(timeline, "labels", lambda index, owner: labels)
    monkeypatch.setattr(
        render, "runs_stop", lambda index, sprite, frame: frame in stops
    )
    return SimpleNamespace(sprite_frames={9: 27})


def test_a_hover_range_runs_from_its_label_to_the_next_stop(monkeypatch):
    index = stub_stops(monkeypatch, {"START": 2, "STOP": 8}, {1, 7, 27})
    assert hotbar_icons.hover_ranges(index, 9) == {"start": [2, 7], "stop": [8, 27]}


def test_a_hover_range_ends_on_its_label_frame_when_that_frame_stops(monkeypatch):
    index = stub_stops(monkeypatch, {"START": 2, "STOP": 8}, {2, 27})
    assert hotbar_icons.hover_ranges(index, 9) == {"start": [2, 2], "stop": [8, 27]}


def test_a_hover_range_with_no_stop_after_its_label_is_refused(monkeypatch):
    index = stub_stops(monkeypatch, {"START": 2, "STOP": 8}, {1, 7})
    with pytest.raises(ValueError, match="STOP"):
        hotbar_icons.hover_ranges(index, 9)


def test_each_icon_is_rendered_alone_on_the_hub_with_its_clip_on_frame_1(monkeypatch):
    hub = {
        126: timeline.Layer(3185),
        153: timeline.Layer(3171, name="ui_but1"),
        163: timeline.Layer(3156, name="ui_but6"),
    }
    monkeypatch.setattr(timeline, "frame_of", lambda index, owner, label: 2)
    monkeypatch.setattr(timeline, "frames", lambda index, owner: [{}, hub])
    monkeypatch.setattr(
        hotbar_icons, "ICONS", {"inventory": "ui_but1", "world_map": "ui_but6"}
    )
    assert hotbar_icons.jobs(None) == {
        "inventory": render.Job(0, 2, 5.0, only_depths=(153,), goto=((153, 1),)),
        "world_map": render.Job(0, 2, 5.0, only_depths=(163,), goto=((163, 1),)),
    }


@pytest.mark.parametrize(
    "hub",
    [
        {},
        {
            153: timeline.Layer(3171, name="ui_but1"),
            154: timeline.Layer(3171, name="ui_but1"),
        },
    ],
)
def test_an_icon_the_hub_does_not_place_once_is_refused(monkeypatch, hub):
    monkeypatch.setattr(timeline, "frame_of", lambda index, owner, label: 1)
    monkeypatch.setattr(timeline, "frames", lambda index, owner: [hub])
    monkeypatch.setattr(hotbar_icons, "ICONS", {"inventory": "ui_but1"})
    with pytest.raises(ValueError, match="ui_but1"):
        hotbar_icons.jobs(None)


def test_the_hover_frames_are_the_glows_of_the_one_depth_of_each_frame(monkeypatch):
    rest = {1: timeline.Layer(3170, filter_records=(glow(0xFF, 0, 0),))}
    full = {1: timeline.Layer(3170, filter_records=(glow(0xFF, 0x66, 0xFF),))}
    monkeypatch.setattr(timeline, "frames", lambda index, owner: [rest, full])
    assert [
        [glow["color"] for glow in frame]
        for frame in hotbar_icons.hover_frames(None, 3171)
    ] == [["#ff0000"], ["#ff66ff"]]


def test_a_hover_frame_that_shows_two_depths_is_refused(monkeypatch):
    layer = timeline.Layer(3170, filter_records=(glow(1, 2, 3),))
    monkeypatch.setattr(timeline, "frames", lambda index, owner: [{1: layer, 2: layer}])
    with pytest.raises(ValueError, match="2 depths"):
        hotbar_icons.hover_frames(None, 3171)


def test_a_hover_frame_with_another_number_of_glows_is_refused(monkeypatch):
    one = {1: timeline.Layer(3170, filter_records=(glow(1, 2, 3),))}
    two = {1: timeline.Layer(3170, filter_records=(glow(1, 2, 3), glow(4, 5, 6)))}
    monkeypatch.setattr(timeline, "frames", lambda index, owner: [one, two])
    with pytest.raises(ValueError, match="frame 2 has 2 Glows"):
        hotbar_icons.hover_frames(None, 3171)
