# The look of the shared tooltip, KrinToolTipper (DefineSprite 2717), which
# scripts/ui/tooltip_theme.gd and scripts/ui/game_tooltip.gd read:
#
#   dev/converted_json/tooltip_look.json
#
# From the SWF: the frame rate, the gradient of the title backer (sprite 2715,
# shape 2714), the fill of the body backer (sprite 2716, shape 68), and the
# colour transforms that sprite 2717's timeline gives fontBacker3 and
# fontBacker4 at each layout label.
#
# From the AS export: the add terms that krinChangeColor gives each rarity,
# each layout's field width and its offsets from the mouse, how many frames
# the ability icon shows the title alone, the texts of the pass button's
# tooltip in each mode, before and after a pick, and the share of the price
# that the sell slot names and pays.
# spec/107-tooltips.md describes each one.
#
# Run: uv run extract_tooltip_look
from __future__ import annotations

import json
import re
import sys

from urchin_dev import ACTION_SCRIPT, CONVERTED_JSON, WEB_SWF
from urchin_dev.swf.swf_index import (
    SwfIndex,
    first_fill_color,
    first_gradient,
    read_swf,
    shape_bounds,
)

OUTPUT = CONVERTED_JSON / "tooltip_look.json"

TOOLTIP = 2717
GLOSS_BACKER = 2715
BODY_BACKER = 2716
# The labels whose frame scripts build text fields. GO5 only removes the stat
# lines and goes to GO4 (DefineSprite_2717/frame_16/DoAction.as).
LAYOUTS = ("GO", "GO2", "GO3", "GO4", "GO7")
# The names krinChangeColor gives an item rarity. Its other names tint other
# clips.
RARITIES = ("Common", "Uncommon", "Rare", "Orange", "Unique")

CHANGE_COLOR_SCRIPT = ACTION_SCRIPT / "frame_42" / "DoAction_3.as"
ICON_SCRIPT = (
    ACTION_SCRIPT
    / "DefineSprite_2427"
    / "frame_1"
    / "PlaceObject2_2241_11"
    / "CLIPACTIONRECORD onClipEvent(enterFrame).as"
)
PASS_SCRIPT = (
    ACTION_SCRIPT
    / "frame_217"
    / "PlaceObject2_2427_484"
    / "CLIPACTIONRECORD onClipEvent(load).as"
)

# addMoveForPlayer, which sets krinToMove's tooltip when the player picks.
PICK_SCRIPT = ACTION_SCRIPT / "frame_42" / "DoAction_11.as"

SELL_SCRIPTS = ACTION_SCRIPT / "DefineButton2_3015"
SELL_ROLL_OVER = SELL_SCRIPTS / "BUTTONCONDACTION on(rollOver).as"
SELL_PRESS = SELL_SCRIPTS / "BUTTONCONDACTION on(press).as"

IDENTITY_MULTIPLY = (256, 256, 256, 256)


def one(pattern: str, text: str, where: str, flags: int = 0):
    """-> the one match of `pattern` in `text`. Raises unless there is one."""
    found = re.findall(pattern, text, flags)
    if len(found) != 1:
        raise ValueError(f"{where}: {len(found)} matches of {pattern}, want 1")
    return found[0]


def rarity_add(script: str) -> dict[str, list[int]]:
    """-> the red, green and blue add terms of each rarity in krinChangeColor.
    Raises when a rarity has no block, or a block does not set each term
    once."""
    blocks = dict(
        re.findall(r'if\(colorType == "(\w+)"\)\s*\{(.*?)\n   \}', script, re.DOTALL)
    )
    terms = {}
    for name in RARITIES:
        if name not in blocks:
            raise ValueError(f"krinChangeColor has no {name} block")
        terms[name] = [
            int(one(rf"\.{channel}Offset = (-?\d+);", blocks[name], name))
            for channel in ("red", "green", "blue")
        ]
    return terms


