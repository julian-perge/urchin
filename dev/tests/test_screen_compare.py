# The compare tool's arithmetic and config rules on arrays and files built by
# hand, so no test needs the gitignored SWF, ffdec or a capture.
from __future__ import annotations

import json

import numpy as np
import pytest
from PIL import Image
from urchin_dev import REPO_ROOT
from urchin_dev.checks import screen_compare
from urchin_dev.swf.extract.screen_rects import Piece, Scene

SCENE = "res://scenes/a.tscn"
SCENES = {
    SCENE: Scene(
        timeline=3142,
        frame="win",
        pieces={
            "LeftPanel": Piece("panel", 11),
            "Slot": Piece("panel", None, instance="itemSlot0"),
            "Row/Frame": Piece("art", 1197, "victory_row", inner_depth=2),
        },
    )
}
PANELS = {"nodes": ["LeftPanel"], "bar": 5}


def write_config(tmp_path, entries: dict):
    path = tmp_path / "screens.json"
    path.write_text(json.dumps(entries))
    return path


def entry(**modes) -> dict:
    return {"scene": SCENE, "modes": modes}


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


def test_masked_boxes_are_the_face_and_doll_pieces_of_the_scene_in_the_rect_record():
    record = {
        "scenes": {
            "res://scenes/a.tscn": {
                "pieces": {
                    "Row/Face": {"kind": "face", "rect": [1.0, 2.0, 3.0, 4.0]},
                    "Row/Doll": {"kind": "doll", "rect": [5.0, 6.0, 7.0, 8.0]},
                    "Row/Name": {"kind": "text", "rect": [9.0, 9.0, 9.0, 9.0]},
                }
            }
        }
    }

    assert screen_compare.masked_boxes(record, "res://scenes/a.tscn") == [
        (1.0, 2.0, 3.0, 4.0),
        (5.0, 6.0, 7.0, 8.0),
    ]
    assert screen_compare.masked_boxes(record, "res://scenes/other.tscn") == []


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
    # Vertical bands 10 px wide in four colours 60 apart, so a 20 px shift
    # lands every band on the colour two bands away, which differs by 120.
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

    entries = screen_compare.load_config(path, SCENES)

    assert list(entries) == ["first", "second"]
    assert entries["first"].frame == "win"
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
        ({"panels": {"bar": 5}}, "nodes"),
        ({"panels": {"nodes": [], "bar": 5}}, "nodes"),
        ({"panels": {"nodes": ["Missing"], "bar": 5}}, "Missing is not a piece"),
        ({"panels": {"nodes": ["Slot"], "bar": 5}}, "Slot is not a piece"),
        ({"panels": {"nodes": ["Row/Frame"], "bar": 5}}, "Row/Frame is not a piece"),
        ({"panels": {"nodes": ["LeftPanel"], "depths": [11], "bar": 5}}, "depths"),
        ({"chrome": {"bar": 5, "nodes": ["LeftPanel"]}}, "chrome takes no nodes"),
        ({"chrome": {}}, "no bar"),
        ({"chrome": {"bar": "5"}}, "not a number"),
        ({"chrome": {"bar": True}}, "not a number"),
        ({"chrome": {"bar": 5, "hide_names": "ItemIcon"}}, "list of node names"),
        ({"chrome": {"bar": 5, "hide_names": [3]}}, "list of node names"),
        ({"panels": {**PANELS, "hide_names": ["Body"]}}, "only chrome mode"),
    ],
)
def test_a_config_entry_that_breaks_the_format_is_refused(tmp_path, modes, message):
    path = write_config(tmp_path, {"broken": entry(**modes)})

    with pytest.raises(screen_compare.CompareError, match=message):
        screen_compare.load_config(path, SCENES)


def test_a_chrome_mode_may_hide_nodes_by_name(tmp_path):
    path = write_config(
        tmp_path, {"ok": entry(chrome={"bar": 5, "hide_names": ["ItemIcon", "Body"]})}
    )

    assert "chrome" in screen_compare.load_config(path, SCENES)["ok"].modes


@pytest.mark.parametrize(
    ("raw", "message"),
    [
        ({"modes": {"chrome": {"bar": 5}}}, "broken: no scene"),
        ({"scene": SCENE}, "broken: no modes"),
        (
            {"scene": "res://scenes/b.tscn", "modes": {"chrome": {"bar": 5}}},
            "b.tscn is not in SCENES",
        ),
    ],
)
def test_an_entry_needs_its_modes_and_a_scene_that_the_rect_extractor_knows(
    tmp_path, raw, message
):
    path = write_config(tmp_path, {"broken": raw})

    with pytest.raises(screen_compare.CompareError, match=message):
        screen_compare.load_config(path, SCENES)


