# extract_model1_animations' reading of the doll's timeline on SWF bytes built
# by hand, so no test needs the gitignored SWF.
from __future__ import annotations

import struct

from test_swf_index import bits, place2, swf, tag
from urchin_dev.swf.extract import model1_animations
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SHAPE,
    TAG_DEFINE_SPRITE,
    TAG_END,
    TAG_SHOW_FRAME,
    parse_swf,
)

SHOW = tag(TAG_SHOW_FRAME)
SHAPE = 10
MODEL = 20


def cxform(rgb: int, alpha: int) -> bytes:
    """A colour transform with multiply terms only: `rgb` for red, green and
    blue and `alpha` for alpha, where the SWF stores 1.0 as 256."""
    return bits((0, 1), (1, 1), (10, 4), (rgb, 10), (rgb, 10), (rgb, 10), (alpha, 10))


def model(*frames: bytes) -> bytes:
    """A shape, and a sprite MODEL holding the given frame tags, each ending
    in a ShowFrame."""
    shape = tag(TAG_DEFINE_SHAPE, struct.pack("<H", SHAPE) + b"\0\0\0\0\0")
    body = struct.pack("<HH", MODEL, len(frames)) + b"".join(frames) + tag(TAG_END)
    return shape + tag(TAG_DEFINE_SPRITE, body)


def test_each_frame_lists_the_parts_its_colour_transforms_fade():
    # MODEL1 darkens its back limbs on every frame with red, green and blue
    # alone, and its dead label fades every part, starting at 233/256 on
    # frame 361.
    index = parse_swf(
        swf(
            model(
                place2(1, cid=SHAPE, name="arm2", cxform=cxform(154, 256))
                + place2(2, cid=SHAPE, name="head")
                + SHOW,
                place2(1, move=True, cxform=cxform(163, 233))
                + place2(2, move=True, cxform=cxform(256, 233))
                + SHOW,
            ),
            SHOW,
        )
    )
    alphas = model1_animations.animations(index, MODEL)["alphas"]
    assert alphas == [{}, {"arm2": 0.9102, "head": 0.9102}]
