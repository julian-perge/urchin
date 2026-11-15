# extract_result_flash's reading of BATTLEFLASH and the root's filter lists on
# SWF bytes built by hand, so no test needs the gitignored SWF.
from __future__ import annotations

import struct

import pytest
from test_avm1 import constant_pool, push, record
from test_swf_index import label, place2, swf, tag
from urchin_dev.swf.extract import result_flash
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SPRITE,
    TAG_DO_ACTION,
    TAG_END,
    TAG_SHOW_FRAME,
    parse_swf,
)

SHOW = tag(TAG_SHOW_FRAME)
STOP = tag(TAG_DO_ACTION, bytes([0x07, 0x00]))
FLASH = 20
GET_VARIABLE = b"\x1c"
GET_MEMBER = b"\x4e"
SET_MEMBER = b"\x4f"
END = b"\0"


def set_filters(to: bytes, then: bytes = b"") -> bytes:
    """A frame script that sets hitTarget.inner.filters to the value `to`
    leaves on the stack, then runs `then`. The pool holds hitTarget, inner,
    filters, _root, DFTF, KrinFilterHit and KrinFilterHeal."""
    return tag(
        TAG_DO_ACTION,
        constant_pool(
            "hitTarget", "inner", "filters", "_root", "DFTF", "KrinFilterHit", "KrinFilterHeal"
        )
        + push(("pool", 0))
        + GET_VARIABLE
        + push(("pool", 1))
        + GET_MEMBER
        + push(("pool", 2))
        + to
        + SET_MEMBER
        + then
        + END,
    )  # fmt: skip


def goto(name: str) -> bytes:
    return record(0x8C, name.encode() + b"\0")


HIT_ON = set_filters(push(("pool", 3)) + GET_VARIABLE + push(("pool", 5)) + GET_MEMBER)
HEAL_ON = set_filters(push(("pool", 3)) + GET_VARIABLE + push(("pool", 6)) + GET_MEMBER)
OFF = set_filters(push(("pool", 4)) + GET_VARIABLE)
OFF_AND_REST = set_filters(push(("pool", 4)) + GET_VARIABLE, goto("none"))

# The clip rests on `none`. `hit` is on for 2 frames, off for 1, on for 1 and
# then goes back. `heal` is on for 1 frame.
FLASH_FRAMES = (
    label("none") + STOP + SHOW,
    label("hit") + HIT_ON + SHOW,
    SHOW,
    OFF + SHOW,
    HIT_ON + SHOW,
    OFF_AND_REST + SHOW,
    label("heal") + HEAL_ON + SHOW,
    OFF_AND_REST + SHOW,
)


def glow_list(name: str, tint: int, **changed) -> bytes:
    """The actions that build the filter list `name` the way
    frame_42/DoAction_3.as:117-123 does: a white inner glow of blur 100 and
    strength 10, then an outer and an inner glow of blur 10 and strength 1 in
    `tint`. `changed` replaces arguments of the white glow."""
    white = {"color": 0xFFFFFF, "blur": 100, "strength": 10, "inner": True, **changed}
    glows = [
        white,
        {"color": tint, "blur": 10, "strength": 1, "inner": False},
        {"color": tint, "blur": 10, "strength": 1, "inner": True},
    ]
    names = [f"{name}{n}" for n in range(3)]
    code = constant_pool(
        *names, name, "flash", "filters", "GlowFilter", "Array", "push"
    )
    for at, glow in enumerate(glows):
        code += (
            push(
                ("pool", at), False, glow["inner"], 1, glow["strength"],
                glow["blur"], glow["blur"], 1, glow["color"], 8, ("pool", 4),
            )
            + GET_VARIABLE
            + push(("pool", 5))
            + GET_MEMBER
            + push(("pool", 6))
            + b"\x53\x3c"
        )  # fmt: skip
    code += push(("pool", 3), 0.0, ("pool", 7)) + b"\x40\x3c"
    for at in range(3):
        code += (
            push(("pool", at))
            + GET_VARIABLE
            + push(1, ("pool", 3))
            + GET_VARIABLE
            + push(("pool", 8))
            + b"\x52\x17"
        )
    return code


def flash_swf(frames: tuple[bytes, ...], *lists: bytes) -> bytes:
    """A SWF whose root frame runs one script that builds `lists` and places
    the sprite FLASH, holding `frames`, as BATTLEFLASH."""
    body = struct.pack("<HH", FLASH, len(frames)) + b"".join(frames) + tag(TAG_END)
    return swf(
        tag(TAG_DEFINE_SPRITE, body),
        tag(TAG_DO_ACTION, b"".join(lists) + END),
        place2(1, cid=FLASH, name="BATTLEFLASH"),
        SHOW,
    )


HIT_LIST = glow_list("KrinFilterHit", 0xFFCC00)
HEAL_LIST = glow_list("KrinFilterHeal", 0x99FF00)


def test_the_layout_has_each_labels_color_and_frames_and_the_two_glows():
    index = parse_swf(flash_swf(FLASH_FRAMES, HIT_LIST, HEAL_LIST))
    assert result_flash.flash_layout(index) == {
        "white_glow": {"blur": 100, "strength": 10},
        "color_glow": {"blur": 10, "strength": 1},
        "labels": {
            "hit": {"color": "ffcc00", "frames": [True, True, False, True]},
            "heal": {"color": "99ff00", "frames": [True]},
        },
    }


def test_a_label_that_runs_into_the_next_label_is_refused():
    frames = (
        label("none") + STOP + SHOW,
        label("hit") + HIT_ON + SHOW,
        label("heal") + HEAL_ON + SHOW,
        OFF_AND_REST + SHOW,
    )
    index = parse_swf(flash_swf(frames, HIT_LIST, HEAL_LIST))
    with pytest.raises(RuntimeError, match="label 'hit' never goes back to 'none'"):
        result_flash.flash_layout(index)


def test_a_label_that_ends_with_the_filter_on_is_refused():
    on_and_rest = set_filters(
        push(("pool", 3)) + GET_VARIABLE + push(("pool", 5)) + GET_MEMBER, goto("none")
    )
    frames = (label("none") + STOP + SHOW, label("hit") + on_and_rest + SHOW)
    index = parse_swf(flash_swf(frames, HIT_LIST))
    with pytest.raises(RuntimeError, match="frame 2 jumps"):
        result_flash.flash_layout(index)


@pytest.mark.parametrize(
    "heal_list, refusal",
    [
        (glow_list("KrinFilterHeal", 0x99FF00, inner=False), "KrinFilterHeal is"),
        (glow_list("KrinFilterHeal", 0x99FF00, color=0xFF0000), "KrinFilterHeal is"),
        (glow_list("KrinFilterHeal", 0x99FF00, blur=50), "differ in blur or strength"),
    ],
    ids=["an outer first glow", "a red first glow", "a blur that one label changes"],
)
def test_a_filter_list_the_shader_does_not_draw_is_refused(heal_list, refusal):
    index = parse_swf(flash_swf(FLASH_FRAMES, HIT_LIST, heal_list))
    with pytest.raises(RuntimeError, match=refusal):
        result_flash.flash_layout(index)
