# label_layout's reading of where a Label draws an edit text's line, on fields
# built by hand, so no test needs the gitignored SWF.
from __future__ import annotations

import struct

import pytest
from test_swf_index import bits, swf, tag
from urchin_dev.swf import label_layout
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_EDIT_TEXT,
    TAG_DEFINE_FONT3,
    TAG_SHOW_FRAME,
    EditText,
    parse_swf,
)


def test_the_text_rect_is_the_fields_bounds_inside_flashs_two_pixel_gutter():
    # Edit text 2849's bounds, placed inside the inner clip at (-372.5, -7.8).
    field = EditText(
        bounds=(-40, -40, 14939, 352),
        font_id=65,
        font_height=240,
        color=(0, 0, 0, 255),
        align=2,
        left_margin=0,
        right_margin=0,
        indent=0,
        leading=40,
        multiline=False,
        word_wrap=False,
        html=False,
        variable_name="combatText",
        initial_text="combat text goes here",
    )
    assert label_layout.text_rect(field, (-372.5, -7.8)) == {
        "x": -372.5,
        "y": -7.8,
        "w": 744.95,
        "h": 15.6,
    }


def field_tags(
    *, multiline: bool, variable_name: str, text: str, cid: int = 7
) -> bytes:
    """The tags of the bold Device font 65 and of edit text `cid`, a
    right-aligned white 12 px field with the given multiline flag, variable and
    text."""
    sans = struct.pack("<H", 65) + bytes([0x05, 1, 6]) + b"_sans\0" + b"\0\0"
    rect = bits((13, 5), (-300, 13), (2100, 13), (-40, 13), (380, 13))
    # HasText, Multiline, HasTextColor and HasFont, then HasLayout.
    flags = 0x80 | (0x20 if multiline else 0) | 0x04 | 0x01
    body = (
        struct.pack("<H", cid) + rect + bytes([flags, 0x20])
        + struct.pack("<HH", 65, 240) + bytes([255, 255, 255, 255])
        + bytes([1]) + struct.pack("<HHHh", 0, 0, 0, 40)
        + variable_name.encode() + b"\0" + text.encode() + b"\0"
    )  # fmt: skip
    return tag(TAG_DEFINE_FONT3, sans) + tag(TAG_DEFINE_EDIT_TEXT, body)


def field_swf(*, multiline: bool, variable_name: str, text: str) -> bytes:
    fields = field_tags(multiline=multiline, variable_name=variable_name, text=text)
    return swf(fields, tag(TAG_SHOW_FRAME))


def test_a_static_field_of_one_line_passes_with_its_closing_paragraph_mark():
    # Edit text 3469, the SKIP caption, is static text that was turned into a
    # multiline field with "SKIP\r" in it. It draws one line.
    index = parse_swf(field_swf(multiline=True, variable_name="", text="SKIP\r"))
    assert label_layout.plain_device_line(index, 7).initial_text == "SKIP\r"


def test_a_multiline_field_the_game_fills_is_refused():
    # Whatever the game puts in the field can run to several lines.
    index = parse_swf(field_swf(multiline=True, variable_name="said", text="hi"))
    with pytest.raises(RuntimeError, match="not one plain line"):
        label_layout.plain_device_line(index, 7)


def test_static_text_of_two_lines_is_refused():
    index = parse_swf(field_swf(multiline=True, variable_name="", text="SKIP\rNOW\r"))
    with pytest.raises(RuntimeError, match="not one plain line"):
        label_layout.plain_device_line(index, 7)
