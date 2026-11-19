# extract_hub_fade's reading of the Hub's fade clip, on SWF bytes built by hand
# and on the clip's own committed ActionScript, so no test needs the gitignored
# SWF.
from __future__ import annotations

import struct

import pytest
from test_swf_index import bits, label, place2, swf, tag
from urchin_dev.swf.extract import hub_fade
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SHAPE3,
    TAG_DEFINE_SPRITE,
    TAG_END,
    TAG_SHOW_FRAME,
    parse_swf,
)

SHAPE, CLIP = 333, hub_fade.FADE_CLIP


def translate(tx: int, ty: int) -> bytes:
    return bits((0, 1), (0, 1), (15, 5), (tx, 15), (ty, 15))


# Scaled 2 across and 1.5 down, which are 131072 and 98304 in 16.16 fixed
# point, then moved to (-200, -100) twips.
SCALED = bits(
    (1, 1), (19, 5), (131072, 19), (98304, 19),
    (0, 1), (15, 5), (-200, 15), (-100, 15),
)  # fmt: skip


def fade_swf(*, rgba: bytes = b"\0\0\0\xff", clip_layers: bytes = b"") -> bytes:
    """A SWF whose frame Navigation places the clip at (8000, 5000) twips. The
    clip shows a shape filled with `rgba` over (-4000, -3000) to (4000, 3000)
    twips, scaled and moved by SCALED, plus `clip_layers`."""
    rect = bits((14, 5), (-4000, 14), (4000, 14), (-3000, 14), (3000, 14))
    fill = b"\x01\x00" + rgba
    shape = tag(TAG_DEFINE_SHAPE3, struct.pack("<H", SHAPE) + rect + fill + b"\0\0\0")
    sprite = struct.pack("<HH", CLIP, 1) + (
        place2(1, cid=SHAPE, matrix=SCALED)
        + clip_layers
        + tag(TAG_SHOW_FRAME)
        + tag(TAG_END)
    )
    return swf(
        shape,
        tag(TAG_DEFINE_SPRITE, sprite),
        label(hub_fade.HUB_FRAME),
        place2(1660, cid=CLIP, matrix=translate(8000, 5000)),
        tag(TAG_SHOW_FRAME),
    )


def test_the_layout_is_the_colour_and_the_rect_the_navigation_frame_shows():
    layout = hub_fade.fade_layout(parse_swf(fade_swf(rgba=b"\x10\x20\x30\xff")))
    # The shape's corner (-4000, -3000) lands at 8000 - 200 - 2 * 4000 = -200
    # and 5000 - 100 - 1.5 * 3000 = 400 twips, and the shape is 16000 by 9000
    # twips on the stage.
    assert layout == {
        "color": "#102030",
        "fps": 30.0,
        "rect": {"x": -10.0, "y": 20.0, "w": 800.0, "h": 450.0},
    }


def test_a_clip_that_shows_a_second_layer_is_refused():
    # The port draws one rect, so the second shape would be dropped without a
    # word.
    second = place2(2, cid=SHAPE, matrix=translate(0, 0))
    with pytest.raises(RuntimeError, match="layers"):
        hub_fade.fade_layout(parse_swf(fade_swf(clip_layers=second)))


def test_a_shape_that_is_not_opaque_is_refused():
    with pytest.raises(RuntimeError, match="opaque"):
        hub_fade.fade_layout(parse_swf(fade_swf(rgba=b"\0\0\0\x80")))


def test_the_clips_own_scripts_start_at_99_and_step_by_15():
    numbers = hub_fade.script_numbers(
        hub_fade.LOAD_SCRIPT.read_text(), hub_fade.ENTER_FRAME_SCRIPT.read_text()
    )
    assert numbers == {"alpha_step": 15, "start_alpha": 99}


def test_a_fade_back_to_black_with_another_step_is_refused():
    # The port records one step, so a second one would be lost without a word.
    enter_frame = "_alpha = _alpha - 15;\n_alpha = _alpha + 10;\n"
    with pytest.raises(RuntimeError, match="down by 15 and up by 10"):
        hub_fade.script_numbers("_alpha = 99;\n", enter_frame)
