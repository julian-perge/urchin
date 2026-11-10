# The parser on SWF bytes built by hand, so no test needs the gitignored SWF.
from __future__ import annotations

import struct

from urchin_dev.swf.swf_index import (
    TAG_DEFINE_EDIT_TEXT,
    TAG_DEFINE_FONT3,
    TAG_DEFINE_SHAPE,
    TAG_DEFINE_SHAPE3,
    TAG_DEFINE_SPRITE,
    TAG_DO_ACTION,
    TAG_END,
    TAG_FRAME_LABEL,
    TAG_PLACE_OBJECT2,
    TAG_REMOVE_OBJECT2,
    TAG_SHOW_FRAME,
    TAG_SOUND_STREAM_BLOCK,
    EditText,
    Font,
    Placement,
    Removal,
    edit_text,
    first_fill_bitmap_id,
    font,
    parse_swf,
    shape_bounds,
    sound_stream,
)


def tag(code: int, body: bytes = b"") -> bytes:
    if len(body) < 0x3F:
        return struct.pack("<H", code << 6 | len(body)) + body
    return struct.pack("<HI", code << 6 | 0x3F, len(body)) + body


def label(name: str) -> bytes:
    return tag(TAG_FRAME_LABEL, name.encode() + b"\0")


def swf(*tags: bytes, frames: int = 1) -> bytes:
    # A RECT with 0 bits per field is the single byte 0, then the frame rate
    # and the frame count.
    body = b"\0" + struct.pack("<HH", 30 << 8, frames) + b"".join(tags)
    body += tag(TAG_END)
    return b"FWS" + bytes([9]) + struct.pack("<I", 8 + len(body)) + body


