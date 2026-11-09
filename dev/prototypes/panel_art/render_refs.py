#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["pillow"]
# ///
# Renders each label's backdrop and panels as ffdec draws them at zoom 2, and
# the three bare panel shapes at zoom 2 and 4, for the variant harness.
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, "/Users/sweetjp/tmp/2026-11-09-panel-art")
import shape_records as sr
from PIL import Image
from urchin_dev import WEB_SWF
from urchin_dev.swf import render, strip, timeline

HERE = Path("/Users/sweetjp/tmp/2026-11-09-panel-art")
OUT = HERE / "refs"
OUT.mkdir(exist_ok=True)
ART = HERE / "art"
ART.mkdir(exist_ok=True)
data = json.load(open(HERE / "labels.json"))
ORIGIN = tuple(data["origin"])
idx = sr.load()
KRINMENU = 3142
STAGE = (800, 600)
jobs = {}
for label, info in data["labels"].items():
    layers = timeline.frames(idx, KRINMENU)[info["frame"] - 1]
    keep = {2994} | {p["sprite"] for p in info["panels"]}
    others = {
        l.character_id: f"depth {d} of {label}"
        for d, l in sorted(layers.items())
        if l.character_id not in keep and l.clip_depth is None
    }
    jobs[label] = render.Job(
        KRINMENU,
        info["frame"],
        2.0,
        ORIGIN,
        strip=tuple(strip.strip_list(WEB_SWF, others)),
    )
art_jobs = {}
for sprite in (2990, 2992, 2988):
    for z in (2.0, 4.0):
        art_jobs[(sprite, z)] = render.Job(sprite, 1, z, (0.0, 0.0))
all_jobs = list(jobs.values()) + list(art_jobs.values())
meta = {}
with render.frames(WEB_SWF, all_jobs) as rendered:
    n = len(jobs)
    for (label, job), frame in zip(jobs.items(), rendered[:n], strict=True):
        cut = render.trim(frame)
        canvas = Image.new("RGBA", (STAGE[0] * 2, STAGE[1] * 2), (0, 0, 0, 0))
        at = (round(cut.rect[0] * 2), round(cut.rect[1] * 2))
        canvas.alpha_composite(cut.image, at)
        canvas.save(OUT / f"{label}.png")
        meta[label] = {"rect": [round(v, 3) for v in cut.rect], "at": at}
        print(label, cut.rect)
    for (key, job), frame in zip(art_jobs.items(), rendered[n:], strict=True):
        sprite, z = key
        cut = render.trim(frame)
        cut.image.save(ART / f"{sprite}_z{int(z)}.png")
        s = sr.parse(idx, {2990: 2989, 2992: 2991, 2988: 2987}[sprite])
        meta[f"{sprite}_z{int(z)}"] = {
            "rect": [round(v, 3) for v in cut.rect],
            "bounds": s.bounds,
            "zoom": z,
        }
        print(sprite, z, cut.image.size, cut.rect, s.bounds)
json.dump(meta, open(HERE / "art.json", "w"), indent=1)
