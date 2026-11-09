#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["pillow", "numpy"]
# ///
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

WORKTREE = Path("/Users/sweetjp/Documents/godot/urchin/.claude/worktrees/gracious-chaplygin-3ca51d")
OUT = Path(__file__).parent
VICTORY = WORKTREE / "references/2026_07_18_flashpoint/16_after_battle_victory_screen_Screenshot 2026-07-18 at 18.16.01.png"
OPTIONS = WORKTREE / "references/2026_07_18_flashpoint/8_start_screen_options_Screenshot 2026-07-18 at 18.13.14.png"
LABEL_FONT = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 22)
ZOOM = 3
GUTTER = 190

LINES = [
    (VICTORY, "Victory! Items that dropped:", 12, False, "666666", (575, 250, 885, 285)),
    (VICTORY, "CLICK on the items that you", 12, True, "ffff33", (575, 558, 915, 592)),
    (VICTORY, "Proceed!", 18, True, "66ff00", (680, 796, 845, 838)),
    (VICTORY, "Character Experience", 13, True, "5e5e5e", (155, 243, 440, 275)),
    (VICTORY, "New Alcatraz: The Iron Prison", 12, True, "90f984", (1075, 1048, 1430, 1078)),
    (VICTORY, "Zone 1", 17, True, "ffffff", (1190, 1000, 1312, 1040)),
    (OPTIONS, "START!", 24, True, "60ef21", (668, 818, 850, 872)),
    (OPTIONS, "Graphics:", 16, True, "9be86c", (450, 480, 610, 522)),
]


def rgb(hex_color: str) -> np.ndarray:
    return np.array([int(hex_color[i : i + 2], 16) for i in (0, 2, 4)], dtype=float)


def load(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=float)


def background(pixels: np.ndarray) -> np.ndarray:
    return np.median(pixels.reshape(-1, 3), axis=0)


def ink_box(pixels: np.ndarray, color: np.ndarray) -> tuple[int, int, int, int]:
    tolerance = 0.5 * np.abs(color - background(pixels)).sum()
    mask = np.abs(pixels - color).sum(axis=2) < tolerance
    columns = np.flatnonzero(mask.any(axis=0))
    rows = np.flatnonzero(mask.any(axis=1))
    return int(columns[0]), int(rows[0]), int(columns[-1]) + 1, int(rows[-1]) + 1


def prepare() -> None:
    payload = []
    for path, text, size, bold, color, (x0, y0, x1, y1) in LINES:
        bg = background(load(path)[y0:y1, x0:x1])
        payload.append({"text": text, "size": size, "bold": bold, "color": color, "bg": "%02x%02x%02x" % tuple(int(v) for v in bg)})
    (OUT / "lines.json").write_text(json.dumps(payload))


def compose() -> None:
    render = np.asarray(Image.open(OUT / "godot_render.png").convert("RGB"), dtype=float)
    scale = render.shape[1] / 800
    print(f"render {render.shape[1]}x{render.shape[0]}, scale {scale}")
    rows = json.loads((OUT / "rows.json").read_text())
    faces = sys.argv[2].split(",") if len(sys.argv) > 2 else list(dict.fromkeys(row["face"] for row in rows))
    captures = {VICTORY: load(VICTORY), OPTIONS: load(OPTIONS)}
    panels: list[tuple[str, Image.Image]] = []
    print(f"{'text':31s} {'capture ink':>11s} " + " ".join(f"{face:>15s}" for face in faces))
    for path, text, size, bold, color, (x0, y0, x1, y1) in LINES:
        crop = captures[path][y0:y1, x0:x1]
        target = rgb(color)
        cx0, cy0, cx1, cy1 = ink_box(crop, target)
        height, width, _ = crop.shape
        bg = background(crop)
        panels.append(("capture", Image.fromarray(crop.astype("uint8"))))
        widths = []
        for face in faces:
            row = next(r for r in rows if r["text"] == text and r["face"] == face)
            top = round(row["y"] * scale)
            bottom = round((row["y"] + row["height"]) * scale)
            left = round(row["x"] * scale)
            strip = render[top + 2 : bottom - 2, left : left + round(400 * scale)]
            ix0, iy0, ix1, iy1 = ink_box(strip, target)
            widths.append((ix1 - ix0) / 2)
            canvas = np.tile(bg, (height, width, 1))
            dx = cx0 - ix0
            dy = (cy0 + cy1) // 2 - (iy0 + iy1) // 2
            for y in range(strip.shape[0]):
                ty = y + dy
                if 0 <= ty < height:
                    span = min(width, strip.shape[1] + dx) - max(0, dx)
                    if span > 0:
                        canvas[ty, max(0, dx) : max(0, dx) + span] = strip[y, max(0, -dx) : max(0, -dx) + span]
            panels.append((face, Image.fromarray(canvas.astype("uint8"))))
        print(f"{text:31s} {(cx1 - cx0) / 2:11.2f} " + " ".join(f"{w:15.2f}" for w in widths))
    per_line = 1 + len(faces)
    gap = 18
    sheet_width = max(p.width for _, p in panels) * ZOOM + GUTTER + 20
    sheet_height = sum(p.height * ZOOM + 3 for _, p in panels) + gap * (len(panels) // per_line) + 20
    sheet = Image.new("RGB", (sheet_width, sheet_height), (12, 12, 12))
    draw = ImageDraw.Draw(sheet)
    y = 10
    for index, (label, panel) in enumerate(panels):
        scaled = panel.resize((panel.width * ZOOM, panel.height * ZOOM), Image.Resampling.LANCZOS)
        sheet.paste(scaled, (GUTTER, y))
        draw.text((10, y + scaled.height // 2), label, font=LABEL_FONT, fill=(220, 220, 220), anchor="lm")
        y += scaled.height + 3
        if index % per_line == per_line - 1:
            y += gap
    sheet.save(OUT / "candidates.png")


{"prepare": prepare, "compose": compose}[sys.argv[1]]()
