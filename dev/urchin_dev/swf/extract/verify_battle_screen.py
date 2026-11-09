# Checks that the extracted hall and sky, composited at the rects
# battle_layout.json records, reproduce what ffdec draws for the battle frame,
# for every hall and sky pair a battle uses. The reference renders through
# ffdec_lib.py from the unmodified SWF, so nothing is written to a SWF.
#
# The reference is root frame KRINBATTLESCENE at the same zoom, with every
# depth hidden except the hall, the sky and DefineShape 333, the ids in
# battle_screen.BATTLE_STRIP deleted through strip.py, and the hall and the
# sky moved to the labels being checked, the way the game's two gotoAndStop
# handlers move them. The CLI could only ever render WHITE
# NOVEMBER over SEA, the frame 1 of each, which is all the check it replaced
# covered.
#
# 333 stays visible because it is the clip mask over both (clipDepth 340 at
# depth 72), and hiding a mask unclips what it covers. The extracted hall and
# sky PNGs are unclipped, so the diff only counts pixels inside 333's box.
# That box holds the edges where the hall's windows meet the sky, which a
# whole-frame diff dilutes with exact matches outside it. Inside the box,
# WHITE NOVEMBER over SEA scores p99 10 against this reference and 9 against a
# CLI render of a stripped copy, and the other 11 pairs score 1. That sets the
# bar at 10, still under the closest wrong pairing in --wrong-hall, CHURCH
# drawn where CHURCH2 belongs, at 18. The two references differ on under
# 0.03% of the box's pixels.
#
# Run: uv run python -m urchin_dev.swf.extract.verify_battle_screen
#   --wrong-hall renders each hall at a different label than the one
#   composited, which has to fail.
from __future__ import annotations

import json
import math
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

from urchin_dev import CONVERTED_JSON, WEB_SWF
from urchin_dev.swf import strip, timeline
from urchin_dev.swf.extract.battle_screen import (
    BATTLE_STRIP,
    FRAME_LABEL,
    HALL_DIR,
    HALL_SPRITE,
    LAYOUT_JSON,
    SKY_DIR,
    SKY_SPRITE,
    ZOOM,
)
from urchin_dev.swf.ffdec_lib import render
from urchin_dev.swf.swf_index import SwfIndex, read_swf, shape_bounds

MASK_SHAPE = 333
FIRST_PAIR = ("WHITE NOVEMBER", "SEA")
TOLERANCE = 10


def battle_pairs() -> list[tuple[str, str]]:
    battles = json.loads((CONVERTED_JSON / "battles.json").read_text())["battles"]
    pairs = sorted({(b["zone_background"], b["sky_background"]) for b in battles})
    return [FIRST_PAIR] + [p for p in pairs if p != FIRST_PAIR]


def transform_rect(matrix, rect):
    """-> the bounding box (xmin, ymin, xmax, ymax) of `rect` after `matrix`,
    which is (scaleX, rotateSkew0, rotateSkew1, scaleY, tx, ty) as the SWF
    stores it: x' = scaleX*x + rotateSkew1*y + tx, y' = rotateSkew0*x +
    scaleY*y + ty."""
    sx, r0, r1, sy, tx, ty = matrix
    xmin, ymin, xmax, ymax = rect
    corners = ((xmin, ymin), (xmax, ymin), (xmin, ymax), (xmax, ymax))
    xs = [sx * x + r1 * y + tx for x, y in corners]
    ys = [r0 * x + sy * y + ty for x, y in corners]
    return min(xs), min(ys), max(xs), max(ys)


def mask_box(
    index: SwfIndex, placements: dict[int, timeline.Layer]
) -> tuple[float, float, float, float]:
    """333's stage rect in design px, from its shape bounds and placement."""
    (layer,) = [p for p in placements.values() if p.character_id == MASK_SHAPE]
    rect = transform_rect(layer.matrix, shape_bounds(index, MASK_SHAPE))
    return tuple(v / 20 for v in rect)