def test_the_capture_arguments_name_the_entry_the_mode_and_the_background():
    assert screen_compare.capture_args("victory", "panels", "green") == [
        "--entry=victory",
        "--mode=panels",
        "--background=green",
    ]


def test_only_the_captures_that_are_not_on_disk_are_listed_as_missing(tmp_path):
    present = screen_compare.capture_path(tmp_path, "victory", "panels", "magenta")
    present.parent.mkdir(parents=True)
    present.write_bytes(b"")

    lines = screen_compare.missing_captures(tmp_path, "victory", ["panels"])

    assert len(lines) == 1
    assert "panels_green.png" in lines[0]
    assert '"--background=green"' in lines[0]


def test_a_capture_loads_only_at_the_stage_size(tmp_path):
    Image.new("RGB", screen_compare.STAGE, (1, 2, 3)).save(tmp_path / "stage.png")
    Image.new("RGB", (1600, 1150)).save(tmp_path / "window.png")

    loaded = screen_compare.load_capture(tmp_path / "stage.png")

    assert loaded.shape == (575, 800, 3)
    assert tuple(loaded[0, 0]) == (1, 2, 3)
    with pytest.raises(screen_compare.CompareError, match="Stage size"):
        screen_compare.load_capture(tmp_path / "window.png")


def test_edit_texts_are_those_of_the_frame_and_of_its_nested_sprites():
    # Depth to character id per timeline. Frame 2 of timeline 20 places text
    # 1 and sprite 10, and its other frames place texts 5 and 6. Sprite 10
    # holds text 3 and sprite 11, and sprite 11 holds text 4 on its second
    # frame and places sprite 10 again, which must not loop.
    frames = {
        20: [{1: 5}, {1: 1, 2: 2, 3: 10}, {1: 6}],
        10: [{1: 3, 2: 11}],
        11: [{1: 2}, {1: 4, 2: 10}],
    }
    kinds = dict.fromkeys((1, 3, 4, 5, 6), "edittext")
    kinds |= {2: "shape", 10: "sprite", 11: "sprite"}

    found = screen_compare.edit_text_ids(
        20, 2, lambda owner: frames[owner], lambda cid: kinds[cid]
    )

    assert found == {1, 3, 4}


def test_every_committed_entry_names_a_scene_that_exists():
    entries = screen_compare.load_config(screen_compare.CONFIG)

    assert entries
    for name, found in entries.items():
        scene = REPO_ROOT / found.scene.removeprefix("res://")
        assert scene.is_file(), f"{name}: {found.scene}"


def test_an_entry_carries_the_depths_its_scene_leaves_out(tmp_path):
    scenes = {SCENE: Scene(timeline=0, frame="mainMenu", pieces={}, left_out=(38, 41))}
    config = write_config(tmp_path, {"title": entry(chrome={"bar": None})})

    entries = screen_compare.load_config(config, scenes)

    assert entries["title"].left_out == (38, 41)


def test_the_left_out_characters_are_those_at_the_left_out_depths():
    layers = {1: 2701, 6: 321, 38: 2689, 41: 294}

    assert screen_compare.left_out_ids(layers, (38, 41), "title") == {2689, 294}


def test_a_left_out_depth_that_the_frame_does_not_place_is_an_error():
    with pytest.raises(screen_compare.CompareError, match="depth 40"):
        screen_compare.left_out_ids({38: 2689}, (38, 40), "title")


def test_a_window_backdrop_reference_keeps_its_stage_filters(monkeypatch):
    from types import SimpleNamespace

    from urchin_dev.swf.extract import window_chrome

    monkeypatch.setattr(
        screen_compare.screen_rects, "origin_of", lambda *_: (400.5, 222.4)
    )
    monkeypatch.setattr(
        screen_compare.timeline,
        "frame_of",
        lambda _, owner, label: 181 if owner == 0 else 1,
    )
    monkeypatch.setattr(
        screen_compare.timeline,
        "frames",
        lambda *_: [
            {2: SimpleNamespace(), 7: SimpleNamespace(), 11: SimpleNamespace()}
        ],
    )
    entry = screen_compare.Entry(
        "res://window.tscn",
        window_chrome.KRINMENU,
        "inventory",
        {"panels": screen_compare.Mode(None, (2, 7))},
    )
    job = screen_compare.reference_job(None, entry, "panels")
    assert job.timeline == 0
    assert job.frame == 181
    assert job.only_depths == (window_chrome.KRINMENU_ROOT_DEPTH,)
    assert job.hide_depths == ((window_chrome.KRINMENU, 11),)
    assert job.goto == ((window_chrome.KRINMENU_ROOT_DEPTH, 1),)


