# extract_cutscene_skip's reading of the SKIP button on SWF bytes built by hand,
# so no test needs the gitignored SWF.
from __future__ import annotations

import struct

import pytest
from test_label_layout import field_tags
from test_swf_index import IDENTITY_MATRIX, bits, button_record, label, place2, swf, tag
from urchin_dev.swf.extract import cutscene_skip
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_BUTTON2,
    TAG_DEFINE_SHAPE,
    TAG_SHOW_FRAME,
    parse_swf,
)

# The ids the web build gives the hit shape, the button and its caption.
SHAPE, BUTTON, CAPTION = 291, 3468, 3469
UP, HIT = 0x01, 0x08


def translate(tx: int, ty: int) -> bytes:
    return bits((0, 1), (0, 1), (15, 5), (tx, 15), (ty, 15))


# Scaled 2.5 across and 0.5 down, which are 163840 and 32768 in 16.16 fixed
# point, then moved to (15000, 11000) twips.
SCALED = bits(
    (1, 1), (19, 5), (163840, 19), (32768, 19),
    (0, 1), (15, 5), (15000, 15), (11000, 15),
)  # fmt: skip


def skip_swf(
    *, button_states: int = HIT, caption_cxform: bytes = b"", second_frame: bytes = b""
) -> bytes:
    """A SWF whose first cutscene frame places the button at depth 77 and its
    caption at depth 76 with `caption_cxform`, and whose second one adds
    `second_frame`'s tags to that. The hit shape is a 600 by 600 twip square
    around its origin."""
    square = bits((11, 5), (-300, 11), (300, 11), (-300, 11), (300, 11))
    shape = tag(TAG_DEFINE_SHAPE, struct.pack("<H", SHAPE) + square + b"\0\0\0\0")
    record = button_record(button_states, SHAPE, 1, IDENTITY_MATRIX)
    button = struct.pack("<HBH", BUTTON, 0, 0) + record + b"\0"
    caption = field_tags(multiline=True, variable_name="", text="SKIP\r", cid=CAPTION)
    return swf(
        shape,
        tag(TAG_DEFINE_BUTTON2, button),
        caption,
        label("CS_ONE"),
        place2(77, cid=BUTTON, matrix=SCALED),
        place2(76, cid=CAPTION, matrix=translate(13500, 10900), cxform=caption_cxform),
        tag(TAG_SHOW_FRAME),
        label("CS_TWO"),
        second_frame,
        tag(TAG_SHOW_FRAME),
        frames=2,
    )


def test_the_layout_is_the_hit_area_and_the_caption_where_the_cutscene_frames_put_them():
    layout = cutscene_skip.skip_layout(parse_swf(skip_swf()))
    # The hit square, 600 twips across, is 2.5 times as wide and half as tall on
    # the frame. Its (-300, -300) corner lands at (14250, 10850) twips.
    assert layout["button"] == {"x": 712.5, "y": 542.5, "w": 75.0, "h": 15.0}
    # The caption's bounds start 15 px left of and 2 px above where the frame
    # puts it, at (675, 545), and Flash lays its text out 2 px inside them.
    assert layout["text"] == {
        "align": "right",
        "color": "#ffffff",
        "rect": {"x": 662.0, "y": 545.0, "w": 116.0, "h": 17.0},
        "size": 12.0,
        "string": "SKIP",
    }


def test_a_button_that_draws_in_a_visible_state_is_refused():
    # The port draws the caption and nothing for the button, so art in the up
    # state would be dropped without a word.
    with pytest.raises(RuntimeError, match="hit"):
        cutscene_skip.skip_layout(parse_swf(skip_swf(button_states=UP | HIT)))


def test_a_cutscene_frame_that_moves_the_button_is_refused():
    moved = place2(77, move=True, matrix=translate(15000, 11000))
    with pytest.raises(RuntimeError, match="CS_TWO"):
        cutscene_skip.skip_layout(parse_swf(skip_swf(second_frame=moved)))


def test_a_caption_with_a_colour_transform_is_refused():
    # Half alpha. The Label would draw the caption at full strength, so the
    # layout would be wrong without a word.
    half = bits((0, 1), (1, 1), (10, 4), (256, 10), (256, 10), (256, 10), (128, 10))
    with pytest.raises(RuntimeError, match="colour transform"):
        cutscene_skip.skip_layout(parse_swf(skip_swf(caption_cxform=half)))
