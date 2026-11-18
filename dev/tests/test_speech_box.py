# extract_speech_box's reading of the skip hint's pulse on SWF bytes built by
# hand, so no test needs the gitignored SWF.
from __future__ import annotations

import struct

import pytest
from test_swf_index import bits, place2, swf, tag
from urchin_dev.swf.extract import speech_box
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SHAPE,
    TAG_DEFINE_SPRITE,
    TAG_END,
    TAG_SHOW_FRAME,
    parse_swf,
)

SHOW = tag(TAG_SHOW_FRAME)
TEXT_CLIP = 20


def tint(multiplier: int, added: int) -> bytes:
    """A colour transform that multiplies red, green and blue by `multiplier`
    over 256 and adds `added` to each, as the hint's pulse does. Alpha keeps
    its multiply of 256 and adds nothing."""
    return bits(
        (1, 1), (1, 1), (10, 4),
        (multiplier, 10), (multiplier, 10), (multiplier, 10), (256, 10),
        (added, 10), (added, 10), (added, 10), (0, 10),
    )  # fmt: skip


def translate(tx: int, ty: int) -> bytes:
    return bits((0, 1), (0, 1), (12, 5), (tx, 12), (ty, 12))


def hint(*frames: bytes) -> bytes:
    """The hint clip, DefineSprite 3359, holding the given frame tags, each
    ending in a ShowFrame."""
    shape = tag(TAG_DEFINE_SHAPE, struct.pack("<H", 10) + b"\0\0\0\0\0")
    text = struct.pack("<HH", TEXT_CLIP, 1) + place2(1, cid=10) + SHOW + tag(TAG_END)
    body = struct.pack("<HH", speech_box.HINT_CLIP, len(frames))
    body += b"".join(frames) + tag(TAG_END)
    return shape + tag(TAG_DEFINE_SPRITE, text) + tag(TAG_DEFINE_SPRITE, body)


def test_the_hint_keeps_each_frames_multiply_and_add_on_a_zero_to_one_scale():
    index = parse_swf(
        swf(
            hint(
                place2(1, cid=TEXT_CLIP, matrix=translate(0, 0)) + SHOW,
                place2(1, move=True, cxform=tint(244, 12)) + SHOW,
            ),
            SHOW,
        )
    )
    first, second = speech_box.hint_colors(index)
    assert first == {"add": [0.0, 0.0, 0.0], "alpha": 1.0, "mult": [1.0, 1.0, 1.0]}
    assert second["mult"] == [0.9531, 0.9531, 0.9531]
    assert second["add"] == [0.0471, 0.0471, 0.0471]


def test_a_frame_that_moves_the_hint_text_is_refused():
    index = parse_swf(
        swf(
            hint(
                place2(1, cid=TEXT_CLIP, matrix=translate(0, 0)) + SHOW,
                place2(1, move=True, matrix=translate(20, 0)) + SHOW,
            ),
            SHOW,
        )
    )
    with pytest.raises(RuntimeError, match="moves the text"):
        speech_box.hint_colors(index)


def test_the_numbers_come_out_of_the_conductor_and_the_box_scripts(
    tmp_path, monkeypatch
):
    conductor = tmp_path / "conductor.as"
    conductor.write_text(
        "if(a)\n{\n_root.combatScript._x = 473.3000000000001;\n"
        "_root.combatScript._y = 460.7;\n}\nelse\n{\n"
        "_root.combatScript._x = 21.800000000000008;\n_root.combatScript._y = 460.7;\n}\n"
    )
    box = tmp_path / "box.as"
    box.write_text("setVolume(100 - _alpha / 1.2);\n_alpha = _alpha + 5;\n")
    hint = tmp_path / "hint.as"
    hint.write_text("say = _root.KrinLang[_root.KLangChoosen].MENU[53];\n")
    monkeypatch.setattr(speech_box, "CONDUCTOR", conductor)
    monkeypatch.setattr(speech_box, "BOX_SCRIPT", box)
    monkeypatch.setattr(speech_box, "HINT_SCRIPT", hint)
    assert speech_box.script_numbers() == {
        "alpha_step": 5.0,
        "hint_menu_index": 53,
        "music_divisor": 1.2,
        "x_others": 21.8,
        "x_side_two": 473.3,
        "y": 460.7,
    }


def test_a_conductor_that_places_the_box_three_times_is_refused(tmp_path, monkeypatch):
    conductor = tmp_path / "conductor.as"
    conductor.write_text("_root.combatScript._x = 1;\n" * 3)
    monkeypatch.setattr(speech_box, "CONDUCTOR", conductor)
    with pytest.raises(RuntimeError, match="want 2 and 1"):
        speech_box.script_numbers()
