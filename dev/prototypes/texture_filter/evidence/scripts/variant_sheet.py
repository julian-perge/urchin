#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["pillow"]
# ///
"""Variants A to D side by side, one row per feature, in real window pixels magnified by a whole number."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

T = Path.home() / "tmp/2026-11-09-urchin-filter"
FRAME = {"battle": 120, "store": 40}
NAMES = {"A": "A NEAREST (today)", "B": "B LINEAR", "C": "C LINEAR art, NEAREST text", "D": "D LINEAR+mips art, NEAREST text"}
ROWS = [
    ("battle hall", "battle", (0, 125, 110, 225)),
    ("doll", "battle", (195, 325, 268, 415)),
    ("item icons", "store", (285, 270, 400, 350)),
    ("text", "store", (30, 250, 140, 290)),
]
font = ImageFont.load_default()
for tag, scale, zoom in (("2x", 2, 2), ("1x", 1, 4)):
    rows = []
    for name, scene, (x0, y0, x1, y1) in ROWS:
        cells = []
        for v in "ABCD":
            im = Image.open(T / "var" / f"{v}_{tag}" / f"{scene}_f{FRAME[scene]:04d}.png").convert("RGB").crop((x0 * scale, y0 * scale, x1 * scale, y1 * scale))
            im = im.resize((im.width * zoom, im.height * zoom), Image.Resampling.NEAREST)
            cell = Image.new("RGB", (im.width + 8, im.height + 20), (15, 15, 15))
            ImageDraw.Draw(cell).text((4, 3), f"{name}: {NAMES[v]}", fill=(235, 235, 235), font=font)
            cell.paste(im, (4, 18))
            cells.append(cell)
        row = Image.new("RGB", (sum(c.width for c in cells) + 12, cells[0].height), (0, 0, 0))
        x = 0
        for c in cells:
            row.paste(c, (x, 0))
            x += c.width + 4
        rows.append(row)
    sheet = Image.new("RGB", (max(r.width for r in rows), sum(r.height for r in rows) + 4 * len(rows)), (0, 0, 0))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height + 4
    out = T / f"variants_{tag}.png"
    sheet.save(out)
    print(out, sheet.size)
