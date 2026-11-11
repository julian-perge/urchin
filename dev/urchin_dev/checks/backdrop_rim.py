# Scores the extracted Window backdrop (assets/ui/window/backdrop.png) against a
# real Flash capture of the victory Window, on a 20 px band just inside the
# backdrop's rim. #161 asks for p90 3 or better, shrunk to a 2x window.
#
# The method, so a number is the same wherever it is measured:
#   - the zoom 4 art goes on a 4x canvas at its rect times 4, and the canvas is
#     shrunk to the capture's 2x scale with a box filter, so a rect that is not
#     a whole 2x pixel lands as it would in a 2x window;
#   - the capture is 1600x1218, and its top 64 px are the browser's bar;
#   - the band is the 20 px just inside the backdrop's shape box, and only the
#     pixels the shrunk art covers completely are scored, so the soft outer edge
#     (the Glow and DropShadow that fade out) is left out, as the prototype that
#     scored the filtered render left out pixels that were not opaque;
#   - the score is the largest channel difference at the 90th percentile.
# rim_p90(shift=20) moves the capture 20 px sideways as a control, and has to
# score well over the bar.
from __future__ import annotations

import json

import numpy as np
from PIL import Image

from urchin_dev import REPO_ROOT

CHROME_DIR = REPO_ROOT / "assets" / "ui" / "window"
REFERENCE = (
    REPO_ROOT
    / "references"
    / "2026_07_18_flashpoint"
    / "16_after_battle_victory_screen_Screenshot 2026-07-18 at 18.16.01.png"
)
BROWSER_BAR = 64
WINDOW = (1600, 1150)
# The backdrop's shape box (x0, y0, x1, y1) in Stage design px, without its
# filters.
SHAPE_BOX = (14.15, 15.0, 782.7, 440.1)
BAND = 20


def rim_p90(shift: int = 0) -> float:
    """-> the p90 of the largest channel difference over the rim band, with the
    capture moved `shift` px sideways."""
    rect = json.loads((CHROME_DIR / "window_chrome.json").read_text())["backdrop"][
        "rect"
    ]
    art = Image.open(CHROME_DIR / "backdrop.png").convert("RGBA")
    width, height = WINDOW
    canvas = Image.new("RGBA", (width * 2, height * 2), (0, 0, 0, 0))
    canvas.alpha_composite(art, (round(rect[0] * 4), round(rect[1] * 4)))
    shrunk = np.asarray(canvas.resize(WINDOW, Image.BOX), dtype=np.int16)
    real = np.asarray(Image.open(REFERENCE).convert("RGB"), dtype=np.int16)
    real = np.roll(real[BROWSER_BAR:][:height], shift, axis=1)

    x0, y0, x1, y1 = (round(v * 2) for v in SHAPE_BOX)
    band = np.zeros((height, width), bool)
    band[y0:y1, x0 : x0 + BAND] = True
    band[y0 : y0 + BAND, x0:x1] = True
    band[y0:y1, x1 - BAND : x1] = True
    band[y1 - BAND : y1, x0:x1] = True
    scored = band & (shrunk[:, :, 3] == 255)
    difference = np.abs(shrunk[:, :, :3] - real).max(axis=2)[scored]
    return float(np.percentile(difference, 90))


def main():
    print(f"rim p90 {rim_p90():.1f}, control shifted 20 px {rim_p90(shift=20):.1f}")


if __name__ == "__main__":
    main()
