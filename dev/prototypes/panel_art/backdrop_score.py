#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["pillow", "numpy"]
# ///
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path("/Users/sweetjp/tmp/2026-11-09-panel-art")
REF = Path(
    "/Users/sweetjp/Documents/godot/urchin/.claude/worktrees/gracious-chaplygin-3ca51d/references"
)
PROTO = Path(
    "/Users/sweetjp/tmp/2026-11-09-inner-shadow/proto/dev/prototypes/victory_containers"
)
real = np.asarray(
    Image.open(
        REF
        / "2026_07_18_flashpoint/16_after_battle_victory_screen_Screenshot 2026-07-18 at 18.16.01.png"
    ).convert("RGB"),
    dtype=np.int16,
)[64:]
W, H = 1600, 1150


def stage(path, rect):
    c = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    im = Image.open(path).convert("RGBA")
    c.alpha_composite(im, (round(rect[0] * 2), round(rect[1] * 2)))
    return np.asarray(c, dtype=np.int16)


art = json.load(open(PROTO / "art.json"))["backdrop"]
plain = stage(PROTO / "images/art/backdrop.png", art["rect"])
meta = json.load(open(HERE / "art/backdrop_filtered_z2.json"))
filt = stage(HERE / "art/backdrop_filtered_z2.png", meta["rect"])
# rim band, 2x px: backdrop rect (14.15,15)-(782.7,440.1)
x0, y0, x1, y1 = [round(v * 2) for v in (14.15, 15.0, 782.7, 440.1)]
m = np.zeros((H, W), bool)
band = 20
m[y0:y1, x0 : x0 + band] = True
m[y0 : y0 + band, x0:x1] = True
m[y0:y1, x1 - band : x1] = True
m[y1 - band : y1, x0:x1] = True
# keep only pixels opaque in both renders
mask = m & (plain[:, :, 3] == 255) & (filt[:, :, 3] == 255)


def stat(v):
    return f"p50 {np.percentile(v, 50):.0f} p90 {np.percentile(v, 90):.0f} p99 {np.percentile(v, 99):.0f} mean {v.mean():.2f}"


for name, im in (
    ("plain backdrop (today's art)", plain),
    ("with KRINMENU filters", filt),
):
    d = np.abs(im[:, :, :3] - real[:H]).max(axis=2)
    print(f"{name:32s} {stat(d[mask])}")
print("n px", int(mask.sum()))
row = 500
print("real  row 500 x 20..60", real[row, 20:60, 0].tolist())
print("filt  row 500 x 20..60", filt[row, 20:60, 0].tolist())
print("plain row 500 x 20..60", plain[row, 20:60, 0].tolist())
