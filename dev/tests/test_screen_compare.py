# The compare tool's arithmetic and config rules on arrays and files built by
# hand, so no test needs the gitignored SWF, ffdec or a capture.
from __future__ import annotations

import json

import numpy as np
import pytest
from urchin_dev import REPO_ROOT
from urchin_dev.checks import screen_compare

PANELS = {"depths": [11], "nodes": ["LeftPanel"], "bar": 5}


def write_config(tmp_path, entries: dict):
    path = tmp_path / "screens.json"
    path.write_text(json.dumps(entries))
    return path


def entry(**modes) -> dict:
    return {
        "scene": "res://scenes/a.tscn",
        "timeline": 3142,
        "frame": "win",
        "modes": modes,
    }


def capture(height: int, width: int, colour, box, fill) -> np.ndarray:
    """-> a capture of one flat rectangle `box` (x0, y0, x1, y1) over a flat
    background."""
    image = np.empty((height, width, 3), dtype=np.int16)
    image[:] = colour
    x0, y0, x1, y1 = box
    image[y0:y1, x0:x1] = fill
    return image


def test_the_mask_is_where_both_captures_match_shrunk_by_one_pixel():
    box = (2, 2, 8, 7)
    magenta = capture(10, 12, (255, 0, 255), box, (55, 55, 55))
    green = capture(10, 12, (0, 255, 0), box, (55, 55, 55))

    mask = screen_compare.drawn_mask(magenta, green)

    expected = np.zeros((10, 12), dtype=bool)
    expected[3:6, 3:7] = True
    assert np.array_equal(mask, expected)


def test_a_pixel_the_screen_blends_with_the_background_leaves_the_mask_with_its_neighbours():
    magenta = capture(7, 7, (255, 0, 255), (0, 0, 7, 7), (55, 55, 55))
    green = magenta.copy()
    green[3, 3] = (40, 70, 40)

    mask = screen_compare.drawn_mask(magenta, green)

    expected = np.zeros((7, 7), dtype=bool)
    expected[1:6, 1:6] = True
    for y, x in ((3, 3), (2, 3), (4, 3), (3, 2), (3, 4)):
        expected[y, x] = False
    assert np.array_equal(mask, expected)


def test_a_box_mask_covers_every_pixel_the_rect_touches():
    mask = screen_compare.box_mask((6, 8), (1.5, 2.2, 3.0, 1.9))

    expected = np.zeros((6, 8), dtype=bool)
    expected[2:5, 1:5] = True
    assert np.array_equal(mask, expected)


def test_face_boxes_are_the_face_pieces_of_the_scene_in_the_rect_record():
    record = {
        "scenes": {
            "res://scenes/a.tscn": {
                "pieces": {
                    "Row/Face": {"kind": "face", "rect": [1.0, 2.0, 3.0, 4.0]},
                    "Row/Name": {"kind": "text", "rect": [9.0, 9.0, 9.0, 9.0]},
                }
            }
        }
    }

    assert screen_compare.face_boxes(record, "res://scenes/a.tscn") == [
        (1.0, 2.0, 3.0, 4.0)
    ]
    assert screen_compare.face_boxes(record, "res://scenes/other.tscn") == []


def test_the_score_counts_only_masked_pixels_where_the_reference_is_opaque():
    shot = np.full((4, 4, 3), 100, dtype=np.int16)
    reference = np.full((4, 4, 4), 100, dtype=np.int16)
    reference[:, :, 3] = 255
    # A wrong pixel outside the mask and one where the reference is clear.
    reference[0, 0, :3] = 0
    reference[1, 1] = (0, 0, 0, 128)
    # A wrong pixel that counts, by 30 on its worst channel.
    reference[2, 2, :3] = (100, 130, 90)
    mask = np.ones((4, 4), dtype=bool)
    mask[0, 0] = False

    score = screen_compare.score(shot, reference, mask)

    assert score.pixels == 14
    assert score.p50 == 0
    assert score.p99 == pytest.approx(np.percentile([0] * 13 + [30], 99))


def test_a_score_with_no_pixels_is_an_error():
    shot = np.zeros((2, 2, 3), dtype=np.int16)
    reference = np.zeros((2, 2, 4), dtype=np.int16)

    with pytest.raises(screen_compare.CompareError, match="no pixels"):
        screen_compare.score(shot, reference, np.ones((2, 2), dtype=bool))


