#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["pillow", "numpy"]
# ///
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

A = Path(
    "/Users/sweetjp/Documents/godot/urchin/.claude/worktrees/gracious-chaplygin-3ca51d/assets/ui/menu"
)
H = Path("/Users/sweetjp/tmp/2026-11-09-panel-art/art")
for hand, ff in (
    ("panel_large", "2990_z2"),
    ("panel_bar", "2992_z2"),
    ("panel_center", "2988_z2"),
):
    a = np.asarray(Image.open(A / f"{hand}.png").convert("RGBA"), dtype=int)
    b = np.asarray(Image.open(H / f"{ff}.png").convert("RGBA"), dtype=int)
    print(
        hand, a.shape, ff, b.shape, "same size" if a.shape == b.shape else "DIFF SIZE"
    )
    print(
        "  hand centre px",
        a[a.shape[0] // 2, a.shape[1] // 2].tolist(),
        "ffdec centre px",
        b[b.shape[0] // 2, b.shape[1] // 2].tolist(),
    )
    print("  hand corners", a[0, 0].tolist(), a[1, 1].tolist(), a[2, 2].tolist())
    print("  ffdec corners", b[0, 0].tolist(), b[1, 1].tolist(), b[2, 2].tolist())
    if a.shape == b.shape:
        d = np.abs(a - b).max(axis=2)
        print(
            "  max diff", d.max(), "px differing >2:", int((d > 2).sum()), "of", d.size
        )
    # horizontal profile across left edge at mid-height, RGBA
    y = a.shape[0] // 2
    print("  hand left edge RGBA", [a[y, i].tolist() for i in range(5)])
    print("  ffdec left edge RGBA", [b[y, i].tolist() for i in range(5)])
