# The two clips that move the Battle screen's hall and fighters, and the spot
# they move it from:
#
#   assets/ui/battle/battle_screen_motion.json
#
# BATTLESCREEN, DefineSprite 3435, holds the hall and the six fighter rigs. Its
# onClipEvent(load) saves where the battle frame places it as saverX and saverY
# (frame_217/PlaceObject2_3435_89). GridZoomer, DefineSprite 3419, zooms it
# toward a move's target, and GridShaker, DefineSprite 3420, shakes it. Both
# clips are empty: their frame scripts move BATTLESCREEN and jump between the
# clip's own labels, so nothing here is rendered and ffdec is not needed.
#
# The port runs those frame scripts on the frames the SWF runs them on, so the
# JSON gives each clip its frame count, its labels, the frame each of its
# scripts runs on, and the variables its onClipEvent(load) sets, worked out
# from its bytecode. It also gives the number GridShaker's last frame adds to
# _y when the shake stops. Every script is checked against what the port
# expects to find on that frame, so a SWF laid out differently raises here.
#
# The conductor, the clip that runs the battle (frame_217/PlaceObject2_3389_480),
# starts GridZoomer at each Dispatch. The JSON gives the zoom each move type
# starts, from the scripts that set it up, and the conductor's
# AttackEndCounterLimit, which paces the actions.
#
# Run: uv run extract_battle_screen_motion
from __future__ import annotations

import json
import sys
from collections import Counter
from dataclasses import dataclass

from urchin_dev import REPO_ROOT, WEB_SWF
from urchin_dev.swf import avm1, render, timeline
from urchin_dev.swf.extract.battle_screen import FRAME_LABEL, HALL_SPRITE
from urchin_dev.swf.swf_index import CodeBlock, SwfIndex, read_swf

MOTION_JSON = REPO_ROOT / "assets" / "ui" / "battle" / "battle_screen_motion.json"

ZOOMER = 3419
SHAKER = 3420
CONDUCTOR = 3389
# A clip action record sets these bits of its event flags for onClipEvent(load)
# and onClipEvent(enterFrame).
CLIP_EVENT_LOAD = 1
CLIP_EVENT_ENTER_FRAME = 2
# The conductor compares mAry1[10] with each of these before it starts a move of
# that type.
MOVE_TYPES = ("Melee", "Missile", "Shock")
# A script sets up a zoom by setting these, in this order.
ZOOM_TARGETS = ("_root.zoomPointX", "_root.zoomPointY", "_root.zoomPause")


@dataclass(frozen=True)
class FrameScript:
    """The DoAction that runs on one frame of a sprite."""

    sprite: int
    frame: int
    block: CodeBlock


def frame_scripts(index: SwfIndex, sprite: int) -> dict[int, FrameScript]:
    """-> {frame: the script that frame runs} for one sprite."""
    return {
        block.frame: FrameScript(sprite, block.frame, block)
        for block in index.code
        if block.kind == "frame" and block.owner == sprite
    }


def first_script_from(scripts: dict[int, FrameScript], frame: int, sprite: int) -> int:
    """-> the first frame from `frame` on that runs a script."""
    later = [f for f in scripts if f >= frame]
    if not later:
        raise RuntimeError(f"{sprite} runs no script from frame {frame} on")
    return min(later)


def clip_script(
    index: SwfIndex, battle_frame: int, sprite: int, event: int
) -> CodeBlock:
    """-> the clip action that the battle frame gives `sprite` for `event`."""
    (block,) = [
        block
        for block in index.code
        if block.kind == "clip"
        and block.owner == 0
        and block.frame == battle_frame
        and block.placed_id == sprite
        and block.events == event
    ]
    return block


def load_variables(index: SwfIndex, battle_frame: int, sprite: int) -> dict:
    """-> the variables the onClipEvent(load) that the battle frame gives
    `sprite` sets, with the values it sets them to."""
    return avm1.assignments(
        index, clip_script(index, battle_frame, sprite, CLIP_EVENT_LOAD)
    )


