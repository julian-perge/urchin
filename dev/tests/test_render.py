# render.py with ffdec_lib.render faked by canned PNGs and result lines, and
# ffdec_lib's load grouping with the driver command faked, so no test needs
# Java, ffdec or the gitignored SWF.
from __future__ import annotations

import json
import math
import struct
import subprocess
from pathlib import Path

import pytest
from PIL import Image
from test_swf_index import bits, place2, swf, tag
from urchin_dev.swf import ffdec_lib, render
from urchin_dev.swf.render import Job, RenderError
from urchin_dev.swf.swf_index import TAG_DEFINE_SHAPE, TAG_SHOW_FRAME, parse_swf


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
