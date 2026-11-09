#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["pillow", "numpy"]
# ///
# Prints the pixels at each panel's outer bottom right corner in real Flash and
# in the flat_mean capture.
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


def rgb(p):
    return np.asarray(Image.open(p).convert("RGB"), dtype=int)


win = rgb(
    REF
    / "2026_07_18_flashpoint/16_after_battle_victory_screen_Screenshot 2026-07-18 at 18.16.01.png"
)[64:]
mean = rgb(HERE / "out2x" / "win__flat_mean.png")
for p in data["win"]["panels"]:
    x, y, w, h = p["rect"]
    cx = int(round((x + w) * 2))
    cy = int(round((y + h) * 2))
    print("win", p["sprite"], "corner px around", cx, cy, "R channel: real | flat_mean")
    for j in range(cy - 4, cy + 3):
        print(
            "   ",
            [int(v) for v in win[j, cx - 4 : cx + 3, 0]],
            "|",
            [int(v) for v in mean[j, cx - 4 : cx + 3, 0]],
        )
