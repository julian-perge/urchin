# The battle recomposition check of verify_battle_screen.py, with its
# reference rendered through ffdec_lib.py from the unmodified SWF instead of
# from a stripped copy. Nothing is written to a SWF.
#
# The reference is root frame KRINBATTLESCENE at the same zoom, with every
# depth hidden except the hall, the sky and DefineShape 333, every nested
# placement of the fighter rig (2676) and the member bars (3312) hidden, and
# the hall and the sky moved to the labels being checked, the way the game's
# two gotoAndStop handlers move them. That lets it check every hall and sky
# pair a battle uses, where the CLI can only ever render WHITE NOVEMBER over
# SEA, the frame 1 of each.
#
# 333 stays visible because it is the clip mask over both (clipDepth 340 at
# depth 72), and hiding a mask unclips what it covers. The extracted hall and
# sky PNGs are unclipped, so the diff only counts pixels inside 333's box.
#
# Run: uv run python -m urchin_dev.swf.extract.verify_battle_screen_lib
#   --wrong-hall renders each hall at a different label than the one
#   composited, which has to fail.
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

from urchin_dev import CONVERTED_JSON, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import parse_swf_xml, root_placements, transform_rect
from urchin_dev.swf.extract.battle_screen import (
    FIGHTER_RIG,
    FRAME_LABEL,
    HALL_DIR,
    HALL_SPRITE,
    LAYOUT_JSON,
    MEMBER_BARS,
    SKY_DIR,
    SKY_SPRITE,
    ZOOM,
)
from urchin_dev.swf.ffdec_lib import render

MASK_SHAPE = 333
FIRST_PAIR = ("WHITE NOVEMBER", "SEA")
TOLERANCE = 8


def battle_pairs() -> list[tuple[str, str]]:
    battles = json.loads((CONVERTED_JSON / "battles.json").read_text())["battles"]
    pairs = sorted({(b["zone_background"], b["sky_background"]) for b in battles})
    return [FIRST_PAIR] + [p for p in pairs if p != FIRST_PAIR]


def mask_box(xml: str, placements: dict) -> tuple[float, float, float, float]:
    """333's stage rect in design px, from its shape bounds and placement."""
    shape_bounds, _sprites, _exports = parse_swf_xml(WEB_SWF_XML)
    (entry,) = [e for e in placements.values() if e.get("cid") == MASK_SHAPE]
    xmin, ymin, xmax, ymax = transform_rect(entry["mat"], shape_bounds[MASK_SHAPE])
    return xmin / 20, ymin / 20, xmax / 20, ymax / 20


def depth_of(placements: dict, character: int) -> int:
    (depth,) = [d for d, e in placements.items() if e.get("cid") == character]
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
    x0, y0, x1, y1 = (round(v * ZOOM) for v in box)
    inside[y0:y1, x0:x1] = True
    mask = drawn & inside
    difference = np.abs(
        np.asarray(canvas.convert("RGB"), dtype=np.int16)
        - np.asarray(reference.convert("RGB"), dtype=np.int16)
    ).max(axis=2)[mask]
    return int(mask.sum()), float(np.percentile(difference, 99))


def main():
    wrong_hall = "--wrong-hall" in sys.argv[1:]
    xml = WEB_SWF_XML.read_text()
    frame, placements = root_placements(xml, FRAME_LABEL)
    box = mask_box(xml, placements)
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

    work = Path(tempfile.mkdtemp(prefix="verify_battle_lib_"))
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
                "hide_characters": [FIGHTER_RIG, MEMBER_BARS],
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