def test_a_window_chrome_reference_keeps_the_backdrop_stage_filters(monkeypatch):
    from types import SimpleNamespace

    from urchin_dev.swf.extract import window_chrome

    monkeypatch.setattr(
        screen_compare.screen_rects, "origin_of", lambda *_: (400.5, 222.4)
    )
    monkeypatch.setattr(
        screen_compare.timeline,
        "frame_of",
        lambda _, owner, label: 181 if owner == 0 else 16,
    )
    frame_16 = {2: SimpleNamespace(character_id=2994)}
    monkeypatch.setattr(
        screen_compare.timeline, "frames", lambda *_: [{}] * 15 + [frame_16]
    )
    monkeypatch.setattr(screen_compare, "character_kind", lambda *_: "shape")
    monkeypatch.setattr(
        screen_compare.strip, "strip_list", lambda _, reasons: sorted(reasons)
    )
    entry = screen_compare.Entry(
        "res://window.tscn",
        window_chrome.KRINMENU,
        "shop",
        {"chrome": screen_compare.Mode(None, ())},
        compare_strip=(3196,),
    )

    job = screen_compare.reference_job(None, entry, "chrome")

    assert job.timeline == 0
    assert job.frame == 181
    assert job.origin == (0.0, 0.0)
    assert job.only_depths == (window_chrome.KRINMENU_ROOT_DEPTH,)
    assert job.goto == ((window_chrome.KRINMENU_ROOT_DEPTH, 16),)
    assert job.strip == (3196,)


def test_an_entry_carries_its_static_chrome_strip_list(tmp_path):
    scenes = {
        SCENE: Scene(
            timeline=0, frame="Navigation", pieces={}, compare_strip=(2837, 3196)
        )
    }
    config = write_config(tmp_path, {"hub": entry(chrome={"bar": 37})})
    assert screen_compare.load_config(config, scenes)["hub"].compare_strip == (
        2837,
        3196,
    )


def test_an_entry_carries_where_each_steam_piece_is_placed_in_both_builds(tmp_path):
    scenes = {
        SCENE: Scene(
            timeline=0,
            frame="Navigation",
            pieces={
                "Square": Piece("art", 126, art="hotbar_square", steam=126),
                "Button": Piece("button", 126, steam=126),
                "Icon": Piece(
                    "art", None, art="save", instance="ui_but1", steam="ui_but1"
                ),
                "Late": Piece("button", 165, steam=157),
                "Bar": Piece("art", 1, art="bottom_bar"),
            },
        )
    }
    config = write_config(tmp_path, {"hub": entry(chrome={"bar": 37})})

    found = screen_compare.load_config(config, scenes)["hub"].steam

    assert found == ((126, 126), ("ui_but1", "ui_but1"), (165, 157))


def layer(character: int, x: int, y: int, scale: float = 1.0, **more):
    from urchin_dev.swf.timeline import Layer

    return Layer(character, matrix=(scale, 0.0, 0.0, scale, x, y), **more)


def test_each_steam_piece_moves_its_web_depth_by_the_steam_placement_difference():
    web = {
        126: layer(3185, 1033, 9878),
        153: layer(3171, 1022, 9871, name="ui_but1"),
        165: layer(3153, 5909, 9878),
    }
    steam = {
        126: layer(3185, 1033, 10138),
        150: layer(3171, 1022, 10131, name="ui_but1"),
        157: layer(3153, 5909, 10138),
    }
    pairs = ((126, 126), ("ui_but1", "ui_but1"), (165, 157))

    offsets = screen_compare.steam_offsets(web, steam, pairs, "hub")

    assert offsets == {126: (0.0, 13.0), 153: (0.0, 13.0), 165: (0.0, 13.0)}


def test_a_steam_piece_at_another_scale_is_refused():
    web = {126: layer(3185, 0, 0, scale=0.67)}
    steam = {126: layer(3185, 0, 260, scale=0.7)}

    with pytest.raises(screen_compare.CompareError, match="scale"):
        screen_compare.steam_offsets(web, steam, ((126, 126),), "hub")


