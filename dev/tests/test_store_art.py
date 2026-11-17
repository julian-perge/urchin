# Checks the committed Store keeper art against the record extract_store_art
# wrote next to it, and the extractor's pure parts on stubbed placements, so
# these tests never read the SWF or run ffdec. The extractor's own render is
# checked by running it twice (see #233).
from __future__ import annotations

import json
import math

import pytest
from PIL import Image
from urchin_dev import REPO_ROOT
from urchin_dev.swf import render
from urchin_dev.swf.extract import store_art, window_chrome

ART_DIR = REPO_ROOT / "assets" / "ui" / "store" / "backdrops"
RECORD = json.loads((ART_DIR / "store_art.json").read_text())

# The keeper scene's mask on the Stage, (x, y, w, h), typed from spec/107-store.md.
# The union crop has to hold it and may reach past it by the keeper's own art.
# #234 replaces this constant: its rect test reads the mask from the SWF.
MASK = (55.25, 99.90, 186.00, 140.00)
EDGE = 0.5


def cut(rect, size) -> render.Trimmed:
    return render.Trimmed(Image.new("RGBA", size), (0, 0, *size), rect)


def test_the_record_is_the_rect_times_the_zoom_for_every_shop_png():
    _x, _y, width, height = RECORD["rect"]
    assert RECORD["zoom"] == store_art.ZOOM
    for shop in store_art.SHOP_IDS:
        with Image.open(ART_DIR / f"shop{shop}.png") as image:
            size = image.size
        assert math.isclose(width * RECORD["zoom"], size[0], abs_tol=1e-6), shop
        assert math.isclose(height * RECORD["zoom"], size[1], abs_tol=1e-6), shop
        assert list(size) == RECORD["size"], shop


def test_the_record_is_measured_from_the_stage_and_holds_the_keeper_mask():
    x, y, width, height = RECORD["rect"]
    assert RECORD["relative_to"] == "stage"
    assert x <= MASK[0] + EDGE
    assert y <= MASK[1] + EDGE
    assert x + width >= MASK[0] + MASK[2] - EDGE
    assert y + height >= MASK[1] + MASK[3] - EDGE


def test_the_record_of_a_crop_is_its_rect_size_and_zoom():
    record = store_art.record_of(cut((54.525, 99.2, 187.25, 141.25), (749, 565)), 4.0)
    assert record == {
        "rect": [54.525, 99.2, 187.25, 141.25],
        "relative_to": "stage",
        "size": [749, 565],
        "zoom": 4.0,
    }


def test_a_crop_whose_rect_times_the_zoom_is_not_its_image_size_is_refused():
    with pytest.raises(ValueError, match="749x565"):
        store_art.record_of(cut((54.525, 99.2, 187.0, 141.25), (749, 565)), 4.0)


def test_the_stage_origin_adds_the_menu_placement_to_the_sprite_placement(monkeypatch):
    monkeypatch.setattr(
        window_chrome.timeline, "frame_of", lambda index, owner, label: 181
    )
    origins = {
        (0, 181, window_chrome.KRINMENU): (400.5, 222.4),
        (window_chrome.KRINMENU, window_chrome.SHOP_FRAME, store_art.STORE_SPRITE): (
            -252.25,
            -52.5,
        ),
    }
    monkeypatch.setattr(
        render,
        "placement_origin",
        lambda index, owner, frame, cid: origins[(owner, frame, cid)],
    )
    assert store_art.stage_origin(None) == pytest.approx((148.25, 169.9))
