#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["pillow", "numpy"]
# ///
# For every panel, measures the right and bottom stroke in the ffdec 2x render
# and real Flash captures, and prints where each model puts the stroke.
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path("/Users/sweetjp/tmp/2026-11-09-panel-art")
REF = Path(
    "/Users/sweetjp/Documents/godot/urchin/.claude/worktrees/gracious-chaplygin-3ca51d/references"
)
data = json.load(open(HERE / "labels.json"))["labels"]


def rgb(p):
    return np.asarray(Image.open(p).convert("RGBA"), dtype=np.float64)


def half_cross(arr, level):
    for i in range(len(arr) - 1):
        a, b = arr[i], arr[i + 1]
        if (a < level <= b) or (a <= level < b):
            return i + (level - a) / (b - a)
    return None


def measure(profile):
    """profile runs across the stroke from the fill to outside. -> (inner, outer) in samples."""
    n = len(profile)
    m = int(np.argmin(profile))
    fill = np.median(profile[: max(3, n // 3)])
    out = np.median(profile[-max(3, n // 4) :])
    i1 = half_cross(profile[: m + 1][::-1], fill / 2)
    i2 = half_cross(profile[m:], out / 2)
    if i1 is None or i2 is None:
        return None
    return (m - i1, m + i2)


def edge(a, x, y, w, h, sx, sy, fracs, span_in, span_out):
    # right edge: scan x across x+w
    right = []
    bottom = []
    for fr in fracs:
        row = int(round((y + h * fr) * sy))
        x0 = int(np.floor((x + w - span_in) * sx))
        x1 = int(np.ceil((x + w + span_out) * sx))
        prof = a[row, x0:x1, 0]
        r = measure(prof)
        if r:
            right.append(((r[0] + x0 + 0.5) / sx, (r[1] + x0 + 0.5) / sx))
        col = int(round((x + w * fr) * sx))
        y0 = int(np.floor((y + h - span_in) * sy))
        y1 = int(np.ceil((y + h + span_out) * sy))
        prof = a[y0:y1, col, 0]
        r = measure(prof)
        if r:
            bottom.append(((r[0] + y0 + 0.5) / sy, (r[1] + y0 + 0.5) / sy))
    med = lambda L, i: float(np.median([v[i] for v in L])) if L else float("nan")
    return med(right, 0), med(right, 1), med(bottom, 0), med(bottom, 1)


print(
    "panel                   model: bounds rect edge | fill+-stroke/2 edge || measured right [inner outer] width | measured bottom [inner outer] width"
)


def report(tag, a, panels, sx, sy):
    print("---", tag)
    for p in panels:
        x, y, w, h = p["rect"]
        fx, fy, fw, fh = p["fill_rect"]
        st = p["stroke"]
        ri, ro, bi, bo = edge(a, x, y, w, h, sx, sy, np.linspace(0.3, 0.7, 9), 8, 3)
        print(
            f" {p['sprite']} s({p['sx']:.3f},{p['sy']:.3f}) stroke {st:.2f} | right bounds {x + w:.2f} fill+s/2 {fx + fw + st / 2:.2f} -> [{ri:.2f} {ro:.2f}] w {ro - ri:.2f} | bottom bounds {y + h:.2f} fill+s/2 {fy + fh + st / 2:.2f} -> [{bi:.2f} {bo:.2f}] w {bo - bi:.2f}"
        )


for label in ("inventory", "win", "shop", "skills", "options"):
    report(
        f"ffdec 2x {label}",
        rgb(HERE / "refs" / f"{label}.png"),
        data[label]["panels"],
        2,
        2,
    )
report(
    "real Flash big inventory",
    rgb(REF / "sonny2_inventory_screen.png"),
    data["inventory"]["panels"],
    4112 / 800,
    2658 / 575,
)
report(
    "real Flash big skills",
    rgb(REF / "sonny2_abilities_screen.png"),
    data["skills"]["panels"],
    4112 / 800,
    2658 / 575,
)
report(
    "real Flash big options",
    rgb(REF / "sonny2_options_screen.png"),
    data["options"]["panels"],
    4112 / 800,
    2658 / 575,
)
# victory real 2x: title bar 64 px
victory = rgb(
    REF
    / "2026_07_18_flashpoint/16_after_battle_victory_screen_Screenshot 2026-07-18 at 18.16.01.png"
)[64:]
report("real Flash 2x win", victory, data["win"]["panels"], 2, 2)
shop = rgb(
    REF
    / "2026_07_18_flashpoint/zone1_itemshop_menu_Screenshot 2026-07-18 at 18.38.33.png"
)
# 1x store: alignment dx=-1, dy=+27 means real[y+27,x-1]=shot[y,x]; shift so real[y,x]=shot
shifted = np.zeros((600, 800, 4))
h = min(600, shop.shape[0] - 27)
w = min(799, shop.shape[1])
shifted[:h, 1 : w + 1] = shop[27 : 27 + h, :w]
report("real Flash 1x shop", shifted, data["shop"]["panels"], 1, 1)
