# avm1.py's reading of scripts on SWF bytes built by hand, so no test needs the
# gitignored SWF.
from __future__ import annotations

import struct

import pytest
from test_swf_index import swf, tag
from urchin_dev.swf import avm1
from urchin_dev.swf.swf_index import TAG_DO_ACTION, TAG_SHOW_FRAME, parse_swf

END = b"\0"
GET_VARIABLE = b"\x1c"
SET_VARIABLE = b"\x1d"
DIVIDE = b"\x0d"
STOP = b"\x07"


def record(code: int, body: bytes) -> bytes:
    return bytes([code]) + struct.pack("<H", len(body)) + body


def constant_pool(*names: str) -> bytes:
    return record(
        0x88,
        struct.pack("<H", len(names)) + b"".join(n.encode() + b"\0" for n in names),
    )


def push(*values) -> bytes:
    """A Push of constant pool indexes, given as ("pool", i), 32-bit integers,
    and doubles, which the SWF stores as two little-endian halves with the high
    half first."""
    body = b""
    for value in values:
        if isinstance(value, tuple):
            body += bytes([8, value[1]])
        elif isinstance(value, int):
            body += bytes([7]) + struct.pack("<i", value)
        else:
            low, high = struct.unpack("<II", struct.pack("<d", value))
            body += bytes([6]) + struct.pack("<II", high, low)
    return record(0x96, body)


def script(actions: bytes):
    """-> (index, block) for a SWF whose one frame runs `actions`."""
    index = parse_swf(swf(tag(TAG_DO_ACTION, actions), tag(TAG_SHOW_FRAME)))
    (block,) = index.code
    return index, block


def test_a_load_script_sets_its_numbers_and_what_it_works_out_from_them():
    # GridShaker's onClipEvent(load) (frame_217/PlaceObject2_3420_330):
    # shakeOriginal = 8; shakeValue = shakeOriginal; shakeMinus = shakeValue / 10;
    names = ("shakeOriginal", "shakeValue", "shakeMinus")
    index, block = script(
        constant_pool(*names)
        + push(("pool", 0), 8)
        + SET_VARIABLE
        + push(("pool", 1), ("pool", 0))
        + GET_VARIABLE
        + SET_VARIABLE
        + push(("pool", 2), ("pool", 1))
        + GET_VARIABLE
        + push(10)
        + DIVIDE
        + SET_VARIABLE
        + END
    )
    assert avm1.assignments(index, block) == {
        "shakeOriginal": 8,
        "shakeValue": 8,
        "shakeMinus": 0.8,
    }


def test_a_script_that_does_more_than_assign_is_refused():
    index, block = script(
        constant_pool("x") + push(("pool", 0), 1) + SET_VARIABLE + STOP + END
    )
    with pytest.raises(ValueError, match="action 0x07"):
        avm1.assignments(index, block)


def test_numbers_are_every_number_a_script_pushes_in_order():
    # The tail of GridShaker's frame 5 (DefineSprite_3420/frame_5): the 0 that
    # shakeValue is compared with, then the 0.9000000000000002 added to _y.
    index, block = script(
        constant_pool("shakeValue", "_y")
        + push(("pool", 0), 0.0)
        + push(("pool", 1), 0.9000000000000002)
        + END
    )
    assert avm1.numbers(index, block) == [0.0, 0.9000000000000002]
