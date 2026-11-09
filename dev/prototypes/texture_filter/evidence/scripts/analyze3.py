#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["numpy"]
# ///
"""Texels per window pixel for every visible texture family at a 2x window, with snapping off."""
from collections import defaultdict
from pathlib import Path
import csv
import numpy as np

T = Path.home() / "tmp/2026-11-09-urchin-filter/cap/scan2"
rows = defaultdict(list)
for path in sorted(T.glob("*_scan.tsv")):
    scene = path.name.split("_")[0]
    with open(path, newline="") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            fam = row["family"].replace("res://", "")
            rows[(scene, fam)].append(row)
print(f"{'scene':7} {'family':30} {'n':>3}  {'texels/winpx p50 (min..max)':30}   rotated  frac-origin")
for (scene, family), items in sorted(rows.items()):
    tx = np.array([float(r["texels_per_window_px_x"]) for r in items])
    ty = np.array([float(r["texels_per_window_px_y"]) for r in items])
    rot = sum(r["rotated"] == "true" for r in items)
    frac = sum(0.01 < float(r["frac_x"]) < 0.99 or 0.01 < float(r["frac_y"]) < 0.99 for r in items)
    print(f"{scene:7} {family:30} {len(items):3d}  x {np.median(tx):5.2f} ({tx.min():.2f}..{tx.max():.2f})  y {np.median(ty):5.2f} ({ty.min():.2f}..{ty.max():.2f})  {rot:4d} {frac:5d}")
