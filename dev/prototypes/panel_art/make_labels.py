#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
# Writes labels.json: every KRINMENU panel placement per label, with the true
# stroke width Flash and ffdec draw (one width from the matrix's mean scale).
from __future__ import annotations

import json
import math
import sys

sys.path.insert(0, "/Users/sweetjp/tmp/2026-11-09-panel-art")
import shape_records as sr
from urchin_dev.swf import timeline

idx = sr.load()
KRINMENU = 3142
PANEL_SPRITES = {2990, 2992, 2988}
ORIGIN = (400.5, 222.4)


def m_px(m):
    a, b, c, d, tx, ty = m
    return a, b, c, d, tx / 20.0, ty / 20.0


def compose(p, c):
    pa, pb, pc, pd, ptx, pty = p
    ca, cb, cc, cd, ctx, cty = c
    return (
        pa * ca + pc * cb,
        pb * ca + pd * cb,
        pa * cc + pc * cd,
        pb * cc + pd * cd,
        pa * ctx + pc * cty + ptx,
        pb * ctx + pd * cty + pty,
    )


root = (1.0, 0.0, 0.0, 1.0, *ORIGIN)


def stage(m, r):
    a, b, c, d, tx, ty = m
    return [tx + a * r[0], ty + d * r[1], a * (r[2] - r[0]), d * (r[3] - r[1])]


out = {}
for label in ["inventory", "win", "shop", "skills", "data", "options", "ach"]:
    f = timeline.frame_of(idx, KRINMENU, label)
    layers = timeline.frames(idx, KRINMENU)[f - 1]
    panels = []
    for depth, layer in sorted(layers.items()):
        if layer.character_id not in PANEL_SPRITES:
            continue
        child_layers = timeline.frames(idx, layer.character_id)[0]
        assert len(child_layers) == 1
        child = next(iter(child_layers.values()))
        m = compose(compose(root, m_px(layer.matrix)), m_px(child.matrix))
        s = sr.parse(idx, child.character_id)
        v = sr.classify(s)
        assert v.category == "flat-rect" and m[1] == 0 and m[2] == 0
        w = math.sqrt((m[0] ** 2 + m[3] ** 2) / 2) * v.line.width
        panels.append(
            {
                "depth": depth,
                "sprite": layer.character_id,
                "shape": child.character_id,
                "fill": sr.hexa(v.fill.color),
                "sx": round(m[0], 5),
                "sy": round(m[3], 5),
                "rect": [round(x, 3) for x in stage(m, s.bounds)],
                "fill_rect": [round(x, 3) for x in stage(m, v.fill_rect)],
                "stroke": round(w, 4),
            }
        )
    out[label] = {"frame": f, "panels": panels}
    print(label, f, len(panels), [p["stroke"] for p in panels])
back = next(
    l for d, l in timeline.frames(idx, KRINMENU)[0].items() if l.character_id == 2994
)
json.dump({"origin": ORIGIN, "labels": out}, open("labels.json", "w"), indent=1)