def test_one_depth_with_two_steam_offsets_is_refused():
    web = {126: layer(3185, 0, 0)}
    steam = {126: layer(3185, 0, 260), 157: layer(3185, 0, 300)}

    with pytest.raises(screen_compare.CompareError, match="depth 126"):
        screen_compare.steam_offsets(web, steam, ((126, 126), (126, 157)), "hub")


def test_the_frame_splits_into_runs_of_depths_that_move_together_in_depth_order():
    layers = {d: layer(d, 0, 0) for d in (1, 59, 126, 128, 132, 152, 153, 155, 169)}
    moved = {126: (0.0, 13.0), 128: (0.0, 13.0), 153: (0.0, 13.0), 155: (0.0, 13.0)}

    runs = screen_compare.depth_runs(layers, moved)

    assert runs == [
        ((1, 59), (0.0, 0.0)),
        ((126, 128), (0.0, 13.0)),
        ((132, 152), (0.0, 0.0)),
        ((153, 155), (0.0, 13.0)),
        ((169,), (0.0, 0.0)),
    ]


def test_a_clip_mask_that_spans_two_runs_is_refused():
    layers = {1: layer(1, 0, 0, clip_depth=3), 2: layer(2, 0, 0), 3: layer(3, 0, 0)}

    with pytest.raises(screen_compare.CompareError, match="clip"):
        screen_compare.depth_runs(layers, {3: (0.0, 13.0)})


def test_a_steam_reference_renders_each_run_on_its_own_with_the_strip(monkeypatch):
    web = {1: layer(1, 0, 0), 126: layer(3185, 0, 0), 152: layer(3172, 0, 0)}
    steam = {126: layer(3185, 0, 260), 152: layer(3172, 0, 0)}
    monkeypatch.setattr(screen_compare.screen_rects, "origin_of", lambda *_: (0, 0))
    monkeypatch.setattr(screen_compare.timeline, "frame_of", lambda *_: 1)
    monkeypatch.setattr(
        screen_compare.timeline,
        "frames",
        lambda index, owner: [web if index == "web" else steam],
    )
    monkeypatch.setattr(screen_compare, "character_kind", lambda *_: "shape")
    monkeypatch.setattr(
        screen_compare.strip, "strip_list", lambda _, reasons: sorted(reasons)
    )
    hub = screen_compare.Entry(
        "res://hub.tscn",
        0,
        "Navigation",
        {"chrome": screen_compare.Mode(None, ())},
        compare_strip=(2837,),
        steam=((126, 126),),
    )

    jobs = screen_compare.reference_jobs("web", hub, "chrome", "steam")

    assert [(job.only_depths, offset) for job, offset in jobs] == [
        ((1,), (0.0, 0.0)),
        ((126,), (0.0, 13.0)),
        ((152,), (0.0, 0.0)),
    ]
    assert all(job.strip == (2837,) for job, _ in jobs)


def test_a_steam_reference_needs_the_steam_build(monkeypatch):
    monkeypatch.setattr(screen_compare, "reference_job", lambda *_: None)
    hub = screen_compare.Entry(
        "res://hub.tscn",
        0,
        "Navigation",
        {"chrome": screen_compare.Mode(None, ())},
        steam=((126, 126),),
    )

    with pytest.raises(screen_compare.CompareError, match="no Steam build"):
        screen_compare.reference_jobs("web", hub, "chrome", None)


def test_a_reference_with_no_steam_piece_is_one_render(monkeypatch):
    from types import SimpleNamespace

    job = SimpleNamespace()
    monkeypatch.setattr(screen_compare, "reference_job", lambda *_: job)
    entry = screen_compare.Entry(
        "res://a.tscn", 0, "x", {"chrome": screen_compare.Mode(None, ())}
    )

    jobs = screen_compare.reference_jobs(None, entry, "chrome", None)

    assert jobs == [(job, (0.0, 0.0))]


def test_runs_are_drawn_in_order_with_each_moved_by_its_offset():
    red = Image.new("RGBA", (2, 2), (255, 0, 0, 255))
    blue = Image.new("RGBA", (2, 2), (0, 0, 255, 255))
    cuts = [((1.0, 1.0), red, (0.0, 0.0)), ((1.0, 1.0), blue, (0.0, 1.0))]

    canvas = np.asarray(screen_compare.composite(cuts, (6, 8), zoom=2))

    assert tuple(canvas[2, 2]) == (255, 0, 0, 255)
    assert tuple(canvas[4, 2]) == (0, 0, 255, 255)
    assert tuple(canvas[5, 3]) == (0, 0, 255, 255)
    assert canvas[1, 2, 3] == 0


