# The Result flash, the original's BATTLEFLASH (DefineSprite 3416), which
# executeMove plays on the unit a Move result lands on
# (frame_42/DoAction_8.as):
#
#   assets/ui/battle/result_flash.json
#       for each of the clip's labels, the color of its glows and whether the
#       filter is on for each frame the label plays, and the blur and the
#       strength of the white glow and of the colored glows
#
# THE CLIP DRAWS NOTHING. It places no character and every frame that does
# anything is a frame script. A script that turns the flash on sets
# hitTarget.inner.filters to one of the root's filter lists, such as
# _root.KrinFilterHit. A script that turns it off sets it to DFTF, the filters
# the unit had when the flash started. The last script of a label turns the
# flash off and runs gotoAndStop() to the label whose frame runs stop(), where
# the clip rests. So this reads which frames are on from the scripts, and
# renders nothing.
#
# THE FILTER LISTS ARE BUILT BY A ROOT FRAME SCRIPT (frame_42/DoAction_3.as).
# It sets each list to a new Array and pushes three GlowFilters onto it, each
# made with new flash.filters.GlowFilter(color, alpha, blurX, blurY, strength,
# quality, inner, knockout). Every label's list has the same shape: a white
# inner glow, then an outer glow and an inner glow that share a color, a blur
# and a strength. Only the color differs between the labels.
# scenes/doll_body.gdshader draws exactly that shape, so flash_layout() raises
# on any other, and the JSON carries the two blurs and strengths once.
#
# Run: uv run extract_result_flash
from __future__ import annotations

import json
import sys
from dataclasses import dataclass

from urchin_dev import REPO_ROOT, WEB_SWF
from urchin_dev.swf import avm1, timeline
from urchin_dev.swf.swf_index import CodeBlock, SwfIndex, read_swf

LAYOUT_JSON = REPO_ROOT / "assets" / "ui" / "battle" / "result_flash.json"

# The instance name the root timeline gives the clip, which executeMove calls
# it by (frame_42/DoAction_8.as:95-99).
INSTANCE_NAME = "BATTLEFLASH"
# The member every script of the clip sets, to a filter list or to DFTF.
FILTERS_TARGET = "hitTarget.inner.filters"
ROOT_PREFIX = "_root."
GLOW_CLASS = "flash.filters.GlowFilter"
WHITE = 0xFFFFFF
ACTION_PLAY = 0x06


@dataclass(frozen=True)
class Glow:
    """A GlowFilter, with the arguments of its constructor in their order."""

    color: int
    alpha: float
    blur_x: float
    blur_y: float
    strength: float
    quality: int
    inner: bool
    knockout: bool


def flash_sprite(index: SwfIndex) -> int:
    """-> the sprite the root timeline places under INSTANCE_NAME. Raises
    unless it places exactly one such sprite."""
    placed = {
        layer.character_id
        for layers in timeline.frames(index, 0)
        for layer in layers.values()
        if layer.name == INSTANCE_NAME
    }
    if len(placed) != 1:
        raise RuntimeError(
            f"the root timeline places {sorted(placed)} as {INSTANCE_NAME}, want 1 sprite"
        )
    return placed.pop()


def label_frames(index: SwfIndex, sprite: int) -> dict[str, tuple[str, list[bool]]]:
    """-> {label: (filter list, frames)} for every label of `sprite` but the
    one it rests on. The filter list is the root variable the label's scripts
    set the filter to, and frames holds whether the filter is on for each
    frame from the label to the last frame before the script that goes back
    to the resting label. Raises when a label never goes back, and when a
    script sets anything else."""
    scripts = {
        block.frame: block
        for block in index.code
        if block.kind == "frame" and block.owner == sprite
    }
    starts = timeline.labels(index, sprite)
    resting = [
        name
        for name, frame in starts.items()
        if frame in scripts
        and avm1.actions(index, scripts[frame]) == [avm1.Action(avm1.ACTION_STOP)]
    ]
    if len(resting) != 1:
        raise RuntimeError(f"{sprite} rests on the labels {resting}, want 1")
    (rest,) = resting
    ends = sorted([*starts.values(), index.sprite_frames[sprite] + 1])
    played: dict[str, tuple[str, list[bool]]] = {}
    for name, start in starts.items():
        if name == rest:
            continue
        lists: set[str] = set()
        frames: list[bool] = []
        on = False
        for frame in range(start, next(end for end in ends if end > start)):
            block = scripts.get(frame)
            if block is not None:
                value = _filters_set(index, block)
                on = isinstance(value, avm1.Read) and value.path.startswith(ROOT_PREFIX)
                if on:
                    lists.add(value.path.removeprefix(ROOT_PREFIX))
                if block.goto_labels:
                    if (
                        on
                        or block.goto_labels != (rest,)
                        or ACTION_PLAY in block.actions
                    ):
                        raise RuntimeError(
                            f"{sprite} frame {frame} jumps to {block.goto_labels},"
                            f" where a label ends with the filter off and stops on {rest!r}"
                        )
                    break
            frames.append(on)
        else:
            raise RuntimeError(f"{sprite} label {name!r} never goes back to {rest!r}")
        if len(lists) != 1:
            raise RuntimeError(
                f"{sprite} label {name!r} sets the filter lists {sorted(lists)}, want 1"
            )
        played[name] = (lists.pop(), frames)
    return played