def check_strings_and_jumps(script: FrameScript, strings: set, gotos: tuple) -> None:
    """Raise unless `script` pushes every one of `strings` and makes exactly
    the GotoLabel jumps in `gotos`, in that order."""
    block = script.block
    missing = strings - set(block.strings)
    if missing or block.goto_labels != gotos:
        raise RuntimeError(
            f"{script.sprite} frame {script.frame} pushes {block.strings} and jumps"
            f" to {block.goto_labels}, want {sorted(strings)} and {gotos}"
        )


def check_stop(index: SwfIndex, script: FrameScript) -> None:
    """Raise unless `script` does nothing but stop()."""
    if avm1.actions(index, script.block) != [avm1.Action(avm1.ACTION_STOP)]:
        raise RuntimeError(
            f"{script.sprite} frame {script.frame} does more than stop()"
        )


def zoomer_motion(index: SwfIndex, battle_frame: int) -> dict:
    """GridZoomer's frames 2, 4 and 6 (DefineSprite_3419): KrinZoomGo works out
    each frame's step toward _root.zoomPointX and zoomPointY, the frame after
    KrinZoomPlay takes one step and the frame after KrinZoomPause holds for
    _root.zoomPause frames. KrinZoomStop's frame stops the clip."""
    labels = timeline.labels(index, ZOOMER)
    scripts = frame_scripts(index, ZOOMER)
    roles = {
        "stop": labels["KrinZoomStop"],
        "go": first_script_from(scripts, labels["KrinZoomGo"], ZOOMER),
        "step": first_script_from(scripts, labels["KrinZoomPlay"], ZOOMER),
        "hold": first_script_from(scripts, labels["KrinZoomPause"], ZOOMER),
    }
    if roles["go"] != labels["KrinZoomGo"] or sorted(scripts) != sorted(roles.values()):
        raise RuntimeError(f"{ZOOMER} runs scripts on {sorted(scripts)}, want {roles}")
    check_stop(index, scripts[roles["stop"]])
    check_strings_and_jumps(
        scripts[roles["go"]],
        {"zoomPointX", "zoomPointY", "saverX", "saverY", "zoomFactor", "scaleChange"},
        (),
    )
    check_strings_and_jumps(
        scripts[roles["step"]],
        {"_x", "_y", "_xscale", "_yscale", "saverX", "saverY"},
        ("KrinZoomPlay", "KrinZoomPause", "KrinZoomStop"),
    )
    check_strings_and_jumps(
        scripts[roles["hold"]],
        {"zoomPause", "zoomPauseCounter"},
        ("KrinZoomPlay", "KrinZoomPause"),
    )
    return {
        "frames": index.sprite_frames[ZOOMER],
        "labels": labels,
        "scripts": roles,
        "variables": load_variables(index, battle_frame, ZOOMER),
    }


