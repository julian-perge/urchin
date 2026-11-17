# The seven white icons of the Hub's hotbar as zoom 5 art, with the hover Glow
# of each as data, from the root frame Navigation:
#
#   assets/ui/hotbar/<icon>.png        - one trimmed render per icon
#   assets/ui/hotbar/hotbar_icons.json - each icon's Stage rect, the Glows of
#                                        every frame of its hover clip, and the
#                                        hover's frame ranges
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
# sprite's placement, and every frame carries its own copy: the strength grows
# over START and falls over STOP on every icon, and the blur and the colour
# change with it on most. Frame 1 has strength 0, so the icon is rendered with
# its clip on frame 1 and comes out with no Glow. "frames" in the record holds
# the filter list of every frame of the clip, frame 1 first, and the port
# shows the list of the frame the game would be on. Each Glow has its colour,
# its strength, its blur as the width of the box in Stage px, and "inner",
# which is true for a Glow that Flash draws inside the icon's shape and over
# it. Where an icon has two Glows, the first is the small one, and it is an
# inner Glow on some frames and an outer one on others.
#
# WORLD MAP has one GradientGlow in place of the Glows. "gradient" holds its
# stops in place of a colour, lowest ratio first. A GradientGlow colours each
# pixel by the blurred alpha there, so the ratio 0 stop is the outer edge of
# the glow and the ratio 255 stop is at the icon.
#
# Run: uv run extract_hotbar_icons
from __future__ import annotations

import json
import struct
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


def glow_values(record: bytes) -> dict:
    """-> the colour or the gradient stops, the blur, the strength and the
    inner flag of one Glow or GradientGlow record. Raises on a Glow the port's
    shader does not draw: one that is not opaque, has two blur values, blurs
    more than once, knocks the icon out, or is a GradientGlow that is moved,
    drawn on top or not from ratio 0 to ratio 255."""
    if record[0] == FILTER_GLOW:
        if record[4] != 255:
            raise ValueError(f"the Glow colour has alpha {record[4]}, not 255")
        values = {"color": _hex(*record[1:4])}
        blurs, tail = 5, 13
    else:
        stops = gradient_stops(record)
        if [stop["ratio"] for stop in stops] != [0, 255]:
            raise ValueError(f"the GradientGlow stops {stops} are not at 0 and 255")
        values = {"gradient": stops}
        blurs = 2 + 5 * record[1]
        tail = blurs + 16
        if struct.unpack_from("<i", record, blurs + 12)[0]:
            raise ValueError("the GradientGlow has a distance")
    blur_x, blur_y = struct.unpack_from("<ii", record, blurs)
    (strength,) = struct.unpack_from("<h", record, tail)
    flags = record[tail + 2]
    if blur_x != blur_y:
        raise ValueError(f"the blurs {blur_x / 65536} and {blur_y / 65536} differ")
    if flags & 0x40 or not flags & 0x20:
        raise ValueError(f"flags {flags:08b} knock the icon out or leave it out")
    if flags & 0x1F != 1:
        raise ValueError(f"flags {flags:08b} are not one blur pass under the icon")
    return {
        **values,
        "blur": round(blur_x / 65536, 4),
        "strength": round(strength / 256, 4),
        "inner": bool(flags & 0x80),
    }


def glow_record(records: tuple[bytes, ...]) -> list[dict]:
    """-> glow_values() of each filter of one list from Layer.filter_records.
    Raises on any list that is neither Glows only nor one GradientGlow."""
    kinds = [record[0] for record in records]
    if set(kinds) != {FILTER_GLOW} and kinds != [FILTER_GRADIENT_GLOW]:
        raise ValueError(f"filter ids {kinds} are not Glows or one GradientGlow")
    return [glow_values(record) for record in records]


def hover_frames(index: SwfIndex, sprite: int) -> list[list[dict]]:
    """-> glow_record() of the one depth the icon clip shows, for each of its
    frames. Raises when a frame has another number of Glows than frame 1,
    because the port makes its layers once."""
    result = []
    for number, layers in enumerate(timeline.frames(index, sprite), 1):
        if len(layers) != 1:
            raise ValueError(
                f"sprite {sprite} frame {number} shows {len(layers)} depths"
            )
        (layer,) = layers.values()
        glows = glow_record(layer.filter_records)
        if result and len(glows) != len(result[0]):
            raise ValueError(
                f"sprite {sprite} frame {number} has {len(glows)} Glows, and"
                f" frame 1 has {len(result[0])}"
            )
        result.append(glows)
    return result


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
            "frames": hover_frames(index, sprite),
            "rect": [round(v, 4) for v in cut.rect],
            "size": list(cut.image.size),
            "zoom": job.zoom,
        }
        held = icons[icon]["frames"][hover["start"][1] - 1]
        print(f"{icon} {icons[icon]['rect']} {held}", file=sys.stderr)
    record = {"hover": {"frame_rate": index.frame_rate, **hover}, "icons": icons}
    RECORD.write_text(json.dumps(record, indent=1, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
