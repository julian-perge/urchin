# Checks the committed window chrome art against the record extract_window_chrome
# wrote next to it, so these tests never read the SWF or run ffdec. The
# extractor's own renders are checked by running it twice (see #161).
from __future__ import annotations

import json
import math

from PIL import Image
from urchin_dev import REPO_ROOT
from urchin_dev.swf.extract import window_chrome

CHROME_DIR = REPO_ROOT / "assets" / "ui" / "window"
RECORD = json.loads((CHROME_DIR / "window_chrome.json").read_text())


def test_every_piece_the_extractor_renders_is_in_the_record():
    assert sorted(RECORD) == sorted(window_chrome.PIECES)


def test_every_piece_is_a_png_whose_pixels_are_its_rect_times_the_zoom():
    for name, piece in RECORD.items():
        with Image.open(CHROME_DIR / f"{name}.png") as image:
            size = image.size
        _x, _y, width, height = piece["rect"]
        assert piece["zoom"] == 4.0, name
        assert math.isclose(width * piece["zoom"], size[0], abs_tol=1e-6), name
        assert math.isclose(height * piece["zoom"], size[1], abs_tol=1e-6), name


def test_every_piece_says_what_its_rect_is_measured_from():
    for name, piece in RECORD.items():
        assert piece["relative_to"] == "stage" or piece["relative_to"].startswith(
            "sprite "
        ), name


def test_squares_that_differ_by_a_subpixel_phase_are_the_same_art():
    # Six hotbar squares sit at x positions that are not whole zoom 4 pixels,
    # so ffdec's anti-aliased edges differ by a few levels and one column.
    first = Image.new("RGBA", (215, 216), (30, 30, 30, 255))
    wider = Image.new("RGBA", (216, 216), (30, 30, 30, 255))
    wider.putpixel((0, 0), (46, 30, 30, 255))
    assert window_chrome.same_art(first, first.copy())
    assert window_chrome.same_art(first, wider)


def test_squares_of_another_colour_or_size_are_not_the_same_art():
    first = Image.new("RGBA", (215, 216), (30, 30, 30, 255))
    assert not window_chrome.same_art(
        first, Image.new("RGBA", (215, 216), (60, 30, 30, 255))
    )
    assert not window_chrome.same_art(
        first, Image.new("RGBA", (218, 216), (30, 30, 30, 255))
    )
