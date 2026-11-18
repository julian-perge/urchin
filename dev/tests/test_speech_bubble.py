# extract_speech_bubble's reading of the fighter rig on SWF bytes built by hand,
# so no test needs the gitignored SWF.
from __future__ import annotations

import struct

import pytest
from test_shield_clip import RESTING_CLIP, RIG, SHAPE, SHIELD, SPEECH, sprite
from test_swf_index import bits, place2, swf, tag
from urchin_dev.swf.extract import speech_bubble
from urchin_dev.swf.swf_index import TAG_DEFINE_SHAPE, TAG_SHOW_FRAME, parse_swf

SHOW = tag(TAG_SHOW_FRAME)


def mirrored(tx: int, ty: int) -> bytes:
    """A matrix with an x scale of -1 and a y scale of 1, which is how the
    original's rig places its speech clip."""
    return bits(
        (1, 1), (18, 5), (-65536, 18), (65536, 18), (0, 1), (12, 5), (tx, 12), (ty, 12)
    )


def rig_with_speech(matrix: bytes) -> bytes:
    """The rig RIG, with its clip "speech" placed with `matrix`."""
    shape = tag(TAG_DEFINE_SHAPE, struct.pack("<H", SHAPE) + b"\0\0\0\0\0")
    return swf(
        shape,
        sprite(SHIELD, *RESTING_CLIP),
        sprite(SPEECH, SHOW),
        sprite(
            RIG,
            place2(35, cid=SHIELD, name="shield")
            + place2(39, cid=SPEECH, name="speech", matrix=matrix)
            + SHOW,
        ),
        SHOW,
    )


def test_the_placement_is_where_the_rig_puts_the_mirrored_clip_in_design_px():
    index = parse_swf(rig_with_speech(mirrored(-213, -1286)))
    assert speech_bubble.rig_placement(index, RIG, "speech") == (-10.65, -64.3)


def test_a_clip_that_the_rig_does_not_mirror_is_refused():
    index = parse_swf(rig_with_speech(b""))
    with pytest.raises(RuntimeError, match="places speech with"):
        speech_bubble.rig_placement(index, RIG, "speech")
