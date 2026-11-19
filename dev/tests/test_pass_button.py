# extract_pass_button's reading of the pass button's states and the icon's
# place, on records and matrices built by hand, so no test needs the SWF.
from __future__ import annotations

import pytest
from urchin_dev.swf import timeline
from urchin_dev.swf.extract import pass_button
from urchin_dev.swf.swf_index import ButtonRecord

UP_RING, OVER_RING, HIT_DISC = 2434, 2435, 2436


def records(over_matrix=timeline.IDENTITY, down=True) -> list[ButtonRecord]:
    """Button 3383 as the web build stores it: one shape for up, one for over
    and down, and one for the hit area."""
    over_states = frozenset({"over", "down"} if down else {"over"})
    return [
        ButtonRecord(frozenset({"up"}), UP_RING, 1, timeline.IDENTITY),
        ButtonRecord(over_states, OVER_RING, 1, over_matrix),
        ButtonRecord(frozenset({"hit"}), HIT_DISC, 1, timeline.IDENTITY),
    ]


def is_shape(_cid: int) -> bool:
    return True


def test_each_visible_state_draws_its_shape_and_shares_a_png_with_the_same_shape():
    shapes = pass_button.state_shapes(records(), is_shape)
    assert shapes == {"up": UP_RING, "over": OVER_RING, "down": OVER_RING}
    assert pass_button.texture_names(shapes) == {
        UP_RING: "pass_button_up.png",
        OVER_RING: "pass_button_over.png",
    }


def test_a_state_with_no_art_is_refused():
    with pytest.raises(RuntimeError, match="0 records in down"):
        pass_button.state_shapes(records(down=False), is_shape)


def test_a_state_whose_art_moves_is_refused():
    moved = (1.0, 0.0, 0.0, 1.0, 20, 0)
    with pytest.raises(RuntimeError, match="moves its over art"):
        pass_button.state_shapes(records(over_matrix=moved), is_shape)


def test_a_state_that_draws_a_sprite_is_refused():
    with pytest.raises(RuntimeError, match="not a shape"):
        pass_button.state_shapes(records(), lambda cid: cid != OVER_RING)


def test_the_icon_rect_is_the_half_size_scaled_around_the_placement():
    # krinToMove's placement: a scale of 1.2294769 at (8000, 10150) twips.
    matrix = (1.2294769, 0.0, 0.0, 1.2294769, 8000, 10150)
    assert pass_button.icon_rect(matrix, 15.5) == {
        "x": 380.94,
        "y": 488.44,
        "w": 38.11,
        "h": 38.11,
    }


def test_an_unevenly_scaled_icon_is_refused():
    with pytest.raises(RuntimeError, match="unevenly"):
        pass_button.icon_rect((1.0, 0.0, 0.0, 2.0, 0, 0), 15.5)
