#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["numpy", "pillow"]
# ///
"""Checks that the switcher's variants draw what they claim, against the captures made with the project filter flipped directly."""
from pathlib import Path
import numpy as np
from PIL import Image

T = Path.home() / "tmp/2026-11-09-urchin-filter"
FRAME = {"battle": 120, "store": 40}
# Regions of text only, on a flat panel or fixed art, in design px.
TEXT = {"store": (30, 250, 270, 330), "battle": (20, 495, 110, 515)}


def var(v, tag, scene):
    return np.asarray(Image.open(T / "var" / f"{v}_{tag}" / f"{scene}_f{FRAME[scene]:04d}.png").convert("RGB"), dtype=np.int16)


def cap(f, tag, scene):
    return np.asarray(Image.open(T / "cap" / f"{f}_{tag}" / f"{scene}_f{FRAME[scene]:04d}.png").convert("RGB"), dtype=np.int16)


def n(a, b, box=None, s=1):
    d = np.abs(a - b).max(axis=2)
    if box:
        x0, y0, x1, y1 = (int(v * s) for v in box)
        d = d[y0:y1, x0:x1]
    return f"{int((d > 0).sum()):7d} of {d.size} differ, max {int(d.max()):3d}"


for tag, s in (("2x", 2), ("1x", 1)):
    for scene in FRAME:
        A, B, C, D = (var(v, tag, scene) for v in "ABCD")
        near, lin, mip = (cap(f, tag, scene) for f in ("nearest", "linear", "mip"))
        print(f"== {scene} {tag}")
        print("  A against the NEAREST capture without mipmaps:", n(A, near))
        print("  B against the LINEAR capture:                 ", n(B, lin))
        print("  D against the LINEAR+mipmaps capture:         ", n(D, mip))
        print("  C against B (whole frame):                    ", n(C, B))
        print("  C against A, text region:                     ", n(C, A, TEXT[scene], s))
        print("  B against A, text region:                     ", n(B, A, TEXT[scene], s))