def layout(script: str, label: str) -> dict:
    """-> a layout's field width and where its fields start from the mouse:
    near_x while the mouse is left of mouse_x_limit, far_x when not, and
    low_shift_y on y while the mouse is below mouse_y_limit, for the one
    layout that moves up. Raises unless each line is found once, or not at all
    for the move up."""
    limit, near, far = one(
        r"if\(_root\._xmouse < (\d+)\)\s*\{\s*scaffold = (-?\d+);\s*\}"
        r"\s*else\s*\{\s*scaffold = (-?\d+);\s*\}",
        script,
        label,
    )
    width = one(
        r'createTextField\("my_txt2",-?\d+,scaffold,[^,]+,(\d+),\d+\)', script, label
    )
    entry = {
        "far_x": int(far),
        "field_width": int(width),
        "mouse_x_limit": int(limit),
        "near_x": int(near),
    }
    low = re.findall(
        r"if\(_root\._ymouse > (\d+)\)\s*\{\s*scaffold2 = (-?\d+);\s*\}"
        r"\s*else\s*\{\s*scaffold2 = 0;\s*\}",
        script,
    )
    if len(low) > 1:
        raise ValueError(f"{label}: {len(low)} moves up, want 0 or 1")
    if low:
        entry["mouse_y_limit"] = int(low[0][0])
        entry["low_shift_y"] = int(low[0][1])
    elif "scaffold2" in script:
        raise ValueError(f"{label}: cannot read the scaffold2 lines")
    return entry


def detail_delay_frames(script: str) -> int:
    """-> how many frames the ability icon plays GO3, which shows the title
    alone, before it plays the full layout."""
    return int(one(r"if\(hitter == (\d+)\)", script, "ability icon"))


def pass_texts(script: str, pick_script: str) -> dict:
    """-> the pass button's tooltip: one title, the bodies of the real-time and
    the turn-based mode while the player picks ("idle") and while a picked
    ability waits for its turn in the fight ("action"), and the body a pick
    shows, with %s where the target's name goes. Raises unless both modes set
    the same title."""
    real_time, turn_based = one(
        r"if\(!_root\.turnBasedKrin\)\s*\{(.*?)\}\s*else\s*\{(.*?)\}",
        script,
        "pass button",
        re.DOTALL,
    )
    titles = {
        one(r'thinger1 = "([^"]*)";', branch, "pass button")
        for branch in (real_time, turn_based)
    }
    if len(titles) != 1:
        raise ValueError(f"pass button: the two modes set titles {titles}")
    return {
        "picked": picked_text(pick_script),
        "real_time": mode_texts(real_time),
        "title": titles.pop(),
        "turn_based": mode_texts(turn_based),
    }


def mode_texts(branch: str) -> dict[str, str]:
    """-> the idle body (thinger2) and the action body (thinger3) that one
    mode's branch of the load script sets."""
    return {
        "action": one(r'thinger3 = "([^"]*)";', branch, "pass button"),
        "idle": one(r'thinger2 = "([^"]*)";', branch, "pass button"),
    }


def picked_text(script: str) -> str:
    """-> the body that addMoveForPlayer gives krinToMove on a pick, with %s in
    place of the target's playerName. Raises when the text holds a % of its
    own, which the port's format would read as a placeholder."""
    before, after = one(
        r'_root\.krinToMove\.toolTip = "([^"]*)" \+ _root\["playerKrin" \+'
        r' _root\.theEnemyToMoveVS\]\.playerName \+ "([^"]*)";',
        script,
        "pick",
    )
    if "%" in before + after:
        raise ValueError(f"pick: the text {before!r} {after!r} holds a %")
    return f"{before}%s{after}"


def sell_ratio(roll_over: str, press: str) -> float:
    """-> the share of an item's price that the Store's sell slot names in its
    tooltip and pays on a press. Raises unless each script reads it once and
    both read the same share."""
    pattern = (
        r'Math\.ceil\(_root\["KRINITEM" \+ _root\.Krin\.mouseItem\]\[5\] \* ([\d.]+)\)'
    )
    shown = float(one(pattern, roll_over, "sell rollOver"))
    paid = float(one(pattern, press, "sell press"))
    if shown != paid:
        raise ValueError(
            f"the sell tooltip names {shown} of the price, the press pays {paid}"
        )
    return shown


def _only_child(index: SwfIndex, sprite: int) -> int:
    """-> the one character a one-layer sprite shows, with no transform."""
    placed = [
        p for p in index.display.get(sprite, []) if getattr(p, "character_id", None)
    ]
    if len(placed) != 1 or placed[0].color_transform is not None:
        raise ValueError(f"sprite {sprite} should show one shape with no transform")
    return placed[0].character_id


