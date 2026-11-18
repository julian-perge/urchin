# extract_doll_shadow's reading of each model's `shadower` clip, on SWF bytes
# built by hand, so no test needs the gitignored SWF.
from __future__ import annotations

import json
import re
import struct

import pytest
from test_swf_index import bits, place2, swf, tag
from urchin_dev import REPO_ROOT
from urchin_dev.swf.extract import doll_shadow
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SHAPE,
    TAG_DEFINE_SPRITE,
    TAG_END,
    TAG_EXPORT_ASSETS,
    TAG_SHOW_FRAME,
    parse_swf,
)

SHOW = tag(TAG_SHOW_FRAME)
SHAPE = 10
SHADOW = 20
OTHER_SHADOW = 21
MODEL_A = 30
MODEL_B = 31
NOT_A_MODEL = 32


def sprite(sprite_id: int, *frames: bytes) -> bytes:
    body = struct.pack("<HH", sprite_id, len(frames)) + b"".join(frames)
    return tag(TAG_DEFINE_SPRITE, body + tag(TAG_END))


def exports(**names: int) -> bytes:
    body = struct.pack("<H", len(names))
    for name, cid in names.items():
        body += struct.pack("<H", cid) + name.encode() + b"\0"
    return tag(TAG_EXPORT_ASSETS, body)


# A matrix with no scale and no skew that moves by (dx, dy) twips, in 11 bits.
def translate(dx: int, dy: int) -> bytes:
    return bits((0, 1), (0, 1), (11, 5), (dx, 11), (dy, 11))


def model(model_id: int, shadow: int, dx: int, dy: int, name="shadower") -> bytes:
    return sprite(
        model_id, place2(1, cid=shadow, matrix=translate(dx, dy), name=name) + SHOW
    )


def build(*models: bytes, **names: int) -> bytes:
    shape = tag(TAG_DEFINE_SHAPE, struct.pack("<H", SHAPE) + b"\0\0\0\0\0")
    return swf(
        shape,
        sprite(SHADOW, place2(1, cid=SHAPE) + SHOW),
        sprite(OTHER_SHADOW, place2(1, cid=SHAPE) + SHOW),
        *models,
        exports(**names),
        SHOW,
    )


def test_each_model_gets_the_shadow_clip_and_the_matrix_it_places_it_with():
    index = parse_swf(
        build(
            model(MODEL_A, SHADOW, 719, 0),
            model(MODEL_B, SHADOW, 40, -100),
            MODEL1=MODEL_A,
            MODEL2=MODEL_B,
        )
    )
    clip, matrices = doll_shadow.shadow_placements(index)
    assert clip == SHADOW
    assert matrices == {
        "MODEL1": (1.0, 0.0, 0.0, 1.0, 35.95, 0.0),
        "MODEL2": (1.0, 0.0, 0.0, 1.0, 2.0, -5.0),
    }


def test_an_export_that_is_not_a_model_is_left_out():
    index = parse_swf(
        build(
            model(MODEL_A, SHADOW, 0, 0),
            model(NOT_A_MODEL, SHADOW, 0, 0),
            MODEL1=MODEL_A,
            MODELLER=NOT_A_MODEL,
        )
    )
    _, matrices = doll_shadow.shadow_placements(index)
    assert list(matrices) == ["MODEL1"]


def test_a_model_with_no_shadower_is_refused():
    index = parse_swf(build(model(MODEL_A, SHADOW, 0, 0, name="floor"), MODEL1=MODEL_A))
    with pytest.raises(RuntimeError, match="MODEL1 .* 0 clips named 'shadower'"):
        doll_shadow.shadow_placements(index)


def test_models_that_use_two_clips_are_refused():
    index = parse_swf(
        build(
            model(MODEL_A, SHADOW, 0, 0),
            model(MODEL_B, OTHER_SHADOW, 0, 0),
            MODEL1=MODEL_A,
            MODEL2=MODEL_B,
        )
    )
    with pytest.raises(RuntimeError, match="2 different clips"):
        doll_shadow.shadow_placements(index)


# The committed output, which the Fighter presenter reads. Each unit names its
# model in dev/converted_json/units.json.
def models_in_units() -> set[str]:
    text = (REPO_ROOT / "dev/converted_json/units.json").read_text()
    return set(re.findall(r"MODEL\d+", text))


def test_the_committed_output_has_a_placement_for_every_model_a_unit_uses():
    layout = json.loads((REPO_ROOT / "resources/sprites/doll_shadow.json").read_text())
    assert set(layout["models"]) == models_in_units()
    assert {"x", "y", "w", "h"} <= set(layout["rect"])
    assert (REPO_ROOT / "resources/sprites/doll_shadow.png").is_file()
