# Checks the committed window chrome art against the record extract_window_chrome
# wrote next to it, and the extractor's job list on a stubbed timeline, so these
# tests never read the SWF or run ffdec. The extractor's own renders are checked
# by running it twice (see #161).
from __future__ import annotations

import json
import math

import pytest
from PIL import Image
from urchin_dev import REPO_ROOT
from urchin_dev.checks import backdrop_rim
from urchin_dev.swf import render, timeline
from urchin_dev.swf.extract import window_chrome

CHROME_DIR = REPO_ROOT / "assets" / "ui" / "window"
RECORD = json.loads((CHROME_DIR / "window_chrome.json").read_text())

# The pieces rendered as sprites of their own. Every other piece is on the stage.
OWN_SPRITE = {
    "slot_inventory": "sprite 2986",
    "xp_gloss_victory": "sprite 3002",
}

# Each piece's shape box on the stage in design px, (x, y, w, h), from the hub
# and window-shell specs, which read them from timeline.frames(). The art is
# the shape with its filters, so its rect has to hold the box and may reach
# past it by a Glow or DropShadow margin and no more.
SHAPE_BOXES = {
    "backdrop": (14.15, 15.00, 768.55, 425.10),
    "close_x": (734.55, 29.75, 36.70, 36.40),
    "hotbar_square": (31.52, 473.79, 40.25, 40.25),
    "hotbar_world_map": (376.32, 484.30, 48.73, 48.73),
    "hotbar_quit": (436.08, 464.91, 18.02, 18.00),
    "hotbar_quit_red": (436.10, 464.90, 18.00, 18.00),
    "zone_track": (505.00, 515.25, 251.40, 14.05),
    "zone_fill": (504.70, 515.25, 251.40, 14.05),
}
FILTER_MARGIN = 25.0
EDGE = 0.5


def test_every_piece_the_extractor_renders_is_in_the_record():
    assert sorted(RECORD) == sorted(window_chrome.PIECES)


def test_every_piece_is_a_png_whose_pixels_are_its_rect_times_the_zoom():
    for name, piece in RECORD.items():
        with Image.open(CHROME_DIR / f"{name}.png") as image:
            size = image.size
        _x, _y, width, height = piece["rect"]
        assert piece["zoom"] == window_chrome.ZOOM, name
        assert math.isclose(width * piece["zoom"], size[0], abs_tol=1e-6), name
        assert math.isclose(height * piece["zoom"], size[1], abs_tol=1e-6), name


def test_a_piece_is_relative_to_its_own_sprite_only_when_it_is_rendered_alone():
    for name, piece in RECORD.items():
        assert piece["relative_to"] == OWN_SPRITE.get(name, "stage"), name


@pytest.mark.parametrize("name", sorted(SHAPE_BOXES))
def test_a_stage_piece_holds_its_shape_and_reaches_past_it_by_a_filter_margin(name):
    x, y, width, height = RECORD[name]["rect"]
    box_x, box_y, box_w, box_h = SHAPE_BOXES[name]
    assert x <= box_x + EDGE
    assert y <= box_y + EDGE
    assert x + width >= box_x + box_w - EDGE
    assert y + height >= box_y + box_h - EDGE
    assert box_x - x <= FILTER_MARGIN
    assert box_y - y <= FILTER_MARGIN
    assert x + width - (box_x + box_w) <= FILTER_MARGIN
    assert y + height - (box_y + box_h) <= FILTER_MARGIN


def test_the_quit_red_square_has_no_filter_so_it_is_its_shape_box():
    x, y, width, height = RECORD["hotbar_quit_red"]["rect"]
    assert (x, y) == pytest.approx((436.10, 464.90), abs=EDGE)
    assert (width, height) == pytest.approx((18.0, 18.0), abs=EDGE)


def test_the_backdrop_rim_matches_a_real_capture_and_the_same_art_shifted_does_not():
    assert backdrop_rim.rim_p90() <= 3
    assert backdrop_rim.rim_p90(shift=20) > 3


