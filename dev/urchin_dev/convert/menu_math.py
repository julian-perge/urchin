# Run: uv run convert_menu_math
# Writes dev/converted_json/menu_math.json, the numbers the inventory menu's
# element bars are drawn from, and the counts that the victory frame's
# experience rows animate with. The formulas come from the menu's script,
# DefineSprite_3142/frame_1/DoAction.as, and the counts from the rows' clip
# scripts in DefineSprite_3142/frame_9. The bar height that the formulas
# scale, saveH, is not in the script: the script reads it from the bar clip
# at run time, so this reads it from the web SWF.
from __future__ import annotations

import json
import re
from pathlib import Path

from urchin_dev import ACTION_SCRIPT, CONVERTED_JSON, WEB_SWF
from urchin_dev.swf import timeline
from urchin_dev.swf.swf_index import SwfIndex, read_swf, shape_bounds

SOURCE = "DefineSprite_3142/frame_1/DoAction.as"
# The victory frame's three experience rows. Each is a placement of sprite 3002
# with a load and an enterFrame clip script.
ROWS = "DefineSprite_3142/frame_9"
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
    in four statements, and all four must agree."""
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
    bars.update(parse_element_bars((action_script / SOURCE).read_text("utf-8")))
    # The rows step once a frame, so they run at the SWF's frame rate.
    rows = {"source": f"{ROWS}/PlaceObject3_3002_*", "frame_rate": index.frame_rate}
    rows.update(parse_victory_rows(_row_scripts(action_script)))
    return {"element_bars": bars, "victory_rows": rows}


def main() -> None:
    output = CONVERTED_JSON / "menu_math.json"
    math = convert(ACTION_SCRIPT, read_swf(WEB_SWF))
    output.write_text(json.dumps(math, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {output}")


if __name__ == "__main__":
    main()
