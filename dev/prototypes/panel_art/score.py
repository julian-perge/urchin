#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["pillow", "numpy"]
# ///
# Scores each label's Godot capture against ffdec at 2x and against the real
# Flash captures. Lower is better: largest channel difference, p50 / p90 / p99.
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
VARIANTS = ["flat_axis", "flat_mean", "flat_mean_brect", "custom", "art2", "art4"]


def rgb(p):
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.int16)


def rgba(p):
    return np.asarray(Image.open(p).convert("RGBA"), dtype=np.int16)


def outer(p):
    # true outer rect: fill rect grown by half the stroke Flash draws
    x, y, w, h = p["fill_rect"]
    s = p["stroke"] / 2
    return x - s, y - s, w + 2 * s, h + 2 * s


def ring_mask(shape, panels, sx, sy, out_px, in_px):
    H, W = shape
    m = np.zeros((H, W), bool)
    for p in panels:
        x, y, w, h = outer(p)
        x0, y0 = (x - out_px) * sx, (y - out_px) * sy
        x1, y1 = (x + w + out_px) * sx, (y + h + out_px) * sy
        ix0, iy0 = (x + in_px) * sx, (y + in_px) * sy
        ix1, iy1 = (x + w - in_px) * sx, (y + h - in_px) * sy
        a = np.zeros((H, W), bool)
        a[max(int(y0), 0) : int(np.ceil(y1)), max(int(x0), 0) : int(np.ceil(x1))] = True
        a[int(iy0) : int(np.ceil(iy1)), int(ix0) : int(np.ceil(ix1))] = False
        m |= a
    return m


def stat(v):
    return f"{np.percentile(v, 50):3.0f}/{np.percentile(v, 90):3.0f}/{np.percentile(v, 99):3.0f} {v.mean():5.2f}"


def diff(a, b):
    return np.abs(a - b).max(axis=2)


out = []


def p(s=""):
    print(s)
    out.append(s)


p(
    "== vs ffdec zoom 2 at a 2x window, stroke ring (2 px out, 4 px in), p50/p90/p99 mean"
)
hdr = "label      " + " ".join(f"{v:>18s}" for v in VARIANTS)
p(hdr)
totals = {v: [] for v in VARIANTS}
for label in data:
    ref = rgba(HERE / "refs" / f"{label}.png")
    m = ring_mask(ref.shape[:2], data[label]["panels"], 2, 2, 2, 4) & (
        ref[:, :, 3] == 255
    )
    cells = []
    for v in VARIANTS:
        shot = rgb(HERE / "out2x" / f"{label}__{v}.png")
        d = diff(shot, ref[:, :, :3])[m]
        totals[v].append(d)
        cells.append(f"{stat(d):>18s}")
    p(f"{label:10s} " + " ".join(cells))
p("ALL        " + " ".join(f"{stat(np.concatenate(totals[v])):>18s}" for v in VARIANTS))
p()
p(
    "== vs real Flash at the capture's stretch (x 5.14, y 4.6226), stroke ring (2 px out, 4 px in)"
)
p(hdr.replace("label", "label"))
big = {
    "inventory": "sonny2_inventory_screen",
    "skills": "sonny2_abilities_screen",
    "options": "sonny2_options_screen",
    "ach": "sonny2_achievements_screen",
}
SX = 4112 / 800
SY = 2658 / 575
totals = {v: [] for v in VARIANTS if v != "flat_mean_brect"}
for label, name in big.items():
    real = rgb(REF / f"{name}.png")
    m = ring_mask(real.shape[:2], data[label]["panels"], SX, SY, 2, 4)
    cells = []
    for v in VARIANTS:
        path = HERE / "outbig" / f"{label}__{v}.png"
        if not path.exists():
            cells.append(f"{'-':>18s}")
            continue
        d = diff(rgb(path), real)[m]
        totals[v].append(d)
        cells.append(f"{stat(d):>18s}")
    p(f"{label:10s} " + " ".join(cells))
p(
    "ALL        "
    + " ".join(
        f"{stat(np.concatenate(totals[v])) if v in totals else '-':>18s}"
        for v in VARIANTS
    )
)
p()
p("== vs real Flash, victory at 2x (title bar 64 px removed), stroke ring")
p(hdr)
real_full = rgb(
    REF
    / "2026_07_18_flashpoint/16_after_battle_victory_screen_Screenshot 2026-07-18 at 18.16.01.png"
)
real = np.zeros((1200, 1600, 3), np.int16)
h = min(1200, real_full.shape[0] - 64)
real[:h, :1600] = real_full[64 : 64 + h, :1600]
rmask = np.zeros((1200, 1600), bool)
rmask[:h, :1600] = True
m = ring_mask((1200, 1600), data["win"]["panels"], 2, 2, 2, 4) & rmask
cells = []
for v in VARIANTS:
    cells.append(f"{stat(diff(rgb(HERE / 'out2x' / f'win__{v}.png'), real)[m]):>18s}")
p("win        " + " ".join(cells))
p()
p("== vs real Flash, store at 1x, aligned by brute force, stroke ring")
real_shop = rgb(
    REF
    / "2026_07_18_flashpoint/zone1_itemshop_menu_Screenshot 2026-07-18 at 18.38.33.png"
)
shot0 = rgb(HERE / "out1x" / "shop__flat_mean.png")
best = None
mask0 = ring_mask(shot0.shape[:2], data["shop"]["panels"], 1, 1, 2, 4)
for dy in range(-10, 50):
    for dx in range(-6, 7):
        # real[y+dy, x+dx] corresponds to shot[y, x]
        ys, xs = np.where(mask0)
        yy = ys + dy
        xx = xs + dx
        keep = (
            (yy >= 0)
            & (yy < real_shop.shape[0])
            & (xx >= 0)
            & (xx < real_shop.shape[1])
        )
        d = (
            np.abs(shot0[ys[keep], xs[keep]] - real_shop[yy[keep], xx[keep]])
            .max(axis=1)
            .mean()
        )
        if best is None or d < best[0]:
            best = (d, dx, dy)
p(f"alignment dx {best[1]} dy {best[2]} (mean {best[0]:.2f})")
dx, dy = best[1], best[2]
p(hdr)
ys, xs = np.where(mask0)
yy = ys + dy
xx = xs + dx
keep = (yy >= 0) & (yy < real_shop.shape[0]) & (xx >= 0) & (xx < real_shop.shape[1])
ys, xs, yy, xx = ys[keep], xs[keep], yy[keep], xx[keep]
cells = []
for v in VARIANTS:
    s = rgb(HERE / "out1x" / f"shop__{v}.png")
    d = np.abs(s[ys, xs] - real_shop[yy, xx]).max(axis=1)
    cells.append(f"{stat(d):>18s}")
p("shop       " + " ".join(cells))
(HERE / "scores.txt").write_text("\n".join(out) + "\n")
