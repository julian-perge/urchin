# Checks the committed hotbar icons against the record extract_hotbar_icons
# wrote next to them, and the extractor's filter decoding, hover ranges and job
# list on bytes and timelines built by hand, so these tests never read the SWF
# or run ffdec. The extractor's own renders are checked by running it twice
# (see #218).
from __future__ import annotations

import json
import math
from types import SimpleNamespace

import pytest
from PIL import Image
from urchin_dev.swf import render, timeline
from urchin_dev.swf.extract import hotbar_icons

RECORD = json.loads(hotbar_icons.RECORD.read_text())

# The hover Glow colours at the end of START, from the table in
# spec/107-hub.md (The hotbar). World Map's are the two GradientGlow stops
# that the spec left undecoded.
SPEC_GLOWS = {
    "inventory": ["#ff66ff"],
    "abilities": ["#66ff66", "#33ff00"],
    "save": ["#00ccff", "#0099ff"],
    "options": ["#ffcc00"],
    "respec": ["#ff66ff", "#6633ff"],
    "achievements": ["#ff9900", "#ff3300"],
    "world_map": ["#00ff00"],
}

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


def glow(red: int, green: int, blue: int) -> bytes:
    """A Glow filter record: its id, the colour, two blurs, the strength and
    the flags."""
    return bytes([2, red, green, blue, 255]) + bytes(8) + bytes([0x8C, 0x01, 0x21])


def gradient_glow(*stops: tuple[int, int, int, int, int]) -> bytes:
    """A GradientGlow filter record from (red, green, blue, alpha, ratio)
    stops: its id, the count, every colour, every ratio, then two blurs, the
    angle, the distance, the strength and the flags."""
    colours = b"".join(bytes(stop[:4]) for stop in stops)
    ratios = bytes(stop[4] for stop in stops)
    return bytes([4, len(stops)]) + colours + ratios + bytes(16) + bytes([0, 1, 0x21])


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


def test_the_record_holds_the_glow_colours_of_the_specs_table():
    assert {name: icon["glow"] for name, icon in RECORD["icons"].items()} == SPEC_GLOWS


def test_the_record_holds_both_stops_of_the_world_map_gradient():
    assert RECORD["icons"]["world_map"]["gradient"] == [
        {"alpha": 0, "color": "#00ff00", "ratio": 0},
        {"alpha": 255, "color": "#00ffff", "ratio": 255},
    ]
    others = [icon for name, icon in RECORD["icons"].items() if name != "world_map"]
    assert all("gradient" not in icon for icon in others)


def test_the_record_holds_both_hover_ranges_and_the_frame_rate():
    assert RECORD["hover"] == {"frame_rate": 30.0, "start": [2, 7], "stop": [8, 27]}


def test_glow_filters_give_their_colours_in_filter_order():
    records = (glow(0x66, 0xFF, 0x66), glow(0x33, 0xFF, 0x00))
    assert hotbar_icons.glow_record(records) == {"glow": ["#66ff66", "#33ff00"]}


def test_a_gradient_glow_gives_its_lowest_ratio_stop_and_every_stop():
    record = gradient_glow((0, 255, 255, 255, 255), (0, 255, 0, 0, 0))
    assert hotbar_icons.glow_record((record,)) == {
        "glow": ["#00ff00"],
        "gradient": [
            {"alpha": 0, "color": "#00ff00", "ratio": 0},
            {"alpha": 255, "color": "#00ffff", "ratio": 255},
        ],
    }


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


def test_the_hover_glow_is_read_from_the_one_depth_of_the_asked_frame(monkeypatch):
    rest = {1: timeline.Layer(3170, filter_records=(glow(0xFF, 0, 0),))}
    full = {1: timeline.Layer(3170, filter_records=(glow(0xFF, 0x66, 0xFF),))}
    monkeypatch.setattr(timeline, "frames", lambda index, owner: [rest, full])
    assert hotbar_icons.hover_glow(None, 3171, 2) == {"glow": ["#ff66ff"]}


def test_a_hover_frame_that_shows_two_depths_is_refused(monkeypatch):
    layer = timeline.Layer(3170, filter_records=(glow(1, 2, 3),))
    monkeypatch.setattr(timeline, "frames", lambda index, owner: [{1: layer, 2: layer}])
    with pytest.raises(ValueError, match="2 depths"):
        hotbar_icons.hover_glow(None, 3171, 1)