def depth_of(placements: dict[int, timeline.Layer], character: int) -> int:
    (depth,) = [d for d, p in placements.items() if p.character_id == character]
    return depth


def composite(size, layout, hall: str, sky: str) -> Image.Image:
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    for folder, prefix, family, label in (
        (SKY_DIR, "SKY_", "skies", sky),
        (HALL_DIR, "", "halls", hall),
    ):
        name = label.replace(" ", "_")
        rect = layout[family][name]
        art = Image.open(folder / f"{prefix}{name}.png").convert("RGBA")
        canvas.alpha_composite(art, (round(rect["x"] * ZOOM), round(rect["y"] * ZOOM)))
    return canvas


def p99_inside(canvas: Image.Image, reference: Image.Image, box) -> tuple[int, float]:
    drawn = np.asarray(canvas.getchannel("A")) == 255
    inside = np.zeros_like(drawn)
    # Round the box inward, so pixels the mask's edge only partly covers stay out.
    x0, y0 = (math.ceil(v * ZOOM) for v in box[:2])
    x1, y1 = (math.floor(v * ZOOM) for v in box[2:])
    inside[y0:y1, x0:x1] = True
    mask = drawn & inside
    difference = np.abs(
        np.asarray(canvas.convert("RGB"), dtype=np.int16)
        - np.asarray(reference.convert("RGB"), dtype=np.int16)
    ).max(axis=2)[mask]
    return int(mask.sum()), float(np.percentile(difference, 99))


def main():
    wrong_hall = "--wrong-hall" in sys.argv[1:]
    index = read_swf(WEB_SWF)
    frame = timeline.frame_of(index, 0, FRAME_LABEL)
    placements = timeline.frames(index, 0)[frame - 1]
    box = mask_box(index, placements)
    keep = [depth_of(placements, c) for c in (MASK_SHAPE, SKY_SPRITE, HALL_SPRITE)]
    hall_depth, sky_depth = keep[2], keep[1]
    layout = json.loads(LAYOUT_JSON.read_text())
    pairs = battle_pairs()
    halls = sorted({h for h, _s in pairs})
    print(
        f"root frame {frame}, kept depths {keep}, "
        f"{MASK_SHAPE} box {tuple(round(v, 2) for v in box)}",
        file=sys.stderr,
    )

    stripped = strip.strip_list(WEB_SWF, BATTLE_STRIP)
    work = Path(tempfile.mkdtemp(prefix="verify_battle_"))
    jobs = []
    for n, (hall, sky) in enumerate(pairs):
        rendered_hall = (
            halls[(halls.index(hall) + 1) % len(halls)] if wrong_hall else hall
        )
        jobs.append(
            {
                "timeline": 0,
                "frame": frame,
                "zoom": ZOOM,
                "out": str(work / f"{n}.png"),
                "background": "swf",
                "only_depths": keep,
                "strip_characters": stripped,
                "goto": [
                    {"depth": hall_depth, "label": rendered_hall},
                    {"depth": sky_depth, "label": sky},
                ],
            }
        )
    results = render(WEB_SWF, jobs)

    worst = 0.0
    for (hall, sky), job, result in zip(pairs, jobs, results):
        reference = Image.open(result["out"])
        canvas = composite(reference.size, layout, hall, sky)
        pixels, p99 = p99_inside(canvas, reference, box)
        worst = max(worst, p99)
        shown = job["goto"][0]["label"]
        print(
            f"{hall} over {sky}: reference hall {shown}, {pixels} pixels, "
            f"p99 {p99:.0f}, render {result['seconds']:.2f}s",
            file=sys.stderr,
        )
    print(
        f"worst p99 {worst:.0f} over {len(pairs)} pairs, renders in {work}",
        file=sys.stderr,
    )
    if worst > TOLERANCE:
        raise SystemExit(
            f"recomposition does not match (p99 {worst:.0f} > {TOLERANCE})"
        )
    print("every pair matches", file=sys.stderr)


if __name__ == "__main__":
    main()
