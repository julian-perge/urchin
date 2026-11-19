# The Radial menu's layout arithmetic on numbers built by hand, so no test needs
# the gitignored SWF. Running extract_battle_screen checks the SWF side.
from __future__ import annotations

from dataclasses import replace

import pytest
from urchin_dev.swf.extract import battle_screen
from urchin_dev.swf.swf_index import ButtonRecord

# The battle frame places the selector clip 3382 with this matrix.
SELECTOR_MATRIX = (1.0383148193359375, 0.0, 0.0, 1.0383148193359375, 8013, 6003)


def test_compose_scales_the_inner_translate_by_the_outer_scale():
    outer = (2.0, 0.0, 0.0, 0.5, 100, 200)
    inner = (3.0, 0.0, 0.0, 4.0, 10, 20)
    assert battle_screen.compose(outer, inner) == (6.0, 0.0, 0.0, 2.0, 120, 210)


def test_compose_refuses_a_rotation():
    with pytest.raises(RuntimeError, match="rotat"):
        battle_screen.compose(
            (1.0, 0.1, 0.0, 1.0, 0, 0), battle_screen.timeline.IDENTITY
        )


def test_union_holds_every_rect():
    assert battle_screen.union([(0, 5, 10, 20), (-3, 7, 4, 30)]) == (-3, 5, 10, 30)


def test_union_refuses_nothing_to_join():
    with pytest.raises(RuntimeError):
        battle_screen.union([])


def test_ring_layout_keeps_the_clips_own_px_and_records_its_scale():
    layout = battle_screen.ring_layout(
        SELECTOR_MATRIX,
        [(-244, -1228, 244, -740)],
        [(-244, -1228, 244, -740), (746, -244, 1235, 244)],
    )
    assert layout == {
        "box": {"x": -12.2, "y": -61.4, "w": 73.95, "h": 73.6},
        "orb_rects": [{"x": -12.2, "y": -61.4, "w": 24.4, "h": 24.4}],
        "scale": 1.0383,
    }


def test_ring_layout_refuses_a_stretched_clip():
    with pytest.raises(RuntimeError, match="placed with"):
        battle_screen.ring_layout((1.0, 0.0, 0.0, 1.2, 0, 0), [(0, 0)], [(0, 0, 1, 1)])


# A Radial menu clip built by hand: frame 217 places 3382, which holds one
# button (thingo0) over one icon sprite (thing0). The button draws shape 20 in
# its up state and the bigger shape 21 only in its over state, and the icon
# sprite's frame 1 is shape 22 under the mask shape 23.
SHAPES = {
    20: (-200, -200, 200, 200),
    21: (-400, -400, 400, 400),
    22: (-100, -100, 100, 100),
    23: (-150, -150, 150, 150),
}
KINDS = {3382: "sprite", 10: "button", 11: "sprite", **{cid: "shape" for cid in SHAPES}}


def fake_ring(monkeypatch, orb_count=1):
    def layer(cid, name=None, x=0, y=0, clip_depth=None):
        return battle_screen.timeline.Layer(
            cid, name=name, matrix=(1.0, 0.0, 0.0, 1.0, x, y), clip_depth=clip_depth
        )

    clip = {}
    for i in range(orb_count):
        clip[2 * i + 1] = layer(11, f"thing{i}", x=1000 * i, y=-1000)
        clip[2 * i + 2] = layer(10, f"thingo{i}", x=1000 * i, y=-1000)
    timelines = {
        0: [{500: replace(layer(3382, "selector"), matrix=SELECTOR_MATRIX)}],
        3382: [clip],
        11: [{1: layer(23, clip_depth=2), 2: layer(22)}],
    }
    monkeypatch.setattr(
        battle_screen.timeline, "frames", lambda _i, owner: timelines[owner]
    )
    monkeypatch.setattr(battle_screen, "character_kind", lambda _i, cid: KINDS[cid])
    monkeypatch.setattr(battle_screen, "shape_bounds", lambda _i, cid: SHAPES[cid])
    monkeypatch.setattr(
        battle_screen,
        "button_records",
        lambda _i, _cid: [
            ButtonRecord(frozenset({"up"}), 20, 1, (1.0, 0.0, 0.0, 1.0, 0, 0)),
            ButtonRecord(
                frozenset({"over", "down"}), 21, 1, (1.0, 0.0, 0.0, 1.0, 0, 0)
            ),
        ],
    )


def test_drawn_bounds_reads_a_buttons_up_state_only(monkeypatch):
    fake_ring(monkeypatch)
    bounds = battle_screen.drawn_bounds(None, 10, (2.0, 0.0, 0.0, 2.0, 100, 0))
    assert bounds == (-300, -400, 500, 400)


def test_drawn_bounds_counts_a_sprites_mask_by_its_own_bounds(monkeypatch):
    fake_ring(monkeypatch)
    bounds = battle_screen.drawn_bounds(None, 11, battle_screen.timeline.IDENTITY)
    assert bounds == (-150, -150, 150, 150)


def test_radial_menu_layout_builds_each_orb_from_its_button(monkeypatch):
    fake_ring(monkeypatch, orb_count=2)
    monkeypatch.setattr(battle_screen, "ORB_COUNT", 2)
    layout = battle_screen.radial_menu_layout(None, 1)
    assert layout["orb_rects"] == [
        {"x": -10.0, "y": -60.0, "w": 20.0, "h": 20.0},
        {"x": 40.0, "y": -60.0, "w": 20.0, "h": 20.0},
    ]
    assert layout["box"] == {"x": -10.0, "y": -60.0, "w": 70.0, "h": 20.0}
    assert layout["scale"] == 1.0383


def test_radial_menu_layout_refuses_a_ring_missing_a_button(monkeypatch):
    fake_ring(monkeypatch, orb_count=1)
    with pytest.raises(RuntimeError, match="want thingo0 to 7"):
        battle_screen.radial_menu_layout(None, 1)
