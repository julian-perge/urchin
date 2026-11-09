#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["numpy", "pillow", "scipy"]
# ///
"""What colour the fully transparent texels next to the art hold, for the textures with and without fix_alpha_border."""
import sys
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage

root = Path(sys.argv[1])
for rel in ("assets/item_slot_icons/OTHER/A_Broken_Pipe.png", "resources/sprites/M_SCHEST_ONE.png", "resources/sprites/M_SARM_ONE.png", "resources/sprites/M_LEG3_ONE.png"):
    p = root / rel
    if not p.exists():
        print(rel, "missing")
        continue
    a = np.asarray(Image.open(p).convert("RGBA"))
    edge = (a[..., 3] == 0) & ndimage.binary_dilation(a[..., 3] > 0)
    print(f"{rel}: {a.shape[1]}x{a.shape[0]}, transparent edge texels {int(edge.sum())}, of those pure black RGB {int((a[edge][:, :3].sum(axis=1) == 0).sum())}")
