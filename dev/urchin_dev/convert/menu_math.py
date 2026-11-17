# Run: uv run convert_menu_math
# Writes dev/converted_json/menu_math.json, the numbers the inventory menu's
# element bars are drawn from, the eight element colours, the width of its
# experience bar, and the counts that the victory frame's experience rows
# animate with. The formulas come from
# the menu's script, DefineSprite_3142/frame_1/DoAction.as, the bar width from
# the bar clip's scripts, and the counts from the rows' clip scripts in
# DefineSprite_3142/frame_9. The bar height that the formulas scale, saveH, is
# not in the script: the script reads it from the bar clip at run time, so this
# reads it from the web SWF.
from __future__ import annotations

import json
import re
from pathlib import Path

from urchin_dev import ACTION_SCRIPT, CONVERTED_JSON, WEB_SWF
from urchin_dev.swf import timeline
from urchin_dev.swf.swf_index import SwfIndex, filter_of, read_swf, shape_bounds

SOURCE = "DefineSprite_3142/frame_1/DoAction.as"
# The root script that sets elementColorArray, the colour of each element. The
# menu script colours its bars from it, and so do the Floating numbers.
COLORS_SOURCE = "frame_41/DoAction_2.as"
ELEMENT_COUNT = 8
# The victory frame's three experience rows. Each is a placement of sprite 3002
# with a load and an enterFrame clip script.
ROWS = "DefineSprite_3142/frame_9"
# The Inventory's experience bar, the clip 2867 at depth 1419 of frame 1. Its
# two clip scripts scale its width to the experience.
BAR = "DefineSprite_3142/frame_1/PlaceObject2_2867_1419"
# The layers of one bar, from the bottom up. Each has eight placements in the
# bar block, named ybar0 to ybar7 and so on.
BAR_LAYERS = ("ybar", "bar", "gbar", "xbar")
BAR_COUNT = 8
# The perBarShow clip that holds the piercing bars. defBarShow is a second
# placement of the same sprite, and the script caps both with perBarShow's
# saveH.
BAR_SPRITE = 2877

NUM = r"-?\d+(?:\.\d+)?"
LEVEL = r"_root\.Krin\.LevelStats\[_root\.Krin\.MenuPlayerSelect\]"
POWER = r"\* Math\.pow\(CRITCALC_X \+ 1,{}\)"


def _number(text: str) -> int | float:
    return int(text) if re.fullmatch(r"-?\d+", text) else float(text)


def _signed(sign: str, text: str) -> int | float:
    value = _number(text)
    return -value if sign == "-" else value


def _one(pattern: str, source: str, name: str) -> re.Match:
    found = re.search(pattern, source)
    if found is None:
        raise ValueError(f"{SOURCE}: no statement for {name}")
    return found


def _same(name: str, piercing, defense):
    if piercing != defense:
        raise ValueError(
            f"{SOURCE}: {name} gives {defense}, but the piercing term gives {piercing}"
        )
    return piercing


def _quartic(source: str, name: str) -> list[int | float]:
    """-> the coefficients of (x + 1) to the powers 4, 3, 2, 1 and 0."""
    term = rf"([+-]) ({NUM}) "
    found = _one(
        rf"{name} = ({NUM}) {POWER.format(4)} "
        + term + POWER.format(3) + " "
        + term + POWER.format(2) + " "
        + term + r"\* \(CRITCALC_X \+ 1\) "
        + term.rstrip() + ";",
        source,
        name,
    )  # fmt: skip
    groups = found.groups()
    return [_number(groups[0])] + [
        _signed(groups[i], groups[i + 1]) for i in range(1, len(groups), 2)
    ]


def _gbar_factor(source: str, name: str, value: str) -> int | float:
    found = _one(rf"{name} = ({NUM}) \* \({value}\[wefjnew\] / ", source, name)
    return _number(found.group(1))


def _xbar(source: str, name: str) -> dict[str, int | float]:
    found = _one(rf"{name} = ({NUM}) \* \(CRITCALC_X ([+-]) ({NUM})\);", source, name)
    return {
        "factor": _number(found.group(1)),
        "offset": _signed(found.group(2), found.group(3)),
    }


def _average(source: str) -> dict[str, int | float]:
    """-> the level's average, base + per_level * level. The script writes it
    in five statements (its lines 104, 105, 106, 109 and 155), and all five
    must agree."""
    pairs = set(re.findall(rf"({NUM}) \+ ({NUM}) \* {LEVEL}", source))
    if len(pairs) != 1:
        raise ValueError(f"{SOURCE}: the average is not one formula: {sorted(pairs)}")
    ((base, per_level),) = pairs
    return {"base": _number(base), "per_level": _number(per_level)}


