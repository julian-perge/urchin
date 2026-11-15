# extract_floating_numbers' reading of NumberFixer and NumberSetter on SWF
# bytes built by hand, so no test needs the gitignored SWF.
from __future__ import annotations

import struct

import pytest
from PIL import Image
from test_avm1 import constant_pool, define_function2, push, record
from test_swf_index import bits, label, place2, swf, tag
from urchin_dev.swf.extract import floating_numbers
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SHAPE,
    TAG_DEFINE_SPRITE,
    TAG_DO_ACTION,
    TAG_END,
    TAG_REMOVE_OBJECT2,
    TAG_SHOW_FRAME,
    parse_swf,
)

SHOW = tag(TAG_SHOW_FRAME)
HOLDER = 20
WORD = 21
FIXER = 22


def matrix(scale: float = 1.0, tx: int = 0, ty: int = 0) -> bytes:
    """A matrix with an even scale and a translation in twips."""
    fixed = round(scale * 65536)
    return bits(
        (1, 1), (18, 5), (fixed, 18), (fixed, 18),
        (0, 1),
        (12, 5), (tx, 12), (ty, 12),
    )  # fmt: skip


def cxform(multiply: tuple[int, ...], add: tuple[int, ...]) -> bytes:
    """A color transform with both term sets, red, green, blue and alpha."""
    return bits((1, 1), (1, 1), (10, 4), *((v, 10) for v in (*multiply, *add)))


def remove_movie_clip() -> bytes:
    """A frame script that runs removeMovieClip(this): Push "this",
    GetVariable, RemoveSprite."""
    push = bytes([0x96]) + struct.pack("<H", 6) + b"\0this\0"
    return tag(TAG_DO_ACTION, push + bytes([0x1C, 0x25, 0x00]))


def remove(depth: int) -> bytes:
    return tag(TAG_REMOVE_OBJECT2, struct.pack("<H", depth))


def fixer(*frames: bytes) -> bytes:
    """A NumberFixer-like sprite FIXER holding the given frame tags, each
    ending in a ShowFrame, with an empty holder sprite HOLDER and a one-frame
    word sprite WORD to place."""
    shape = tag(TAG_DEFINE_SHAPE, struct.pack("<H", 10) + b"\0\0\0\0\0")
    holder = struct.pack("<HH", HOLDER, 1) + SHOW + tag(TAG_END)
    word = struct.pack("<HH", WORD, 1) + place2(1, cid=10) + SHOW + tag(TAG_END)
    body = struct.pack("<HH", FIXER, len(frames)) + b"".join(frames) + tag(TAG_END)
    return (
        shape
        + tag(TAG_DEFINE_SPRITE, holder)
        + tag(TAG_DEFINE_SPRITE, word)
        + tag(TAG_DEFINE_SPRITE, body)
    )


def test_each_label_runs_to_its_remove_frame_with_the_holders_scale_height_alpha_and_white():
    index = parse_swf(
        swf(
            fixer(
                # normal: the holder pops in all white at 1.5x, settles at 1x
                # 27 twips higher in its own color, then fades to half.
                label("normal")
                + place2(
                    1,
                    cid=HOLDER,
                    name="flasher",
                    matrix=matrix(1.5),
                    cxform=cxform((0, 0, 0, 256), (255, 255, 255, 0)),
                )
                + SHOW,
                place2(
                    1,
                    move=True,
                    matrix=matrix(1.0, ty=-27),
                    cxform=cxform((256, 256, 256, 256), (0, 0, 0, 0)),
                )
                + SHOW,
                place2(1, move=True, cxform=cxform((256, 256, 256, 128), (0, 0, 0, 0)))
                + SHOW,
                remove(1) + remove_movie_clip() + SHOW,
                # miss: the word, clear.
                label("miss")
                + place2(
                    1,
                    cid=WORD,
                    name="flasher",
                    matrix=matrix(1.0),
                    cxform=cxform((256, 256, 256, 0), (0, 0, 0, 0)),
                )
                + SHOW,
                remove(1) + remove_movie_clip() + SHOW,
            ),
            SHOW,
        )
    )
    labels = floating_numbers.number_labels(index, FIXER)
    assert {name: label.holder for name, label in labels.items()} == {
        "normal": HOLDER,
        "miss": WORD,
    }
    assert labels["normal"].frames == [
        {"scale": 1.5, "y": 0.0, "alpha": 1.0, "white": 1.0},
        {"scale": 1.0, "y": -1.35, "alpha": 1.0, "white": 0.0},
        {"scale": 1.0, "y": -1.35, "alpha": 0.5, "white": 0.0},
    ]
    assert labels["miss"].frames == [
        {"scale": 1.0, "y": 0.0, "alpha": 0.0, "white": 0.0}
    ]


def one_frame_label(placed: bytes) -> bytes:
    return swf(
        fixer(label("normal") + placed + SHOW, remove(1) + remove_movie_clip() + SHOW),
        SHOW,
    )


def test_a_holder_moved_sideways_is_refused():
    index = parse_swf(
        one_frame_label(
            place2(1, cid=HOLDER, name="flasher", matrix=matrix(1.0, tx=40))
        )
    )
    with pytest.raises(RuntimeError, match="frame 1 places flasher"):
        floating_numbers.number_labels(index, FIXER)


