# extract_ability_icons's reading of the orb's cooldown count on SWF bytes
# built by hand, so no test needs the gitignored SWF.
from __future__ import annotations

import struct

import pytest
from test_combat_text import translate
from test_swf_index import bits, place2, swf, tag
from urchin_dev.swf.extract import ability_icons
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_EDIT_TEXT,
    TAG_DEFINE_FONT3,
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