def _value(source: str) -> dict[str, str]:
    """-> how the script rounds the average that it adds to a bar's
    allocation. The bar's value is allocation + rounding(average), and x is
    value / average, with the average not rounded. The piercing and defense
    statements must agree."""
    roundings = []
    for value, sets in (("yut_per2", "PerSets"), ("yut_def2", "DefSets")):
        found = _one(
            rf'{value}\[wefjnew\] = _root\.Krin\["{sets}" \+ '
            r"_root\.Krin\.MenuPlayerSelect\]\[wefjnew\] \+ "
            rf"Math\.(\w+)\({NUM} \+ {NUM} \* {LEVEL}\);",
            source,
            value,
        )
        _one(rf"CRITCALC_X = {value}\[wefjnew\] / AVGNUMC;", source, f"x of {value}")
        roundings.append(found.group(1))
    return {"average_rounding": _same("yut_def2", *roundings)}


def _capped(source: str, clip: str) -> list[str]:
    return re.findall(
        rf'if\({clip}\["(\w+)" \+ wefjnew\]\._height > '
        r'perBarShow\["bar" \+ wefjnew\]\.saveH\)',
        source,
    )


def _defense_tips(source: str) -> dict:
    """-> the DEFTIP index for 1 / x: the default, then each rule in script
    order. A later rule that matches replaces an earlier one."""
    default = _one(r"DEF_FACTOR = (\d+);", source, "DEF_FACTOR")
    _one(r"DEF_CALC_ER = 1 / CRITCALC_X;", source, "DEF_CALC_ER")
    rules = re.findall(
        rf"if\(DEF_CALC_ER ([<>]) ({NUM})\)\s*\{{\s*DEF_FACTOR = (\d+);", source
    )
    if not rules:
        raise ValueError(f"{SOURCE}: no DEF_FACTOR rules")
    return {
        "default": int(default.group(1)),
        "rules": [
            {"compare": compare, "threshold": _number(threshold), "tip": int(tip)}
            for compare, threshold, tip in rules
        ],
    }


def parse_element_bars(source: str) -> dict:
    """-> the element bar formulas from the menu script's text."""
    divisor = _one(
        r'perBarShow\["gbar" \+ wefjnew\]\.saveH = '
        rf'perBarShow\["bar" \+ wefjnew\]\._height / ({NUM});',
        source,
        "the gbar saveH",
    )
    return {
        "average": _average(source),
        "value": _value(source),
        "bar_quartic": _same("nT4", _quartic(source, "nT1"), _quartic(source, "nT4")),
        "gbar": {
            "factor": _same(
                "nT5",
                _gbar_factor(source, "nT2", "yut_per2"),
                _gbar_factor(source, "nT5", "yut_def2"),
            ),
            "divisor": _number(divisor.group(1)),
        },
        "xbar": _same("nT6", _xbar(source, "nT3"), _xbar(source, "nT6")),
        "capped": _same(
            "the defBarShow caps",
            _capped(source, "perBarShow"),
            _capped(source, "defBarShow"),
        ),
        "defense_tips": _defense_tips(source),
    }


def parse_element_colors(source: str) -> list[str]:
    """-> the colour of each element, "#rrggbb", in the order of the elements,
    from the root script's elementColorArray."""
    found = re.search(r"elementColorArray = \[([^\]]*)\];", source)
    if found is None:
        raise ValueError(f"{COLORS_SOURCE}: no elementColorArray")
    colors = []
    for entry in found.group(1).split(","):
        digits = re.fullmatch(r'"0x([0-9A-Fa-f]{6})"', entry.strip())
        if digits is None:
            raise ValueError(
                f"{COLORS_SOURCE}: {entry.strip()} is not a 0xRRGGBB colour"
            )
        colors.append("#" + digits.group(1).lower())
    if len(colors) != ELEMENT_COUNT:
        raise ValueError(
            f"{COLORS_SOURCE}: {len(colors)} element colours, not {ELEMENT_COUNT}"
        )
    return colors


def parse_layer_tints(source: str) -> dict[str, str]:
    """-> what the menu script colours for each bar layer it colours: "inner"
    for the shape inside the layer's clip and "clip" for the clip itself. The
    colour is the bar's element colour, and a layer that is not here is not
    coloured. The piercing and defense blocks must colour the same things."""
    blocks: dict[str, dict[str, str]] = {"perBarShow": {}, "defBarShow": {}}
    pattern = (
        r'new Color\((perBarShow|defBarShow)\["(\w+)" \+ wefjnew\](\.inner)?\);'
        r"\s*my_colorKKCCXX\.setRGB\(([^)]*)\);"
    )
    for block, layer, inner, color in re.findall(pattern, source):
        if color != "_root.elementColorArray[wefjnew]":
            raise ValueError(
                f"{SOURCE}: {block} {layer} is coloured with {color}, not elementColorArray"
            )
        blocks[block][layer] = "inner" if inner else "clip"
    if blocks["perBarShow"] != blocks["defBarShow"]:
        raise ValueError(
            f"{SOURCE}: the piercing and defense blocks colour different layers:"
            f" {blocks['perBarShow']} and {blocks['defBarShow']}"
        )
    return blocks["perBarShow"]


