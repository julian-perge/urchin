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
# The union rect is where the shared crop sits on the Stage, in design px, so a
# TextureRect and the rect test read it from the record instead of placing the
# art by hand:
#
#   assets/ui/store/backdrops/store_art.json
#
# Run: uv run extract_store_art
from __future__ import annotations

import json
import sys

from urchin_dev import REPO_ROOT, WEB_SWF, png
from urchin_dev.swf import render
from urchin_dev.swf.extract import window_chrome
from urchin_dev.swf.swf_index import SwfIndex, read_swf

OUT_DIR = REPO_ROOT / "assets" / "ui" / "store" / "backdrops"
RECORD = OUT_DIR / "store_art.json"
STORE_SPRITE = 3036
ZOOM = 4.0
# StoreManager.ZONE_SHOP_IDS selects 0 through 6; the sprite holds each on
# frame id + 1.
SHOP_IDS = range(7)


def stage_origin(index: SwfIndex) -> tuple[float, float]:
    """-> where the Stage places the keeper sprite's own (0, 0): the Hub frame
    places KRINMENU, and KRINMENU's `shop` frame places the sprite."""
    menu = render.placement_origin(
        index, 0, window_chrome.hub_frame(index), window_chrome.KRINMENU
    )
    inside = render.placement_origin(
        index, window_chrome.KRINMENU, window_chrome.SHOP_FRAME, STORE_SPRITE
    )
    return menu[0] + inside[0], menu[1] + inside[1]


def record_of(cut: render.Trimmed, zoom: float) -> dict:
    """-> the record of the union crop: its Stage rect (x, y, w, h), the PNG
    size and the zoom. Raises when the rect times the zoom is not the size."""
    rect = [round(v, 4) for v in cut.rect]
    size = list(cut.image.size)
    if (round(rect[2] * zoom), round(rect[3] * zoom)) != tuple(size):
        raise ValueError(
            f"rect {rect[2]}x{rect[3]} at zoom {zoom} is not the {size[0]}x{size[1]} image"
        )
    return {"rect": rect, "relative_to": "stage", "size": size, "zoom": zoom}


def main():
    origin = stage_origin(read_swf(WEB_SWF))
    jobs = [
        render.Job(STORE_SPRITE, shop + 1, ZOOM, origin=origin) for shop in SHOP_IDS
    ]
    with render.frames(WEB_SWF, jobs) as rendered:
        shops = render.trim_union(rendered)
    if shops is None:
        raise RuntimeError("every exported shop frame is fully transparent")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for shop, cropped in zip(SHOP_IDS, shops, strict=True):
        png.save(cropped.image, OUT_DIR / f"shop{shop}.png")
        print(f"shop {shop} <- frame {shop + 1} {cropped.image.size}", file=sys.stderr)
    record = record_of(shops[0], ZOOM)
    if any(record_of(cropped, ZOOM) != record for cropped in shops):
        raise RuntimeError("the seven shop crops do not share one rect")
    RECORD.write_text(json.dumps(record, indent=1, sort_keys=True) + "\n")
    print(f"union rect {record['rect']}", file=sys.stderr)


if __name__ == "__main__":
    main()
