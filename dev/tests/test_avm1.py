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
GET_MEMBER = b"\x4e"
SET_MEMBER = b"\x4f"
ADD2 = b"\x47"
SUBTRACT = b"\x0b"
MULTIPLY = b"\x0c"
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
    """A Push of constant pool indexes, given as ("pool", i), registers, given
    as ("register", n), booleans, 32-bit integers, and doubles, which the SWF
    stores as two little-endian halves with the high half first."""
    body = b""
    for value in values:
        if isinstance(value, tuple):
            body += bytes([{"pool": 8, "register": 4}[value[0]], value[1]])
        elif isinstance(value, bool):
            body += bytes([5, value])
        elif isinstance(value, int):
            body += bytes([7]) + struct.pack("<i", value)
        else:
            low, high = struct.unpack("<II", struct.pack("<d", value))
            body += bytes([6]) + struct.pack("<II", high, low)
    return record(0x96, body)


def define_function2(name: str, flags: tuple, params: tuple, body: bytes) -> bytes:
    """A DefineFunction2 record and the body that follows it. flags is its two
    flag bytes, and params holds (register, name) pairs."""
    header = name.encode() + b"\0" + struct.pack("<HB", len(params), 4) + bytes(flags)
    for register, param in params:
        header += bytes([register]) + param.encode() + b"\0"
    return record(0x8E, header + struct.pack("<H", len(body))) + body


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


def test_statements_name_each_member_a_script_sets_and_what_it_sets_it_to():
    # The conductor's Missile zoom (frame_217/PlaceObject2_3389_480 enterFrame,
    # lines 425 and 428): _root.zoomPointX = _root.xPoint1 * (- _root.zoomRatioNEW)
    # + 400; _root.zoomPause = 5;
    index, block = script(
        constant_pool("_root", "zoomPointX", "xPoint1", "zoomRatioNEW", "zoomPause")
        + push(("pool", 0))
        + GET_VARIABLE
        + push(("pool", 1), ("pool", 0))
        + GET_VARIABLE
        + push(("pool", 2))
        + GET_MEMBER
        + push(0.0, ("pool", 0))
        + GET_VARIABLE
        + push(("pool", 3))
        + GET_MEMBER
        + SUBTRACT
        + MULTIPLY
        + push(400)
        + ADD2
        + SET_MEMBER
        + push(("pool", 0))
        + GET_VARIABLE
        + push(("pool", 4), 5)
        + SET_MEMBER
        + END
    )
    ratio = avm1.Arithmetic(0x0B, 0.0, avm1.Read("_root.zoomRatioNEW"))
    point = avm1.Arithmetic(0x0C, avm1.Read("_root.xPoint1"), ratio)
    assert [(s.target, s.value) for s in avm1.statements(index, block)] == [
        ("_root.zoomPointX", avm1.Arithmetic(0x47, point, 400)),
        ("_root.zoomPause", 5),
    ]


def test_statements_name_the_registers_a_function_preloads_and_its_parameters():
    # krinMelee's Melee zoom hold, and a step of its swing set-up
    # (frame_42/DoAction_4.as:65 and 42), then krinMeleeAttackCD at 217. The
    # function preloads this and _root, which take registers 1 and 2, and keeps
    # shooter in register 3: _root.zoomPause = krinMeleeAttackCD * 2;
    # shooter.dir = 1;
    body = (
        push(("register", 2), ("pool", 0), ("pool", 1))
        + GET_VARIABLE
        + push(2)
        + MULTIPLY
        + SET_MEMBER
        + push(("register", 3), ("pool", 2), 1)
        + SET_MEMBER
    )
    index, block = script(
        constant_pool("zoomPause", "krinMeleeAttackCD", "dir")
        + define_function2("krinMelee", (0x41, 0x00), ((3, "shooter"),), body)
        + push(("pool", 1), 15)
        + SET_VARIABLE
        + END
    )
    hold = avm1.Arithmetic(0x0C, avm1.Read("krinMeleeAttackCD"), 2)
    assert [(s.target, s.value) for s in avm1.statements(index, block)] == [
        ("_root.zoomPause", hold),
        ("shooter.dir", 1),
        ("krinMeleeAttackCD", 15),
    ]


NEW_OBJECT = b"\x40"
NEW_METHOD = b"\x53"
DEFINE_LOCAL = b"\x3c"
CALL_METHOD = b"\x52"
POP = b"\x17"
EQUALS2 = b"\x49"
NOT = b"\x12"
INCREMENT = b"\x50"


