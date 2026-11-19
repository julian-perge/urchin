# The Radial menu's layout arithmetic on numbers built by hand, so no test needs
# the gitignored SWF. Running extract_battle_screen checks the SWF side.
from __future__ import annotations

import pytest
from urchin_dev.swf.extract import battle_screen

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
        [(0, -984), (990, 0)],
        [(-244, -1228, 244, -740), (746, -244, 1235, 244)],
    )
    assert layout == {
        "box": {"x": -12.2, "y": -61.4, "w": 73.95, "h": 73.6},
        "orb_offsets": [{"x": 0.0, "y": -49.2}, {"x": 49.5, "y": 0.0}],
        "scale": 1.0383,
    }


def test_ring_layout_refuses_a_stretched_clip():
    with pytest.raises(RuntimeError, match="placed with"):
        battle_screen.ring_layout((1.0, 0.0, 0.0, 1.2, 0, 0), [(0, 0)], [(0, 0, 1, 1)])
