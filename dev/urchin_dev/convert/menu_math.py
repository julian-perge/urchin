# Run: uv run convert_menu_math
# Writes dev/converted_json/menu_math.json, the numbers the inventory menu's
# element bars are drawn from. The formulas come from the menu's script,
# DefineSprite_3142/frame_1/DoAction.as. The bar height that the formulas
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


def _layer(index: SwfIndex, owner: int, name: str | None) -> timeline.Layer:
    layers = timeline.frames(index, owner)[0].values()
    found = [layer for layer in layers if name is None or layer.name == name]
    if len(found) != 1:
        raise ValueError(f"sprite {owner}: {len(found)} layers match {name!r}")
    return found[0]


def bar_save_height(index: SwfIndex, owner: int) -> float:
    """-> the _height of the bar0 clip in sprite owner, in px. The script
    stores it as saveH before it resizes the bar. The clip holds "inner",
    which holds the bar shape, and each step can scale it."""
    scale = 1.0
    layer = _layer(index, owner, "bar0")
    for name in ("inner", None):
        scale *= layer.matrix[3]
        layer = _layer(index, layer.character_id, name)
    scale *= layer.matrix[3]
    _xmin, ymin, _xmax, ymax = shape_bounds(index, layer.character_id)
    # Flash keeps a clip's bounds in whole twips, and 20 twips are 1 px.
    return round((ymax - ymin) * scale) / 20


def convert(script: Path, index: SwfIndex) -> dict:
    bars = {"source": SOURCE, "save_height": bar_save_height(index, BAR_SPRITE)}
    bars.update(parse_element_bars(script.read_text(encoding="utf-8")))
    return {"element_bars": bars}


def main() -> None:
    output = CONVERTED_JSON / "menu_math.json"
    math = convert(ACTION_SCRIPT / SOURCE, read_swf(WEB_SWF))
    output.write_text(json.dumps(math, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {output}")


if __name__ == "__main__":
    main()
