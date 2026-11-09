"""Renders every hall and sky pair the battles use through ffdec at zoom 1, 2 and 4, the way verify_battle_screen.py does."""
import json
import sys
from pathlib import Path

from urchin_dev import WEB_SWF
from urchin_dev.swf import strip, timeline
from urchin_dev.swf.extract.battle_screen import BATTLE_STRIP, FRAME_LABEL, HALL_SPRITE, LAYOUT_JSON, SKY_SPRITE
from urchin_dev.swf.extract.verify_battle_screen import MASK_SHAPE, battle_pairs, depth_of, mask_box
from urchin_dev.swf.ffdec_lib import render
from urchin_dev.swf.swf_index import read_swf

out = Path.home() / "tmp/2026-11-09-urchin-filter/halls/ref"
index = read_swf(WEB_SWF)
frame = timeline.frame_of(index, 0, FRAME_LABEL)
placements = timeline.frames(index, 0)[frame - 1]
box = mask_box(index, placements)
sky_depth = depth_of(placements, SKY_SPRITE)
hall_depth = depth_of(placements, HALL_SPRITE)
keep = [depth_of(placements, MASK_SHAPE), sky_depth, hall_depth]
stripped = strip.strip_list(WEB_SWF, BATTLE_STRIP)
pairs = battle_pairs()
jobs = []
for zoom in (1.5, 3.0):
    for n, (hall, sky) in enumerate(pairs):
        jobs.append({
            "timeline": 0, "frame": frame, "zoom": zoom, "out": str(out / f"z{zoom:g}_{n:02d}.png"),
            "background": "swf", "only_depths": keep, "strip_characters": stripped,
            "goto": [{"depth": hall_depth, "label": hall}, {"depth": sky_depth, "label": sky}],
        })
results = render(WEB_SWF, jobs)
layout = json.loads(LAYOUT_JSON.read_text())
Path("/dev/null").write_text(json.dumps({
    "pairs": pairs, "box": box,
    "halls": {h.replace(" ", "_"): layout["halls"][h.replace(" ", "_")] for h, _ in pairs},
    "skies": {s.replace(" ", "_"): layout["skies"][s.replace(" ", "_")] for _, s in pairs},
    "seconds": sum(r["seconds"] for r in results),
}, indent=1))
print(len(results), "renders,", len(pairs), "pairs, box", box, file=sys.stderr)
