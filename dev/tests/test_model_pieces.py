# extract_model_pieces' reading of a model's unnamed placements on SWF bytes
# built by hand, so no test needs the gitignored SWF.
from __future__ import annotations

import struct

import pytest
from test_model_animations import cxform
from test_swf_index import bits, place2, swf, tag
from urchin_dev.swf.extract import model_pieces
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SHAPE,
    TAG_DEFINE_SPRITE,
    TAG_END,
    TAG_REMOVE_OBJECT2,
    TAG_SHOW_FRAME,
    parse_swf,
)

SHOW = tag(TAG_SHOW_FRAME)
SHAPE = 10
LOOP = 11
ONCE = 12
EFFECT = 13
MODEL = 20


def shape(cid: int) -> bytes:
    return tag(TAG_DEFINE_SHAPE, struct.pack("<H", cid) + b"\0\0\0\0\0")


def sprite(cid: int, *frames: bytes) -> bytes:
    body = struct.pack("<HH", cid, len(frames)) + b"".join(frames) + tag(TAG_END)
    return tag(TAG_DEFINE_SPRITE, body)


def translate(tx: int, ty: int) -> bytes:
    """A matrix with a translation of (tx, ty) twips and no scale or skew."""
    return bits((0, 1), (0, 1), (12, 5), (tx, 12), (ty, 12))


def model_swf(*frames: bytes) -> bytes:
    """Clips LOOP and ONCE of three frames and EFFECT of two, each showing
    SHAPE, and MODEL holding the given frames."""
    inner = place2(1, cid=SHAPE) + SHOW
    return swf(
        shape(SHAPE)
        + sprite(LOOP, inner, SHOW, SHOW)
        + sprite(ONCE, inner, SHOW, SHOW)
        + sprite(EFFECT, inner, SHOW)
        + sprite(MODEL, *frames),
        SHOW,
    )


def test_a_clip_placed_on_frame_1_loops_with_its_matrix_and_colour_per_frame():
    # MODEL2 places its orb on frame 1 and tints it on later frames.
    index = parse_swf(
        model_swf(
            place2(3, cid=LOOP, matrix=translate(200, 400)) + SHOW,
            place2(3, move=True, cxform=cxform(256, 128)) + SHOW,
        )
    )
    planned = model_pieces.plan(index, MODEL, set())
    assert planned.loops == {3: LOOP}
    assert planned.looks == {}
    assert planned.frames[0][3] == {
        "matrix": [1.0, 0.0, 0.0, 1.0, 10.0, 20.0],
        "color": [1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0],
    }
    assert planned.frames[1][3]["color"] == [1.0, 1.0, 1.0, 0.5, 0.0, 0.0, 0.0, 0.0]


def test_a_clip_placed_later_shows_the_frame_it_has_reached():
    # MODEL9 places BOOM1 on the first frame of its dead label.
    index = parse_swf(model_swf(SHOW, place2(6, cid=ONCE) + SHOW, SHOW))
    planned = model_pieces.plan(index, MODEL, set())
    assert planned.loops == {}
    assert 6 not in planned.frames[0]
    assert planned.frames[1][6] == model_pieces.Look(frame=2, depth=6, child_frame=1)
    assert planned.frames[2][6] == model_pieces.Look(frame=3, depth=6, child_frame=2)


def test_a_shape_shares_one_look_until_its_colour_changes():
    # MODEL8 keeps its two body shapes still and fades them on its dead label.
    index = parse_swf(
        model_swf(
            place2(9, cid=SHAPE) + SHOW,
            SHOW,
            place2(9, move=True, cxform=cxform(256, 128)) + SHOW,
        )
    )
    planned = model_pieces.plan(index, MODEL, set())
    first, second, faded = (frame[9] for frame in planned.frames)
    assert first == second == model_pieces.Look(frame=1, depth=9, child_frame=0)
    assert faded == model_pieces.Look(frame=3, depth=9, child_frame=0)
    assert len(planned.looks) == 2


def test_parts_the_shadow_and_the_effect_clips_are_left_out():
    index = parse_swf(
        model_swf(
            place2(1, cid=SHAPE, name="shadower")
            + place2(5, cid=SHAPE, name="head")
            + place2(33, cid=EFFECT)
            + SHOW
        )
    )
    planned = model_pieces.plan(index, MODEL, {EFFECT})
    assert planned.frames == [{}]
    assert planned.loops == {}


def test_a_named_clip_that_is_not_a_part_fails():
    index = parse_swf(model_swf(place2(5, cid=SHAPE, name="tail") + SHOW))
    with pytest.raises(ValueError, match="tail"):
        model_pieces.plan(index, MODEL, set())


def test_a_clip_placed_again_after_a_gap_starts_from_its_frame_1():
    index = parse_swf(
        model_swf(
            SHOW,
            place2(6, cid=ONCE) + SHOW,
            SHOW,
            tag(TAG_REMOVE_OBJECT2, struct.pack("<H", 6)) + SHOW,
            place2(6, cid=ONCE) + SHOW,
        )
    )
    planned = model_pieces.plan(index, MODEL, set())
    assert planned.frames[4][6].child_frame == 1


def test_a_clip_with_no_stop_shown_past_its_last_frame_fails():
    # ONCE has three frames and no script, so Flash would loop it on frame 4,
    # which a render of one look per frame cannot show.
    index = parse_swf(model_swf(SHOW, place2(6, cid=ONCE) + SHOW, SHOW, SHOW, SHOW))
    with pytest.raises(ValueError, match="no stop"):
        model_pieces.plan(index, MODEL, set())


def test_each_model_writes_its_own_file():
    assert model_pieces.out_path("MODEL8").name == "model8_pieces.json"
