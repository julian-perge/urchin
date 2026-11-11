# render.py with ffdec_lib.render faked by canned PNGs and result lines,
# ffdec_lib's load grouping with the driver command faked, and played_frames()
# on SWF bytes built by hand, so no test needs Java, ffdec or the gitignored
# SWF.
from __future__ import annotations

import json
import math
import struct
import subprocess
from pathlib import Path

import pytest
from PIL import Image
from test_swf_index import bits, place2, swf, tag
from test_timeline import remove
from urchin_dev.swf import ffdec_lib, render
from urchin_dev.swf.render import Job, RenderError
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SHAPE,
    TAG_DEFINE_SPRITE,
    TAG_DO_ACTION,
    TAG_END,
    TAG_SHOW_FRAME,
    SwfIndex,
    parse_swf,
)


def fake_driver(monkeypatch, results: list[dict], boxes: list[tuple | None]):
    """Make ffdec_lib.render write one canvas per job, sized as its result
    says, opaque inside the matching box, and return the canned results."""

    def fake(swf_path, jobs):
        lines = []
        for job, result, box in zip(jobs, results, boxes, strict=True):
            canvas = Image.new("RGBA", (result["width"], result["height"]))
            if box is not None:
                canvas.paste((255, 0, 0, 255), box)
            canvas.save(job["out"])
            lines.append({**result, "out": job["out"]})
        return lines

    monkeypatch.setattr(ffdec_lib, "render", fake)


def result(width, height, canvas, display):
    return {
        "width": width,
        "height": height,
        "xmin": canvas[0],
        "ymin": canvas[1],
        "xmax": canvas[2],
        "ymax": canvas[3],
        "display": list(display),
    }


def old_content_rect(origin, display_rect, canvas, bbox, zoom):
    """battle_screen.content_rect and start_screens.content_rect as they were
    before this module, with display_rect as (x, y, w, h) in design px."""
    centre_x = origin[0] + display_rect[0] + display_rect[2] / 2
    centre_y = origin[1] + display_rect[1] + display_rect[3] / 2
    canvas_x = centre_x - canvas[0] / zoom / 2
    canvas_y = centre_y - canvas[1] / zoom / 2
    return (
        canvas_x + bbox[0] / zoom,
        canvas_y + bbox[1] / zoom,
        (bbox[2] - bbox[0]) / zoom,
        (bbox[3] - bbox[1]) / zoom,
    )


# A filtered sprite: displayRect -150..250 x -40..360 twips, grown by a
# 30-twip margin on every side, which at 4x is a 92x92 canvas. 430 twips at
# 4x is 86 px exactly, so the display rect is 21.5x20 design px.
CANVAS = (-180, -70, 280, 390)
DISPLAY = (-150, -40, 250, 360)


def test_trim_keeps_the_old_centre_formula(tmp_path, monkeypatch):
    fake_driver(monkeypatch, [result(92, 92, CANVAS, DISPLAY)], [(10, 20, 40, 50)])
    job = Job(timeline=7, frame=1, zoom=4.0, origin=(100.5, 33.25))
    with render.frames(tmp_path / "a.swf", [job]) as (frame,):
        trimmed = render.trim(frame)
    display_px = (-7.5, -2.0, 20.0, 20.0)
    expected = old_content_rect(
        (100.5, 33.25), display_px, (92, 92), (10, 20, 40, 50), 4.0
    )
    assert trimmed.rect == expected
    assert trimmed.image.size == (30, 30)
    assert trimmed.rect[2] * 4.0 == trimmed.image.width


def test_trim_union_cuts_every_frame_to_one_box(tmp_path, monkeypatch):
    fake_driver(
        monkeypatch,
        [result(92, 92, CANVAS, DISPLAY)] * 3,
        [(10, 20, 40, 50), (30, 5, 60, 25), None],
    )
    jobs = [Job(timeline=7, frame=n, zoom=4.0) for n in (1, 2, 3)]
    with render.frames(tmp_path / "a.swf", jobs) as rendered:
        cut = render.trim_union(rendered)
    assert [t.bbox for t in cut] == [(10, 5, 60, 50)] * 3
    assert [t.image.size for t in cut] == [(50, 45)] * 3
    assert cut[0].rect == cut[2].rect
    assert math.isclose(cut[0].rect[2] * 4.0, 50)


def test_trim_gives_none_for_a_blank_frame(tmp_path, monkeypatch):
    fake_driver(monkeypatch, [result(92, 92, CANVAS, DISPLAY)], [None])
    with render.frames(tmp_path / "a.swf", [Job(7, 1, 4.0)]) as (frame,):
        assert render.trim(frame) is None


