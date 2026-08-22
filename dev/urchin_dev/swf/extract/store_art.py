# The shop keeper scene behind each store screen, from DefineSprite 3036:
#
#   assets/ui/store/backdrops/shop<id>.png
#
# 3036 carries no frame labels - the store screen jumps it to shopId + 1, so
# frame 1 is shop 0. Its 13 frames only hold 7 distinct scenes: depth 2 is the
# keeper, changing per frame (3023, 3025, 3027, 3029, 3031, 3033, 3035), and
# frames 8-12 repeat the last one while frame 13 drops it entirely. Only the
# first seven are exported, which covers every shop StoreManager can select
# (ZONE_SHOP_IDS reaches 0-6; shop 7 exists in krinSetShop but no store orb
# sets it).
#
# Depths 1 and 4 (3021 and 3020) hold still across every frame - they are the
# scene the keeper stands in, not per-shop art, so they stay in the render.
#
# The earlier hand-cropped set trimmed each frame to its own content, which
# left them at sizes between 258x193 and 1592x863. Every frame is cropped to
# the union of all seven here instead, so one TextureRect rect shows any shop
# at the same scale.
#
# Run: uv run extract_store_art
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF

OUT_DIR = REPO_ROOT / "assets" / "ui" / "store" / "backdrops"
STORE_SPRITE = 3036
ZOOM = 4.0
# StoreManager.ZONE_SHOP_IDS selects 0 through 6; the sprite holds each on
# frame id + 1.
SHOP_IDS = range(7)


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed (exit {proc.returncode}): {' '.join(cmd)}\n"
            f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
        )
    return proc


def union_bbox(images):
    """-> the smallest box holding every image's opaque pixels, or None when
    they are all fully transparent."""
    box = None
    for image in images:
        found = image.getchannel("A").getbbox()
        if found is None:
            continue
        box = (
            found
            if box is None
            else (
                min(box[0], found[0]),
                min(box[1], found[1]),
                max(box[2], found[2]),
                max(box[3], found[3]),
            )
        )
    return box


def main():
    work = Path(tempfile.mkdtemp(prefix="store_art_"))
    try:
        run(
            [
                str(FFDEC),
                "-zoom",
                str(ZOOM),
                "-format",
                "sprite:png",
                "-selectid",
                str(STORE_SPRITE),
                "-select",
                ",".join(f"{STORE_SPRITE}:{shop + 1}" for shop in SHOP_IDS),
                "-export",
                "sprite",
                str(work),
                str(WEB_SWF),
            ]
        )
        rendered = work / f"DefineSprite_{STORE_SPRITE}"
        shops = {
            shop: Image.open(rendered / f"{shop + 1}.png").convert("RGBA")
            for shop in SHOP_IDS
        }

        crop = union_bbox(shops.values())
        if crop is None:
            raise RuntimeError("every exported shop frame is fully transparent")

        OUT_DIR.mkdir(parents=True, exist_ok=True)
        for shop, image in sorted(shops.items()):
            cropped = image.crop(crop)
            cropped.save(OUT_DIR / f"shop{shop}.png")
            print(f"shop {shop} <- frame {shop + 1} {cropped.size}", file=sys.stderr)
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