def shaker_motion(index: SwfIndex, battle_frame: int) -> dict:
    """GridShaker's frames 2, 4 and 5 (DefineSprite_3420): the frame after the
    stop frame moves _y down by half of shakeValue, the frame after
    KrinShakeplayHere moves it up by shakeValue, and the frame after that moves
    it down again, each time taking shakeMinus off shakeValue. The last of
    those loops back to KrinShakeplayHere while shakeValue is above 0, and
    otherwise adds `settle` to _y and stops."""
    labels = timeline.labels(index, SHAKER)
    scripts = frame_scripts(index, SHAKER)
    stop = labels["KrinShakestopHere"]
    up = first_script_from(scripts, labels["KrinShakeplayHere"], SHAKER)
    roles = {
        "stop": stop,
        "open": first_script_from(scripts, stop + 1, SHAKER),
        "up": up,
        "down": first_script_from(scripts, up + 1, SHAKER),
    }
    if sorted(scripts) != sorted(roles.values()):
        raise RuntimeError(f"{SHAKER} runs scripts on {sorted(scripts)}, want {roles}")
    check_stop(index, scripts[stop])
    check_strings_and_jumps(scripts[roles["open"]], {"_y", "shakeValue"}, ())
    check_strings_and_jumps(scripts[up], {"_y", "shakeValue", "shakeMinus"}, ())
    down = scripts[roles["down"]]
    check_strings_and_jumps(
        down,
        {"_y", "shakeValue", "shakeMinus", "shakeOriginal"},
        ("KrinShakeplayHere", "KrinShakestopHere"),
    )
    # The down frame pushes the 0 that it compares shakeValue with, and then the
    # number that it adds to _y.
    pushed = avm1.numbers(index, down.block)
    if len(pushed) != 2 or pushed[0] != 0:
        raise RuntimeError(f"{SHAKER} frame {roles['down']} pushes {pushed}")
    return {
        "frames": index.sprite_frames[SHAKER],
        "labels": labels,
        "scripts": roles,
        "settle": pushed[1],
        "variables": load_variables(index, battle_frame, SHAKER),
    }


def rest(index: SwfIndex, battle_frame: int) -> dict:
    """-> where the battle frame places BATTLESCREEN, which is where its
    onClipEvent(load) saves saverX and saverY from."""
    block = clip_script(index, battle_frame, HALL_SPRITE, CLIP_EVENT_LOAD)
    if not {"saverX", "saverY"} <= set(block.strings):
        raise RuntimeError(f"{HALL_SPRITE}'s clip action sets {block.strings}")
    x, y = render.placement_origin(index, 0, battle_frame, HALL_SPRITE)
    return {"x": x, "y": y}


def constants(index: SwfIndex, block: CodeBlock) -> dict:
    """-> {path: number} for every path that `block` sets exactly once, to a
    number."""
    assigned = avm1.statements(index, block)
    counts = Counter(assignment.target for assignment in assigned)
    return {
        assignment.target: assignment.value
        for assignment in assigned
        if counts[assignment.target] == 1
        and isinstance(assignment.value, (int, float))
        and not isinstance(assignment.value, bool)
    }


def defining_block(index: SwfIndex, path: str) -> CodeBlock:
    """-> the one DoAction on the root timeline that sets `path`."""
    (block,) = [
        block
        for block in index.code
        if block.kind == "frame"
        and block.owner == 0
        and path.rsplit(".", 1)[-1] in block.strings
        and any(a.target == path for a in avm1.statements(index, block))
    ]
    return block


def zoom_setups(index: SwfIndex, block: CodeBlock) -> list[tuple]:
    """-> each zoom `block` sets up, in order, as its assignments to
    ZOOM_TARGETS."""
    found = [a for a in avm1.statements(index, block) if a.target in ZOOM_TARGETS]
    setups = [tuple(found[i : i + 3]) for i in range(0, len(found), 3)]
    for setup in setups:
        if tuple(a.target for a in setup) != ZOOM_TARGETS:
            raise RuntimeError(f"a zoom sets {[a.target for a in setup]}")
    return setups


def zoom(setup: tuple, variables: dict) -> dict:
    """-> the factor and the center that a zoom works its point out with, and
    its hold. Its script sets _root.zoomPointX to _root.xPoint1 times the
    factor, plus the center's x, _root.zoomPointY the same way from
    _root.yPoint1, and _root.zoomPause to the hold."""
    x, y, pause = setup
    factor, center_x = point_terms(x.value, "_root.xPoint1", variables)
    y_factor, center_y = point_terms(y.value, "_root.yPoint1", variables)
    if y_factor != factor:
        raise RuntimeError(f"a zoom's factors are {factor} for x and {y_factor} for y")
    return {
        "center": {"x": center_x, "y": center_y},
        "factor": factor,
        "hold": avm1.evaluate(pause.value, variables),
    }


