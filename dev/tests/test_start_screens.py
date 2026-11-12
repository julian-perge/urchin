# Checks the committed SONNY 2 logo against the record extract_start_screens
# wrote next to it, and the logo's render job on a stubbed timeline, so these
# tests never read the SWF or run ffdec. A second run of the extractor checks
# the render itself (#214).
from __future__ import annotations

import json
import math

import pytest
from PIL import Image
from urchin_dev import REPO_ROOT
from urchin_dev.swf import render, timeline
from urchin_dev.swf.extract import start_screens

MENU_DIR = REPO_ROOT / "assets" / "ui" / "menu"
RECORD = json.loads((MENU_DIR / "logo.json").read_text())

# Shape 320's box on the stage in design px, (x, y, w, h), from
# spec/107-title-slots.md, which read it from timeline.frames(). The PNG holds
# the shape with its Glow, so its rect holds the box and reaches past it by no
# more than the Glow's blur of 17 px. Each edge may add half a px, because the
# render rounds it to a whole pixel at zoom 4.
SHAPE_BOX = (123.20, 119.80, 549.55, 97.70)
GLOW_BLUR = 17.0
EDGE = 0.5


def test_the_logo_png_is_its_rect_times_the_zoom():
    with Image.open(MENU_DIR / "logo.png") as image:
        size = image.size
    _x, _y, width, height = RECORD["rect"]
    assert RECORD["zoom"] == start_screens.LOGO_ZOOM == 4.0
    assert RECORD["size"] == list(size)
    assert math.isclose(width * RECORD["zoom"], size[0], abs_tol=1e-6)
    assert math.isclose(height * RECORD["zoom"], size[1], abs_tol=1e-6)


def test_the_logo_holds_its_shape_and_reaches_past_it_by_the_glow_only():
    x, y, width, height = RECORD["rect"]
    box_x, box_y, box_w, box_h = SHAPE_BOX
    assert x <= box_x + EDGE
    assert y <= box_y + EDGE
    assert x + width >= box_x + box_w - EDGE
    assert y + height >= box_y + box_h - EDGE
    assert box_x - x <= GLOW_BLUR + EDGE
    assert box_y - y <= GLOW_BLUR + EDGE
    assert x + width - (box_x + box_w) <= GLOW_BLUR + EDGE
    assert y + height - (box_y + box_h) <= GLOW_BLUR + EDGE


def layer(character_id: int, matrix=timeline.IDENTITY) -> timeline.Layer:
    return timeline.Layer(
        character_id=character_id,
        name=None,
        matrix=matrix,
        color_transform=None,
        clip_depth=None,
        ratio=None,
        filters=(),
        blend_mode=None,
    )


def stub_swf(monkeypatch, frame_46):
    """Make start_screens read `frame_46` as the root's mainMenu frame."""
    monkeypatch.setattr(timeline, "frame_of", lambda index, owner, label: 46)
    monkeypatch.setattr(
        timeline, "frames", lambda index, owner: [{}] * 45 + [frame_46]
    )


def test_the_logo_renders_the_title_frame_with_only_the_logo_depth(monkeypatch):
    # The Glow is a filter on the root's placement of sprite 321, so a render
    # of sprite 321 alone would leave it out.
    stub_swf(monkeypatch, {1: layer(2701), 6: layer(start_screens.LOGO), 9: layer(2)})
    assert start_screens.logo_job(None) == render.Job(
        0, 46, start_screens.LOGO_ZOOM, only_depths=(6,)
    )


@pytest.mark.parametrize(
    "frame_46",
    [{1: layer(2701)}, {6: layer(321), 7: layer(321)}],
    ids=["absent", "twice"],
)
def test_the_logo_job_refuses_a_frame_that_does_not_place_the_logo_once(
    monkeypatch, frame_46
):
    stub_swf(monkeypatch, frame_46)
    with pytest.raises(render.RenderError):
        start_screens.logo_job(None)


def test_the_record_holds_the_rect_size_and_zoom_of_the_cut():
    job = render.Job(0, 46, 4.0, only_depths=(6,))
    cut = render.Trimmed(
        Image.new("RGBA", (8, 4)), (0, 0, 8, 4), (1.123456, 2.0, 2.0, 1.0)
    )
    assert start_screens.logo_record(job, cut) == {
        "rect": [1.1235, 2.0, 2.0, 1.0],
        "size": [8, 4],
        "zoom": 4.0,
    }
