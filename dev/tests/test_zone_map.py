# Checks the World map art against the record extract_zone_map wrote next to
# it, and the extractor's job list and record math on values built by hand, so
# these tests never read the SWF or run ffdec. The renders are checked by
# running the extractor twice.
from __future__ import annotations

import json

import pytest
from PIL import Image
from urchin_dev.swf import render
from urchin_dev.swf.extract import zone_map
from urchin_dev.swf.swf_index import DropShadow

RECORD = json.loads(zone_map.RECORD.read_text())


def test_the_locked_button_moves_the_nested_face_to_its_blank_frame():
    art, opened, locked = zone_map.jobs(blank_frame=2)
    assert art.timeline == zone_map.MAP_SPRITE
    assert art.hide_depths == ((zone_map.MAP_SPRITE, zone_map.FRAME_DEPTH),)
    assert opened.only_depths == locked.only_depths == (zone_map.BUTTON_DEPTH,)
    assert opened.nested_goto == ()
    assert locked.nested_goto == ((zone_map.BUTTON_SPRITE, zone_map.FACE_DEPTH, 2),)


def test_a_button_rect_is_measured_from_the_sprite_it_sits_in():
    # mb1 sits at (-283.0, 180.25) in krinMapper, in twips here.
    matrix = (1.0, 0.0, 0.0, 1.0, -5660, 3605)
    assert zone_map.in_sprite((-299.125, 164.1, 36.8, 36.8), matrix) == [
        -16.125,
        -16.15,
        36.8,
        36.8,
    ]


def test_a_scaled_placement_has_no_one_origin():
    with pytest.raises(ValueError, match="scales or turns"):
        zone_map.in_sprite((0, 0, 1, 1), (2.0, 0.0, 0.0, 2.0, 0, 0))


def test_the_links_shadow_keeps_its_alpha_apart_from_its_colour():
    shadow = DropShadow(
        color=(0, 0, 0, 255),
        blur_x=2.0,
        blur_y=2.0,
        angle=45.0,
        distance=5.0,
        strength=0.609375,
        inner=False,
        knockout=False,
    )
    assert zone_map.shadow_entry(shadow) == {
        "color": "#000000",
        "alpha": 1.0,
        "blur": [2.0, 2.0],
        "angle": 45.0,
        "distance": 5.0,
        "strength": 0.609375,
    }


def test_an_inner_shadow_is_refused():
    shadow = DropShadow((0, 0, 0, 255), 2.0, 2.0, 45.0, 5.0, 1.0, True, False)
    with pytest.raises(ValueError, match="plain outer shadow"):
        zone_map.shadow_entry(shadow)


def test_the_two_button_states_share_one_rect_and_one_size():
    art = RECORD["art"]
    assert art["zone_button_open"] == art["zone_button_locked"]


@pytest.mark.parametrize("name", ["zone_map", "zone_button_open", "zone_button_locked"])
def test_each_png_is_its_rect_times_its_zoom(name):
    entry = RECORD["art"][name]
    with Image.open(zone_map.OUT_DIR / f"{name}.png") as image:
        assert list(image.size) == entry["size"]
    for length, pixels in zip(entry["rect"][2:], entry["size"], strict=True):
        assert round(length * entry["zoom"]) == pixels
    assert entry["relative_to"] in (
        f"sprite {zone_map.MAP_SPRITE}",
        f"sprite {zone_map.BUTTON_SPRITE}",
    )


def test_the_map_art_is_rendered_at_the_hub_zoom():
    assert RECORD["art"]["zone_map"]["zoom"] == zone_map.MAP_ZOOM
    assert render.TWIPS == 20
