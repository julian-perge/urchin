# extract_ability_icons's reading of the orb's cooldown count on SWF bytes
# built by hand, so no test needs the gitignored SWF.
from __future__ import annotations

import struct

import pytest
from PIL import Image
from test_combat_text import translate
from test_swf_index import bits, place2, swf, tag
from urchin_dev.swf import render
from urchin_dev.swf.extract import ability_icons
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_EDIT_TEXT,
    TAG_DEFINE_FONT3,
    TAG_DEFINE_SHAPE,
    TAG_DEFINE_SPRITE,
    TAG_END,
    TAG_SHOW_FRAME,
    parse_swf,
)

SHOW = tag(TAG_SHOW_FRAME)
COUNT_DEPTH = 13


def count_field(variable: str) -> bytes:
    """Edit text 2245 as the web build stores it, in the bold _sans Device
    font DefineFont3 65, with `variable` as its variable name."""
    sans = struct.pack("<H", 65) + bytes([0x05, 1, 6]) + b"_sans\0" + b"\0\0"
    rect = bits((15, 5), (-40, 15), (647, 15), (-40, 15), (341, 15))
    body = (
        struct.pack("<H", ability_icons.COUNT_TEXT) + rect + bytes([0x8D, 0x30])
        + struct.pack("<HH", 65, 240) + bytes([153, 153, 153, 255])
        + bytes([2]) + struct.pack("<HHHh", 0, 0, 0, 40)
        + variable.encode() + b"\0" + b"00\0"
    )  # fmt: skip
    return tag(TAG_DEFINE_FONT3, sans) + tag(TAG_DEFINE_EDIT_TEXT, body)


def orb(*spots: tuple[int, int] | None, variable: str = "ACD") -> bytes:
    """The count's field and an orb sprite with one frame per spot: None for a
    frame without the count, or the (x, y) in twips the frame places it at."""
    frames, placed = b"", False
    for spot in spots:
        if spot is not None:
            frames += place2(
                COUNT_DEPTH,
                move=placed,
                cid=None if placed else ability_icons.COUNT_TEXT,
                matrix=translate(*spot),
            )
            placed = True
        frames += SHOW
    body = struct.pack("<HH", ability_icons.ICON_SPRITE, len(spots))
    return count_field(variable) + tag(TAG_DEFINE_SPRITE, body + frames + tag(TAG_END))


def test_the_count_is_edit_text_2245_laid_out_where_every_frame_places_it():
    # The orb places edit text 2245 at (-15.2, -6.65) on every icon frame and
    # leaves it off the frames before the first icon.
    index = parse_swf(swf(orb(None, (-304, -133), (-304, -133)), SHOW))
    assert ability_icons.count_layout(index) == {
        "align": "center",
        "color": "#999999",
        "rect": {"x": -15.2, "y": -6.65, "w": 30.35, "h": 15.05},
        "size": 12.0,
    }


def test_a_count_placed_in_two_spots_is_refused():
    index = parse_swf(swf(orb((-304, -133), (-300, -133)), SHOW))
    with pytest.raises(RuntimeError, match="2245"):
        ability_icons.count_layout(index)


def test_a_count_field_the_ring_does_not_write_to_is_refused():
    index = parse_swf(swf(orb((-304, -133), variable="combatText"), SHOW))
    with pytest.raises(RuntimeError, match="ACD"):
        ability_icons.count_layout(index)


DISC_SHAPE = 2243


def disc_sheet(*frames: bytes) -> bytes:
    """The disc sprite 2244 holding one shape, and an icon sheet with one
    frame per entry of `frames`, each the place tags of that frame."""
    shape = tag(
        TAG_DEFINE_SHAPE, struct.pack("<H", DISC_SHAPE) + bits((0, 5)) + b"\0\0\0"
    )
    disc = (
        struct.pack("<HH", ability_icons.DISC_SPRITE, 1)
        + place2(1, cid=DISC_SHAPE)
        + SHOW
    )
    body = struct.pack("<HH", ability_icons.ICON_SPRITE, len(frames))
    body += b"".join(placed + SHOW for placed in frames)
    return (
        shape
        + tag(TAG_DEFINE_SPRITE, disc + tag(TAG_END))
        + tag(TAG_DEFINE_SPRITE, body + tag(TAG_END))
    )


def test_the_disc_is_the_placement_named_movecolor_on_each_frame_it_shows():
    # Frame 1 places the disc at depth 4 with no name, as the "Empty" frames
    # do, and frame 2 places it again at depth 1 as moveColor.
    unnamed = place2(4, cid=ability_icons.DISC_SPRITE, matrix=translate(0, 0))
    named = place2(
        1, cid=ability_icons.DISC_SPRITE, matrix=translate(0, 0), name="moveColor"
    )
    index = parse_swf(swf(disc_sheet(unnamed, named), SHOW))
    assert ability_icons.disc_depths(index) == {2: 1}


def test_a_movecolor_off_the_orbs_centre_is_refused():
    named = place2(
        1, cid=ability_icons.DISC_SPRITE, matrix=translate(20, 0), name="moveColor"
    )
    index = parse_swf(swf(disc_sheet(named), SHOW))
    with pytest.raises(RuntimeError, match="moveColor"):
        ability_icons.disc_depths(index)


def test_a_sheet_with_no_movecolor_is_refused():
    unnamed = place2(4, cid=ability_icons.DISC_SPRITE, matrix=translate(0, 0))
    index = parse_swf(swf(disc_sheet(unnamed), SHOW))
    with pytest.raises(RuntimeError, match="never places"):
        ability_icons.disc_depths(index)


def frame_at(canvas_rect: tuple[int, int, int, int]) -> render.Frame:
    job = render.Job(ability_icons.ICON_SPRITE, 1, ability_icons.ZOOM)
    return render.Frame(job, None, (0, 0), canvas_rect, canvas_rect)


def test_the_orb_box_is_centred_on_the_sprites_origin():
    # A canvas whose left edge is at -50 design px puts the origin at canvas
    # x 100 at 2x, so a 62 px box starts 31 px before it.
    assert ability_icons.orb_box(frame_at((-1000, -1040, 0, 0)), (62, 62)) == (
        69,
        73,
        131,
        135,
    )


def test_an_orb_centre_on_half_a_pixel_rounds_up():
    # The icon sheet's canvas starts at -1005 twips, which is canvas x 100.5.
    assert ability_icons.orb_box(frame_at((-1005, -1052, 0, 0)), (62, 62))[:2] == (
        70,
        74,
    )


def test_white_keeps_the_alpha_and_drops_the_colour():
    image = Image.new("RGBA", (2, 1))
    image.putpixel((0, 0), (38, 38, 38, 255))
    image.putpixel((1, 0), (38, 38, 38, 100))
    drawn = ability_icons.white(image)
    assert [drawn.getpixel((0, 0)), drawn.getpixel((1, 0))] == [
        (255, 255, 255, 255),
        (255, 255, 255, 100),
    ]


def test_the_disc_share_is_the_disc_alpha_the_art_leaves_clear():
    disc = Image.new("RGBA", (2, 1), (255, 255, 255, 255))
    icon = Image.new("RGBA", (2, 1))
    icon.putpixel((0, 0), (9, 9, 9, 255))
    assert ability_icons.disc_share(disc, icon) == 0.5
