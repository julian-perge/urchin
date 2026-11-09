"""One image comparing the top-left corner of the left win-frame panel across the options."""

from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path.home() / "tmp/2026-11-09-inner-shadow"
PROTO = ROOT / "proto/dev/prototypes/victory_containers"
REAL = Path(
    "/Users/sweetjp/Documents/godot/urchin/.claude/worktrees/goofy-mestorf-dddf9f/references/2026_07_18_flashpoint/16_after_battle_victory_screen_Screenshot 2026-07-18 at 18.16.01.png"
)
font = ImageFont.load_default(18)


def crop(img, x, y, w, h, scale):
    return img.crop((x, y, x + w, y + h)).resize((w * scale, h * scale), Image.NEAREST)


real = Image.open(REAL).convert("RGB")
ref = Image.open(PROTO / "images/ref/win_panels_2x.png").convert("RGB")
out = ROOT / "out"
out4 = ROOT / "out4x"
# Top-left corner of the left panel in the stage at 2x: x 60-130, y 150-200.
X, Y, W, H, S = 60, 150, 70, 50, 5
items = [
    ("real Flash, 2x", real.crop((0, 64, 1600, 1264))),
    ("ffdec 2x", ref),
    ("no shadow (StyleBoxFlat)", Image.open(out / "flat.png").convert("RGB")),
    ("baked, stretched (prototype C)", Image.open(out / "baked.png").convert("RGB")),
    (
        "1x nine-patch, raw ffdec 1x",
        Image.open(out / "nine_raw_nearest.png").convert("RGB"),
    ),
    (
        "1x nine-patch, aligned, nearest",
        Image.open(out / "nine_aligned_nearest.png").convert("RGB"),
    ),
    (
        "1x nine-patch, aligned, linear",
        Image.open(out / "nine_aligned_linear.png").convert("RGB"),
    ),
    ("shader, box 5", Image.open(out / "shader5.png").convert("RGB")),
    ("custom StyleBox, box 5", Image.open(out / "stylebox.png").convert("RGB")),
]
cols = 3
cell_w, cell_h = W * S + 20, H * S + 40
rows = (len(items) + cols - 1) // cols
sheet = Image.new("RGB", (cell_w * cols + 20, cell_h * rows + 20), (30, 30, 30))
d = ImageDraw.Draw(sheet)
for i, (name, img) in enumerate(items):
    cx, cy = 20 + (i % cols) * cell_w, 10 + (i // cols) * cell_h
    d.text((cx, cy), name, fill=(235, 235, 235), font=font)
    sheet.paste(crop(img, X, Y, W, H, S), (cx, cy + 28))
sheet.save(ROOT / "out/comparison_2x_window.png")
# 4x window: nearest vs linear nine-patch vs shader at the same stage area.
items4 = [
    (
        "1x nine-patch, nearest, 4x window",
        Image.open(out4 / "nine_aligned_nearest.png").convert("RGB"),
    ),
    (
        "1x nine-patch, linear, 4x window",
        Image.open(out4 / "nine_aligned_linear.png").convert("RGB"),
    ),
    ("shader, 4x window", Image.open(out4 / "shader5.png").convert("RGB")),
]
X4, Y4, W4, H4, S4 = 120, 300, 100, 70, 4
sheet4 = Image.new("RGB", ((W4 * S4 + 20) * 3 + 20, H4 * S4 + 60), (30, 30, 30))
d = ImageDraw.Draw(sheet4)
for i, (name, img) in enumerate(items4):
    cx = 20 + i * (W4 * S4 + 20)
    d.text((cx, 10), name, fill=(235, 235, 235), font=font)
    sheet4.paste(crop(img, X4, Y4, W4, H4, S4), (cx, 38))
sheet4.save(ROOT / "out/comparison_4x_window.png")
