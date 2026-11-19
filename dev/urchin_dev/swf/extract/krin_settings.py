# The numbers that krinMelee and krinBoltMake read from _root, read out of the
# original's ActionScript. frame_42/DoAction_4.as sets them on its own top-level
# lines (213-218), once, when the frame runs:
#
#   krinBoltTime        - a bolt's step, and a melee step, is the distance
#                         measured at the start over this
#   krinBoltSpeed       - the SpeedConst that a bolt starts with
#   krinBoltIncrease    - a bolt multiplies its SpeedConst by this each frame
#   krinBodyMove        - a melee step is this many of those steps
#   krinMeleeAttackCD   - the frames from the strike to Impact
#   krinMeleeAttackEndCD - the frames from Impact to the Runback, counting the
#                         frame of Impact
#
# The two functions also write numbers of their own as literals. LITERALS reads
# each one by the line that writes it and gives it a name, since the
# ActionScript names none:
#
#   krinBoltTrailGrowth    - the trail's _xscale grows by this many percent of
#                            the bolt's step length each frame (lines 200, 209)
#   krinBoltMissX          - a missed bolt goes once its x is more than this
#                            either side of BATTLESCREEN's origin (line 201)
#   krinMeleeDashBase,
#   krinMeleeDashSlope     - the dash's coefficient is base - slope * goRat
#                            (line 102)
#   krinMeleeRunbackSlope  - the Runback's coefficient is slope * goRat
#                            (line 106)
#   krinMeleeStepCap       - either coefficient is at most this (lines 108-111)
#   krinMeleeHomeTolerance - the Runback ends once relX is no more than this
#                            on the target's side (line 117)
#
# They all go to assets/battle/krin_settings.json. Projectile and
# CharacterVisual read it.
#
# Run: uv run extract_krin_settings
from __future__ import annotations

import json
import re
import sys

from urchin_dev import ACTION_SCRIPT, REPO_ROOT

SCRIPT = ACTION_SCRIPT / "frame_42" / "DoAction_4.as"
JSON_PATH = REPO_ROOT / "assets" / "battle" / "krin_settings.json"
NAMES = (
    "krinBoltTime",
    "krinBoltSpeed",
    "krinBoltIncrease",
    "krinBodyMove",
    "krinMeleeAttackCD",
    "krinMeleeAttackEndCD",
)


def settings(text: str) -> dict:
    """-> {name: number} for each of NAMES, from the line at the start of a line
    that sets it. Raises unless each name is set on one such line."""
    numbers = {}
    for name in NAMES:
        found = re.findall(rf"^{name} = ([0-9.]+);$", text, re.MULTILINE)
        if len(found) != 1:
            raise RuntimeError(f"{name}: {len(found)} matches, want 1")
        value = float(found[0])
        numbers[name] = int(value) if value.is_integer() else value
    return numbers


# name -> (pattern, how many lines match it). Every number that the matches
# capture must be the same, because the port keeps one value for each name.
LITERALS = {
    "krinBoltTrailGrowth": (r"inner\._xscale \+= ([0-9.]+) \* \(Math\.sqrt", 2),
    "krinBoltMissX": (r"this\._x > ([0-9.]+) \|\| this\._x < -([0-9.]+)\)", 1),
    "krinMeleeDashBase": (
        r"this\.spdXCoEFFER = ([0-9.]+) - [0-9.]+ \* this\.goRat;",
        1,
    ),
    "krinMeleeDashSlope": (
        r"this\.spdXCoEFFER = [0-9.]+ - ([0-9.]+) \* this\.goRat;",
        1,
    ),
    "krinMeleeRunbackSlope": (r"this\.spdXCoEFFER = ([0-9.]+) \* this\.goRat;", 1),
    "krinMeleeStepCap": (
        r"if\(this\.spdXCoEFFER > ([0-9.]+)\)\s*\{\s*this\.spdXCoEFFER = ([0-9.]+);",
        1,
    ),
    "krinMeleeHomeTolerance": (r"this\.relX \* this\.faceing <= ([0-9.]+) &&", 1),
}


def literals(text: str) -> dict:
    """-> {name: number} for each of LITERALS. Raises unless the pattern
    matches the expected number of lines and they all write one number."""
    numbers = {}
    for name, (pattern, count) in LITERALS.items():
        found = re.findall(pattern, text)
        if len(found) != count:
            raise RuntimeError(f"{name}: {len(found)} matches, want {count}")
        written = sorted(
            {
                group
                for match in found
                for group in ((match,) if isinstance(match, str) else match)
            },
            key=float,
        )
        values = {float(group) for group in written}
        if len(values) != 1:
            raise RuntimeError(
                f"{name}: the script writes {' and '.join(written)}, want one number"
            )
        value = values.pop()
        numbers[name] = int(value) if value.is_integer() else value
    return numbers


def main():
    text = SCRIPT.read_text()
    numbers = settings(text) | literals(text)
    JSON_PATH.parent.mkdir(parents=True, exist_ok=True)
    JSON_PATH.write_text(json.dumps(numbers, indent=1, sort_keys=True) + "\n")
    print(f"wrote {JSON_PATH}: {numbers}", file=sys.stderr)


if __name__ == "__main__":
    main()
