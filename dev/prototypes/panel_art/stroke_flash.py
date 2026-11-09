#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["pillow", "numpy"]
# ///
# Measures the right and bottom stroke of each panel in the big real Flash
# captures, whose stage is stretched to the whole 4112x2658 window.
from __future__ import annotations

import numpy as np
from PIL import Image

R = "/Users/sweetjp/Documents/godot/urchin/.claude/worktrees/gracious-chaplygin-3ca51d/references/"
SX = 4112 / 800
SY = 2658 / 575
PANELS = {
    "sonny2_achievements_screen": [
        ("ach 2989 s2.614x1.123", (74.96, 82.41, 651.11, 299.94), 2.614, 1.123)
    ],
    "sonny2_options_screen": [
        ("options 2989 s2.614x1.123", (74.96, 82.41, 651.11, 299.94), 2.614, 1.123)
    ],
    "sonny2_inventory_screen": [
        ("left 2989 1x1", (47.50, 86.60, 249.05, 267.15), 1, 1),
        ("bar 2991 1x1", (47.50, 358.20, 249.05, 50.85), 1, 1),
        ("centre 2987 1x1", (308.95, 82.15, 183.05, 326.50), 1, 1),
        ("right 2989 1x1", (503.5, 81.6, 249.05, 267.15), 1, 1),
        ("bar R 2991", (503.5, 358.2, 249.05, 50.85), 1, 1),
    ],
    "sonny2_abilities_screen": [
        ("left 2989 1x1.296", (44.94, 73.43, 249.08, 346.10), 1, 1.296),
        ("right 2989 1x1.296", (506.32, 73.43, 249.10, 346.10), 1, 1.296),
        ("centre top 2987 1.041x0.662", (304.21, 74.15, 190.62, 216.31), 1.041, 0.662),
        (
            "centre bottom 2987 1.041x0.357",
            (304.21, 302.20, 190.62, 116.56),
            1.041,
            0.357,
        ),
    ],
}


def crossings(profile, inner, outer):
    # profile runs from inside the fill out past the stroke; darkness is relative to each neighbour
    n = len(profile)
    m = int(np.argmin(profile))

    # inner edge: half way between inner level and 0, going from m towards start
    def cross(arr, level):
        for i in range(len(arr) - 1):
            a, b = arr[i], arr[i + 1]
            if a < level <= b or a <= level < b:
                return i + (level - a) / (b - a)
        return None

    left = profile[: m + 1][::-1]
    right = profile[m:]
    i1 = cross(left, inner / 2)
    i2 = cross(right, outer / 2)
    if i1 is None or i2 is None:
        return None
    return (m - i1, m + i2)


for name, items in PANELS.items():
    a = np.asarray(Image.open(R + name + ".png").convert("RGB")).astype(float)
    print(name)
    for label, (x, y, w, h), sx, sy in items:
        xr = (x + w) * SX
        yb = (y + h) * SY
        xres = []
        yres = []
        for frac in np.linspace(0.2, 0.8, 13):
            row = int(round((y + h * frac) * SY))
            x0 = int(xr - 14 * SX)
            x1 = int(xr + 6 * SX)
            p = a[row, x0:x1, 0]
            inner = np.median(p[: int(4 * SX)])
            outer = np.median(p[-int(2 * SX) :])
            c = crossings(p, inner, outer)
            if c:
                xres.append(((c[1] - c[0]), x0 + c[0], x0 + c[1], inner, outer))
            col = int(round((x + w * frac) * SX))
            y0 = int(yb - 14 * SY)
            y1 = int(yb + 6 * SY)
            p = a[y0:y1, col, 0]
            inner = np.median(p[: int(4 * SY)])
            outer = np.median(p[-int(2 * SY) :])
            c = crossings(p, inner, outer)
            if c:
                yres.append(((c[1] - c[0]), y0 + c[0], y0 + c[1], inner, outer))
        tx = np.median([r[0] for r in xres]) if xres else float("nan")
        ty = np.median([r[0] for r in yres]) if yres else float("nan")
        cxr = np.median([r[1] for r in xres]) / SX if xres else float("nan")
        cxo = np.median([r[2] for r in xres]) / SX if xres else float("nan")
        cyr = np.median([r[1] for r in yres]) / SY if yres else float("nan")
        cyo = np.median([r[2] for r in yres]) / SY if yres else float("nan")
        print(
            f"  {label:34s} right stroke {tx:6.2f} dev = {tx / SX:5.2f} design (sx {sx:.3f}) [{cxr:.2f}..{cxo:.2f}, swf outer {x + w:.2f}]   bottom {ty:6.2f} dev = {ty / SY:5.2f} design (sy {sy:.3f}) [{cyr:.2f}..{cyo:.2f}, swf outer {y + h:.2f}]"
        )
