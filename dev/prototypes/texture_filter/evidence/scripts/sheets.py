#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["pillow"]
# ///
"""One sheet per feature: NEAREST, LINEAR, LINEAR with mipmaps across, the 2x window over the 1x window."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

T = Path.home() / "tmp/2026-11-09-urchin-filter"
FRAME = {"battle": 120, "hub": 60, "inv": 40, "store": 40, "abil": 40, "title": 30}
CROPS = {
    "hall": ("battle", (0, 125, 150, 250), 2, 4),
    "skyline": ("battle", (235, 155, 415, 240), 2, 4),
    "doll_veradux": ("battle", (195, 325, 268, 415), 3, 6),
    "doll_felicity": ("battle", (605, 250, 665, 340), 3, 6),
    "buff": ("battle", (570, 196, 600, 226), 6, 12),
    "hotbar": ("store", (15, 505, 330, 565), 1, 2),
    "items": ("store", (285, 270, 475, 350), 2, 4),
    "text": ("store", (30, 250, 270, 330), 2, 4),
    "header_text": ("store", (505, 85, 750, 112), 2, 4),
    "portrait": ("store", (35, 90, 262, 242), 1, 2),
    "zone_text": ("store", (480, 490, 785, 570), 1, 2),
    "battle_ui": ("battle", (20, 488, 320, 530), 2, 4),
}
HUB_ORB = ("hub", (0, 0, 800, 470), 1, 1)
font = ImageFont.load_default()
FILTERS = (("NEAREST", "nearest"), ("LINEAR", "linear"), ("LINEAR+mips", "mip"))
out = T / "sheets"
out.mkdir(exist_ok=True)
for name, (scene, (x0, y0, x1, y1), z2, z1) in CROPS.items():
    grid = []
    for tag, scale, zoom in (("2x", 2, z2), ("1x", 1, z1)):
        row = []
        for label, f in FILTERS:
            im = Image.open(T / "cap" / f"{f}_{tag}" / f"{scene}_f{FRAME[scene]:04d}.png").convert("RGB").crop((x0 * scale, y0 * scale, x1 * scale, y1 * scale))
            im = im.resize((im.width * zoom, im.height * zoom), Image.Resampling.NEAREST)
            canvas = Image.new("RGB", (im.width + 8, im.height + 20), (15, 15, 15))
            ImageDraw.Draw(canvas).text((4, 3), f"{label}, {tag} window, x{zoom}", fill=(235, 235, 235), font=font)
            canvas.paste(im, (4, 18))
            row.append(canvas)
        grid.append(row)
    w = sum(c.width for c in grid[0]) + 4 * 3
    h = sum(r[0].height for r in grid) + 8
    sheet = Image.new("RGB", (w, h), (0, 0, 0))
    y = 0
    for row in grid:
        x = 0
        for c in row:
            sheet.paste(c, (x, y))
            x += c.width + 4
        y += row[0].height + 4
    sheet.save(out / f"{name}.png")
    print(name, sheet.size)
