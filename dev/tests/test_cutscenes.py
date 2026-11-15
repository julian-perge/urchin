# Pins every cutscene to the wrapper the root timeline places on its own
# label's frame, as recorded in label_xref.json, so the mapping can no longer
# shift by one label. It also pins each committed clip to the frame count its
# table entry declares.
from __future__ import annotations

import json
import struct
from pathlib import Path

from test_swf_index import IDENTITY_MATRIX, place2, swf, tag
from urchin_dev.swf.extract.cutscenes import (
    CONTENT_X,
    CONTENT_Y,
    CUTSCENES,
    OUT_DIR,
    OUT_H,
    OUT_W,
    find_broken_bitmap_fill_cids,
)
from urchin_dev.swf.label_xref import OUT
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SHAPE3,
    TAG_DEFINE_SPRITE,
    TAG_END,
    TAG_SHOW_FRAME,
    parse_swf,
)


def test_each_cutscene_uses_the_wrapper_on_its_own_label_frame():
    xref = json.loads(OUT.read_text())
    root = {r["label"]: r for r in xref["labels"] if r["sprite"] == 0}
    for label, (_animation, wrapper, _frames, _overlay) in CUTSCENES.items():
        assert root[label]["places"] == [wrapper], label


OGG_PAGE = struct.Struct("<4sBBqIIIB")
THEORA_HEADER = struct.Struct(">7sBBBHH3s3sBBII3s3sB3sH")


def ogv_frame_count(path: Path) -> int:
    """Count the frames of an Ogg Theora file from its container alone, so the
    test needs no ffprobe, which a fresh checkout may not have.

    The last page of the Theora stream holds the granule position of the last
    frame. Its low KFGSHIFT bits count the frames since the last keyframe, and
    the bits above them count the frames before that keyframe. A stream of
    version 3.2.1 or later stores a count and not an index, so the two parts
    add up to the frame count as they are. KFGSHIFT is in the header's first
    packet, as bits 5 to 9 of its last 16 bits.
    """
    data = path.read_bytes()
    theora_serial = None
    key_shift = 0
    last_granule = 0
    page = 0
    while page < len(data):
        capture, _version, _flags, granule, serial, _sequence, _crc, segments = (
            OGG_PAGE.unpack_from(data, page)
        )
        if capture != b"OggS":
            raise ValueError(f"{path.name}: no Ogg page at byte {page}")
        body = page + OGG_PAGE.size + segments
        if theora_serial is None and data[body : body + 7] == b"\x80theora":
            theora_serial = serial
            _signature, major, minor, revision, *_fields, last_16_bits = (
                THEORA_HEADER.unpack_from(data, body)
            )
            if (major, minor, revision) < (3, 2, 1):
                raise ValueError(f"{path.name}: Theora {major}.{minor}.{revision}")
            key_shift = (last_16_bits >> 5) & 0x1F
        if serial == theora_serial and granule >= 0:
            last_granule = granule
        page = body + sum(data[page + OGG_PAGE.size : body])
    if theora_serial is None:
        raise ValueError(f"{path.name}: no Theora stream")
    return (last_granule >> key_shift) + (last_granule & ((1 << key_shift) - 1))


def test_each_extracted_clip_is_as_long_as_its_table_entry():
    for label, (_animation, _wrapper, frames, _overlay) in CUTSCENES.items():
        assert ogv_frame_count(OUT_DIR / f"{label}.ogv") == frames, label


def ogv_picture_size(path: Path) -> tuple[int, int]:
    """Read the picture size of an Ogg Theora file from its first packet, so
    the test needs no ffprobe.

    The first page of the Theora stream is the first page of the file here,
    and its packet gives the picture's width and height as two 24-bit numbers.
    The coded frame is larger, because Theora rounds it up to whole 16 px
    blocks.
    """
    data = path.read_bytes()
    body = OGG_PAGE.size + data[OGG_PAGE.size - 1]
    if data[body : body + 7] != b"\x80theora":
        raise ValueError(f"{path.name}: the first Ogg page is not a Theora header")
    fields = THEORA_HEADER.unpack_from(data, body)
    return int.from_bytes(fields[6], "big"), int.from_bytes(fields[7], "big")


def test_each_extracted_clip_is_the_size_of_the_stage():
    for label in CUTSCENES:
        assert ogv_picture_size(OUT_DIR / f"{label}.ogv") == (800, 575), label


def test_the_clip_mask_sits_where_the_original_centers_it_on_the_stage():
    # The wrapper is at (133.5, 137.5) px on the 800x575 Stage, and the pad
    # filter takes whole pixels.
    assert (OUT_W, OUT_H) == (800, 575)
    assert (CONTENT_X, CONTENT_Y) == (133, 137)


def test_only_shapes_whose_first_fill_is_the_missing_bitmap_get_stripped():
    def shape3(cid: int, *fills: bytes) -> bytes:
        styles = bytes([len(fills)]) + b"".join(fills) + b"\0\0\0"
        return tag(TAG_DEFINE_SHAPE3, struct.pack("<H", cid) + b"\0" + styles)

    solid = bytes([0x00]) + b"\0\0\0\xff"
    missing = bytes([0x40]) + struct.pack("<H", 65535) + IDENTITY_MATRIX
    placed = place2(1, cid=1) + place2(2, cid=2) + place2(3, cid=3)
    sprite = tag(
        TAG_DEFINE_SPRITE,
        struct.pack("<HH", 9, 1) + placed + tag(TAG_SHOW_FRAME) + tag(TAG_END),
    )
    index = parse_swf(
        swf(
            shape3(1, missing),
            shape3(2, solid, missing),
            shape3(3, solid),
            shape3(4, missing),
            sprite,
            tag(TAG_SHOW_FRAME),
        )
    )
    assert find_broken_bitmap_fill_cids(index, 9) == {1}
