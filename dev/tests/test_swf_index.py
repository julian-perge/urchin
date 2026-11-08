# The parser on SWF bytes built by hand, so no test needs the gitignored SWF.
from __future__ import annotations

import struct

from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SPRITE,
    TAG_DO_ACTION,
    TAG_END,
    TAG_FRAME_LABEL,
    TAG_PLACE_OBJECT2,
    TAG_SHOW_FRAME,
    parse_swf,
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
