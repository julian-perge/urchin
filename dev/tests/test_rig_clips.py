# extract_rig_clips' reading of the fighter rig on SWF bytes built by hand, so
# no test needs the gitignored SWF.
from __future__ import annotations

import struct

import pytest
from test_swf_index import place2, swf, tag
from test_timeline import remove
from urchin_dev.swf.extract import rig_clips
from urchin_dev.swf.render import RenderError
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SHAPE,
    TAG_DEFINE_SPRITE,
    TAG_DO_ACTION,
    TAG_END,
    TAG_SHOW_FRAME,
    parse_swf,
)

SHOW = tag(TAG_SHOW_FRAME)
# A frame script that runs stop(), the one action the rig's clips have.
STOP = tag(TAG_DO_ACTION, bytes([0x07, 0x00]))
SHAPE = 10
SHIELD = 21
SPEECH = 22
RIG = 23
NESTED = 24


def sprite(sprite_id: int, *frames: bytes) -> bytes:
    """A DefineSprite holding the given frame tags, each ending in a
    ShowFrame."""
    body = struct.pack("<HH", sprite_id, len(frames)) + b"".join(frames)
    return tag(TAG_DEFINE_SPRITE, body + tag(TAG_END))


def rig(shield_frames: tuple[bytes, ...], *nested: bytes) -> bytes:
    """A rig RIG that places a clip SHIELD with the given frames as "shield"
    and a clip SPEECH as "speech", the way DefineSprite 2676 places its
    clips. `nested` holds the sprites SHIELD places."""
    shape = tag(TAG_DEFINE_SHAPE, struct.pack("<H", SHAPE) + b"\0\0\0\0\0")
    return swf(
        shape,
        *nested,
        sprite(SHIELD, *shield_frames),
        sprite(SPEECH, STOP + SHOW, place2(1, cid=SHAPE) + SHOW),
        sprite(
            RIG,
            place2(35, cid=SHIELD, name="shield")
            + place2(39, cid=SPEECH, name="speech")
            + SHOW,
        ),
        SHOW,
    )


# Frame 1 stops the clip and shows nothing, and the clip draws from frame 2.
RESTING_CLIP = (STOP + SHOW, place2(1, cid=SHAPE) + SHOW, SHOW)


def test_a_clip_is_the_sprite_the_rig_places_under_its_name():
    index = parse_swf(rig(RESTING_CLIP))
    assert rig_clips.rig_clip(index, RIG, "shield") == SHIELD
    assert rig_clips.rig_clip(index, RIG, "speech") == SPEECH


def test_a_name_the_rig_does_not_place_is_refused():
    index = parse_swf(rig(RESTING_CLIP))
    with pytest.raises(RuntimeError, match="places 0 clips named 'bubble'"):
        rig_clips.rig_clip(index, RIG, "bubble")


def test_a_clip_that_draws_on_its_frame_1_is_refused():
    index = parse_swf(rig((place2(1, cid=SHAPE) + STOP + SHOW, SHOW)))
    with pytest.raises(RuntimeError, match=f"{SHIELD} frame 1 shows 1 layer"):
        rig_clips.rig_clip(index, RIG, "shield")


# gotoAndPlay("hit"): GoToLabel, then Play.
GOTO_AND_PLAY = tag(
    TAG_DO_ACTION, bytes([0x8C]) + struct.pack("<H", 4) + b"hit\0" + bytes([0x06, 0x00])
)


@pytest.mark.parametrize(
    "frames, error, refusal",
    [
        (
            (SHOW, place2(1, cid=SHAPE) + SHOW),
            RuntimeError,
            r"runs stop\(\) on frames \[\]",
        ),
        (
            (STOP + SHOW, place2(1, cid=SHAPE) + STOP + SHOW),
            RuntimeError,
            r"runs stop\(\) on frames \[1, 2\]",
        ),
        (
            (GOTO_AND_PLAY + SHOW, place2(1, cid=SHAPE) + SHOW),
            RenderError,
            f"timeline {SHIELD} frame 1 moves its playhead",
        ),
    ],
    ids=["no stop on frame 1", "a stop on a later frame", "a jump on frame 1"],
)
def test_a_clip_that_does_more_than_stop_on_frame_1_is_refused(frames, error, refusal):
    index = parse_swf(rig(frames))
    with pytest.raises(error, match=refusal):
        rig_clips.rig_clip(index, RIG, "shield")


def test_a_clip_that_a_nested_clip_ends_early_is_refused():
    # render.played_frames() ends a clip where a clip nested in it stops on an
    # empty frame, and the port plays a rig clip through its last frame before
    # it loops back to frame 1. Here NESTED stops on its empty frame 2, which
    # is the Shield clip's frame 3 of 4.
    nested = sprite(NESTED, place2(1, cid=SHAPE) + SHOW, remove(1) + STOP + SHOW)
    frames = (STOP + SHOW, place2(1, cid=NESTED) + SHOW, SHOW, SHOW)
    index = parse_swf(rig(frames, nested))
    with pytest.raises(RuntimeError, match=r"plays frames \[2, 3\] after play\(\)"):
        rig_clips.rig_clip(index, RIG, "shield")
