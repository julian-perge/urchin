"""Scores each throwaway capture against ffdec's 2x panels render and the real Flash capture.

Run from the repo root:
  uv run python ~/tmp/2026-11-09-inner-shadow/compare_variants.py [--out-dir out]
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path.home() / "tmp/2026-11-09-inner-shadow"
PROTO = ROOT / "proto/dev/prototypes/victory_containers"
WORKTREE = Path(
    "/Users/sweetjp/Documents/godot/urchin/.claude/worktrees/goofy-mestorf-dddf9f"
)
REAL = (
    WORKTREE
    / "references/2026_07_18_flashpoint/16_after_battle_victory_screen_Screenshot 2026-07-18 at 18.16.01.png"
)
OUT = ROOT / (sys.argv[1] if len(sys.argv) > 1 else "out")
VARIANTS = [
    "flat",
    "plainart",
    "baked",
    "nine_raw_nearest",
    "nine_raw_linear",
    "nine_aligned_nearest",
    "nine_aligned_linear",
    "shader5",
    "shader45",
    "stylebox",
    "stylebox45",
    "shader_wrong",
    "shader_plainart",
]
BAND = 14

layout = json.loads((PROTO / "win_layout.json").read_text())
rects = {k: v["rect"] for k, v in layout["panels"].items()}

ref2x = np.asarray(
    Image.open(PROTO / "images/ref/win_panels_2x.png").convert("RGBA"), dtype=np.int16
)
ref1x = np.asarray(
    Image.open(PROTO / "images/ref/win_panels_1x.png").convert("RGBA"), dtype=np.int16
)
real_full = np.asarray(Image.open(REAL).convert("RGB"), dtype=np.int16)
# The capture is the stage at 2x under a 64 px title bar. Pad or crop to the 1600x1200 canvas.
real = np.zeros((1200, 1600, 3), dtype=np.int16)
h = min(1200, real_full.shape[0] - 64)
w = min(1600, real_full.shape[1])
real[:h, :w] = real_full[64 : 64 + h, :w]
real_mask = np.zeros((1200, 1600), dtype=bool)
real_mask[:h, :w] = True


def stats(values):
    return f"p50 {np.percentile(values, 50):5.1f}  p90 {np.percentile(values, 90):5.1f}  p99 {np.percentile(values, 99):5.1f}  mean {values.mean():5.2f}"


def bands(scale, skip):
    """-> mask of the shadow band of each panel: within BAND/2*scale device px of its left or top edge."""
    size = (600 * scale, 800 * scale)
    mask = np.zeros(size, dtype=bool)
    width = BAND * scale // 2
    for x, y, w, h in rects.values():
        x0, y0 = int(np.ceil(x * scale)), int(np.ceil(y * scale))
        x1, y1 = int(np.floor((x + w) * scale)), int(np.floor((y + h) * scale))
        mask[y0 + skip : y1, x0 + skip : x0 + width] = True
        mask[y0 + skip : y0 + width, x0 + skip : x1] = True
    return mask


def whole_panels(scale, inset):
    size = (600 * scale, 800 * scale)
    mask = np.zeros(size, dtype=bool)
    for x, y, w, h in rects.values():
        x0, y0 = int(np.ceil(x * scale)) + inset, int(np.ceil(y * scale)) + inset
        x1, y1 = (
            int(np.floor((x + w) * scale)) - inset,
            int(np.floor((y + h) * scale)) - inset,
        )
        mask[y0:y1, x0:x1] = True
    return mask


def difference(shot, ref):
    return np.abs(shot[:, :, :3] - ref[:, :, :3]).max(axis=2)


band2 = bands(2, 0)
band2_inner = bands(2, 3)
panels2 = whole_panels(2, 0)
print(f"{'variant':24s} {'frame 1x (compare.py style)':42s} {'panel rects 2x':42s}")
rows = {}
for name in VARIANTS:
    path = OUT / f"{name}.png"
    if not path.exists():
        continue
    shot2 = np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)
    drawn2 = ~(
        (shot2[:, :, 0] == 255) & (shot2[:, :, 1] == 0) & (shot2[:, :, 2] == 255)
    )
    opaque2 = ref2x[:, :, 3] == 255
    d2 = difference(shot2, ref2x)
    shot1 = np.asarray(
        Image.open(path).convert("RGB").resize((800, 600), Image.LANCZOS),
        dtype=np.int16,
    )
    opaque1 = ref1x[:, :, 3] == 255
    d1 = difference(shot1, ref1x)
    drawn1 = ~(
        (np.abs(shot1[:, :, 0] - 255) < 40)
        & (shot1[:, :, 1] < 40)
        & (np.abs(shot1[:, :, 2] - 255) < 40)
    )
    # shrink by 1 px like compare.py
    s = drawn1.copy()
    s[1:, :] &= drawn1[:-1, :]
    s[:-1, :] &= drawn1[1:, :]
    s[:, 1:] &= drawn1[:, :-1]
    s[:, :-1] &= drawn1[:, 1:]
    frame1 = stats(d1[s & opaque1])
    rect2 = stats(d2[panels2 & opaque2])
    print(f"{name:24s} {frame1:42s} {rect2:42s}")
    rows[name] = (d2, opaque2, drawn2, shot2)

print(
    "\nShadow band only (14 device px at left/top of each panel, outer 3 device px skipped), 2x"
)
print(f"{'variant':24s} {'vs ffdec 2x':42s} {'vs real Flash':42s}")
d_ref_real = np.abs(ref2x[:, :, :3] - real).max(axis=2)
print(
    f"{'(ffdec itself)':24s} {'-':42s} {stats(d_ref_real[band2_inner & real_mask & (ref2x[:, :, 3] == 255)]):42s}"
)
for name, (d2, opaque2, drawn2, shot2) in rows.items():
    vs_real = np.abs(shot2 - real).max(axis=2)
    print(
        f"{name:24s} {stats(d2[band2_inner & opaque2]):42s} {stats(vs_real[band2_inner & real_mask & opaque2]):42s}"
    )

print("\nPer-panel band vs real Flash, p99")
for name, (d2, opaque2, drawn2, shot2) in rows.items():
    vs_real = np.abs(shot2 - real).max(axis=2)
    cells = []
    for key, (x, y, w, h) in rects.items():
        m = np.zeros((1200, 1600), dtype=bool)
        x0, y0 = int(np.ceil(x * 2)), int(np.ceil(y * 2))
        x1, y1 = int(np.floor((x + w) * 2)), int(np.floor((y + h) * 2))
        m[y0 + 3 : y1, x0 + 3 : x0 + 14] = True
        m[y0 + 3 : y0 + 14, x0 + 3 : x1] = True
        vals = vs_real[m & real_mask]
        cells.append(f"{key} {np.percentile(vals, 99):5.1f}")
    print(f"{name:24s} " + "  ".join(cells))