def _filters_set(index: SwfIndex, block: CodeBlock):
    """-> the value the script sets FILTERS_TARGET to. Raises unless that is
    the one thing it sets."""
    sets = avm1.statements(index, block)
    if [a.target for a in sets] != [FILTERS_TARGET]:
        raise RuntimeError(
            f"timeline {block.owner} frame {block.frame} sets"
            f" {[a.target for a in sets]}, want {FILTERS_TARGET} alone"
        )
    return sets[0].value


def filter_list(index: SwfIndex, name: str) -> list[Glow]:
    """-> the GlowFilters the root frame script pushes onto the list `name`,
    in order. Raises unless one root frame script sets `name` to a new Array,
    and every value it pushes is a variable the same script set to a new
    GlowFilter."""
    found = []
    for block in index.code:
        if block.kind != "frame" or block.owner != 0 or name not in block.strings:
            continue
        variables = {a.target: a.value for a in avm1.statements(index, block)}
        if variables.get(name) == avm1.New("Array", ()):
            found.append((block, variables))
    if len(found) != 1:
        raise RuntimeError(
            f"{len(found)} root frame scripts set {name} to a new Array, want 1"
        )
    block, variables = found[0]
    glows = []
    for call in avm1.calls(index, block):
        if call.path != f"{name}.push":
            continue
        (pushed,) = call.args
        made = variables.get(pushed.path) if isinstance(pushed, avm1.Read) else None
        if not (
            isinstance(made, avm1.New)
            and made.path == GLOW_CLASS
            and len(made.args) == 8
        ):
            raise RuntimeError(f"{name} holds {pushed}, which is no GlowFilter: {made}")
        glows.append(Glow(*made.args))
    return glows


def flash_layout(index: SwfIndex) -> dict:
    """-> the JSON layout: the color and the frames of each label, and the
    blur and the strength of the white glow and of the colored glows. Raises
    unless every label's filter list is a white inner glow, then an outer glow
    and an inner glow alike in everything else, with the same blurs and
    strengths in every label. The port's shader draws that and nothing
    else."""
    labels = {}
    shapes = set()
    for name, (list_name, frames) in label_frames(index, flash_sprite(index)).items():
        glows = filter_list(index, list_name)
        plain = all(
            glow.alpha == 1
            and glow.blur_x == glow.blur_y
            and glow.quality == 1
            and not glow.knockout
            for glow in glows
        )
        if not (
            plain
            and [glow.inner for glow in glows] == [True, False, True]
            and glows[0].color == WHITE
            and glows[1] == Glow(**{**vars(glows[2]), "inner": False})
        ):
            raise RuntimeError(
                f"{list_name} is {glows}, where the port draws a white inner glow,"
                " then an outer glow and an inner glow that are otherwise alike"
            )
        white, colored, _ = glows
        shapes.add((white.blur_x, white.strength, colored.blur_x, colored.strength))
        labels[name] = {"color": f"{colored.color:06x}", "frames": frames}
    if len(shapes) != 1:
        raise RuntimeError(
            f"the labels' glows differ in blur or strength: {sorted(shapes)}"
        )
    white_blur, white_strength, color_blur, color_strength = shapes.pop()
    return {
        "white_glow": {"blur": white_blur, "strength": white_strength},
        "color_glow": {"blur": color_blur, "strength": color_strength},
        "labels": labels,
    }


def main():
    layout = flash_layout(read_swf(WEB_SWF))
    LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
    print(
        f"wrote {LAYOUT_JSON} with labels "
        + ", ".join(
            f"{name} #{label['color']} {len(label['frames'])} frames"
            for name, label in layout["labels"].items()
        ),
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
