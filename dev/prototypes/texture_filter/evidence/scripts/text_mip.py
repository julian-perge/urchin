#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["numpy", "pillow"]
# ///
"""Whether mipmaps change the store's dialogue text, which sits on a flat panel."""
from pathlib import Path
import numpy as np
from PIL import Image

T = Path.home() / "tmp/2026-11-09-urchin-filter/cap"
for tag, s in (("1x", 1), ("2x", 2)):
    a, b = (np.asarray(Image.open(T / f"{f}_{tag}" / "store_f0040.png").convert("RGB"), dtype=np.int16)[250 * s:330 * s, 30 * s:270 * s] for f in ("linear", "mip"))
    d = np.abs(a - b).max(axis=2)
    print(tag, "pixels differing", int((d > 0).sum()), "of", d.size, "max", int(d.max()))
