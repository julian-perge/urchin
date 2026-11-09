#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["numpy", "pillow"]
# ///
"""How much each filter changes each screen, and how much mipmaps add on top of LINEAR."""
from pathlib import Path
import numpy as np
from PIL import Image

T = Path.home() / "tmp/2026-11-09-urchin-filter/cap"
FRAME = {"battle": 120, "hub": 60, "inv": 40, "store": 40, "abil": 40, "title": 30}


def load(label, scene):
    p = T / label / f"{scene}_f{FRAME[scene]:04d}.png"
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.int16)


def line(a, b):
    d = np.abs(a - b).max(axis=2)
    c = d > 0
    s = f"{c.mean():6.2%}"
    if c.any():
        s += f"  p50 {np.percentile(d[c], 50):3.0f} p90 {np.percentile(d[c], 90):3.0f} p99 {np.percentile(d[c], 99):3.0f}  over24 {(d > 24).mean():6.2%}"
    return s


print(f"{'scene':7} {'window':4} {'NEAREST vs LINEAR':48} {'LINEAR vs LINEAR+MIP':48}")
for scene in FRAME:
    for tag in ("1x", "2x"):
        n, l, m = (load(f"{f}_{tag}", scene) for f in ("nearest", "linear", "mip"))
        print(f"{scene:7} {tag:4} {line(n, l):48} {line(l, m):48}")
for res in ("1200x900", "2400x1800", "3200x2400"):
    n, l, m = (load(f"{f}_{res}", "battle") for f in ("nearest", "linear", "mip"))
    print(f"battle  {res:9} {line(n, l):48} {line(l, m):48}")