def glow_look(record: bytes) -> dict:
    """-> the Glow that one filter record holds, for a layer's art. The bar
    layers draw an outer Glow with the shape over it, so an inner or knockout
    Glow is refused."""
    glow = filter_of(record)
    if glow.kind != "Glow":
        raise ValueError(f"a bar layer has a {glow.kind}, not a Glow")
    if glow.inner or glow.knockout:
        raise ValueError("a bar layer has an inner or knockout Glow")
    red, green, blue, alpha = glow.color
    return {
        "color": f"#{red:02x}{green:02x}{blue:02x}",
        "alpha": alpha / 255,
        "blur_x": glow.blur_x,
        "blur_y": glow.blur_y,
        "strength": glow.strength,
        "passes": glow.passes,
        "composite_source": glow.composite_source,
    }


def layer_look(
    placed: list[timeline.Layer], name: str, tint: str | None, glow: bytes | None
) -> dict:
    """-> how one bar layer is drawn. `placed` holds its eight placements in
    the bar block, which must agree. The layer's colour transform multiplies
    each colour channel by multiplier and then adds `add`, and the transform
    never changes alpha."""
    if len(placed) != BAR_COUNT:
        raise ValueError(f"{name}: {len(placed)} placements, not {BAR_COUNT}")
    transforms = {layer.color_transform for layer in placed}
    if len(transforms) != 1:
        raise ValueError(f"{name}: the eight bars are placed with {transforms}")
    (transform,) = transforms
    if transform is None:
        transform = (256, 256, 256, 256, 0, 0, 0, 0)
    red, green, blue, alpha, add_red, add_green, add_blue, add_alpha = transform
    if len({red, green, blue}) != 1 or len({add_red, add_green, add_blue}) != 1:
        raise ValueError(f"{name}: the colour transform {transform} tints one channel")
    if alpha != 256 or add_alpha != 0:
        raise ValueError(f"{name}: the colour transform {transform} changes alpha")
    return {
        "tint": tint,
        "multiplier": red / 256,
        "add": add_red / 255,
        "glow": glow_look(glow) if glow is not None else None,
    }


def bar_layers(index: SwfIndex, owner: int, tints: dict[str, str]) -> dict:
    """-> layer_look() of each layer of the bar block `owner`. A layer's Glow
    is on the "inner" clip that its sprite holds."""
    first = timeline.frames(index, owner)[0]
    looks = {}
    for name in BAR_LAYERS:
        placed = [
            layer
            for layer in first.values()
            if layer.name in (f"{name}{k}" for k in range(BAR_COUNT))
        ]
        sprites = {layer.character_id for layer in placed}
        if len(sprites) != 1:
            raise ValueError(f"{name}: placed as sprites {sprites}")
        inner = _layer(index, sprites.pop(), "inner")
        if len(inner.filter_records) > 1:
            raise ValueError(f"{name}: more than one filter")
        glow = inner.filter_records[0] if inner.filter_records else None
        looks[name] = layer_look(placed, name, tints.get(name), glow)
    return looks


def _victory_row(load: str, enter_frame: str) -> dict:
    """-> the counts of one victory experience row's two clip scripts."""
    frames = _one(r"setLimiter = (?:sLmT2 = )?(\d+);", load, "setLimiter")
    _one(r"adderPer = _root\.Krin\.totalXP / setLimiter;", load, "adderPer")
    cap = _one(
        r"if\(_root\.Krin\.LevelStats\[prx\] < (\d+)\)", enter_frame, "the level cap"
    )
    scaled = _one(rf"bar\._width = exp / 100 \* ({NUM});", enter_frame, "bar_width")
    full = _one(rf"bar\._width = ({NUM});", enter_frame, "the full bar_width")
    return {
        "frames": int(frames.group(1)),
        "bar_width": _same(
            "bar_width", _number(scaled.group(1)), _number(full.group(1))
        ),
        "level_cap": int(cap.group(1)),
    }


