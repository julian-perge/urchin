# The seven white icons of the Hub's hotbar as zoom 5 art, with the hover Glow
# of each as data, from the root frame Navigation:
#
#   assets/ui/hotbar/<icon>.png        - one trimmed render per icon
#   assets/ui/hotbar/hotbar_icons.json - each icon's Stage rect and Glow
#                                        colours, and the hover's frame ranges
#
# THE ICONS are the clips the hub places with the instance names ui_but1 to
# ui_but7. Each clip holds one inner sprite at one depth, and that sprite holds
# the white shape. The root frame is rendered with only the icon's depth kept,
# so each rect is in Stage design px, and the rect times the zoom is the PNG's
# pixel size. Quit has no icon: its red square is extract_window_chrome's
# hotbar_quit_red.
#
# THE HOVER is the clip's own timeline. The game plays the clip from its START
# label on roll over and from its STOP label on roll out, and each run ends on
# the next frame whose script runs stop(). The Glow is a filter on the inner
# sprite's placement, and every frame carries its own copy: the colour, the
# blur and the strength all grow over START and fall over STOP. Frame 1 has
# strength 0, so the icon is rendered with its clip on frame 1 and comes out
# with no Glow. The "glow" colours in the record are those of the last frame
# of START, where the hover is at full strength, in the order of the filter
# list. Where an icon has two, the first is the inner Glow.
#
# WORLD MAP has one GradientGlow in place of the Glows. "gradient" holds its
# stops, lowest ratio first. A GradientGlow colours each pixel by the blurred
# alpha there, so the ratio 0 stop is the outer edge of the glow and the ratio
# 255 stop is at the icon. The port's hover takes one colour, and "glow" holds
# the ratio 0 stop for it, as #218 chose. That stop has alpha 0 in the SWF, so
# whether it is the right one colour is a guess to check against the game.
#
# Run: uv run extract_hotbar_icons
from __future__ import annotations

import json
import sys

from urchin_dev import REPO_ROOT, WEB_SWF, png
from urchin_dev.swf import render, timeline
from urchin_dev.swf.swf_index import SwfIndex, read_swf

OUT_DIR = REPO_ROOT / "assets" / "ui" / "hotbar"
RECORD = OUT_DIR / "hotbar_icons.json"
ZOOM = 5.0

HUB_FRAME = "Navigation"
FILTER_GLOW = 2
FILTER_GRADIENT_GLOW = 4

# Each icon's file name and the instance name the hub frame places it with.
ICONS: dict[str, str] = {
    "inventory": "ui_but1",
    "abilities": "ui_but2",
    "save": "ui_but3",
    "options": "ui_but4",
    "respec": "ui_but5",
    "world_map": "ui_but6",
    "achievements": "ui_but7",
}


def placements(index: SwfIndex) -> dict[str, tuple[int, timeline.Layer]]:
    """-> (depth, layer) on the hub frame for each icon in ICONS. Raises unless
    the frame places each instance name exactly once."""
    hub = timeline.frames(index, 0)[timeline.frame_of(index, 0, HUB_FRAME) - 1]
    result = {}
    for icon, instance in ICONS.items():
        placed = [
            (depth, layer) for depth, layer in hub.items() if layer.name == instance
        ]
        if len(placed) != 1:
            raise ValueError(f"the hub frame places {instance} {len(placed)} times")
        result[icon] = placed[0]
    return result


def jobs(index: SwfIndex) -> dict[str, render.Job]:
    """-> the render job for each icon in ICONS, in that order."""
    hub = timeline.frame_of(index, 0, HUB_FRAME)
    return {
        icon: render.Job(0, hub, ZOOM, only_depths=(depth,), goto=((depth, 1),))
        for icon, (depth, _layer) in placements(index).items()
    }


def hover_ranges(index: SwfIndex, sprite: int) -> dict[str, list[int]]:
    """-> the first and last frame of the clip's START run and of its STOP
    run. A run ends on the first frame from its label on that runs stop()."""
    labels = timeline.labels(index, sprite)
    result = {}
    for label in ("START", "STOP"):
        first = labels[label]
        last = next(
            (
                frame
                for frame in range(first, index.sprite_frames[sprite] + 1)
                if render.runs_stop(index, sprite, frame)
            ),
            None,
        )
        if last is None:
            raise ValueError(f"sprite {sprite} never stops after its {label} label")
        result[label.lower()] = [first, last]
    return result


def _hex(red: int, green: int, blue: int) -> str:
    return f"#{red:02x}{green:02x}{blue:02x}"


def gradient_stops(record: bytes) -> list[dict]:
    """-> the stops of one GradientGlow record, lowest ratio first. The record
    holds its id, the stop count, every stop's RGBA and then every stop's
    ratio."""
    count = record[1]
    ratios = record[2 + 4 * count : 2 + 5 * count]
    stops = []
    for n, ratio in enumerate(ratios):
        red, green, blue, alpha = record[2 + 4 * n : 6 + 4 * n]
        stops.append({"alpha": alpha, "color": _hex(red, green, blue), "ratio": ratio})
    return sorted(stops, key=lambda stop: stop["ratio"])


def glow_record(records: tuple[bytes, ...]) -> dict:
    """-> the "glow" colours of one filter list from Layer.filter_records, and
    the "gradient" stops when the list is one GradientGlow. Raises on any list
    that is neither Glows only nor one GradientGlow."""
    kinds = [record[0] for record in records]
    if kinds and set(kinds) == {FILTER_GLOW}:
        return {"glow": [_hex(*record[1:4]) for record in records]}
    if kinds == [FILTER_GRADIENT_GLOW]:
        stops = gradient_stops(records[0])
        return {"glow": [stops[0]["color"]], "gradient": stops}
    raise ValueError(f"filter ids {kinds} are not Glows or one GradientGlow")


def hover_glow(index: SwfIndex, sprite: int, frame: int) -> dict:
    """-> glow_record() of the one depth the icon clip shows on `frame`."""
    layers = timeline.frames(index, sprite)[frame - 1]
    if len(layers) != 1:
        raise ValueError(f"sprite {sprite} frame {frame} shows {len(layers)} depths")
    (layer,) = layers.values()
    return glow_record(layer.filter_records)


def main():
    index = read_swf(WEB_SWF)
    placed = placements(index)
    by_icon = jobs(index)

    ranges = {
        icon: hover_ranges(index, layer.character_id)
        for icon, (_d, layer) in placed.items()
    }
    hover = ranges["inventory"]
    different = sorted(icon for icon, found in ranges.items() if found != hover)
    if different:
        raise RuntimeError(f"{different} do not share inventory's hover ranges {hover}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    icons = {}
    with render.frames(WEB_SWF, list(by_icon.values())) as rendered:
        cuts = [render.trim(frame) for frame in rendered]
    for (icon, job), cut in zip(by_icon.items(), cuts, strict=True):
        if cut is None:
            raise RuntimeError(f"{icon} rendered fully transparent")
        png.save(cut.image, OUT_DIR / f"{icon}.png")
        sprite = placed[icon][1].character_id
        icons[icon] = {
            **hover_glow(index, sprite, hover["start"][1]),
            "rect": [round(v, 4) for v in cut.rect],
            "size": list(cut.image.size),
            "zoom": job.zoom,
        }
        print(f"{icon} {icons[icon]['rect']} {icons[icon]['glow']}", file=sys.stderr)
    record = {"hover": {"frame_rate": index.frame_rate, **hover}, "icons": icons}
    RECORD.write_text(json.dumps(record, indent=1, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