def bits(*fields: tuple[int, int]) -> bytes:
    """Pack (value, width) fields big-endian into whole bytes."""
    text = "".join(format(v & ((1 << w) - 1), f"0{w}b") for v, w in fields)
    text += "0" * (-len(text) % 8)
    return int(text, 2).to_bytes(len(text) // 8, "big")


def test_label_names_the_frame_its_show_frame_closes():
    index = parse_swf(
        swf(
            label("first"),
            tag(TAG_SHOW_FRAME),
            tag(TAG_SHOW_FRAME),
            label("third"),
            tag(TAG_SHOW_FRAME),
            frames=3,
        )
    )
    assert [(lb.owner, lb.frame, lb.name) for lb in index.labels] == [
        (0, 1, "first"),
        (0, 3, "third"),
    ]
    assert index.root_frames == 3


def test_nested_sprite_tags_belong_to_the_sprite():
    sprite = struct.pack("<HH", 5, 2) + (
        tag(TAG_SHOW_FRAME) + label("inner") + tag(TAG_SHOW_FRAME) + tag(TAG_END)
    )
    index = parse_swf(
        swf(tag(TAG_DEFINE_SPRITE, sprite), label("outer"), tag(TAG_SHOW_FRAME))
    )
    assert index.sprite_frames == {5: 2}
    assert [(lb.owner, lb.frame, lb.name) for lb in index.labels] == [
        (5, 2, "inner"),
        (0, 1, "outer"),
    ]


def test_place_object2_keeps_clip_depth_after_a_matrix():
    # HasClipDepth | HasName | HasMatrix | HasCharacter. The matrix has no
    # scale or rotate and 5-bit translations, so it ends mid-byte.
    flags = 0x40 | 0x20 | 0x04 | 0x02
    matrix = bits((0, 1), (0, 1), (5, 5), (3, 5), (-4, 5))
    body = (
        bytes([flags])
        + struct.pack("<HH", 2, 1913)
        + matrix
        + b"mask\0"
        + struct.pack("<H", 15)
    )
    index = parse_swf(swf(tag(TAG_PLACE_OBJECT2, body), tag(TAG_SHOW_FRAME)))
    (placed,) = index.placements
    assert (placed.owner, placed.frame, placed.depth) == (0, 1, 2)
    assert (placed.character_id, placed.name, placed.clip_depth) == (1913, "mask", 15)
    assert placed.matrix == (1.0, 0.0, 0.0, 1.0, 3, -4)


def test_do_action_records_goto_label_goto_frame_and_pushed_strings():
    actions = (
        bytes([0x8C]) + struct.pack("<H", 3) + b"GO\0"
        + bytes([0x81]) + struct.pack("<H", 2) + struct.pack("<H", 4)
        + bytes([0x96]) + struct.pack("<H", 7) + b"\0stand\0"
        + b"\0"
    )  # fmt: skip
    index = parse_swf(swf(tag(TAG_SHOW_FRAME), tag(TAG_DO_ACTION, actions), frames=2))
    (block,) = index.code
    assert (block.kind, block.owner, block.frame) == ("frame", 0, 2)
    assert block.goto_labels == ("GO",)
    assert block.goto_frames == (5,)
    assert block.strings == ("GO", "stand")


def test_clip_action_belongs_to_its_placement_and_skips_the_key_code():
    key_press = 1 << 17
    record_actions = bytes([0x8C]) + struct.pack("<H", 4) + b"hit\0" + b"\0"
    record = (
        struct.pack("<I", key_press)
        + struct.pack("<I", 1 + len(record_actions))
        # A key code byte, which the parser would misread as a Push if it
        # took it for the first action.
        + b"\x96"
        + record_actions
    )
    clip_actions = struct.pack("<HI", 0, key_press) + record + struct.pack("<I", 0)
    body = bytes([0x80 | 0x02]) + struct.pack("<HH", 7, 3312) + clip_actions
    index = parse_swf(swf(tag(TAG_PLACE_OBJECT2, body), tag(TAG_SHOW_FRAME)))
    (block,) = index.code
    assert (block.kind, block.owner, block.placed_id, block.depth) == (
        "clip",
        0,
        3312,
        7,
    )
    assert block.goto_labels == ("hit",)


def place2(
    depth: int, *, move=False, cid=None, matrix=b"", cxform=b"", ratio=None, name=None
):
    """A PlaceObject2 body carrying only the fields given."""
    flags = (0x01 if move else 0) | (0x02 if cid is not None else 0)
    flags |= (0x04 if matrix else 0) | (0x08 if cxform else 0)
    flags |= (0x10 if ratio is not None else 0) | (0x20 if name is not None else 0)
    body = bytes([flags]) + struct.pack("<H", depth)
    if cid is not None:
        body += struct.pack("<H", cid)
    body += matrix + cxform
    if ratio is not None:
        body += struct.pack("<H", ratio)
    if name is not None:
        body += name.encode() + b"\0"
    return tag(TAG_PLACE_OBJECT2, body)


def test_place_object2_reads_scale_rotate_colour_and_ratio():
    # Scale 0.5 and 0.5, skew 0.25 and -0.25, all 16.16 in 18 bits, then a
    # translation of (100, -40) twips in 10 bits.
    matrix = bits(
        (1, 1), (18, 5), (32768, 18), (32768, 18),
        (1, 1), (18, 5), (16384, 18), (-16384, 18),
        (10, 5), (100, 10), (-40, 10),
    )  # fmt: skip
    # Add terms only, in 9 bits: red +10, green +20, blue +30, alpha 0.
    cxform = bits((1, 1), (0, 1), (9, 4), (10, 9), (20, 9), (30, 9), (0, 9))
    index = parse_swf(
        swf(
            place2(3, cid=12, matrix=matrix, cxform=cxform, ratio=7),
            tag(TAG_SHOW_FRAME),
        )
    )
    (placed,) = index.placements
    assert placed.matrix == (0.5, 0.25, -0.25, 0.5, 100, -40)
    assert placed.color_transform == (256, 256, 256, 256, 10, 20, 30, 0)
    assert placed.ratio == 7
    assert placed.move is False


def test_removals_and_placements_keep_their_tag_order_per_timeline():
    index = parse_swf(
        swf(
            place2(1, cid=10),
            tag(TAG_SHOW_FRAME),
            tag(TAG_REMOVE_OBJECT2, struct.pack("<H", 1)),
            place2(1, cid=11),
            tag(TAG_SHOW_FRAME),
            frames=2,
        )
    )
    assert [type(e) for e in index.display[0]] == [Placement, Removal, Placement]
    assert [(e.frame, e.depth) for e in index.display[0]] == [(1, 1), (2, 1), (2, 1)]


def test_sound_stream_returns_each_block_body_in_order():
    index = parse_swf(
        swf(
            tag(TAG_SOUND_STREAM_BLOCK, b"\x01\x00\x00\x00one"),
            tag(TAG_SHOW_FRAME),
            tag(TAG_SOUND_STREAM_BLOCK, b"\x01\x00\x00\x00two"),
            tag(TAG_SHOW_FRAME),
            frames=2,
        )
    )
    assert sound_stream(index, 0) == [b"\x01\x00\x00\x00one", b"\x01\x00\x00\x00two"]
    assert sound_stream(index, 5) == []


IDENTITY_MATRIX = bits((0, 1), (0, 1), (0, 5))


def test_shape_bounds_reads_the_rect_in_twips():
    rect = bits((10, 5), (-20, 10), (300, 10), (0, 10), (40, 10))
    body = struct.pack("<H", 30) + rect + b"\0\0\0\0"
    index = parse_swf(swf(tag(TAG_DEFINE_SHAPE, body), tag(TAG_SHOW_FRAME)))
    assert shape_bounds(index, 30) == (-20, 0, 300, 40)


def test_first_fill_bitmap_id_reads_only_the_first_fill_style():
    solid = bytes([0x00]) + b"\0\0\0\xff"
    missing = bytes([0x40]) + struct.pack("<H", 65535) + IDENTITY_MATRIX
    bitmap = bytes([0x41]) + struct.pack("<H", 7) + IDENTITY_MATRIX
    # A RECT, the fill styles, no line styles, zero style bits, EndShapeRecord.
    second = b"\0" + bytes([2]) + solid + missing + b"\0\0\0"
    first = b"\0" + bytes([1]) + bitmap + b"\0\0\0"
    none = b"\0\0\0\0\0"
    index = parse_swf(
        swf(
            tag(TAG_DEFINE_SHAPE3, struct.pack("<H", 1) + second),
            tag(TAG_DEFINE_SHAPE3, struct.pack("<H", 2) + first),
            tag(TAG_DEFINE_SHAPE3, struct.pack("<H", 3) + none),
            tag(TAG_SHOW_FRAME),
        )
    )
    assert [first_fill_bitmap_id(index, cid) for cid in (1, 2, 3)] == [None, 7, None]


def test_edit_text_reads_its_bounds_font_colour_and_layout():
    # Edit text 2849 as the web build stores it. Its flags are HasText,
    # ReadOnly, HasTextColor and HasFont, then HasLayout and NoSelect.
    rect = bits((15, 5), (-40, 15), (14939, 15), (-40, 15), (352, 15))
    body = (
        struct.pack("<H", 2849) + rect + bytes([0x8D, 0x30])
        + struct.pack("<HH", 65, 240) + bytes([0, 0, 0, 255])
        + bytes([2]) + struct.pack("<HHHh", 0, 0, 0, 40)
        + b"combatText\0" + b"combat text goes here\0"
    )  # fmt: skip
    index = parse_swf(swf(tag(TAG_DEFINE_EDIT_TEXT, body), tag(TAG_SHOW_FRAME)))
    assert edit_text(index, 2849) == EditText(
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


def test_edit_text_without_its_optional_fields_reads_them_as_none():
    rect = bits((5, 5), (0, 5), (10, 5), (0, 5), (10, 5))
    body = struct.pack("<H", 7) + rect + bytes([0x60, 0x00]) + b"name\0"
    index = parse_swf(swf(tag(TAG_DEFINE_EDIT_TEXT, body), tag(TAG_SHOW_FRAME)))
    field = edit_text(index, 7)
    assert (field.font_id, field.font_height, field.color) == (None, None, None)
    assert (field.align, field.leading, field.initial_text) == (None, None, None)
    assert (field.multiline, field.word_wrap) == (True, True)
    assert field.variable_name == "name"


def test_a_font_with_no_glyphs_is_a_device_font():
    # DefineFont3 65 as the web build stores it: WideCodes and Bold set,
    # language 1, the name "_sans" with a NUL inside its length, no glyphs.
    sans = struct.pack("<H", 65) + bytes([0x05, 1, 6]) + b"_sans\0" + b"\0\0"
    # The same header with two glyphs, followed by whatever their tables hold.
    embedded = struct.pack("<H", 66) + bytes([0x06, 1, 5]) + b"Arial" + b"\2\0"
    index = parse_swf(
        swf(
            tag(TAG_DEFINE_FONT3, sans),
            tag(TAG_DEFINE_FONT3, embedded + b"\0" * 12),
            tag(TAG_SHOW_FRAME),
        )
    )
    assert font(index, 65) == Font(name="_sans", bold=True, italic=False, glyphs=0)
    assert font(index, 65).device
    assert font(index, 66) == Font(name="Arial", bold=False, italic=True, glyphs=2)
    assert not font(index, 66).device