def parse_victory_rows(rows: list[tuple[str, str]]) -> dict:
    """-> the frame count, the full bar width and the level cap of the victory
    experience rows. rows holds the load and enterFrame scripts of each row,
    and every row must give the same numbers."""
    first, *others = [_victory_row(load, enter) for load, enter in rows]
    for other in others:
        for name, value in first.items():
            if other[name] != value:
                raise ValueError(
                    f"{ROWS}: the rows disagree on {name}: {value} and {other[name]}"
                )
    return first


def parse_experience_bar(load: str, enter_frame: str) -> dict:
    """-> the width of the Inventory's full experience bar, from the load and
    enterFrame scripts of the bar clip. Both scale the clip's _width to the
    experience, and they must agree."""
    pattern = (
        r"_width = _root\.Krin\.ExpSets\[_root\.Krin\.MenuPlayerSelect\]"
        rf" / 100 \* ({NUM});"
    )
    widths = []
    for name, script in (("load", load), ("enterFrame", enter_frame)):
        found = re.search(pattern, script)
        if found is None:
            raise ValueError(f"{BAR}: the {name} script does not scale the width")
        widths.append(_number(found.group(1)))
    if widths[0] != widths[1]:
        raise ValueError(f"{BAR}: the width is {widths[0]} on load and {widths[1]}")
    return {"width": widths[0]}


def _row_scripts(action_script: Path) -> list[tuple[str, str]]:
    folders = sorted((action_script / ROWS).glob("PlaceObject3_3002_*"))
    if len(folders) != 3:
        raise ValueError(f"{ROWS}: {len(folders)} experience rows, not 3")
    return [
        (
            (folder / "CLIPACTIONRECORD onClipEvent(load).as").read_text("utf-8"),
            (folder / "CLIPACTIONRECORD onClipEvent(enterFrame).as").read_text("utf-8"),
        )
        for folder in folders
    ]


def _layer(index: SwfIndex, owner: int, name: str | None) -> timeline.Layer:
    layers = timeline.frames(index, owner)[0].values()
    found = [layer for layer in layers if name is None or layer.name == name]
    if len(found) != 1:
        raise ValueError(f"sprite {owner}: {len(found)} layers match {name!r}")
    return found[0]


def _scale_y(layer: timeline.Layer) -> float:
    """-> the layer's y scale. A rotated or skewed layer is refused, because
    its height then depends on the shape's width too."""
    if layer.matrix[1] != 0 or layer.matrix[2] != 0:
        raise ValueError(f"character {layer.character_id} is placed rotated or skewed")
    return layer.matrix[3]


def bar_save_height(index: SwfIndex, owner: int) -> float:
    """-> the _height of the bar0 clip in sprite owner, in px. The script
    stores it as saveH before it resizes the bar. The clip holds "inner",
    which holds the bar shape, and each step can scale it."""
    scale = 1.0
    layer = _layer(index, owner, "bar0")
    for name in ("inner", None):
        scale *= _scale_y(layer)
        layer = _layer(index, layer.character_id, name)
    scale *= _scale_y(layer)
    _xmin, ymin, _xmax, ymax = shape_bounds(index, layer.character_id)
    # Flash keeps a clip's bounds in whole twips, and 20 twips are 1 px.
    return round((ymax - ymin) * scale) / 20


def convert(action_script: Path, index: SwfIndex) -> dict:
    bars = {"source": SOURCE, "save_height": bar_save_height(index, BAR_SPRITE)}
    script = (action_script / SOURCE).read_text("utf-8")
    bars.update(parse_element_bars(script))
    bars["layers"] = bar_layers(index, BAR_SPRITE, parse_layer_tints(script))
    # The rows step once a frame, so they run at the SWF's frame rate.
    rows = {"source": f"{ROWS}/PlaceObject3_3002_*", "frame_rate": index.frame_rate}
    rows.update(parse_victory_rows(_row_scripts(action_script)))
    folder = action_script / BAR
    bar = {"source": f"{BAR}/CLIPACTIONRECORD onClipEvent(*)"}
    bar.update(
        parse_experience_bar(
            (folder / "CLIPACTIONRECORD onClipEvent(load).as").read_text("utf-8"),
            (folder / "CLIPACTIONRECORD onClipEvent(enterFrame).as").read_text("utf-8"),
        )
    )
    colors = {
        "source": COLORS_SOURCE,
        "colors": parse_element_colors(
            (action_script / COLORS_SOURCE).read_text("utf-8")
        ),
    }
    return {
        "element_bars": bars,
        "element_colors": colors,
        "experience_bar": bar,
        "victory_rows": rows,
    }


def main() -> None:
    output = CONVERTED_JSON / "menu_math.json"
    math = convert(ACTION_SCRIPT, read_swf(WEB_SWF))
    output.write_text(json.dumps(math, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {output}")


if __name__ == "__main__":
    main()
