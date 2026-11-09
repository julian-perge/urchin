#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["numpy", "pillow"]
# ///
"""Text softness at 8 fractional offsets under each root filter, on today's font and on TeX Gyre Heros."""
import re
from pathlib import Path
import numpy as np
from PIL import Image

T = Path.home() / "tmp/2026-11-09-urchin-filter/text"


def labels(log):
    out = []
    for line in log.read_text().splitlines():
        m = re.match(r"snapdriver: label (\d+) (\w+) ([\d.]+) y=([\d.]+)", line)
        if m:
            out.append((int(m[1]), m[2], float(m[3]), float(m[4])))
    return out


def stats(c):
    a = c.astype(float)
    ink = a.sum()
    dx = np.abs(np.diff(a, axis=1)).sum()
    dy = np.abs(np.diff(a, axis=0)).sum()
    mid = ((a > 40) & (a < 215)).sum()
    on = (a >= 40).sum()
    return (dx + dy) / ink, mid / on


print("mid = share of inked pixels that are mid-grey, edge = gradient energy per unit of ink, mean over 8 offsets")
print(f"{'font':9} {'win':5} {'size':>4} {'NEAREST mid edge':>18} {'LINEAR mid edge':>18}  {'at whole window px: NEAREST / LINEAR mid':42}")
scales = {"1x": 1, "1p5x": 1.5, "2x": 2}
for font in ("opensans", "heros"):
    for tag, s in scales.items():
        for size in (12, 16):
            row = []
            whole = []
            for filter_name in ("nearest", "linear"):
                d = T / f"{font}_{filter_name}_{tag}"
                img = np.asarray(Image.open(d / "syn.png").convert("RGB")).astype(int)[..., 0]
                L = [l for l in labels(d / "syn.log") if l[0] == size and l[1] == "inherit"]
                vals, wh = [], []
                for _size, _f, frac, y in L:
                    top = int(y * s) - 2
                    crop = img[top : top + int((size + 6) * s) + 2, int(15 * s) : int(450 * s)]
                    v = stats(crop)
                    vals.append(v)
                    if abs(frac * s - round(frac * s)) < 1e-6:
                        wh.append(v[1])
                row.append((np.mean([v[1] for v in vals]), np.mean([v[0] for v in vals])))
                whole.append(np.mean(wh) if wh else float("nan"))
            print(f"{font:9} {tag:5} {size:4d} {row[0][0]:9.3f} {row[0][1]:8.3f} {row[1][0]:9.3f} {row[1][1]:8.3f}  {whole[0]:.3f} / {whole[1]:.3f}")
