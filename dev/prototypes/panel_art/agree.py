#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["pillow", "numpy"]
# ///
# Counts the right and bottom panel edges where a Godot variant's stroke lands
# on the same device pixels as real Flash, and prints the width each drew.
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


def rgba(p):
    return np.asarray(Image.open(p).convert("RGBA"), dtype=np.float64)


def half_cross(arr, level):
    for i in range(len(arr) - 1):
        a, b = arr[i], arr[i + 1]
        if (a < level <= b) or (a <= level < b):
            return i + (level - a) / (b - a)
    return None


def measure(profile):
    n = len(profile)
    m = int(np.argmin(profile))
    fill = np.median(profile[: max(3, n // 3)])
    out = np.median(profile[-max(3, n // 4) :])
    i1 = half_cross(profile[: m + 1][::-1], fill / 2)
    i2 = half_cross(profile[m:], out / 2)
    if i1 is None or i2 is None:
        return None
    return (m - i1, m + i2)


def edges(a, panel, sx, sy):
    x, y, w, h = panel["rect"]
    out = {}
    r = []
    b = []
    for fr in np.linspace(0.3, 0.7, 9):
        row = int(round((y + h * fr) * sy))
        x0 = int(np.floor((x + w - 8) * sx))
        x1 = int(np.ceil((x + w + 3) * sx))
        m = measure(a[row, x0:x1, 0])
        if m:
            r.append((m[0] + x0, m[1] + x0))
        col = int(round((x + w * fr) * sx))
        y0 = int(np.floor((y + h - 8) * sy))
        y1 = int(np.ceil((y + h + 3) * sy))
        m = measure(a[y0:y1, col, 0])
        if m:
            b.append((m[0] + y0, m[1] + y0))
    return (
        float(np.median([v[0] for v in r])),
        float(np.median([v[1] for v in r])),
        float(np.median([v[0] for v in b])),
        float(np.median([v[1] for v in b])),
    )


def compare(tag, real, label, sx, sy, shots, tol):
    print("##", tag)
    panels = data[label]["panels"]
    real_e = [edges(real, p, sx, sy) for p in panels]
    print(
        "  real device-pixel strokes [right inner,outer / bottom inner,outer]:",
        [tuple(round(v, 2) for v in e) for e in real_e],
    )
    for v, a in shots.items():
        count = 0
        total = 0
        widths = []
        es = [edges(a, p, sx, sy) for p in panels]
        for ee, rr in zip(es, real_e):
            for i in (0, 2):
                total += 1
                good = abs(ee[i] - rr[i]) <= tol and abs(ee[i + 1] - rr[i + 1]) <= tol
                count += good
                widths.append(round(ee[i + 1] - ee[i], 2))
        print(
            f"  {v:18s} edges matching within {tol} device px: {count}/{total}  widths {widths}"
        )


VS = ["flat_axis", "flat_mean", "flat_mean_brect", "custom", "art2", "art4"]
win = rgba(
    REF
    / "2026_07_18_flashpoint/16_after_battle_victory_screen_Screenshot 2026-07-18 at 18.16.01.png"
)[64:]
compare(
    "victory, real Flash 2x window (device px)",
    win,
    "win",
    2,
    2,
    {v: rgba(HERE / "out2x" / f"win__{v}.png") for v in VS},
    0.51,
)
shop = rgba(
    REF
    / "2026_07_18_flashpoint/zone1_itemshop_menu_Screenshot 2026-07-18 at 18.38.33.png"
)
real = np.zeros((600, 800, 4))
h = min(600, shop.shape[0] - 27)
w = min(799, shop.shape[1])
real[:h, 1 : w + 1] = shop[27 : 27 + h, :w]
compare(
    "store, real Flash 1x window",
    real,
    "shop",
    1,
    1,
    {v: rgba(HERE / "out1x" / f"shop__{v}.png") for v in VS},
    0.51,
)
for label, name in {
    "inventory": "sonny2_inventory_screen",
    "skills": "sonny2_abilities_screen",
    "options": "sonny2_options_screen",
}.items():
    a = rgba(REF / f"{name}.png")
    compare(
        f"{label}, real Flash at x5.14 y4.62",
        a,
        label,
        4112 / 800,
        2658 / 575,
        {
            v: rgba(HERE / "outbig" / f"{label}__{v}.png")
            for v in VS
            if v != "flat_mean_brect"
        },
        1.01,
    )
