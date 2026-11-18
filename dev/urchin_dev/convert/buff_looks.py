# What a unit's buffs do to the look of its doll in the original. Output:
# dev/converted_json/buff_looks.json.
#
# applyChangesKrin (frame_42/DoAction_10.as) counts the buffs of each visual
# filter index in the unit's FILTERSBUFFARRAY. Then it runs one `if` for each
# index it knows, in a fixed order, and each `if` that finds a buff of its index
# sets a color state, a filter list or a form, so the last one to run wins. This
# reads those `if`s in the order they run:
#
#   color_by_index   [[index, color name], ...], and default_color
#   filter_by_index  [[index, filter name], ...], and default_filter
#
# krinChangeColor (frame_42/DoAction_3.as) turns a color name into a
# ColorTransform whose three offsets (red, green, blue, each -255 to 255) it
# adds to the doll's color. The same script builds each filter list from
# GlowFilters made as GlowFilter(color, alpha, blurX, blurY, strength, quality,
# inner, knockout). The JSON holds both:
#
#   colors   {color name: [red, green, blue]}
#   filters  {filter name: [glow, ...]}, a glow being a dictionary of those
#            arguments, in the order the list pushes them
#
# CharacterVisual draws them (scenes/doll_body.gdshader), which draws a glow of
# full alpha, one pass and a square blur. read_looks() raises on one that differs.
#
# Run: uv run convert_buff_looks
from __future__ import annotations

import json
import re

from urchin_dev import ACTION_SCRIPT, CONVERTED_JSON

FRAME_42 = ACTION_SCRIPT / "frame_42"
COLORS_SCRIPT = FRAME_42 / "DoAction_3.as"
APPLY_SCRIPT = FRAME_42 / "DoAction_10.as"
OUTPUT = CONVERTED_JSON / "buff_looks.json"

COLOR_BLOCK = re.compile(r'if\(colorType == "(\w+)"\)\s*\{(.*?)\n\s*\}', re.DOTALL)
OFFSET = re.compile(r"\.(red|green|blue)Offset = (-?\d+);")
GLOW = re.compile(r"var (\w+) = new flash\.filters\.GlowFilter\(([^)]*)\);")
LIST_DECLARATION = re.compile(r"var KrinFilter(\w+) = new Array\(\);")
LIST_PUSH = re.compile(r"KrinFilter(\w+)\.push\((\w+)\);")
DEFAULT = re.compile(r'statusOf([CF]) = (?:"(\w+)"|KrinFilter(\w+));')
STATE = re.compile(
    r"if\(ukcb\.FILTERSBUFFARRAY\[(\d+)\] > 0\)\s*\{\s*"
    r'statusOf([CFM]) = (?:"(\w+)"|KrinFilter(\w+));\s*\}'
)
APPLY_FUNCTION = re.compile(r"function applyChangesKrin\(.*?\n\}", re.DOTALL)


def _number(text: str) -> int | float:
    value = float(text)
    return int(value) if value == int(value) else round(value, 4)


def read_colors(text: str) -> dict[str, list[int]]:
    colors: dict[str, list[int]] = {}
    for name, body in COLOR_BLOCK.findall(text):
        offsets = dict(OFFSET.findall(body))
        if set(offsets) != {"red", "green", "blue"}:
            raise ValueError(f"color {name!r} sets offsets {sorted(offsets)}")
        colors[name] = [int(offsets[channel]) for channel in ("red", "green", "blue")]
    return colors


def read_glows(text: str) -> dict[str, dict]:
    glows: dict[str, dict] = {}
    for name, arguments in GLOW.findall(text):
        color, alpha, blur_x, blur_y, strength, quality, inner, knockout = (
            part.strip() for part in arguments.split(",")
        )
        glows[name] = {
            "color": f"{int(color):06x}",
            "alpha": _number(alpha),
            "blur_x": _number(blur_x),
            "blur_y": _number(blur_y),
            "strength": _number(strength),
            "quality": int(quality),
            "inner": inner == "true",
            "knockout": knockout == "true",
        }
    return glows


def check_drawable(name: str, glow: dict) -> None:
    """doll_body.gdshader draws a glow of full alpha, one pass and a square
    blur, so raise on one that differs."""
    if glow["alpha"] != 1 or glow["quality"] != 1 or glow["blur_x"] != glow["blur_y"]:
        raise ValueError(
            f"KrinFilter{name} holds a glow the shader cannot draw: {glow}"
        )


def read_filter_lists(text: str) -> dict[str, list[str]]:
    """-> {list name: the names of what it pushes}. Some lists push a BlurFilter,
    so the names are looked up in read_glows() only for the lists a state uses."""
    lists: dict[str, list[str]] = {name: [] for name in LIST_DECLARATION.findall(text)}
    for name, pushed in LIST_PUSH.findall(text):
        if name in lists:
            lists[name].append(pushed)
    return lists


def read_looks(colors_text: str, apply_text: str) -> dict:
    """Read the colors and filters from the script of krinChangeColor and the
    filter lists, and the state lists from the script of applyChangesKrin. A
    state that names a color or a filter the first script lacks raises
    ValueError."""
    colors = read_colors(colors_text)
    lists = read_filter_lists(colors_text)
    glows = read_glows(colors_text)
    function = APPLY_FUNCTION.search(apply_text)
    if function is None:
        raise ValueError("no applyChangesKrin")
    body = function.group(0)
    # The first assignment of each state is the one before any `if`.
    defaults: dict[str, str] = {}
    for kind, color, filter_ in DEFAULT.findall(body):
        defaults.setdefault(kind, color or filter_)
    by_index: dict[str, list[list]] = {"C": [], "F": []}
    for index, kind, color, filter_ in STATE.findall(body):
        if kind == "M":
            continue
        name = color or filter_
        if kind == "C" and name not in colors:
            raise ValueError(f"index {index} sets the unknown color {name!r}")
        if kind == "F" and name not in lists:
            raise ValueError(f"index {index} sets the unknown filter KrinFilter{name}")
        by_index[kind].append([int(index), name])
    for name in {name for _, name in by_index["F"]} | {defaults["F"]}:
        for glow in lists[name]:
            check_drawable(name, glows[glow])
    used_colors = {defaults["C"]} | {name for _, name in by_index["C"]}
    used_filters = {defaults["F"]} | {name for _, name in by_index["F"]}
    return {
        "colors": {name: colors[name] for name in sorted(used_colors)},
        "color_by_index": by_index["C"],
        "default_color": defaults["C"],
        "filters": {
            name: [glows[glow] for glow in lists[name]] for name in sorted(used_filters)
        },
        "filter_by_index": by_index["F"],
        "default_filter": defaults["F"],
    }


def main() -> None:
    looks = read_looks(
        COLORS_SCRIPT.read_text(encoding="utf-8"),
        APPLY_SCRIPT.read_text(encoding="utf-8"),
    )
    OUTPUT.write_text(
        json.dumps(looks, indent=2) + "\n", encoding="utf-8", newline="\n"
    )
    print(
        f"Wrote {len(looks['colors'])} colors and {len(looks['filters'])} filters to"
        f" {OUTPUT}"
    )


if __name__ == "__main__":
    main()