@pytest.mark.parametrize(
    ("canned", "message"),
    [
        (result(93, 92, CANVAS, DISPLAY), "isn't its rect"),
        (result(92, 92, CANVAS, (-150, -40, 350, 360)), "smaller than its displayRect"),
    ],
)
def test_a_canvas_that_disagrees_with_its_rects_raises(
    tmp_path, monkeypatch, canned, message
):
    fake_driver(monkeypatch, [canned], [None])
    with (
        pytest.raises(RenderError, match=message),
        render.frames(tmp_path / "a.swf", [Job(7, 1, 4.0)]),
    ):
        pass


def test_an_empty_rect_renders_a_one_pixel_canvas(tmp_path, monkeypatch):
    fake_driver(monkeypatch, [result(1, 1, (0, 0, 0, 0), (0, 0, 0, 0))], [None])
    with render.frames(tmp_path / "a.swf", [Job(7, 1, 2.0)]) as (frame,):
        assert frame.size == (1, 1)


def matrix(tx: int, ty: int, scale: int | None = None) -> bytes:
    if scale is None:
        return bits((0, 1), (0, 1), (12, 5), (tx, 12), (ty, 12))
    return bits(
        (1, 1), (19, 5), (scale, 19), (scale, 19), (0, 1), (12, 5), (tx, 12), (ty, 12)
    )


def test_an_origin_has_to_be_a_pure_translate():
    shape = tag(TAG_DEFINE_SHAPE, struct.pack("<H", 10) + b"\0\0\0\0\0")
    index = parse_swf(
        swf(
            shape,
            place2(3, cid=10, matrix=matrix(200, -60)),
            place2(4, cid=10, matrix=matrix(0, 0, scale=0x20000)),
            tag(TAG_SHOW_FRAME),
        )
    )
    with pytest.raises(RenderError, match="places 10 2 times"):
        render.placement_origin(index, 0, 1, 10)
    single = parse_swf(
        swf(shape, place2(3, cid=10, matrix=matrix(200, -60)), tag(TAG_SHOW_FRAME))
    )
    assert render.placement_origin(single, 0, 1, 10) == (10.0, -3.0)
    scaled = parse_swf(
        swf(
            shape,
            place2(4, cid=10, matrix=matrix(0, 0, scale=0x20000)),
            tag(TAG_SHOW_FRAME),
        )
    )
    with pytest.raises(RenderError, match="timeline 0 frame 1 depth 4: .*not a pure"):
        render.placement_origin(scaled, 0, 1, 10)


def test_strip_lists_group_into_one_load_each(tmp_path, monkeypatch):
    seen = []

    def fake_run(cmd):
        spec = json.loads(Path(cmd[-1]).read_text())
        seen.append(spec)
        lines = [
            json.dumps({"out": job["out"]})
            for load in spec["loads"]
            for job in load["jobs"]
        ]
        return subprocess.CompletedProcess(cmd, 0, "\n".join(lines), "")

    monkeypatch.setattr(ffdec_lib, "run", fake_run)
    jobs = [
        {
            "timeline": 1,
            "frame": 1,
            "out": str(tmp_path / "1.png"),
            "strip_characters": [3312, 2676],
        },
        {"timeline": 2, "frame": 1, "out": str(tmp_path / "2.png")},
        {
            "timeline": 3,
            "frame": 1,
            "out": str(tmp_path / "3.png"),
            "strip_characters": [2676, 3312],
        },
    ]
    results = ffdec_lib.render(tmp_path / "a.swf", jobs)
    (spec,) = seen
    assert [load["strip_characters"] for load in spec["loads"]] == [[2676, 3312], []]
    assert [len(load["jobs"]) for load in spec["loads"]] == [2, 1]
    assert [r["out"] for r in results] == [job["out"] for job in jobs]


def test_only_depths_and_goto_reach_the_driver_only_when_a_job_sets_them(
    tmp_path, monkeypatch
):
    # The driver reads an only_depths list as "hide every other depth", so an
    # empty one would hide everything a job meant to keep.
    sent = []

    def fake(swf_path, jobs):
        sent.extend(jobs)
        for job in jobs:
            Image.new("RGBA", (92, 92)).save(job["out"])
        return [{**result(92, 92, CANVAS, DISPLAY), "out": j["out"]} for j in jobs]

    monkeypatch.setattr(ffdec_lib, "render", fake)
    jobs = [
        Job(0, 217, 4.0),
        Job(0, 217, 4.0, only_depths=(72, 630), goto=((630, 12),)),
    ]
    with render.frames(tmp_path / "a.swf", jobs):
        pass
    assert "only_depths" not in sent[0] and "goto" not in sent[0]
    assert sent[1]["only_depths"] == [72, 630]
    assert sent[1]["goto"] == [{"depth": 630, "frame": 12}]


