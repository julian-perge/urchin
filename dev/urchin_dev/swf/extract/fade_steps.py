# The alpha steps of the fades that the port runs frame by frame, and the alpha
# of two covers, read out of the original's ActionScript. Each number goes to a
# JSON next to the code that draws the fade:
#
#   assets/ui/battle/fighter_ring_fade.json - the hover ring under a fighter
#       (frame_217/PlaceObject3_3394_450 to _475 enterFrame): the step up while
#       the mouse is on the fighter and the step down while it is off
#   assets/ui/battle/radial_menu_fade.json  - the Radial menu
#       (frame_217/PlaceObject3_3382_500 enterFrame): the step up while it
#       fades in, the step down while the mouse is off it, and the alpha of
#       the black cover over a darkened orb while the menu fades in and after
#   assets/vfx/bolts/bolt_fade.json         - a bolt (frame_42/DoAction_4.as,
#       the onEnterFrame that krinBoltMake gives it): the step up to 100
#   assets/cutscenes/cutscene_fade.json     - the black over a cutscene
#       (frame_263/PlaceObject2_3466_80 enterFrame): the step down at the
#       start and the step up at the end, which are the same
#   assets/ui/abilities/talent_cover.json   - the black cover over a talent
#       tree node with no point in it
#       (DefineSprite_3142/frame_25/PlaceObject3_3100_153 load, krinRemakeTree)
#
# The steps and the alphas are in percent, as the scripts write them. FlashAlpha
# turns them into Flash's 1/256 steps.
#
# Run: uv run extract_fade_steps
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from urchin_dev import ACTION_SCRIPT, REPO_ROOT

ENTER_FRAME = "CLIPACTIONRECORD onClipEvent(enterFrame).as"
LOAD = "CLIPACTIONRECORD onClipEvent(load).as"

RING_SCRIPTS = sorted((ACTION_SCRIPT / "frame_217").glob("PlaceObject3_3394_*"))
RADIAL_SCRIPT = ACTION_SCRIPT / "frame_217" / "PlaceObject3_3382_500" / ENTER_FRAME
BOLT_SCRIPT = ACTION_SCRIPT / "frame_42" / "DoAction_4.as"
CUTSCENE_SCRIPT = ACTION_SCRIPT / "frame_263" / "PlaceObject2_3466_80" / ENTER_FRAME
TALENT_SCRIPT = (
    ACTION_SCRIPT / "DefineSprite_3142" / "frame_25" / "PlaceObject3_3100_153" / LOAD
)

RING_JSON = REPO_ROOT / "assets" / "ui" / "battle" / "fighter_ring_fade.json"
RADIAL_JSON = REPO_ROOT / "assets" / "ui" / "battle" / "radial_menu_fade.json"
BOLT_JSON = REPO_ROOT / "assets" / "vfx" / "bolts" / "bolt_fade.json"
CUTSCENE_JSON = REPO_ROOT / "assets" / "cutscenes" / "cutscene_fade.json"
TALENT_JSON = REPO_ROOT / "assets" / "ui" / "abilities" / "talent_cover.json"


def one(pattern: str, text: str, where: str) -> int:
    """-> the one match of `pattern` in `text`, as an int. Raises unless there
    is one."""
    found = re.findall(pattern, text)
    if len(found) != 1:
        raise RuntimeError(f"{where}: {len(found)} matches of {pattern}, want 1")
    return int(found[0])


def ring_steps(scripts: list[str]) -> dict:
    """-> the hover ring's steps up and down. Raises unless each of the
    six rings' scripts holds one of each, and unless they all agree, because
    the port runs one fade for every fighter."""
    if not scripts:
        raise RuntimeError("no hover ring scripts")
    steps = [
        {
            "fade_in_step": one(r"_alpha = _alpha \+ (\d+);", text, "ring"),
            "fade_out_step": one(r"_alpha = _alpha - (\d+);", text, "ring"),
        }
        for text in scripts
    ]
    if any(s != steps[0] for s in steps):
        raise RuntimeError(f"the hover rings step their _alpha differently: {steps}")
    return steps[0]


def radial_steps(text: str) -> dict:
    """-> the Radial menu's steps up and down, and its cover's alpha while it
    fades in and after. The fade-in sets the cover's alpha once before it adds
    its step, and every later write sets the other alpha. Raises unless each
    step is found once and every later write of the cover's alpha agrees."""
    covers = [
        (m.start(), int(m.group(1)))
        for m in re.finditer(r"bfilter\._alpha = (\d+);", text)
    ]
    step_in = re.search(r"_alpha = _alpha \+ (\d+);", text)
    if step_in is None:
        raise RuntimeError("radial: no step up")
    before = [alpha for at, alpha in covers if at < step_in.start()]
    after = {alpha for at, alpha in covers if at > step_in.start()}
    if len(before) != 1 or len(after) != 1:
        raise RuntimeError(
            f"radial: cover alphas {before} before the step up and {sorted(after)}"
            " after it, want one of each"
        )
    return {
        "cover_percent": after.pop(),
        "cover_percent_fading_in": before[0],
        "fade_in_step": one(r"_alpha = _alpha \+ (\d+);", text, "radial"),
        "fade_out_step": one(r"_alpha = _alpha - (\d+);", text, "radial"),
    }


def bolt_step(text: str) -> dict:
    """-> the step a bolt adds to its _alpha each frame while it is under 100.
    Raises unless the script adds to a bolt's _alpha in one place."""
    return {"fade_in_step": one(r"this\._alpha \+= (\d+);", text, "bolt")}


def cutscene_step(text: str) -> dict:
    """-> the step the cutscene's black takes each frame. Raises unless the
    step down and the step up are each found once and are the same, because
    the port records one step."""
    down = one(r"_alpha = _alpha - (\d+);", text, "cutscene")
    up = one(r"_alpha = _alpha \+ (\d+);", text, "cutscene")
    if down != up:
        raise RuntimeError(f"cutscene steps _alpha down by {down} and up by {up}")
    return {"fade_step": down}


def talent_cover(text: str) -> dict:
    """-> the alpha krinRemakeTree gives the cover of a node with no point.
    Raises unless it sets that alpha in one place."""
    return {"cover_percent": one(r"thing2\.bfilter\._alpha = (\d+);", text, "talent")}


def write(path: Path, numbers: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(numbers, indent=1, sort_keys=True) + "\n")
    print(f"wrote {path}: {numbers}", file=sys.stderr)


def main():
    write(RING_JSON, ring_steps([(d / ENTER_FRAME).read_text() for d in RING_SCRIPTS]))
    write(RADIAL_JSON, radial_steps(RADIAL_SCRIPT.read_text()))
    write(BOLT_JSON, bolt_step(BOLT_SCRIPT.read_text()))
    write(CUTSCENE_JSON, cutscene_step(CUTSCENE_SCRIPT.read_text()))
    write(TALENT_JSON, talent_cover(TALENT_SCRIPT.read_text()))


if __name__ == "__main__":
    main()
