# Pins every cutscene to the wrapper the root timeline places on its own
# label's frame, as recorded in label_xref.json, so the mapping can no longer
# shift by one label.
from __future__ import annotations

import json
import struct

from test_swf_index import IDENTITY_MATRIX, place2, swf, tag
from urchin_dev.swf.extract.cutscenes import CUTSCENES, find_broken_bitmap_fill_cids
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