@pytest.mark.parametrize(
    "piece",
    [
        Piece("button", 126, inner_depth=2, steam=126),
        Piece("button", 126, via=(3149,), steam=126),
    ],
)
def test_a_steam_piece_inside_a_sprite_is_refused(tmp_path, piece):
    scenes = {SCENE: Scene(timeline=0, frame="Navigation", pieces={"In": piece})}
    config = write_config(tmp_path, {"hub": entry(chrome={"bar": 37})})

    with pytest.raises(screen_compare.CompareError, match="inside a sprite"):
        screen_compare.load_config(config, scenes)


def test_a_blend_mode_over_an_earlier_run_is_refused():
    layers = {1: layer(1, 0, 0), 2: layer(2, 0, 0, blend_mode=3)}

    with pytest.raises(screen_compare.CompareError, match="blend mode at depth 2"):
        screen_compare.depth_runs(layers, {2: (0.0, 13.0)})


def test_a_layer_blend_mode_over_an_earlier_run_is_kept():
    layers = {1: layer(1, 0, 0), 2: layer(2, 0, 0, blend_mode=2)}

    runs = screen_compare.depth_runs(layers, {2: (0.0, 13.0)})

    assert runs == [((1,), (0.0, 0.0)), ((2,), (0.0, 13.0))]


def test_a_steam_piece_in_a_krinmenu_entry_is_refused(monkeypatch):
    monkeypatch.setattr(screen_compare, "reference_job", lambda *_: None)
    menu = screen_compare.Entry(
        "res://a.tscn",
        screen_compare.window_chrome.KRINMENU,
        "win",
        {"chrome": screen_compare.Mode(None, ())},
        steam=((126, 126),),
    )

    with pytest.raises(screen_compare.CompareError, match="KRINMENU"):
        screen_compare.reference_jobs(None, menu, "chrome", None)


def test_a_steam_reference_splits_only_the_depths_its_mode_renders(monkeypatch):
    from urchin_dev.swf import render

    web = {1: layer(1, 0, 0), 126: layer(3185, 0, 0), 152: layer(3172, 0, 0)}
    steam = {126: layer(3185, 0, 260)}
    monkeypatch.setattr(
        screen_compare,
        "reference_job",
        lambda *_: render.Job(0, 1, 4, only_depths=(1, 126)),
    )
    monkeypatch.setattr(screen_compare.timeline, "frame_of", lambda *_: 1)
    monkeypatch.setattr(
        screen_compare.timeline,
        "frames",
        lambda index, owner: [web if index == "web" else steam],
    )
    panels = screen_compare.Entry(
        "res://hub.tscn",
        0,
        "Navigation",
        {"panels": screen_compare.Mode(None, ())},
        steam=((126, 126),),
    )

    jobs = screen_compare.reference_jobs("web", panels, "panels", "steam")

    assert [(job.only_depths, offset) for job, offset in jobs] == [
        ((1,), (0.0, 0.0)),
        ((126,), (0.0, 13.0)),
    ]


# The alpha mode: scores what a filter draws by alpha alone, against ffdec,
# with a capture of the same nodes with no material as its control.
ALPHA = {"nodes": ["Bar/Clip"], "bar": 40}
ALPHA_SCENES = {
    SCENE: Scene(
        timeline=0,
        frame="KRINBATTLESCENE",
        pieces={
            "Bar/Clip": Piece("bar_part", None, instance="p1BAR", art="filter"),
            "LeftPanel": Piece("panel", 11),
            "Row/Frame": Piece("art", 1197, "victory_row", inner_depth=2),
        },
    )
}


def test_the_alpha_of_a_capture_comes_from_its_magenta_and_green_copies():
    box = (1, 1, 3, 2)
    # Grey 100 at alpha 0.6 over magenta and over green.
    magenta = capture(3, 4, (255, 0, 255), box, (162, 60, 162))
    green = capture(3, 4, (0, 255, 0), box, (60, 162, 60))

    alpha = screen_compare.alpha_of(magenta, green)

    assert alpha[0, 0] == 0.0
    assert alpha[1, 1] == pytest.approx(0.6, abs=0.005)
    assert alpha[1, 2] == pytest.approx(0.6, abs=0.005)


