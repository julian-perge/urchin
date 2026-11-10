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
# Run: uv run extract_battle_screen_motion
from __future__ import annotations

import json
import sys

from urchin_dev import REPO_ROOT, WEB_SWF
from urchin_dev.swf import avm1, render, timeline
from urchin_dev.swf.extract.battle_screen import FRAME_LABEL, HALL_SPRITE
from urchin_dev.swf.swf_index import CodeBlock, SwfIndex, read_swf

MOTION_JSON = REPO_ROOT / "assets" / "ui" / "battle" / "battle_screen_motion.json"

ZOOMER = 3419
SHAKER = 3420
# The onClipEvent(load) bit of a clip action record's event flags.
CLIP_EVENT_LOAD = 1


def frame_scripts(index: SwfIndex, sprite: int) -> dict[int, CodeBlock]:
    """-> {frame: the DoAction that frame runs} for one sprite."""
    return {
        block.frame: block
        for block in index.code
        if block.kind == "frame" and block.owner == sprite
    }


def first_script_from(scripts: dict[int, CodeBlock], frame: int, sprite: int) -> int:
    """-> the first frame from `frame` on that runs a script."""
    later = [f for f in scripts if f >= frame]
    if not later:
        raise RuntimeError(f"{sprite} runs no script from frame {frame} on")
    return min(later)


def load_variables(index: SwfIndex, battle_frame: int, sprite: int) -> dict:
    """-> the variables the onClipEvent(load) that the battle frame gives
    `sprite` sets, with the values it sets them to."""
    (block,) = [
        block
        for block in index.code
        if block.kind == "clip"
        and block.owner == 0
        and block.frame == battle_frame
        and block.placed_id == sprite
        and block.events == CLIP_EVENT_LOAD
    ]
    return avm1.assignments(index, block)


def check(sprite: int, frame: int, block: CodeBlock, strings: set, gotos: tuple):
    """Raise unless `block` pushes every one of `strings` and makes exactly
    the GotoLabel jumps in `gotos`, in that order."""
    missing = strings - set(block.strings)
    if missing or block.goto_labels != gotos:
        raise RuntimeError(
            f"{sprite} frame {frame} pushes {block.strings} and jumps to"
            f" {block.goto_labels}, want {sorted(strings)} and {gotos}"
        )


def check_stop(index: SwfIndex, sprite: int, frame: int, block: CodeBlock) -> None:
    if avm1.actions(index, block) != [avm1.Action(avm1.ACTION_STOP)]:
        raise RuntimeError(f"{sprite} frame {frame} does more than stop()")


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
    check_stop(index, ZOOMER, roles["stop"], scripts[roles["stop"]])
    check(
        ZOOMER,
        roles["go"],
        scripts[roles["go"]],
        {"zoomPointX", "zoomPointY", "saverX", "saverY", "zoomFactor", "scaleChange"},
        (),
    )
    check(
        ZOOMER,
        roles["step"],
        scripts[roles["step"]],
        {"_x", "_y", "_xscale", "_yscale", "saverX", "saverY"},
        ("KrinZoomPlay", "KrinZoomPause", "KrinZoomStop"),
    )
    check(
        ZOOMER,
        roles["hold"],
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
    check_stop(index, SHAKER, stop, scripts[stop])
    check(SHAKER, roles["open"], scripts[roles["open"]], {"_y", "shakeValue"}, ())
    check(SHAKER, up, scripts[up], {"_y", "shakeValue", "shakeMinus"}, ())
    down = scripts[roles["down"]]
    check(
        SHAKER,
        roles["down"],
        down,
        {"_y", "shakeValue", "shakeMinus", "shakeOriginal"},
        ("KrinShakeplayHere", "KrinShakestopHere"),
    )
    # The 0 that shakeValue is compared with, then the number added to _y.
    pushed = avm1.numbers(index, down)
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
    (block,) = [
        block
        for block in index.code
        if block.kind == "clip" and block.placed_id == HALL_SPRITE
    ]
    if not {"saverX", "saverY"} <= set(block.strings):
        raise RuntimeError(f"{HALL_SPRITE}'s clip action sets {block.strings}")
    x, y = render.placement_origin(index, 0, battle_frame, HALL_SPRITE)
    return {"x": x, "y": y}


def main():
    index = read_swf(WEB_SWF)
    battle_frame = timeline.frame_of(index, 0, FRAME_LABEL)
    motion = {
        "fps": index.frame_rate,
        "rest": rest(index, battle_frame),
        "shaker": shaker_motion(index, battle_frame),
        "zoomer": zoomer_motion(index, battle_frame),
    }
    MOTION_JSON.parent.mkdir(parents=True, exist_ok=True)
    MOTION_JSON.write_text(json.dumps(motion, indent=1, sort_keys=True) + "\n")
    print(f"wrote {MOTION_JSON}", file=sys.stderr)


if __name__ == "__main__":
    main()