SHOW = tag(TAG_SHOW_FRAME)
# A frame script that runs stop(): ActionStop, then the end flag.
STOP = tag(TAG_DO_ACTION, bytes([0x07, 0x00]))
SHAPE = 10
# The clip a test plays, and a clip nested in it.
CLIP = 21
INNER = 22


def sprite(sprite_id: int, *frames: bytes) -> bytes:
    """A DefineSprite with one frame for each argument, which holds that
    frame's tags."""
    body = b"".join(frame + SHOW for frame in frames)
    return tag(
        TAG_DEFINE_SPRITE,
        struct.pack("<HH", sprite_id, len(frames)) + body + tag(TAG_END),
    )


def clips(*sprites: bytes) -> SwfIndex:
    """-> the index of a SWF that defines the shape SHAPE and then `sprites`."""
    shape = tag(TAG_DEFINE_SHAPE, struct.pack("<H", SHAPE) + b"\0\0\0\0\0")
    return parse_swf(swf(shape, *sprites, SHOW))


def test_a_clip_that_never_stops_plays_through_its_last_frame():
    index = clips(sprite(CLIP, place2(1, cid=SHAPE), b"", b""))
    assert render.played_frames(index, CLIP) == [1, 2, 3]


def test_a_clip_ends_on_the_frame_whose_script_runs_stop():
    index = clips(sprite(CLIP, place2(1, cid=SHAPE), STOP, b""))
    assert render.played_frames(index, CLIP) == [1, 2]


def test_a_clip_resumed_past_a_stop_plays_on_from_where_it_resumes():
    # The Shield clip rests on its frame 1, which runs stop(), and play() runs
    # it on from frame 2 (DECODED_ALGORITHMS.md, The Shield clip).
    index = clips(sprite(CLIP, STOP, place2(1, cid=SHAPE), b""))
    assert render.played_frames(index, CLIP) == [1]
    assert render.played_frames(index, CLIP, start=2) == [2, 3]


def test_a_clip_ends_where_a_nested_clip_stops_when_nothing_draws_after():
    # BOOM_SPARK (DefineSprite 1712) shows sprite 884 until its frame 25, and
    # 884 runs stop() on its empty frame 20 (DefineSprite_884/frame_20), so the
    # game draws nothing after frame 20 while ffdec loops 884 back to its
    # frame 1. Here INNER stops on its empty frame 3 and CLIP shows it to its
    # frame 5.
    index = clips(
        sprite(INNER, place2(1, cid=SHAPE), b"", remove(1) + STOP),
        sprite(CLIP, place2(1, cid=INNER), b"", b"", b"", b"", remove(1)),
    )
    assert render.played_frames(index, CLIP) == [1, 2, 3]


@pytest.mark.parametrize(
    "inner, clip",
    [
        ((place2(1, cid=SHAPE), STOP), (place2(1, cid=INNER), b"", b"")),
        (
            (place2(1, cid=SHAPE), remove(1) + STOP),
            (place2(1, cid=INNER), b"", place2(2, cid=SHAPE)),
        ),
    ],
    ids=["the nested clip stops on a frame it draws", "the clip draws more"],
)
def test_a_clip_that_draws_after_a_nested_clip_stops_is_refused(inner, clip):
    index = clips(sprite(INNER, *inner), sprite(CLIP, *clip))
    with pytest.raises(RenderError, match=f"timeline {CLIP} frame 3 still draws"):
        render.played_frames(index, CLIP)


def test_a_nested_clip_counts_its_frames_from_the_frame_that_places_it():
    # The Shield clip (DefineSprite 2675) places BOOM_SPARK on its frame 2, so
    # sprite 884 inside the spark is one frame behind the Shield clip and only
    # reaches its frame 19 of 20. Here CLIP places INNER on its frame 2, so
    # INNER runs its stop() on CLIP's last frame and never plays past it.
    index = clips(
        sprite(INNER, place2(1, cid=SHAPE), remove(1) + STOP),
        sprite(CLIP, b"", place2(1, cid=INNER), b""),
    )
    assert render.played_frames(index, CLIP) == [1, 2, 3]


def test_a_clip_nested_two_deep_that_stops_ends_the_clip_too():
    # The Shield clip holds BOOM_SPARK, which holds sprite 884, so 884 plays
    # two levels down. Here MIDDLE places INNER on its frame 2, and INNER stops
    # on its empty frame 2, which is CLIP's frame 3.
    middle = 23
    index = clips(
        sprite(INNER, place2(1, cid=SHAPE), remove(1) + STOP),
        sprite(middle, b"", place2(1, cid=INNER), b"", b""),
        sprite(CLIP, place2(1, cid=middle), b"", b"", b""),
    )
    assert render.played_frames(index, CLIP) == [1, 2, 3]