def test_the_alpha_score_counts_every_pixel_either_side_draws():
    port = np.zeros((4, 4))
    port[1, 1] = 1.0
    reference = np.zeros((4, 4, 4), dtype=np.int16)
    reference[1, 1, 3] = 255
    reference[2, 2, 3] = 102

    found = screen_compare.alpha_score(port, reference)

    assert found.pixels == 2
    assert found.p50 == pytest.approx(51.0)
    assert found.p99 == pytest.approx(101.0, abs=0.1)


def test_an_alpha_score_with_nothing_drawn_is_an_error():
    with pytest.raises(screen_compare.CompareError, match="no pixels"):
        screen_compare.alpha_score(np.zeros((2, 2)), np.zeros((2, 2, 4)))


def test_an_alpha_mode_takes_pieces_placed_by_a_depth_or_an_instance_name(tmp_path):
    path = write_config(
        tmp_path, {"bars": entry(alpha={"nodes": ["Bar/Clip", "LeftPanel"], "bar": 40})}
    )

    mode = screen_compare.load_config(path, ALPHA_SCENES)["bars"].modes["alpha"]

    assert mode.places == ("p1BAR", 11)
    assert mode.nodes == ("Bar/Clip", "LeftPanel")


@pytest.mark.parametrize(
    ("fields", "message"),
    [
        ({"bar": 40}, "alpha needs its nodes"),
        ({"nodes": ["Row/Frame"], "bar": 40}, "Row/Frame is not a piece"),
        ({**ALPHA, "hide_names": ["Body"]}, "only chrome mode"),
    ],
)
def test_an_alpha_mode_that_breaks_the_format_is_refused(tmp_path, fields, message):
    path = write_config(tmp_path, {"broken": entry(alpha=fields)})

    with pytest.raises(screen_compare.CompareError, match=message):
        screen_compare.load_config(path, ALPHA_SCENES)


def test_an_alpha_mode_needs_a_control_capture_with_no_material(tmp_path):
    missing = screen_compare.missing_captures(tmp_path, "bars", ["alpha"])

    assert len(missing) == 4
    assert any("alpha_control_green.png" in line for line in missing)
    assert any('"--control"' in line for line in missing)


def test_the_control_capture_arguments_ask_for_no_material():
    assert screen_compare.capture_args("bars", "alpha", "magenta", control=True) == [
        "--entry=bars",
        "--mode=alpha",
        "--background=magenta",
        "--control",
    ]


def test_an_alpha_reference_keeps_only_the_depths_of_its_nodes_with_no_text(
    monkeypatch,
):
    from types import SimpleNamespace

    layers = {
        72: SimpleNamespace(character_id=333, name=None),
        342: SimpleNamespace(character_id=3414, name="p5BAR"),
        360: SimpleNamespace(character_id=3414, name="p1BAR"),
    }
    monkeypatch.setattr(screen_compare.screen_rects, "origin_of", lambda *_: (0, 0))
    monkeypatch.setattr(screen_compare.timeline, "frame_of", lambda *_: 1)
    inside = {1: SimpleNamespace(character_id=3407, name=None)}
    monkeypatch.setattr(
        screen_compare.timeline,
        "frames",
        lambda _, owner: [layers] if owner == 0 else [inside],
    )
    kinds = {333: "shape", 3414: "sprite", 3407: "edittext"}
    monkeypatch.setattr(screen_compare, "character_kind", lambda _, cid: kinds[cid])
    monkeypatch.setattr(
        screen_compare.strip, "strip_list", lambda _, reasons: sorted(reasons)
    )
    bars = screen_compare.Entry(
        SCENE,
        0,
        "KRINBATTLESCENE",
        {"alpha": screen_compare.Mode(40, places=("p1BAR", "p5BAR"))},
        compare_strip=(3435,),
    )

    job = screen_compare.reference_job(None, bars, "alpha")

    assert job.timeline == 0
    assert job.only_depths == (342, 360)
    assert job.strip == (3407,)


def test_an_alpha_mode_in_a_krinmenu_entry_is_refused(monkeypatch):
    monkeypatch.setattr(screen_compare.screen_rects, "origin_of", lambda *_: (0, 0))
    monkeypatch.setattr(screen_compare.timeline, "frame_of", lambda *_: 1)
    menu = screen_compare.Entry(
        SCENE,
        screen_compare.window_chrome.KRINMENU,
        "win",
        {"alpha": screen_compare.Mode(40, places=(11,))},
    )

    with pytest.raises(screen_compare.CompareError, match="KRINMENU"):
        screen_compare.reference_job(None, menu, "alpha")
