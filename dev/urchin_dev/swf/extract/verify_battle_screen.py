# Checks that the extracted hall and sky, composited at the rects
# battle_layout.json records, reproduce what ffdec draws for the whole
# KRINBATTLESCENE frame with the foreground stripped. Same recomposition check
# the class-select work used.
#
# The pair checked is WHITE NOVEMBER over SEA, and it has to be: ffdec does not
# run ActionScript, so the two gotoAndStop handlers that pick a hall and a sky
# never fire and both sprites render at their own frame 1. Those frame-1 labels
# happen to be a real pairing - battle 49's.
#
# The diff is masked to pixels the recomposition actually draws. The reference
# render also paints the stage behind everything, so the roughly 29% of the
# frame the two backgrounds do not cover would otherwise count as mismatched.
# Across the drawn pixels the median difference is 0 and the 99th percentile is
# 8; what is left sits on edges where the hall's window meets the sky.
#
# Run: uv run python -m urchin_dev.swf.extract.verify_battle_screen
from __future__ import annotations

import json
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

from urchin_dev import FFDEC, WEB_SWF
from urchin_dev.swf import timeline
from urchin_dev.swf.extract.battle_screen import (
    FIGHTER_RIG,
    FRAME_LABEL,
    HALL_DIR,
    LAYOUT_JSON,
    SKY_DIR,
    ZOOM,
    run,
)
from urchin_dev.swf.swf_index import read_swf

# Every character the battle frame places except the hall (3435) and the sky
# (3454), so the reference render shows those two alone.
FOREGROUND = (
    333,
    2427,
    2717,
    2852,
    3172,
    3317,
    3355,
    3356,
    3367,
    3368,
    3369,
    3373,
    3382,
    3383,
    3389,
    3394,
    3414,
    3415,
    3416,
    3417,
    3418,
    3419,
    3420,
    3455,
    3460,
    3465,
)
HALL_LABEL = "WHITE_NOVEMBER"
SKY_LABEL = "SEA"
# Difference allowed at the 99th percentile of drawn pixels, in 8-bit levels.
TOLERANCE = 8


def main():
    frame = timeline.frame_of(read_swf(WEB_SWF), 0, FRAME_LABEL)
    layout = json.loads(LAYOUT_JSON.read_text())

    work = Path(tempfile.mkdtemp(prefix="verify_battle_"))
    try:
        stripped = work / "bare.swf"
        run(
            [
                str(FFDEC),
                "-removeCharacter",
                str(WEB_SWF),
                str(stripped),
                str(FIGHTER_RIG),
            ]
            + [str(c) for c in FOREGROUND]
        )
        run(
            [
                str(FFDEC),
                "-zoom",
                str(ZOOM),
                "-format",
                "frame:png",
                "-select",
                str(frame),
                "-export",
                "frame",
                str(work / "ref"),
                str(stripped),
            ]
        )
        reference = Image.open(work / "ref" / f"{frame}.png").convert("RGB")

        canvas = Image.new("RGBA", reference.size, (0, 0, 0, 0))
        for folder, prefix, family, label in (
            (SKY_DIR, "SKY_", "skies", SKY_LABEL),
            (HALL_DIR, "", "halls", HALL_LABEL),
        ):
            rect = layout[family][label]
            art = Image.open(folder / f"{prefix}{label}.png").convert("RGBA")
            canvas.alpha_composite(
                art, (round(rect["x"] * ZOOM), round(rect["y"] * ZOOM))
            )

        drawn = np.asarray(canvas.getchannel("A")) == 255
        difference = np.abs(
            np.asarray(canvas.convert("RGB"), dtype=np.int16)
            - np.asarray(reference, dtype=np.int16)
        ).max(axis=2)[drawn]
        p99 = float(np.percentile(difference, 99))
        print(
            f"drawn pixels {drawn.sum()}, median {np.median(difference):.0f}, "
            f"p99 {p99:.0f}, max {difference.max()}",
            file=sys.stderr,
        )
        if p99 > TOLERANCE:
            raise SystemExit(
                f"recomposition does not match the reference render "
                f"(p99 {p99:.0f} > {TOLERANCE})"
            )
        print("recomposition matches", file=sys.stderr)
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