# gotoAndPlay("hit"): GotoLabel, then Play.
GOTO_AND_PLAY = tag(
    TAG_DO_ACTION, bytes([0x8C]) + struct.pack("<H", 4) + b"hit\0" + bytes([0x06, 0x00])
)
# if (x) stop();: Push "x", GetVariable, Not, then an If that jumps over the
# Stop.
MAYBE_STOP = tag(
    TAG_DO_ACTION,
    bytes([0x96]) + struct.pack("<H", 3) + b"\0x\0"
    + bytes([0x1C, 0x12, 0x9D]) + struct.pack("<Hh", 2, 1)
    + bytes([0x07, 0x00]),
)  # fmt: skip
# _parent.stop();: Push 0 and "_parent", GetVariable, Push "stop", CallMethod,
# then Pop.
PARENT_STOP = tag(
    TAG_DO_ACTION,
    bytes([0x96]) + struct.pack("<H", 14) + b"\x07\0\0\0\0" + b"\0_parent\0"
    + bytes([0x1C, 0x96]) + struct.pack("<H", 6) + b"\0stop\0"
    + bytes([0x52, 0x17, 0x00]),
)  # fmt: skip
# with (_parent) { stop(); }: Push "_parent", GetVariable, then a With whose
# 1-byte body is the Stop.
WITH_PARENT_STOP = tag(
    TAG_DO_ACTION,
    bytes([0x96]) + struct.pack("<H", 9) + b"\0_parent\0"
    + bytes([0x1C, 0x94]) + struct.pack("<HH", 2, 1)
    + bytes([0x07, 0x00]),
)  # fmt: skip


@pytest.mark.parametrize(
    "script, refusal",
    [
        (GOTO_AND_PLAY, "moves its playhead"),
        (MAYBE_STOP, "may skip its stop"),
        (WITH_PARENT_STOP, "may skip its stop.* or run it on another clip"),
        (PARENT_STOP, "calls stop by name"),
    ],
    ids=[
        "a jump",
        "a stop() behind a branch",
        "a stop() inside a with block",
        "a stop() called by name",
    ],
)
def test_a_script_whose_effect_on_the_playhead_is_unclear_is_refused(script, refusal):
    index = clips(sprite(CLIP, place2(1, cid=SHAPE), script, b""))
    with pytest.raises(RenderError, match=f"timeline {CLIP} frame 2 {refusal}"):
        render.played_frames(index, CLIP)


def test_a_clip_resumed_while_an_earlier_nested_clip_plays_is_refused():
    # INNER has played for as long as CLIP rested on its frame 1, and no tag
    # says how long that was.
    index = clips(
        sprite(INNER, place2(1, cid=SHAPE), b""),
        sprite(CLIP, place2(1, cid=INNER) + STOP, b"", b""),
    )
    with pytest.raises(
        RenderError, match=f"timeline {CLIP} frame 2 shows {INNER}, placed on frame 1"
    ):
        render.played_frames(index, CLIP, start=2)


def test_a_nested_clip_is_read_only_as_far_as_it_plays():
    # INNER jumps on its frame 3, and CLIP shows it for 2 frames.
    index = clips(
        sprite(INNER, place2(1, cid=SHAPE), b"", GOTO_AND_PLAY),
        sprite(CLIP, place2(1, cid=INNER), b""),
    )
    assert render.played_frames(index, CLIP) == [1, 2]


def test_hide_depths_reach_the_driver_as_owner_and_depth(tmp_path, monkeypatch):
    # The window chrome backdrop hides every depth of KRINMENU (3142) but one
    # while the root frame draws it, so a job has to carry (owner, depth) pairs.
    fake_driver(monkeypatch, [result(92, 92, CANVAS, DISPLAY)] * 2, [None, None])
    real = ffdec_lib.render
    seen: list[dict] = []

    def spy(swf_path, jobs):
        seen.extend(jobs)
        return real(swf_path, jobs)

    monkeypatch.setattr(ffdec_lib, "render", spy)
    jobs = [Job(7, 1, 4.0, hide_depths=((3142, 5), (3142, 9))), Job(7, 1, 4.0)]
    with render.frames(tmp_path / "a.swf", jobs):
        pass
    assert seen[0]["hide_depths"] == [
        {"owner": 3142, "depth": 5},
        {"owner": 3142, "depth": 9},
    ]
    assert "hide_depths" not in seen[1]
