# The display list walk on SWF bytes built by hand, so no test needs the
# gitignored SWF.
from __future__ import annotations

import struct

import pytest
from test_swf_index import bits, label, place2, swf, tag
from urchin_dev.swf import timeline
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SHAPE,
    TAG_DEFINE_SPRITE,
    TAG_END,
    TAG_PLACE_OBJECT,
    TAG_PLACE_OBJECT2,
    TAG_REMOVE_OBJECT2,
    TAG_SHOW_FRAME,
    parse_swf,
)
from urchin_dev.swf.timeline import IDENTITY, TimelineError

SHOW = tag(TAG_SHOW_FRAME)


def shape(cid: int) -> bytes:
    # An empty RECT, no fill or line styles, zero style bits, EndShapeRecord.
    return tag(TAG_DEFINE_SHAPE, struct.pack("<H", cid) + b"\0\0\0\0\0")


def sprite(cid: int) -> bytes:
    return tag(TAG_DEFINE_SPRITE, struct.pack("<HH", cid, 1) + SHOW + tag(TAG_END))


def translate(tx: int, ty: int) -> bytes:
    return bits((0, 1), (0, 1), (12, 5), (tx, 12), (ty, 12))


def remove(depth: int) -> bytes:
    return tag(TAG_REMOVE_OBJECT2, struct.pack("<H", depth))


def walk(*tags: bytes, frames: int) -> list[dict]:
    return timeline.frames(parse_swf(swf(*tags, frames=frames)), 0)


def test_a_move_without_a_matrix_keeps_its_depths_matrix():
    # MODEL1 frame 123's foot2 is this case: the tag carries a filter or a
    # colour transform and no matrix, so the part stays where frame 122 put
    # it. Reading a later tag's matrix put it a quarter turn off (#6).
    cxform = bits((1, 1), (0, 1), (6, 4), (10, 6), (0, 6), (0, 6), (0, 6))
    result = walk(
        shape(10),
        place2(1, cid=10, matrix=translate(216, 654)),
        SHOW,
        place2(1, move=True, cxform=cxform),
        SHOW,
        frames=2,
    )
    assert result[0][1].matrix == (1.0, 0.0, 0.0, 1.0, 216, 654)
    assert result[1][1].matrix == (1.0, 0.0, 0.0, 1.0, 216, 654)
    assert result[1][1].color_transform == (256, 256, 256, 256, 10, 0, 0, 0)


def test_a_place_without_a_matrix_starts_from_identity():
    (frame,) = walk(shape(10), place2(4, cid=10), SHOW, frames=1)
    assert frame[4].matrix == IDENTITY
    assert (frame[4].character_id, frame[4].color_transform) == (10, None)


def test_a_replace_swaps_the_character_and_keeps_the_rest():
    result = walk(
        shape(10),
        shape(11),
        place2(2, cid=10, matrix=translate(40, 20), ratio=3),
        SHOW,
        place2(2, move=True, cid=11),
        SHOW,
        frames=2,
    )
    assert result[1][2].character_id == 11
    assert (result[1][2].matrix, result[1][2].ratio) == (result[0][2].matrix, 3)


def test_a_frame_with_no_tags_repeats_the_one_before_and_remove_empties():
    result = walk(shape(10), place2(1, cid=10), SHOW, SHOW, remove(1), SHOW, frames=3)
    assert [sorted(frame) for frame in result] == [[1], [1], []]


@pytest.mark.parametrize(
    ("tags", "message"),
    [
        ((place2(1, cid=10), place2(1, cid=10)), "place on an occupied depth"),
        ((place2(1, move=True, matrix=translate(1, 1)),), "move on an empty depth"),
        ((remove(1),), "RemoveObject on an empty depth"),
        (
            (
                place2(1, cid=10),
                tag(TAG_PLACE_OBJECT2, bytes([0x21]) + struct.pack("<H", 1) + b"b1\0"),
            ),
            "move carrying a name",
        ),
        (
            (
                place2(1, cid=10),
                tag(TAG_PLACE_OBJECT2, bytes([0x41]) + struct.pack("<HH", 1, 3)),
            ),
            "move carrying a name, clipDepth",
        ),
        ((place2(1, cid=10), place2(1, move=True, cid=20)), "involves a shape/sprite"),
        (
            (tag(TAG_PLACE_OBJECT, struct.pack("<HH", 10, 1) + translate(0, 0)),),
            "PlaceObject version 1",
        ),
    ],
)
def test_the_walk_refuses_what_neither_swf_contains(tags, message):
    with pytest.raises(TimelineError, match=message):
        walk(shape(10), sprite(20), *tags, SHOW, frames=1)


def test_a_tag_after_the_last_frame_is_refused():
    with pytest.raises(TimelineError, match="after the last of the timeline's 1"):
        walk(shape(10), SHOW, place2(1, cid=10), frames=1)


def test_the_error_names_the_timeline_frame_and_depth():
    with pytest.raises(TimelineError, match="timeline 0 frame 2 depth 7"):
        walk(SHOW, remove(7), SHOW, frames=2)


def test_labels_match_case_insensitively_and_refuse_a_repeat():
    index = parse_swf(swf(label("White November"), SHOW, label("SEA"), SHOW, frames=2))
    assert timeline.labels(index, 0) == {"White November": 1, "SEA": 2}
    assert timeline.frame_of(index, 0, "white november") == 1
    with pytest.raises(KeyError):
        timeline.frame_of(index, 0, "SKY")
    repeated = parse_swf(swf(label("Sea"), SHOW, label("SEA"), SHOW, frames=2))
    with pytest.raises(TimelineError, match="case-insensitively"):
        timeline.labels(repeated, 0)