SETTER = 23
DIGIT_NAMES = [
    "One",
    "Two",
    "Three",
    "Four",
    "Five",
    "Six",
    "Seven",
    "Eight",
    "Nine",
    "Zero",
]


def setter() -> bytes:
    """A NumberSetter-like sprite SETTER with a label per digit, One on frame
    1 to Zero on frame 10, each frame showing an outline shape at depth 1, the
    KN fill sprite at depth 2 and a shine shape at depth 4."""
    shape = tag(TAG_DEFINE_SHAPE, struct.pack("<H", 10) + b"\0\0\0\0\0")
    fill = struct.pack("<HH", 11, 1) + place2(1, cid=10) + SHOW + tag(TAG_END)
    frames = place2(1, cid=10) + place2(2, cid=11, name="KN") + place2(4, cid=10)
    for name in DIGIT_NAMES:
        frames += label(name) + SHOW
    body = struct.pack("<HH", SETTER, len(DIGIT_NAMES)) + frames + tag(TAG_END)
    return shape + tag(TAG_DEFINE_SPRITE, fill) + tag(TAG_DEFINE_SPRITE, body)


def test_each_digit_is_the_numbersetter_label_that_spells_it():
    index = parse_swf(swf(setter(), SHOW))
    assert floating_numbers.digit_frames(index, SETTER) == {
        "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9, "0": 10,
    }  # fmt: skip


def test_the_kn_layer_is_the_one_that_takes_the_tint():
    index = parse_swf(swf(setter(), SHOW))
    assert floating_numbers.glyph_layers(index, SETTER, 1) == [
        (1, False),
        (2, True),
        (4, False),
    ]


def test_layers_that_do_not_rebuild_the_whole_glyph_are_refused():
    outline = Image.new("RGBA", (4, 4), (0, 0, 0, 0))
    outline.paste((0, 0, 0, 255), (0, 0, 3, 3))
    shine = Image.new("RGBA", (4, 4), (0, 0, 0, 0))
    shine.paste((255, 255, 255, 128), (1, 1, 4, 4))
    whole = Image.new("RGBA", (4, 4), (0, 0, 0, 0))
    whole.alpha_composite(outline)
    whole.alpha_composite(shine)
    floating_numbers.check_rebuild("Seven", whole, [outline, shine])
    with pytest.raises(RuntimeError, match="Seven"):
        floating_numbers.check_rebuild("Seven", whole, [shine, outline])


def number_script(reset: int = 1620, halve: int = 2) -> bytes:
    """A root frame script that reads as frame_42/DoAction_7.as does, cut down
    to the lines number_show() reads: lines 3-4, and in KrinNumberShow, which
    keeps _root in register 1, lines 34-35 and 75-79. `reset` is the depth
    line 78 goes back to, and `halve` is what line 35 divides by."""
    depth = (("register", 1), ("pool", 1))
    body = (
        push(("pool", 3), ("register", 1), ("pool", 0))
        + b"\x4e"
        + push(("pool", 4))
        + b"\x1c"
        + push(1)
        + b"\x0b\x0c\x1d"
        + push(("pool", 5), 0.0, ("pool", 3))
        + b"\x1c"
        + push(halve)
        + b"\x0d\x0b"
        + push(10)
        + b"\x0b\x1d"
        + push(*depth, *depth)
        + b"\x4e\x50\x4f"
        + push(*depth)
        + b"\x4e"
        + push(1640)
        + b"\x49\x12"
        + record(0x9D, struct.pack("<h", 0))
        + push(*depth, reset)
        + b"\x4f"
    )
    names = (
        "numberSpacingKrin", "numberDepthCyler", "KrinNumberShow",
        "totalLKrinN", "gKMPsteps", "KrinNOffset",
    )  # fmt: skip
    return tag(
        TAG_DO_ACTION,
        constant_pool(*names)
        + push(("pool", 0), 19)
        + b"\x1d"
        + push(("pool", 1), 1620)
        + b"\x1d"
        + push(("pool", 2))
        + define_function2("", (0x40, 0x00), (), body)
        + b"\x1d\0",
    )


def test_number_show_reads_the_slot_count_the_digit_spacing_and_the_offset():
    index = parse_swf(swf(number_script(), SHOW))
    assert floating_numbers.number_show(index) == {
        "slots": 20,
        "digits": {"spacing": 19, "offset": -10.0},
    }


@pytest.mark.parametrize(
    "script, refusal",
    [
        (number_script(reset=1600), "wraps to its start"),
        (number_script(halve=3), "does not center the digits"),
    ],
    ids=["a wrap to another depth", "digits that are not centered"],
)
def test_a_krinnumbershow_that_reads_another_way_is_refused(script, refusal):
    index = parse_swf(swf(script, SHOW))
    with pytest.raises(RuntimeError, match=refusal):
        floating_numbers.number_show(index)


def test_a_tint_toward_anything_but_white_is_refused():
    red = cxform((0, 0, 0, 256), (255, 0, 0, 0))
    index = parse_swf(
        one_frame_label(place2(1, cid=HOLDER, name="flasher", cxform=red))
    )
    with pytest.raises(RuntimeError, match="frame 1 transforms flasher"):
        floating_numbers.number_labels(index, FIXER)