def test_a_reference_shifted_20_px_scores_over_an_exact_match():
    # Vertical bands 10 px wide, so a 20 px shift lands every band on its
    # neighbour's colour only when the bands differ two apart.
    columns = (np.arange(80) // 10 % 4 * 60).astype(np.int16)
    reference = np.zeros((20, 80, 4), dtype=np.int16)
    reference[:, :, :3] = columns[None, :, None]
    reference[:, :, 3] = 255
    shot = reference[:, :, :3].copy()
    mask = np.ones((20, 80), dtype=bool)

    exact = screen_compare.score(shot, reference, mask)
    control = screen_compare.score(shot, screen_compare.shifted(reference), mask)

    assert exact.p99 == 0
    assert control.p99 == 120


def test_the_shifted_reference_moves_its_alpha_too():
    reference = np.zeros((1, 40, 4), dtype=np.int16)
    reference[0, 5] = (9, 9, 9, 255)

    moved = screen_compare.shifted(reference)

    assert tuple(moved[0, 25]) == (9, 9, 9, 255)
    assert moved[0, 5, 3] == 0


@pytest.mark.parametrize(
    ("p99", "control", "bar", "problem"),
    [
        (4.0, 60.0, 5, None),
        (5.0, 60.0, 5, None),
        (6.0, 60.0, 5, "over the bar"),
        (4.0, 5.0, 5, "cannot fail"),
        (4.0, 60.0, None, "no bar"),
    ],
)
def test_the_verdict_needs_a_score_under_the_bar_and_a_control_over_it(
    p99, control, bar, problem
):
    found = screen_compare.verdict(p99, control, bar)

    if problem is None:
        assert found is None
    else:
        assert problem in found


def test_a_second_entry_loads_from_the_config_file_alone(tmp_path):
    path = write_config(
        tmp_path, {"first": entry(panels=PANELS), "second": entry(chrome={"bar": None})}
    )

    entries = screen_compare.load_config(path)

    assert list(entries) == ["first", "second"]
    assert entries["first"].modes["panels"].depths == (11,)
    assert entries["first"].modes["panels"].nodes == ("LeftPanel",)
    assert entries["first"].modes["panels"].bar == 5
    assert entries["second"].timeline == 3142
    assert entries["second"].modes["chrome"].bar is None


@pytest.mark.parametrize(
    ("modes", "message"),
    [
        ({}, "no modes"),
        ({"live": {"bar": 5}}, "unknown mode"),
        ({"panels": {"bar": 5}}, "depths"),
        ({"panels": {"depths": [11], "nodes": [], "bar": 5}}, "nodes"),
        ({"chrome": {"bar": 5, "depths": [11]}}, "chrome"),
        ({"chrome": {}}, "bar"),
    ],
)
def test_a_config_entry_that_breaks_the_format_is_refused(tmp_path, modes, message):
    path = write_config(tmp_path, {"broken": entry(**modes)})

    with pytest.raises(screen_compare.CompareError, match=message):
        screen_compare.load_config(path)


def test_the_capture_arguments_name_the_entry_the_mode_and_the_background():
    assert screen_compare.capture_args("victory", "panels", "green") == [
        "--entry=victory",
        "--mode=panels",
        "--background=green",
    ]


def test_edit_texts_are_found_inside_nested_sprites():
    # Depth to character id per timeline: sprite 10 holds text 3 and sprite
    # 11, and sprite 11 holds text 4 on its second frame and places sprite 10
    # again, which must not loop.
    frames = {10: [{1: 3, 2: 11}], 11: [{1: 2}, {1: 4, 2: 10}]}
    kinds = {1: "edittext", 2: "shape", 3: "edittext", 4: "edittext"}
    kinds |= {10: "sprite", 11: "sprite"}

    found = screen_compare.edit_text_ids(
        [1, 2, 10], lambda sprite: frames[sprite], lambda cid: kinds[cid]
    )

    assert found == {1, 3, 4}


def test_every_committed_entry_names_a_scene_that_exists():
    entries = screen_compare.load_config(screen_compare.CONFIG)

    assert entries
    for name, found in entries.items():
        scene = REPO_ROOT / found.scene.removeprefix("res://")
        assert scene.is_file(), f"{name}: {found.scene}"