def gloss_stops(index: SwfIndex) -> list[dict]:
    """-> the stops of the title backer's gradient. Raises unless the gradient
    runs from the top of its shape to the bottom, which is what lets the port
    draw it as a vertical gradient over the whole field."""
    shape = _only_child(index, GLOSS_BACKER)
    found = first_gradient(index, shape)
    if found is None:
        raise ValueError(f"shape {shape} is not filled with a linear gradient")
    (scale_x, skew0, skew1, scale_y, _tx, ty), stops = found
    _xmin, ymin, _xmax, ymax = shape_bounds(index, shape)
    turned = not scale_x and not scale_y and skew0 > 0 and skew1 == -skew0
    if not turned or round(skew0 * 32768) != ymax - ymin:
        raise ValueError(f"shape {shape}'s gradient does not run top to bottom")
    if ty * 2 != ymin + ymax:
        raise ValueError(f"shape {shape}'s gradient is not centred on the shape")
    return [{"color": list(color), "ratio": ratio} for ratio, color in stops]


def backer_transforms(index: SwfIndex) -> tuple[dict, dict]:
    """-> (the add terms of fontBacker3 at each layout label, the transform of
    fontBacker4). Raises when fontBacker2 or fontBacker is ever transformed,
    when fontBacker3 is multiplied, or when fontBacker4 is not placed once."""
    frames = {
        label.name: label.frame for label in index.labels if label.owner == TOOLTIP
    }
    subheader = {}
    next_rank = []
    for placement in index.display.get(TOOLTIP, []):
        name = getattr(placement, "name", None)
        transform = placement.color_transform if name else None
        if name in ("fontBacker", "fontBacker2") and transform is not None:
            raise ValueError(f"{name} is placed with transform {transform}")
        if name == "fontBacker3":
            label = next((k for k, v in frames.items() if v == placement.frame), None)
            if label is None:
                raise ValueError(
                    f"fontBacker3 is placed on unlabelled frame {placement.frame}"
                )
            transform = transform or IDENTITY_MULTIPLY + (0, 0, 0, 0)
            if transform[:4] != IDENTITY_MULTIPLY or transform[7]:
                raise ValueError(f"fontBacker3 at {label} has transform {transform}")
            subheader[label] = list(transform[4:7])
        if name == "fontBacker4":
            next_rank.append(transform)
    missing = [label for label in LAYOUTS if label != "GO" and label not in subheader]
    if missing or len(next_rank) != 1 or next_rank[0] is None:
        raise ValueError(f"fontBacker3 missing at {missing}, fontBacker4 {next_rank}")
    return subheader, {
        "add": list(next_rank[0][4:]),
        "multiply": list(next_rank[0][:4]),
    }


def tooltip_look(index: SwfIndex) -> dict:
    frames = {
        label.name: label.frame for label in index.labels if label.owner == TOOLTIP
    }
    layouts = {}
    for label in LAYOUTS:
        script = (
            ACTION_SCRIPT
            / f"DefineSprite_{TOOLTIP}"
            / f"frame_{frames[label]}"
            / "DoAction.as"
        )
        layouts[label] = layout(script.read_text(encoding="utf-8"), label)
    subheader, next_rank = backer_transforms(index)
    body = first_fill_color(index, _only_child(index, BODY_BACKER))
    if body is None:
        raise ValueError(f"sprite {BODY_BACKER} is not one solid colour")
    return {
        "body_fill": list(body),
        "detail_delay_frames": detail_delay_frames(
            ICON_SCRIPT.read_text(encoding="utf-8")
        ),
        "frame_rate": index.frame_rate,
        "gloss_stops": gloss_stops(index),
        "layouts": layouts,
        "next_rank": next_rank,
        "pass_button": pass_texts(
            PASS_SCRIPT.read_text(encoding="utf-8"),
            PICK_SCRIPT.read_text(encoding="utf-8"),
        ),
        "rarity_add": rarity_add(CHANGE_COLOR_SCRIPT.read_text(encoding="utf-8")),
        "sell_ratio": sell_ratio(
            SELL_ROLL_OVER.read_text(encoding="utf-8"),
            SELL_PRESS.read_text(encoding="utf-8"),
        ),
        "subheader_add": subheader,
    }


def main() -> None:
    look = tooltip_look(read_swf(WEB_SWF))
    OUTPUT.write_text(
        json.dumps(look, indent=1, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(f"wrote {OUTPUT}", file=sys.stderr)


if __name__ == "__main__":
    main()
