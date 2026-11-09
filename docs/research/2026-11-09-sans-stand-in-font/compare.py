#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["pillow", "numpy"]
# ///
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

WORKTREE = Path("/Users/sweetjp/Documents/godot/urchin/.claude/worktrees/gracious-chaplygin-3ca51d")
OUT = Path(__file__).parent
CAPTURE = WORKTREE / "references/2026_07_18_flashpoint/16_after_battle_victory_screen_Screenshot 2026-07-18 at 18.16.01.png"
ARIAL = "/System/Library/Fonts/Supplemental/Arial.ttf"
ARIAL_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
HELVETICA = "/System/Library/Fonts/Helvetica.ttc"
SCALE = 2
INK_SCALE = 20

LINES = [
    ("Victory! Items that dropped:", 12, False, "666666", (575, 250, 885, 285)),
    ("Once you are finished, press", 12, False, "666666", (578, 722, 900, 755)),
    ("below to proceed:", 12, False, "666666", (578, 758, 800, 790)),
    ("CLICK on the items that you", 12, True, "ffff33", (575, 558, 915, 592)),
    ("wish to keep!", 12, True, "ffff33", (575, 594, 750, 626)),
    ("Money gained:", 12, True, "fad95a", (590, 643, 775, 674)),
    ("Exp. gained:", 12, True, "ffffff", (590, 680, 750, 710)),
    ("Proceed!", 18, True, "66ff00", (680, 796, 845, 838)),
    ("Character Experience", 13, True, "5e5e5e", (155, 243, 440, 275)),
    ("Your Inventory", 13, True, "5e5e5e", (1160, 243, 1360, 275)),
    ("New Alcatraz: The Iron Prison", 12, True, "90f984", (1075, 1048, 1430, 1078)),
    ("Zone 1", 17, True, "ffffff", (1190, 1000, 1312, 1040)),
    ("Stage 2", 10, True, "ffffff", (1432, 1130, 1516, 1156)),
]
SHOWN = {"Victory! Items that dropped:", "CLICK on the items that you", "Proceed!", "Character Experience", "New Alcatraz: The Iron Prison", "Zone 1"}


def helvetica_faces() -> dict[str, int]:
    faces: dict[str, int] = {}
    index = 0
    while True:
        try:
            font = ImageFont.truetype(HELVETICA, 12, index=index)
        except OSError:
            return faces
        faces[font.getname()[1]] = index
        index += 1


def rgb(hex_color: str) -> np.ndarray:
    return np.array([int(hex_color[i : i + 2], 16) for i in (0, 2, 4)], dtype=float)


def capture_ink(pixels: np.ndarray, color: np.ndarray) -> tuple[int, int, int, int]:
    background = np.median(pixels.reshape(-1, 3), axis=0)
    tolerance = 0.5 * np.abs(color - background).sum()
    mask = np.abs(pixels - color).sum(axis=2) < tolerance
    columns = np.flatnonzero(mask.any(axis=0))
    rows = np.flatnonzero(mask.any(axis=1))
    return int(columns[0]), int(columns[-1]) + 1, int(rows[0]), int(rows[-1]) + 1


def font_ink_width(path: str, index: int, text: str, size: int) -> float:
    font = ImageFont.truetype(path, size * INK_SCALE, index=index)
    left, _, right, _ = font.getbbox(text)
    return (right - left) / INK_SCALE


def render(path: str, index: int, text: str, size: int, color: str, width: int, height: int) -> Image.Image:
    image = Image.new("RGB", (width, height), (30, 30, 30))
    font = ImageFont.truetype(path, size * SCALE, index=index)
    ImageDraw.Draw(image).text((6, height // 2), text, font=font, fill="#" + color, anchor="lm")
    return image


def write_corpus() -> None:
    source = (WORKTREE / "dev/source_files/action_script/frame_41/DoAction.as").read_text(errors="replace")
    strings = sorted({s for s in re.findall(r'"((?:[^"\\]|\\.)*)"', source) if len(s) >= 4 and re.search(r"[a-z] ?[A-Za-z]", s)})
    (OUT / "corpus.txt").write_text("\n".join(s.replace("\\n", " ").replace('\\"', '"') for s in strings))
    print(f"corpus: {len(strings)} strings from frame_41/DoAction.as")


def main() -> None:
    faces = helvetica_faces()
    print("helvetica faces:", faces)
    capture = np.asarray(Image.open(CAPTURE).convert("RGB"), dtype=float)
    print(f"capture {capture.shape[1]}x{capture.shape[0]}; widths below are design px (capture px / {SCALE})")
    header = f"{'text':31s} {'sz':>2s} {'bold':>4s} {'capture':>8s} {'arial':>7s} {'helv':>7s}  {'cap h':>6s}"
    print(header)
    regular_helv, bold_helv = faces["Regular"], faces["Bold"]
    panels: list[Image.Image] = []
    for text, size, bold, color, box in LINES:
        x0, y0, x1, y1 = box
        left, right, top, bottom = capture_ink(capture[y0:y1, x0:x1], rgb(color))
        width = (right - left) / SCALE
        arial_path = ARIAL_BOLD if bold else ARIAL
        arial = font_ink_width(arial_path, 0, text, size)
        helv = font_ink_width(HELVETICA, bold_helv if bold else regular_helv, text, size)
        print(f"{text:31s} {size:2d} {bold!s:>5s} {width:8.2f} {arial:7.2f} {helv:7.2f}  {(bottom - top) / SCALE:6.2f}")
        if text in SHOWN:
            crop = Image.fromarray(capture[y0:y1, x0:x1].astype("uint8"))
            w, h = crop.size
            rows = [crop, render(arial_path, 0, text, size, color, w, h), render(HELVETICA, bold_helv if bold else regular_helv, text, size, color, w, h)]
            panels.extend(r.resize((w * 3, h * 3), Image.Resampling.LANCZOS) for r in rows)
    sheet = Image.new("RGB", (max(p.width for p in panels) + 20, sum(p.height + 6 for p in panels) + 20), (0, 0, 0))
    y = 10
    for i, panel in enumerate(panels):
        sheet.paste(panel, (10, y))
        y += panel.height + (24 if i % 3 == 2 else 2)
        if y > sheet.height:
            break
    sheet.save(OUT / "shapes.png")
    write_corpus()


main()
