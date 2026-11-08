# Checks the committed label_xref.json against the game data and the AS
# export. Neither the SWF nor the XML dump is read, since both are absent
# from a fresh checkout.
from __future__ import annotations

import json
import struct
from pathlib import Path

import pytest
from test_swf_index import place2, swf, tag
from urchin_dev import ACTION_SCRIPT
from urchin_dev.swf.label_xref import (
    BATTLES_JSON,
    OUT,
    Resolver,
    goto_calls,
    load_value_sets,
    parse_script_path,
    receiver_segments,
    unescape,
)
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SHAPE,
    TAG_PLACE_OBJECT2,
    TAG_SHOW_FRAME,
    parse_swf,
)


@pytest.fixture(scope="module")
def xref():
    return json.loads(OUT.read_text())


@pytest.fixture(scope="module")
def values():
    return load_value_sets(ACTION_SCRIPT, BATTLES_JSON)


def labels_of(xref, sprite: int) -> set[str]:
    return {r["label"].lower() for r in xref["labels"] if r["sprite"] == sprite}


def missing(entries, labels: set[str]) -> list:
    return sorted((key, value) for key, value in entries if value.lower() not in labels)


def test_counts_match_the_swf_and_the_script_export(xref):
    counts = xref["counts"]
    assert counts["sprites"] == 1571
    assert counts["labels"] == 1137
    assert counts["clip_depth_placements"] == 62
    assert counts["code_blocks"] == 869
    assert counts["gotos_by_argument"] == {"dynamic": 60, "literal": 322, "numeric": 56}


def test_every_goto_in_the_export_is_resolved_or_listed_unresolved(xref):
    expected = sorted(
        (path.relative_to(ACTION_SCRIPT).as_posix(), call.line, call.argument)
        for path in ACTION_SCRIPT.rglob("*.as")
        for call in goto_calls(path.read_text())
    )
    recorded = sorted((g["file"], g["line"], g["argument"]) for g in xref["gotos"])
    assert recorded == expected
    for goto in xref["gotos"]:
        assert goto["status"] in ("label", "frame", "unresolved")
        assert goto.get("selects") or goto.get("reason"), goto


def test_every_zone_background_is_a_hall_label(xref, values):
    assert missing(values["zone_background"], labels_of(xref, 3435)) == []
    assert len({v for _k, v in values["zone_background"]}) == 10


def test_every_sky_background_is_a_sky_label(xref, values):
    assert missing(values["sky_background"], labels_of(xref, 3454)) == []
    assert len({v for _k, v in values["sky_background"]}) == 9


def test_item_names_without_an_icon_label(xref, values):
    # AVM1 folds case on labels, so "White T-shirt" (11) is served by the
    # label "White T-Shirt" and is not a miss.
    assert len(values["item_name"]) == 316
    assert missing(values["item_name"], labels_of(xref, 2064)) == [
        (1, "Tool"),
        (681, "Golden Crowbar"),
        (682, "Golden Pipe"),
        (683, "Golden Axe"),
    ]


def test_recorded_misses_match_the_sources(xref, values):
    sprites = {"zone_background": 3435, "sky_background": 3454}
    sprites |= {"item_name": 2064, "zone_name": 3287}
    for name, sprite in sprites.items():
        recorded = [(m["key"], m["value"]) for m in xref["value_sets"][name]["misses"]]
        assert recorded == sorted(set(missing(values[name], labels_of(xref, sprite))))


def test_zone_names_without_a_hub_label(xref, values):
    assert missing(values["zone_name"], labels_of(xref, 3287)) == [
        (0, "EMPTY"),
        (12, "DOME"),
    ]


