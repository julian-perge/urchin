# extract_combat_text's reading of the Combat text banner on SWF bytes built
# by hand, so no test needs the gitignored SWF.
from __future__ import annotations

import struct

import pytest
from test_swf_index import bits, place2, swf, tag
from urchin_dev.swf.extract import combat_text
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SHAPE,
    TAG_DEFINE_SPRITE,
    TAG_END,
    TAG_SHOW_FRAME,
    parse_swf,
)

SHOW = tag(TAG_SHOW_FRAME)
INNER = 20
BANNER = 21


def translate(tx: int, ty: int) -> bytes:
    return bits((0, 1), (0, 1), (12, 5), (tx, 12), (ty, 12))


def alpha(multiplier: int) -> bytes:
    """A colour transform with multiply terms only: 1.0 for red, green and
    blue, which the SWF stores as 256, and `multiplier` for alpha."""
    return bits(
        (0, 1), (1, 1), (10, 4), (256, 10), (256, 10), (256, 10), (multiplier, 10)
    )


def banner(*frames: bytes) -> bytes:
    """A sprite BANNER holding the given frame tags, each ending in a
    ShowFrame, with a one-frame sprite INNER holding a shape to place."""
    shape = tag(TAG_DEFINE_SHAPE, struct.pack("<H", 10) + b"\0\0\0\0\0")
    inner = struct.pack("<HH", INNER, 1) + place2(1, cid=10) + SHOW + tag(TAG_END)
    body = struct.pack("<HH", BANNER, len(frames)) + b"".join(frames) + tag(TAG_END)
    return shape + tag(TAG_DEFINE_SPRITE, inner) + tag(TAG_DEFINE_SPRITE, body)


def test_the_motion_is_how_far_each_frame_slides_and_fades_the_inner_clip():
    # The original's frames 1 to 3: nothing, then the inner clip 10 px down
    # and clear, then a step up at 49/256 alpha.
    index = parse_swf(
        swf(
            banner(
                SHOW,
                place2(
                    1,
                    cid=INNER,
                    name="inner",
                    matrix=translate(0, 200),
                    cxform=alpha(0),
                )
                + SHOW,
                place2(1, move=True, matrix=translate(0, 162), cxform=alpha(49)) + SHOW,
            ),
            SHOW,
        )
    )
    alphas, offsets = combat_text.motion(index, BANNER)
    assert alphas == [0.0, 0.0, 49 / 256]
    assert offsets == [0.0, 10.0, 8.1]


def test_a_frame_that_moves_the_inner_clip_sideways_is_refused():
    index = parse_swf(
        swf(
            banner(
                place2(1, cid=INNER, name="inner", matrix=translate(40, 200)) + SHOW
            ),
            SHOW,
        )
    )
    with pytest.raises(RuntimeError, match="frame 1"):
        combat_text.motion(index, BANNER)
