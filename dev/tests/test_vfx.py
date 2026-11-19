# extract_vfx's clean-up of a clip's folder on files made in a temporary
# folder, and vfx.clip_offset on a hand-built render.Frame, so no test needs
# ffdec or the gitignored SWF.
from __future__ import annotations

from pathlib import Path

import pytest
from urchin_dev.swf import render
from urchin_dev.swf.extract import vfx


def test_a_run_deletes_the_frames_a_clip_no_longer_has_and_their_imports(tmp_path):
    # BOOM_SPARK went from 25 frames to 20, and vfx_scenes.py builds a clip's
    # scene from every PNG in its folder.
    for n in range(1, 6):
        (tmp_path / f"{n}.png").write_bytes(b"")
        (tmp_path / f"{n}.png.import").write_bytes(b"")
    vfx.remove_frames_past(tmp_path, 3)
    assert sorted(path.name for path in tmp_path.iterdir()) == [
        "1.png",
        "1.png.import",
        "2.png",
        "2.png.import",
        "3.png",
        "3.png.import",
    ]


def test_a_clip_offset_starts_at_the_canvas_origin():
    # 461 twips at 2x is 46.1 px, which ffdec rounds up to a 47x47 canvas. Its
    # left and top edges are the rect the canvas was sized from, (-180, -70)
    # twips, whatever the rounding adds on the right and bottom.
    frame = render.Frame(
        job=render.Job(timeline=7, frame=1, zoom=vfx.ZOOM),
        path=Path("unused.png"),
        size=(47, 47),
        canvas_rect=(-180, -70, 281, 391),
        display_rect=(-150, -40, 251, 361),
    )
    offset, pad_x, pad_y = vfx.clip_offset(frame)
    assert offset == {"x": -9.0, "y": -3.5, "w": 23.5, "h": 23.5}
    assert pad_x == pytest.approx(pad_y)