def test_hidden_on_load_handlers(xref):
    hidden = {(h["owner"], h["placed"], h["depth"]): h for h in xref["hidden_on_load"]}
    assert len(hidden) == 13
    assert sum(h["hides_self"] for h in hidden.values()) == 10
    assert hidden[(2427, 2241, 11)]["hides_self"]
    assert hidden[(3317, 3312, 7)]["hides_self"]
    others = {
        (h["file"], tuple(h["receivers"]))
        for h in hidden.values()
        if not h["hides_self"]
    }
    assert others == {
        (
            (
                "DefineSprite_3142/frame_1/PlaceObject2_2979_995/"
                "CLIPACTIONRECORD onClipEvent(load).as"
            ),
            ("blacker",),
        ),
        (
            (
                "DefineSprite_3142/frame_25/PlaceObject3_3100_153/"
                "CLIPACTIONRECORD onClipEvent(load).as"
            ),
            ('this["st" + krink].thing2.bfilter', 'this["st" + krink].thingoShow'),
        ),
        (
            "frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(load).as",
            ('_root["p" + i + "BAR"]',),
        ),
    }


def test_the_hall_picks_its_label_from_its_own_load_handler(xref):
    (record,) = [
        r for r in xref["labels"] if (r["sprite"], r["label"]) == (3435, "CHURCH")
    ]
    gotos = [xref["gotos"][i] for i in record["gotos"]]
    assert [(g["file"], g["receiver"], g["via"]) for g in gotos] == [
        (
            "frame_217/PlaceObject2_3435_89/CLIPACTIONRECORD onClipEvent(load).as",
            "this",
            "zone_background",
        )
    ]


@pytest.mark.parametrize(
    ("path", "expected"),
    [
        ("frame_217/DoAction.as", ("frame", 0, 217, None, None, None)),
        (
            "DefineSprite_166_MODEL1/frame_107/DoAction.as",
            ("frame", 166, 107, None, None, None),
        ),
        (
            "frame_217/PlaceObject2_3435_89/CLIPACTIONRECORD onClipEvent(load).as",
            ("clip", 0, 217, 3435, 89, None),
        ),
        (
            (
                "DefineSprite_121/frame_1/PlaceObject2_120_M_HAND_NINJA_1/"
                "CLIPACTIONRECORD onClipEvent(load).as"
            ),
            ("clip", 121, 1, 120, 1, None),
        ),
        (
            "DefineButton2_3186/BUTTONCONDACTION on(press).as",
            ("button", None, None, None, None, 3186),
        ),
        ("__Packages/mx/core/UIObject.as", ("other", None, None, None, None, None)),
    ],
)
def test_script_paths_name_their_owner(path, expected):
    s = parse_script_path(Path(path))
    assert (s.kind, s.timeline, s.frame, s.placed, s.depth, s.button) == expected


def test_goto_calls_split_receiver_and_argument():
    text = 'x = 1;\n_root.BATTLESCREEN["p" + a[0]].inner.gotoAndStop("dead");\n'
    (call,) = goto_calls(text)
    assert (call.line, call.method) == (2, "gotoAndStop")
    assert call.receiver == '_root.BATTLESCREEN["p" + a[0]].inner'
    assert call.argument == '"dead"'
    assert receiver_segments(call.receiver) == [
        ("name", "_root"),
        ("name", "BATTLESCREEN"),
        ("index", '"p" + a[0]'),
        ("name", "inner"),
    ]


def test_gotos_inside_a_function_are_marked():
    text = 'function f()\n{\n   this.inner.gotoAndStop("a\\\\");\n}\ngotoAndStop(2);\n'
    inside, outside = goto_calls(text)
    assert (inside.in_function, inside.argument) == (True, '"a\\\\"')
    assert (outside.in_function, outside.receiver) == (False, None)


def test_unescape_undoes_ffdec_quotes():
    assert unescape(r"Guard\'s Leggings") == "Guard's Leggings"


def test_the_resolver_refuses_a_move_that_names_its_depth():
    shape = tag(TAG_DEFINE_SHAPE, struct.pack("<H", 10) + b"\0\0\0\0\0")
    named_move = tag(TAG_PLACE_OBJECT2, bytes([0x21]) + struct.pack("<H", 1) + b"b1\0")
    index = parse_swf(swf(shape, place2(1, cid=10), named_move, tag(TAG_SHOW_FRAME)))
    with pytest.raises(ValueError, match="timeline 0 frame 1 depth 1: move naming"):
        Resolver(index)
