#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["numpy", "pillow"]
# ///
"""Checks the capture controls, then tabulates the texture scan and the per-scene filter differences."""
from collections import defaultdict
from pathlib import Path
import csv
import re
import numpy as np
from PIL import Image

T = Path.home() / "tmp/2026-11-09-urchin-filter/cap"
FRAME = {"battle": 120, "hub": 60, "inv": 40, "store": 40, "abil": 40, "title": 30}


def load(label, scene):
    p = T / label / f"{scene}_f{FRAME[scene]:04d}.png"
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.int16)


bad = 0
for log in sorted(T.glob("*/*.log")):
    text = log.read_text(errors="replace")
    if re.search(r"SCRIPT ERROR|Parse Error", text):
        print("ERROR in", log)
        bad += 1
    if "stretch" not in text and log.parent.name:
        print("no capture line in", log)
        bad += 1
print("logs checked, problems:", bad)


def compare(a, b):
    d = np.abs(a - b).max(axis=2)
    return int((d > 0).sum()), d.size, d


for pair in (("nearest_2x", "nearest_2x_repeat"), ("linear_2x", "linear_2x_clone")):
    changed, total, _ = compare(load(pair[0], "battle"), load(pair[1], "battle"))
    print(f"control {pair[0]} vs {pair[1]}: {changed} of {total} differ")

print("\n== texture scan, 2x window: texels per window px (1.00 = 1:1, 2.00 = minified 2:1, 0.50 = magnified)")
rows = defaultdict(list)
for scene in FRAME:
    path = T / "nearest_2x" / f"{scene}_scan.tsv"
    with open(path, newline="") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            key = (row["family"].replace("res://", ""))
            rows[(scene, key)].append(row)
print(f"{'scene':7} {'family':34} {'count':>5} {'texels/winpx x p50 (min..max)':>30} {'rotated':>7} {'frac origin':>11}")
for (scene, family), items in sorted(rows.items()):
    tx = np.array([float(r["texels_per_window_px_x"]) for r in items])
    ty = np.array([float(r["texels_per_window_px_y"]) for r in items])
    rotated = sum(r["rotated"] == "true" for r in items)
    frac = sum(0.001 < float(r["frac_x"]) < 0.999 or 0.001 < float(r["frac_y"]) < 0.999 for r in items)
    print(f"{scene:7} {family:34} {len(items):5d} {np.median(tx):8.2f} ({tx.min():.2f}..{tx.max():.2f}) y {np.median(ty):.2f} ({ty.min():.2f}..{ty.max():.2f}) {rotated:>4} {frac:>6}")
