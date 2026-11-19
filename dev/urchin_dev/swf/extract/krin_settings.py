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
# They go to assets/battle/krin_settings.json, under their ActionScript names.
# Projectile and CharacterVisual read it.
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


def main():
    numbers = settings(SCRIPT.read_text())
    JSON_PATH.parent.mkdir(parents=True, exist_ok=True)
    JSON_PATH.write_text(json.dumps(numbers, indent=1, sort_keys=True) + "\n")
    print(f"wrote {JSON_PATH}: {numbers}", file=sys.stderr)


if __name__ == "__main__":
    main()
