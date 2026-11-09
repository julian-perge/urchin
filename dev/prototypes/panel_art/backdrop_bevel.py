#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["pillow", "numpy"]
# ///
# Renders the hub frame with only KRINMENU's backdrop visible, so the sprite's
# own Bevel, Glow and DropShadow are drawn, and scores that against real Flash
# on the backdrop's rim next to today's plain backdrop art.
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, "/Users/sweetjp/tmp/2026-11-09-panel-art")
import shape_records as sr
from urchin_dev import WEB_SWF
from urchin_dev.swf import ffdec_lib, render, timeline

HERE = Path("/Users/sweetjp/tmp/2026-11-09-panel-art")
idx = sr.load()
KM = 3142
NAV = timeline.frame_of(idx, 0, "Navigation")
root_layers = timeline.frames(idx, 0)[NAV - 1]
km_depth = next(d for d, l in root_layers.items() if l.character_id == KM)
print("KRINMENU root depth", km_depth, "nav frame", NAV)
frames = timeline.frames(idx, KM)
placed_depths = sorted(
    {d for f in frames for d, l in f.items() if l.clip_depth is None}
)
masks = sorted({d for f in frames for d, l in f.items() if l.clip_depth is not None})
print("mask depths in KRINMENU", masks)
hide = [{"owner": KM, "depth": d} for d in placed_depths if d != 2]
with tempfile.TemporaryDirectory(prefix="bevel_") as tmp:
    out = str(Path(tmp) / "a.png")
    job = {
        "timeline": 0,
        "frame": NAV,
        "zoom": 2.0,
        "out": out,
        "background": "none",
        "only_depths": [km_depth],
        "hide_depths": hide,
    }
    res = ffdec_lib.render(WEB_SWF, [job])[0]
    frame = render.Frame(
        job=render.Job(0, NAV, 2.0, (0.0, 0.0)),
        path=Path(res["out"]),
        size=(res["width"], res["height"]),
        canvas_rect=(res["xmin"], res["ymin"], res["xmax"], res["ymax"]),
        display_rect=tuple(res["display"]),
    )
    render.check_canvas(frame)
    cut = render.trim(frame)
    print("trimmed rect", [round(v, 3) for v in cut.rect], "size", cut.image.size)
    cut.image.save(HERE / "art" / "backdrop_filtered_z2.png")
    json.dump(
        {"rect": list(cut.rect)}, open(HERE / "art" / "backdrop_filtered_z2.json", "w")
    )