def point_terms(value, point: str, variables: dict) -> tuple:
    """-> (factor, center) of a zoom point that is `point` times the factor,
    plus the center."""
    match value:
        case avm1.Arithmetic(
            avm1.ACTION_ADD2,
            avm1.Arithmetic(avm1.ACTION_MULTIPLY, avm1.Read(path), factor),
            center,
        ) if path == point:
            return avm1.evaluate(factor, variables), avm1.evaluate(center, variables)
    raise RuntimeError(f"a zoom point is {value}, not {point} * factor + center")


def functions_around(acts: list[avm1.Action], at: int) -> list[str]:
    """-> the names of the functions whose bodies hold the action `at`."""
    return [
        action.args[0]
        for start, action in enumerate(acts[:at])
        if action.code in (avm1.ACTION_DEFINE_FUNCTION, avm1.ACTION_DEFINE_FUNCTION2)
        and at <= start + action.args[2]
    ]


def move_type_before(acts: list[avm1.Action], at: int) -> str | None:
    """-> the last move type that the script pushes before the action `at`."""
    pushed = [
        value
        for action in acts[:at]
        if action.code == avm1.ACTION_PUSH
        for value in action.args
        if value in MOVE_TYPES
    ]
    return pushed[-1] if pushed else None


def zooms(index: SwfIndex, battle_frame: int) -> dict:
    """-> {move type: zoom} for the zoom each move type starts at Dispatch. The
    conductor sets up a Missile's and a Shock's zoom once it has compared
    mAry1[10] with their type (enterFrame, lines 412-428 and 445-462), and
    krinMelee sets up a Melee move's (frame_42/DoAction_4.as:58-65). They read
    zoomRatioNEW and krinMeleeAttackCD, which krinMelee's DoAction sets."""
    library = defining_block(index, "krinMeleeAttackCD")
    variables = constants(index, library)
    found = []
    library_actions = avm1.actions(index, library)
    for setup in zoom_setups(index, library):
        if functions_around(library_actions, setup[0].at) != ["krinMelee"]:
            raise RuntimeError(
                f"frame {library.frame} sets up a zoom outside krinMelee"
            )
        found.append(("Melee", zoom(setup, variables)))
    script = clip_script(index, battle_frame, CONDUCTOR, CLIP_EVENT_ENTER_FRAME)
    script_actions = avm1.actions(index, script)
    for setup in zoom_setups(index, script):
        move_type = move_type_before(script_actions, setup[0].at)
        found.append((move_type, zoom(setup, variables)))
    if sorted(move_type for move_type, _ in found) != sorted(MOVE_TYPES):
        raise RuntimeError(f"zooms are set up for {[t for t, _ in found]}")
    return dict(found)


def conductor(index: SwfIndex, battle_frame: int) -> dict:
    """-> the conductor's AttackEndCounterLimit, which its onClipEvent(load)
    sets (frame_217/PlaceObject2_3389_480, line 7)."""
    load = clip_script(index, battle_frame, CONDUCTOR, CLIP_EVENT_LOAD)
    return {"AttackEndCounterLimit": constants(index, load)["AttackEndCounterLimit"]}


def main():
    index = read_swf(WEB_SWF)
    battle_frame = timeline.frame_of(index, 0, FRAME_LABEL)
    motion = {
        "conductor": conductor(index, battle_frame),
        "fps": index.frame_rate,
        "rest": rest(index, battle_frame),
        "shaker": shaker_motion(index, battle_frame),
        "zoomer": zoomer_motion(index, battle_frame),
        "zooms": zooms(index, battle_frame),
    }
    MOTION_JSON.parent.mkdir(parents=True, exist_ok=True)
    MOTION_JSON.write_text(json.dumps(motion, indent=1, sort_keys=True) + "\n")
    print(f"wrote {MOTION_JSON}", file=sys.stderr)


if __name__ == "__main__":
    main()
