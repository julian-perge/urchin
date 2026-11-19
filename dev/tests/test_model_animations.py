# extract_model_animations' reading of a doll model's timeline on SWF bytes
# built by hand, so no test needs the gitignored SWF.
from __future__ import annotations

import struct

import pytest
from test_swf_index import bits, label, place2, swf, tag
from urchin_dev.swf.extract import model_animations
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
    alphas = model_animations.animations(index, MODEL)["alphas"]
    assert alphas == [{}, {"arm2": 0.9102, "head": 0.9102}]


def test_labels_that_share_a_start_frame_share_its_range():
    # MODEL4 starts Attack_Stab, Attack_Upper and Attack on the same frame, 78,
    # and attack2 starts on frame 93.
    place = place2(1, cid=SHAPE, name="head")
    index = parse_swf(
        swf(
            model(
                label("stand") + place + SHOW,
                label("Attack_Stab") + label("Attack_Upper") + label("Attack") + SHOW,
                SHOW,
                label("attack2") + SHOW,
            ),
            SHOW,
        )
    )
    labels = model_animations.animations(index, MODEL)["labels"]
    assert labels == {
        "stand": {"start": 1, "end": 1},
        "Attack_Stab": {"start": 2, "end": 3},
        "Attack_Upper": {"start": 2, "end": 3},
        "Attack": {"start": 2, "end": 3},
        "attack2": {"start": 4, "end": 4},
    }


def test_depths_give_each_part_its_depth_on_the_first_frame():
    # MODEL4 draws head above arm1, at depths 25 and 23, where MODEL1 draws
    # arm1 above head.
    index = parse_swf(
        swf(
            model(
                place2(23, cid=SHAPE, name="arm1")
                + place2(25, cid=SHAPE, name="head")
                + place2(1, cid=SHAPE, name="shadower")
                + SHOW
            ),
            SHOW,
        )
    )
    assert model_animations.animations(index, MODEL)["depths"] == {
        "arm1": 23,
        "head": 25,
    }


def test_a_part_that_moves_to_another_depth_fails():
    index = parse_swf(
        swf(
            model(
                place2(3, cid=SHAPE, name="head") + SHOW,
                tag(TAG_REMOVE_OBJECT2, struct.pack("<H", 3))
                + place2(5, cid=SHAPE, name="head")
                + SHOW,
            ),
            SHOW,
        )
    )
    with pytest.raises(ValueError, match="head"):
        model_animations.animations(index, MODEL)


def test_each_model_writes_its_own_file():
    assert model_animations.MODELS == {"MODEL1": 166, "MODEL4": 2668}
    assert model_animations.out_path("MODEL4").name == "model4_animations.json"