def test_squares_that_differ_by_a_subpixel_phase_are_the_same_art():
    # Six hotbar squares sit at x positions that are not whole zoom 4 pixels,
    # so ffdec's anti-aliased edges differ by a few levels and one column.
    first = Image.new("RGBA", (215, 216), (30, 30, 30, 255))
    wider = Image.new("RGBA", (216, 216), (30, 30, 30, 255))
    wider.putpixel((0, 0), (46, 30, 30, 255))
    assert window_chrome.same_art(first, first.copy())
    assert window_chrome.same_art(first, wider)


def test_squares_of_another_colour_or_size_are_not_the_same_art():
    first = Image.new("RGBA", (215, 216), (30, 30, 30, 255))
    other_colour = Image.new("RGBA", (215, 216), (60, 30, 30, 255))
    other_size = Image.new("RGBA", (218, 216), (30, 30, 30, 255))
    assert not window_chrome.same_art(first, other_colour)
    assert not window_chrome.same_art(first, other_size)


def layer() -> timeline.Layer:
    return timeline.Layer(
        character_id=1,
        name=None,
        matrix=timeline.IDENTITY,
        color_transform=None,
        clip_depth=None,
        ratio=None,
        filters=(),
        blend_mode=None,
    )


def stub_swf(monkeypatch, menu_frames):
    """Make window_chrome read `menu_frames` as KRINMENU's frames, the hub as
    frame 181, KRINMENU at (400.5, 222.4) and the zone bar at (630.7, 522.25)."""
    monkeypatch.setattr(timeline, "frame_of", lambda index, owner, label: 181)
    monkeypatch.setattr(timeline, "frames", lambda index, owner: menu_frames)
    origins = {3142: (400.5, 222.4), 3149: (630.7, 522.25)}
    monkeypatch.setattr(
        render, "placement_origin", lambda index, owner, frame, cid: origins[cid]
    )


def test_the_backdrop_hides_every_depth_of_krinmenu_on_every_frame_but_its_own(
    monkeypatch,
):
    stub_swf(monkeypatch, [{2: layer(), 5: layer()}, {2: layer(), 9: layer()}])
    assert window_chrome.backdrop_hides(None) == ((3142, 5), (3142, 9))


def test_each_piece_renders_the_timeline_and_depth_that_places_it(monkeypatch):
    stub_swf(monkeypatch, [{2: layer(), 5: layer()}])
    by_name = window_chrome.jobs(None, (3138,))
    assert list(by_name) == list(window_chrome.PIECES)
    menu = (400.5, 222.4)
    assert by_name["close_x"] == render.Job(3142, 1, 4.0, menu, only_depths=(1431,))
    assert by_name["sell_slot"].frame == 16
    assert by_name["xp_gloss_victory"].timeline == 3002
    assert by_name["xp_gloss_victory"].only_depths == (41,)
    for frame, name in ((1, "achievement_plate_1"), (2, "achievement_plate_2")):
        plate = by_name[name]
        assert (plate.timeline, plate.frame, plate.origin) == (3142, 45, menu)
        assert plate.goto == ((7, frame),)
        assert plate.strip == (3138,)
    backdrop = by_name["backdrop"]
    assert (backdrop.timeline, backdrop.frame) == (0, 181)
    assert backdrop.only_depths == (175,)
    assert backdrop.hide_depths == ((3142, 5),)
    assert by_name["zone_track"].hide_depths == ((3149, 2),)
    assert by_name["zone_fill"].origin == (630.7, 522.25)
    assert by_name["hotbar_quit_red"].only_depths == (152,)


def test_a_job_with_an_origin_or_on_the_root_is_on_the_stage():
    assert window_chrome.relative_to(render.Job(0, 181, 4.0)) == "stage"
    assert (
        window_chrome.relative_to(render.Job(3142, 1, 4.0, (400.5, 222.4))) == "stage"
    )
    assert window_chrome.relative_to(render.Job(2986, 1, 4.0)) == "sprite 2986"
