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
    TAG_DO_ACTION,
    TAG_END,
    TAG_PLACE_OBJECT2,
    TAG_REMOVE_OBJECT2,
    TAG_SHOW_FRAME,
    parse_swf,
)

SHOW = tag(TAG_SHOW_FRAME)
SHAPE = 10
LOOP = 11
ONCE = 12
EFFECT = 13
TINTED = 14
GLOW = 15
MODEL = 20
STOP = tag(TAG_DO_ACTION, b"\x07\0")


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


def place_with_load(depth: int, cid: int, *strings: str) -> bytes:
    """A PlaceObject2 of `cid` at `depth` whose onClipEvent(load) pushes
    `strings`, as DefineSprite 162 places 161 with setRGB(colortobe)."""
    pushed = b"".join(b"\0" + s.encode() + b"\0" for s in strings)
    actions = bytes([0x96]) + struct.pack("<H", len(pushed)) + pushed + b"\0"
    record = struct.pack("<II", model_pieces.CLIP_EVENT_LOAD, len(actions)) + actions
    clip_actions = (
        struct.pack("<HI", 0, model_pieces.CLIP_EVENT_LOAD)
        + record
        + struct.pack("<I", 0)
    )
    body = bytes([0x80 | 0x02]) + struct.pack("<HH", depth, cid) + clip_actions
    return tag(TAG_PLACE_OBJECT2, body)


def test_a_clip_placed_on_frame_1_loops_with_its_matrix_and_colour_per_frame():
    # MODEL2 places its orb on frame 1 and tints it on later frames.
    index = parse_swf(
        model_swf(
            place2(3, cid=LOOP, matrix=translate(200, 400)) + SHOW,
            place2(3, move=True, cxform=cxform(256, 128)) + SHOW,
        )
    )
    planned = model_pieces.plan(index, MODEL, set())
    assert planned.clips == {LOOP}
    assert planned.looks == {}
    assert planned.frames[0][3] == {
        "clip": str(LOOP),
        "since": 1,
        "matrix": [1.0, 0.0, 0.0, 1.0, 10.0, 20.0],
        "color": [1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0],
    }
    assert planned.frames[1][3]["color"] == [1.0, 1.0, 1.0, 0.5, 0.0, 0.0, 0.0, 0.0]
    assert planned.frames[1][3]["since"] == 1


def test_an_effect_clip_plays_as_a_clip_from_the_frame_that_placed_it():
    # MODEL1 places the stun mark (DefineSprite 165) on the first frame of
    # stun2 and keeps it for 40 frames, past its own 30.
    index = parse_swf(
        model_swf(
            SHOW, place2(33, cid=EFFECT, matrix=translate(20, 40)) + SHOW, SHOW, SHOW
        )
    )
    planned = model_pieces.plan(index, MODEL, {EFFECT})
    assert planned.clips == {EFFECT}
    assert planned.looks == {}
    assert 33 not in planned.frames[0]
    for frame in planned.frames[1:]:
        assert frame[33]["clip"] == str(EFFECT)
        assert frame[33]["since"] == 2
        assert frame[33]["matrix"] == [1.0, 0.0, 0.0, 1.0, 1.0, 2.0]


def test_an_effect_clip_placed_again_after_a_gap_has_a_new_since():
    index = parse_swf(
        model_swf(
            place2(33, cid=EFFECT) + SHOW,
            tag(TAG_REMOVE_OBJECT2, struct.pack("<H", 33)) + SHOW,
            place2(33, cid=EFFECT) + SHOW,
        )
    )
    planned = model_pieces.plan(index, MODEL, {EFFECT})
    assert planned.frames[0][33]["since"] == 1
    assert planned.frames[2][33]["since"] == 3


def test_a_clip_holds_the_frame_whose_script_runs_stop_and_otherwise_loops():
    # The swing trails stop on their frame 12, and the stun mark loops.
    inner = place2(1, cid=SHAPE) + SHOW
    index = parse_swf(
        swf(
            shape(SHAPE)
            + sprite(ONCE, inner, STOP + SHOW, SHOW)
            + sprite(LOOP, inner, SHOW),
            SHOW,
        )
    )
    assert model_pieces.clip_hold(index, ONCE) == 2
    assert model_pieces.clip_hold(index, LOOP) is None


def glow_swf(tinted_depth: int = 1, plain_depth: int = 3) -> bytes:
    """GLOW holds SHAPE at plain_depth and TINTED at tinted_depth, and TINTED
    holds SHAPE with an onClipEvent(load) that runs setRGB(colortobe), as the
    swing trail 149 holds 147, which holds 146."""
    return swf(
        shape(SHAPE)
        + sprite(TINTED, place_with_load(1, SHAPE, "setRGB", "colortobe") + SHOW)
        + sprite(
            GLOW,
            place2(tinted_depth, cid=TINTED) + place2(plain_depth, cid=SHAPE) + SHOW,
        ),
        SHOW,
    )


def test_tint_path_leads_to_the_placement_whose_load_runs_set_rgb_with_colortobe():
    index = parse_swf(glow_swf())
    assert model_pieces.tint_path(index, GLOW) == (
        (GLOW, 1, TINTED),
        (TINTED, 1, SHAPE),
    )
    assert model_pieces.tint_path(index, TINTED) == ((TINTED, 1, SHAPE),)
    assert model_pieces.tint_path(index, SHAPE) == ()


def test_a_load_script_without_colortobe_tints_nothing():
    index = parse_swf(
        swf(
            shape(SHAPE)
            + sprite(TINTED, place_with_load(1, SHAPE, "setRGB", "red") + SHOW),
            SHOW,
        )
    )
    assert model_pieces.tint_path(index, TINTED) == ()


def test_a_tinted_part_above_the_plain_part_fails():
    # The port draws the tinted part behind the rest of its clip, as all four
    # of the original's tinted parts are.
    index = parse_swf(glow_swf(tinted_depth=3, plain_depth=1))
    with pytest.raises(ValueError, match="above"):
        model_pieces.tint_path(index, GLOW)


def test_the_tint_render_hides_every_other_depth_on_the_path_and_the_plain_render_hides_the_tint():
    index = parse_swf(glow_swf())
    path = model_pieces.tint_path(index, GLOW)
    assert model_pieces.plain_hides(path) == ((TINTED, 1),)
    assert model_pieces.tint_hides(index, path) == ((GLOW, 3),)


def test_a_clip_placed_later_shows_the_frame_it_has_reached():
    # MODEL9 places BOOM1 on the first frame of its dead label.
    index = parse_swf(model_swf(SHOW, place2(6, cid=ONCE) + SHOW, SHOW))
    planned = model_pieces.plan(index, MODEL, set())
    assert planned.clips == set()
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


def test_parts_and_the_shadow_are_left_out():
    index = parse_swf(
        model_swf(
            place2(1, cid=SHAPE, name="shadower")
            + place2(5, cid=SHAPE, name="head")
            + SHOW
        )
    )
    planned = model_pieces.plan(index, MODEL, set())
    assert planned.frames == [{}]
    assert planned.clips == set()


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
