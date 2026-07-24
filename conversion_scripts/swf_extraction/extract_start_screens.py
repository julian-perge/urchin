# extract_start_screens.py
# Start-menu art cropped from the RENDERED root frames in
# source_files/exported_assets/frames/ (ffdec renders Flash blend modes and
# masks correctly, which per-shape compositing cannot):
# - root frame 85 = class select (gray cards), 90 = colored/hover cards
#   -> assets/ui/menu/class_cards/<class>{,_gray}.png
# - root frame 65 = name entry on the clean splatter background; the few
#   baked texts are erased by resampling the gradient from each side
#   -> assets/ui/menu/start_background.png
#
# Card rects come from the root-timeline placements (sprites 2746/2766/2755
# at frame 85). Frames are 2x (1600x1150 for the 800x575 stage).
#
# Run: uv run python3 conversion_scripts/swf_extraction/extract_start_screens.py
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

from .. import REPO_ROOT, SOURCE_FILES

FRAMES = SOURCE_FILES / "exported_assets" / "frames"
OUT_MENU = REPO_ROOT / "assets" / "ui" / "menu"
ZOOM = 2.0

# Design-px rects of the three class cards (root frame 85 placements).
CARDS = {
    "psychological": (56.6, 159.8, 230.8, 320.9),
    "biological": (295.2, 160.1, 215.7, 299.1),
    "hydraulic": (518.6, 160.1, 232.8, 299.1),
}
# Baked texts on frame 65 to erase from the background (design px,
# corner-coordinate rects x0,y0,x1,y1).
ERASE_RECTS = [
    (170, 235, 625, 390),  # name input + OK!
    (5, 5, 210, 70),  # Armor Games logo
    (0, 520, 270, 575),  # credits lines
    (690, 540, 800, 575),  # PLAY
    (690, 0, 800, 45),  # rhttner watermark
]


def crop(frame_number: int, rect, out_path: Path):
    src = Image.open(FRAMES / ("%d.png" % frame_number)).convert("RGBA")
    x, y, w, h = (v * ZOOM for v in rect)
    img = src.crop((int(x), int(y), int(x + w), int(y + h)))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)
    print("wrote", out_path, img.size, file=sys.stderr)


def erase_rect(img: Image.Image, rect):
    """Fill a rect by lerping each row between the pixels just outside it -
    good enough on a smooth radial gradient."""
    x0, y0, x1, y1 = (int(v * ZOOM) for v in rect)
    width = img.width
    left_x = max(x0 - 6, 0)
    right_x = min(x1 + 6, width - 1)
    pixels = img.load()
    for y in range(y0, min(y1, img.height)):
        left = pixels[left_x, y]
        right = pixels[right_x, y]
        span = max(x1 - x0, 1)
        for x in range(x0, min(x1, width)):
            t = (x - x0) / span
            pixels[x, y] = tuple(
                int(left[c] + (right[c] - left[c]) * t) for c in range(4)
            )


def main():
    for name, rect in CARDS.items():
        crop(85, rect, OUT_MENU / "class_cards" / ("%s_gray.png" % name))
        crop(90, rect, OUT_MENU / "class_cards" / ("%s.png" % name))
    background = Image.open(FRAMES / "65.png").convert("RGBA")
    for rect in ERASE_RECTS:
        erase_rect(background, rect)
    out = OUT_MENU / "start_background.png"
    background.save(out)
    print("wrote", out, background.size, file=sys.stderr)


if __name__ == "__main__":
    main()
