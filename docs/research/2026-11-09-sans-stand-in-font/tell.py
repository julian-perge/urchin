#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["pillow", "numpy"]
# ///
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

WORKTREE = Path("/Users/sweetjp/Documents/godot/urchin/.claude/worktrees/gracious-chaplygin-3ca51d")
OUT = Path(__file__).parent
CAPTURE = WORKTREE / "references/2026_07_18_flashpoint/8_start_screen_options_Screenshot 2026-07-18 at 18.13.14.png"
ARIAL_BOLD = ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 0)
HELVETICA_BOLD = ("/System/Library/Fonts/Helvetica.ttc", 1)
ZOOM = 5
CROPS = [
    ("START!", "60ef21", (668, 818, 850, 872)),
    ("Graphics:", "9be86c", (450, 480, 610, 522)),
    ("Tutorial", "ff9900", (292, 212, 442, 262)),
]


def coverage(pixels: np.ndarray, color: np.ndarray) -> np.ndarray:
    background = np.median(pixels.reshape(-1, 3), axis=0)
    axis = color - background
    return np.clip(((pixels - background) * axis).sum(axis=2) / (axis * axis).sum(), 0, 1)


def ink_box(mask: np.ndarray) -> tuple[int, int, int, int]:
    columns = np.flatnonzero((mask > 0.5).any(axis=0))
    rows = np.flatnonzero((mask > 0.5).any(axis=1))
    return int(columns[0]), int(rows[0]), int(columns[-1]) + 1, int(rows[-1]) + 1


def draw(face: tuple[str, int], text: str, size: float, canvas: tuple[int, int], origin: tuple[float, float]) -> np.ndarray:
    image = Image.new("L", canvas, 0)
    font = ImageFont.truetype(face[0], size, index=face[1])
    ImageDraw.Draw(image).text(origin, text, font=font, fill=255)
    return np.asarray(image, dtype=float) / 255


def best_fit(face: tuple[str, int], text: str, target: np.ndarray, width: int) -> tuple[float, np.ndarray]:
    height, canvas_width = target.shape
    base = ImageFont.truetype(face[0], 100, index=face[1])
    left, top, right, _ = base.getbbox(text)
    guess = 100 * width / (right - left)
    best = (-2.0, np.zeros_like(target))
    for size in np.arange(guess * 0.96, guess * 1.04, 0.1):
        font = ImageFont.truetype(face[0], float(size), index=face[1])
        bx0, by0, _, _ = font.getbbox(text)
        ix0, iy0, _, _ = ink_box(target)
        for dx in range(-3, 4):
            for dy in range(-3, 4):
                rendered = draw(face, text, float(size), (canvas_width, height), (ix0 - bx0 + dx, iy0 - by0 + dy))
                score = float(np.corrcoef(rendered.ravel(), target.ravel())[0, 1])
                if score > best[0]:
                    best = (score, rendered)
    return best


def main() -> None:
    capture = np.asarray(Image.open(CAPTURE).convert("RGB"), dtype=float)
    print("capture", capture.shape[1], "x", capture.shape[0])
    rows: list[Image.Image] = []
    for text, hex_color, (x0, y0, x1, y1) in CROPS:
        pixels = capture[y0:y1, x0:x1]
        color = np.array([int(hex_color[i : i + 2], 16) for i in (0, 2, 4)], dtype=float)
        target = coverage(pixels, color)
        box = ink_box(target)
        width = box[2] - box[0]
        arial_score, arial = best_fit(ARIAL_BOLD, text, target, width)
        helvetica_score, helvetica = best_fit(HELVETICA_BOLD, text, target, width)
        print(f"{text:10s} correlation with capture: Arial Bold {arial_score:.4f}, Helvetica Bold {helvetica_score:.4f}")
        h, w = target.shape
        for layer in (pixels.astype("uint8"), np.dstack([arial * 255] * 3).astype("uint8"), np.dstack([helvetica * 255] * 3).astype("uint8")):
            rows.append(Image.fromarray(layer).resize((w * ZOOM, h * ZOOM), Image.Resampling.LANCZOS))
    sheet = Image.new("RGB", (max(r.width for r in rows) + 20, sum(r.height + 4 for r in rows) + 80), (90, 0, 90))
    y = 10
    for i, row in enumerate(rows):
        sheet.paste(row, (10, y))
        y += row.height + (24 if i % 3 == 2 else 4)
    sheet.save(OUT / "tell.png")


main()