def test_statements_read_a_var_set_to_a_new_object_with_its_arguments():
    # The Result flash's white glow and its filter list
    # (frame_42/DoAction_3.as:117 and 120): var KFHit1 = new
    # flash.filters.GlowFilter(16777215,1,100,100,10,1,true,false);
    # var KrinFilterHit = new Array();
    index, block = script(
        constant_pool("KFHit1", "flash", "filters", "GlowFilter", "KrinFilterHit", "Array")
        + push(("pool", 0), False, True, 1, 10, 100, 100, 1, 16777215, 8, ("pool", 1))
        + GET_VARIABLE
        + push(("pool", 2))
        + GET_MEMBER
        + push(("pool", 3))
        + NEW_METHOD
        + DEFINE_LOCAL
        + push(("pool", 4), 0.0, ("pool", 5))
        + NEW_OBJECT
        + DEFINE_LOCAL
        + END
    )  # fmt: skip
    glow = avm1.New(
        "flash.filters.GlowFilter", (16777215, 1, 100, 100, 10, 1, True, False)
    )
    assert [(s.target, s.value) for s in avm1.statements(index, block)] == [
        ("KFHit1", glow),
        ("KrinFilterHit", avm1.New("Array", ())),
    ]


def test_calls_name_each_method_a_script_calls_and_its_arguments():
    # frame_42/DoAction_3.as:121: KrinFilterHit.push(KFHit1);
    index, block = script(
        constant_pool("KFHit1", "KrinFilterHit", "push")
        + push(("pool", 0))
        + GET_VARIABLE
        + push(1, ("pool", 1))
        + GET_VARIABLE
        + push(("pool", 2))
        + CALL_METHOD
        + POP
        + END
    )
    assert [(c.path, c.args) for c in avm1.calls(index, block)] == [
        ("KrinFilterHit.push", (avm1.Read("KFHit1"),))
    ]


def test_a_new_and_a_call_whose_argument_count_is_not_a_number_are_not_read():
    # var made = new Array(<count arguments>); list.push(<count arguments>);
    # with a count the script reads from a variable.
    index, block = script(
        constant_pool("made", "count", "Array", "list", "push")
        + push(("pool", 0), ("pool", 1))
        + GET_VARIABLE
        + push(("pool", 2))
        + NEW_OBJECT
        + DEFINE_LOCAL
        + push(("pool", 1))
        + GET_VARIABLE
        + push(("pool", 3))
        + GET_VARIABLE
        + push(("pool", 4))
        + CALL_METHOD
        + POP
        + END
    )
    assert [(s.target, s.value) for s in avm1.statements(index, block)] == [
        ("made", avm1.UNKNOWN)
    ]
    assert avm1.calls(index, block) == []


def test_an_increment_is_an_add_of_1_and_comparisons_name_what_an_equals_compares():
    # The end of KrinNumberShow (frame_42/DoAction_7.as:75-78), which keeps
    # _root in register 1: _root.numberDepthCyler = _root.numberDepthCyler + 1;
    # if(_root.numberDepthCyler == 1640) { _root.numberDepthCyler = 1620; }
    body = (
        push(("register", 1), ("pool", 0), ("register", 1), ("pool", 0))
        + GET_MEMBER
        + INCREMENT
        + SET_MEMBER
        + push(("register", 1), ("pool", 0))
        + GET_MEMBER
        + push(1640)
        + EQUALS2
        + NOT
        + record(0x9D, struct.pack("<h", 0))
        + push(("register", 1), ("pool", 0), 1620)
        + SET_MEMBER
    )
    index, block = script(
        constant_pool("numberDepthCyler")
        + define_function2("KrinNumberShow", (0x40, 0x00), (), body)
        + END
    )
    depth = avm1.Read("_root.numberDepthCyler")
    assert [(s.target, s.value) for s in avm1.statements(index, block)] == [
        ("_root.numberDepthCyler", avm1.Arithmetic(0x47, depth, 1)),
        ("_root.numberDepthCyler", 1620),
    ]
    assert [(c.left, c.right) for c in avm1.comparisons(index, block)] == [
        (depth, 1640)
    ]


def test_evaluate_works_a_value_out_from_the_variables_it_reads():
    hold = avm1.Arithmetic(0x0C, avm1.Read("krinMeleeAttackCD"), 2)
    assert avm1.evaluate(hold, {"krinMeleeAttackCD": 15}) == 30
    with pytest.raises(ValueError, match="krinMeleeAttackCD"):
        avm1.evaluate(hold, {})
    with pytest.raises(ValueError):
        avm1.evaluate(avm1.UNKNOWN, {})


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
