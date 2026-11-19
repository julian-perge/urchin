# vfx.clip_offset on a hand-built render.Frame, so no test needs ffdec or the
# gitignored SWF.
from __future__ import annotations

from pathlib import Path

import pytest
from urchin_dev.swf import render
from urchin_dev.swf.extract import vfx


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
