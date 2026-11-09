#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["numpy", "pillow"]
# ///
"""Scores Godot's hall and sky at their SWF rects against ffdec at the window's zoom, for all 12 pairs and each filter."""
import json
import math
from pathlib import Path
import numpy as np
from PIL import Image

T = Path.home() / "tmp/2026-11-09-urchin-filter"
W = Path("/Users/sweetjp/Documents/godot/urchin/.claude/worktrees/admiring-davinci-f28a5d")
data = json.loads((T / "halls/ref/pairs.json").read_text())
pairs = data["pairs"]
box = data["box"]


def opaque_4x(hall, sky):
    canvas = np.zeros((575 * 4, 800 * 4), dtype=bool)
    for folder, prefix, family, label in (("sky", "SKY_", "skies", sky), ("battle", "", "halls", hall)):
        name = label.replace(" ", "_")
        rect = data[family][name]
        art = np.asarray(Image.open(W / f"assets/backgrounds/{folder}/{prefix}{name}.png").convert("RGBA"))[:, :, 3] == 255
        x, y = round(rect["x"] * 4), round(rect["y"] * 4)
        sx0, sy0 = max(-x, 0), max(-y, 0)
        dx0, dy0 = max(x, 0), max(y, 0)
        h = min(art.shape[0] - sy0, canvas.shape[0] - dy0)
        w = min(art.shape[1] - sx0, canvas.shape[1] - dx0)
        canvas[dy0:dy0 + h, dx0:dx0 + w] |= art[sy0:sy0 + h, sx0:sx0 + w]
    return canvas


def window_mask(hall, sky, zoom):
    op = opaque_4x(hall, sky)
    if zoom in (1, 2, 4):
        f = int(4 / zoom)
        h, w = op.shape[0] // f, op.shape[1] // f
        small = op[: h * f, : w * f].reshape(h, f, w, f).all(axis=(1, 3))
    else:
        im = Image.fromarray(op.astype(np.uint8) * 255).resize((int(800 * zoom), int(575 * zoom)), Image.Resampling.BOX)
        small = np.asarray(im) == 255
    inside = np.zeros_like(small)
    x0, y0 = (math.ceil(v * zoom) for v in box[:2])
    x1, y1 = (math.floor(v * zoom) for v in box[2:])
    inside[y0:y1, x0:x1] = True
    return small & inside


def score(shot, ref, mask):
    d = np.abs(shot - ref).max(axis=2)[mask]
    return d


def run(tag, zoom):
    print(f"\n== window {tag} (zoom {zoom}) against ffdec at the same zoom, all pairs pooled")
    print(f"{'filter':8} {'p50':>4} {'p90':>4} {'p99':>4} {'mean':>6}   per-pair p99 min..max   per-pair mean min..max")
    refs = []
    masks = []
    for n, (hall, sky) in enumerate(pairs):
        refs.append(np.asarray(Image.open(T / f"halls/ref/z{zoom}_{n:02d}.png").convert("RGB"), dtype=np.int16))
        masks.append(window_mask(hall, sky, zoom))
    for filter_name in ("nearest", "linear", "mip"):
        pooled = []
        p99s, means = [], []
        for n in range(len(pairs)):
            shot = np.asarray(Image.open(T / f"halls/{filter_name}_{tag}/h_{n:02d}.png").convert("RGB"), dtype=np.int16)[: refs[n].shape[0]]
            d = score(shot, refs[n], masks[n])
            pooled.append(d)
            p99s.append(np.percentile(d, 99))
            means.append(d.mean())
        all_d = np.concatenate(pooled)
        print(f"{filter_name:8} {np.percentile(all_d, 50):4.0f} {np.percentile(all_d, 90):4.0f} {np.percentile(all_d, 99):4.0f} {all_d.mean():6.2f}   {min(p99s):4.0f}..{max(p99s):<4.0f}              {min(means):5.2f}..{max(means):<5.2f}")
    # What a perfect resample of ffdec's own 4x render would score, and the check that a shifted capture scores worse.
    if zoom in (1, 2):
        f = 4 / zoom
        pooled = []
        for n in range(len(pairs)):
            big = Image.open(T / f"halls/ref/z4_{n:02d}.png").convert("RGB")
            small = np.asarray(big.resize((int(800 * zoom), int(575 * zoom)), Image.Resampling.BOX), dtype=np.int16)
            pooled.append(score(small, refs[n], masks[n]))
        all_d = np.concatenate(pooled)
        print(f"{'floor':8} {np.percentile(all_d, 50):4.0f} {np.percentile(all_d, 90):4.0f} {np.percentile(all_d, 99):4.0f} {all_d.mean():6.2f}   (ffdec 4x box-shrunk to this zoom, against ffdec at this zoom)")
    pooled = []
    for n in range(len(pairs)):
        shot = np.asarray(Image.open(T / f"halls/nearest_{tag}/h_{n:02d}.png").convert("RGB"), dtype=np.int16)[: refs[n].shape[0]]
        pooled.append(score(np.roll(shot, 3, axis=1), refs[n], masks[n]))
    all_d = np.concatenate(pooled)
    print(f"{'shift3px':8} {np.percentile(all_d, 50):4.0f} {np.percentile(all_d, 90):4.0f} {np.percentile(all_d, 99):4.0f} {all_d.mean():6.2f}   (NEAREST moved 3 window px, has to be worse)")


for tag, zoom in (("1x", 1), ("2x", 2), ("4x", 4)):
    run(tag, zoom)
