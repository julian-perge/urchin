# The Abilities window's hint box, the clip `reader` (DefineSprite 3059) that
# frame 25 of the menu clip (DefineSprite 3142, label `skills`) places at depth
# 675, and its tutorial steps:
#
#   assets/ui/menu/hint_steps/<strip>/<n>.png   frame n of one strip of glow art
#   assets/ui/menu/hint_steps/hint_steps.json   the labels, their text, their
#                                                click areas and their strips
#
# THE CLIP. Its frame 1, `stable`, shows MENU[43 + random(4)] and runs stop().
# The clip's onClipEvent(load) goes to `level` when the player has upgrade
# points (DefineSprite_3142/frame_25/PlaceObject2_3059_675). `level` shows a
# prompt, and each later label, `part1` to `part4`, one step. Each of those
# labels places a button that goes to the next label on release, and the button
# on `part4` goes back to `stable`. A label's frame script sets the text field
# `reader` to one MENU string and `clicker` to another. `level` and `part4`
# hold still. `part1` to `part3` loop: a later frame script runs
# gotoAndStop() on the label and then play(), so the frames from the label up to
# the frame before that script repeat.
#
# THE ART. Two pieces of glow art sit above the text. The box is the 40-frame
# sprite 3040, which `level` places and every later label moves and scales,
# and which keeps playing across the labels. The pointer is the bar and the
# arrow that `part1` to `part3` animate on the clip's own timeline. Flash does
# not scale a filter with the matrix of the sprite that holds it, so the box is
# rendered in place for each matrix that a label gives it, one frame for each of
# its own frames. The pointer is rendered for each frame of a label's loop.
# Text and buttons are left out of every render, because the port draws them.
#
# The MENU indices come from the numbers each frame script pushes, because the
# script reads MENU through _root.KrinLang[_root.KLangChoosen], which avm1 does
# not resolve. step_strings() checks that the script sets reader and then
# clicker and pushes exactly two numbers.
#
# Run: uv run extract_hint_steps
from __future__ import annotations

import json
import sys
from dataclasses import dataclass

from urchin_dev import REPO_ROOT, WEB_SWF, png
from urchin_dev.swf import avm1, render, timeline
from urchin_dev.swf.extract.battle_screen import rect_entry
from urchin_dev.swf.extract.screen_rects import (
    KRINMENU,
    hit_record,
    origin_of,
    text_record,
)
from urchin_dev.swf.swf_index import (
    SwfIndex,
    button_records,
    character_kind,
    edit_text,
    font,
    read_swf,
    shape_bounds,
)

OUT_DIR = REPO_ROOT / "assets" / "ui" / "menu" / "hint_steps"
LAYOUT_JSON = OUT_DIR / "hint_steps.json"
# The art is rendered at 2x, the window's default scale.
ZOOM = 2.0
# The menu clip's label for the Abilities window. That frame gives the hint
# box no instance name, so the box is the clip whose onClipEvent(load) reads
# both kinds of upgrade points.
SKILLS_FRAME = "skills"
POINTS = ("skillPoints", "statPoints")
# The text field variables each label's script sets.
READER = "reader"
CLICKER = "clicker"
ACTION_PLAY = 0x06


@dataclass(frozen=True)
class Jump:
    """A frame script or a button that runs gotoAndStop(label), and whether
    play() follows it."""

    label: str
    plays: bool


def label_frames(
    labels: dict[str, int], jumps: dict[int, Jump], frame_count: int
) -> dict[str, list[int]]:
    """-> the frames each label shows, from its frame scripts' `jumps`. A label
    that no later script jumps back to holds still on its own frame. A label
    whose frames reach a script that runs gotoAndStop() on it and then play()
    loops from its frame up to the frame before that script. Raises when a
    label's frames reach a script that jumps anywhere else, or one that jumps
    back without play()."""
    starts = sorted(labels.values())
    shown: dict[str, list[int]] = {}
    for name, start in labels.items():
        end = next((s for s in starts if s > start), frame_count + 1)
        back = [frame for frame in range(start + 1, end) if frame in jumps]
        if not back:
            shown[name] = [start]
            continue
        jump = jumps[back[0]]
        if jump.label != name or not jump.plays:
            raise RuntimeError(
                f"label {name!r} reaches frame {back[0]}, which jumps to"
                f" {jump.label!r}{' and plays' if jump.plays else ''}, where a"
                " label loops back to itself and plays"
            )
        shown[name] = list(range(start, back[0]))
    return shown


def step_strings(targets: list[str], numbers: list[float]) -> tuple[int, int]:
    """-> the MENU indices a step's frame script sets reader and clicker to,
    from the variables it sets and the numbers it pushes, in order. Raises
    unless it sets reader and then clicker and pushes one whole number for
    each."""
    if targets != [READER, CLICKER] or len(numbers) != 2:
        raise RuntimeError(
            f"the script sets {targets} and pushes {numbers}, where a step sets"
            f" {READER} and then {CLICKER} to one MENU string each"
        )
    if not all(float(n).is_integer() for n in numbers):
        raise RuntimeError(f"the script pushes {numbers}, which are not MENU indices")
    return int(numbers[0]), int(numbers[1])


def tip_strings(targets: list[str], numbers: list[float]) -> tuple[int, int]:
    """-> (the first MENU index, the number of tips) of the resting frame's
    script, `reader = MENU[first + random(count)]`. Raises unless it sets
    reader alone and pushes those two numbers."""
    if READER not in targets or len(numbers) != 2:
        raise RuntimeError(
            f"the resting frame sets {targets} and pushes {numbers}, where it"
            f" sets {READER} to MENU[first + random(count)]"
        )
    return int(numbers[0]), int(numbers[1])


def field_record(index: SwfIndex, layer: timeline.Layer, origin) -> dict:
    """-> text_record() of the field `layer` places, with whether its font is
    bold and whether it wraps, which the port's Label needs to draw it."""
    text = edit_text(index, layer.character_id)
    record = text_record(text, layer.matrix, origin)
    record["bold"] = font(index, text.font_id).bold
    record["wrap"] = text.word_wrap
    return record


def _frame_scripts(index: SwfIndex, sprite: int) -> dict[int, list]:
    scripts: dict[int, list] = {}
    for block in index.code:
        if block.kind == "frame" and block.owner == sprite:
            scripts.setdefault(block.frame, []).append(block)
    return scripts


def _jump(block) -> Jump | None:
    if not block.goto_labels:
        return None
    if len(block.goto_labels) != 1:
        raise RuntimeError(f"{block.kind} {block.owner} jumps to {block.goto_labels}")
    return Jump(block.goto_labels[0], ACTION_PLAY in block.actions)


def _button_jump(index: SwfIndex, button: int) -> Jump:
    blocks = [b for b in index.code if b.kind == "button" and b.owner == button]
    jumps = [j for j in (_jump(b) for b in blocks) if j is not None]
    if len(jumps) != 1:
        raise RuntimeError(f"button {button} jumps {len(jumps)} times, want 1")
    return jumps[0]


def _hint_placement(index: SwfIndex) -> tuple[int, int, tuple[float, float], str]:
    """-> (the hint box's sprite, its depth, its origin on the stage, the label
    its onClipEvent(load) goes to)."""
    frame = timeline.frame_of(index, KRINMENU, SKILLS_FRAME)
    loads = [
        b
        for b in index.code
        if b.kind == "clip"
        and b.owner == KRINMENU
        and b.frame == frame
        and all(name in b.strings for name in POINTS)
    ]
    if len({(b.depth, b.placed_id) for b in loads}) != 1:
        raise RuntimeError(
            f"{len(loads)} clips on {SKILLS_FRAME} read {POINTS}, want 1 hint box"
        )
    depth, sprite = loads[0].depth, loads[0].placed_id
    inside = render.placement_origin(index, KRINMENU, frame, sprite)
    menu = origin_of(index, KRINMENU)
    origin = (menu[0] + inside[0], menu[1] + inside[1])
    starts = {j.label for j in (_jump(b) for b in loads) if j is not None}
    if len(starts) != 1:
        raise RuntimeError(
            f"the clip's event code goes to {sorted(starts)}, want 1 label"
        )
    return sprite, depth, origin, starts.pop()


def _numbers(index: SwfIndex, blocks: list) -> tuple[list[str], list[float]]:
    targets = [a.target for b in blocks for a in avm1.statements(index, b)]
    numbers = [n for b in blocks for n in avm1.numbers(index, b)]
    if not any("MENU" in b.strings for b in blocks):
        raise RuntimeError(f"the script sets {targets} from no MENU string")
    return targets, numbers


def hint_layout(index: SwfIndex) -> tuple[dict, list[tuple[str, list[render.Job]]]]:
    """-> the JSON layout without its strips' frames and rects, and the render
    jobs of each strip by its name."""
    sprite, _depth, origin, start = _hint_placement(index)
    labels = timeline.labels(index, sprite)
    scripts = _frame_scripts(index, sprite)
    jumps = {
        frame: jump
        for frame, blocks in scripts.items()
        for jump in (_jump(b) for b in blocks)
        if jump is not None
    }
    shown = label_frames(labels, jumps, index.sprite_frames[sprite])
    rests = [name for name, frame in labels.items() if frame == 1]
    if len(rests) != 1:
        raise RuntimeError(f"{sprite} has {len(rests)} labels on frame 1, want 1")
    rest = rests[0]
    first_tip, tip_count = tip_strings(*_numbers(index, scripts[1]))
    if start == rest or start not in labels:
        raise RuntimeError(f"the load code goes to {start!r}, which is no step label")

    frames = timeline.frames(index, sprite)
    box_depth = None
    steps: dict[str, dict] = {}
    strips: list[tuple[str, list[render.Job]]] = []
    box_strips: dict[tuple, str] = {}
    for name, label_shown in shown.items():
        if name == rest:
            continue
        frame = labels[name]
        layers = frames[frame - 1]
        kinds = {
            depth: character_kind(index, layer.character_id)
            for depth, layer in layers.items()
        }
        fields = {
            edit_text(index, layers[d].character_id).variable_name: d
            for d, kind in kinds.items()
            if kind == "edittext"
        }
        buttons = [d for d, kind in kinds.items() if kind == "button"]
        sprites = sorted(d for d, kind in kinds.items() if kind == "sprite")
        if set(fields) != {READER, CLICKER} or len(buttons) != 1:
            raise RuntimeError(
                f"label {name!r} places the fields {sorted(fields)} and"
                f" {len(buttons)} buttons, want {READER}, {CLICKER} and 1 button"
            )
        if box_depth is None:
            if name != start or len(sprites) != 1:
                raise RuntimeError(
                    f"the first step label is {name!r} with sprites at {sprites},"
                    f" where {start!r} places the box alone"
                )
            box_depth = sprites[0]
        if box_depth not in sprites:
            raise RuntimeError(f"label {name!r} has no box at depth {box_depth}")
        pointer = tuple(d for d in sprites if d != box_depth)
        reader, clicker = step_strings(*_numbers(index, scripts.get(frame, [])))
        button = layers[buttons[0]]
        records = button_records(index, button.character_id)
        jump = _button_jump(index, button.character_id)
        if jump.label not in labels:
            raise RuntimeError(f"button {button.character_id} goes to {jump.label!r}")
        if jump.plays != (len(shown[jump.label]) > 1):
            raise RuntimeError(
                f"button {button.character_id} goes to {jump.label!r}"
                f"{' and plays' if jump.plays else ''}, which does not match"
                f" that label's {len(shown[jump.label])} frames"
            )

        box = layers[box_depth]
        box_key = (box.character_id, box.matrix)
        if box_key not in box_strips:
            box_strips[box_key] = f"box_{name}"
            box_frames = index.sprite_frames[box.character_id]
            if render.played_frames(index, box.character_id) != list(
                range(1, box_frames + 1)
            ):
                raise RuntimeError(
                    f"the box {box.character_id} stops before its last frame"
                )
            strips.append(
                (
                    box_strips[box_key],
                    [
                        render.Job(
                            sprite,
                            frame,
                            ZOOM,
                            origin=origin,
                            only_depths=(box_depth,),
                            goto=((box_depth, n),),
                        )
                        for n in range(1, box_frames + 1)
                    ],
                )
            )
        pointer_strip = None
        if pointer:
            if len(label_shown) < 2:
                raise RuntimeError(f"label {name!r} holds still with a pointer")
            pointer_strip = f"pointer_{name}"
            strips.append(
                (
                    pointer_strip,
                    [
                        render.Job(sprite, n, ZOOM, origin=origin, only_depths=pointer)
                        for n in label_shown
                    ],
                )
            )
        steps[name] = {
            "reader": reader,
            "clicker": clicker,
            "reader_field": field_record(index, layers[fields[READER]], origin),
            "clicker_field": field_record(index, layers[fields[CLICKER]], origin),
            "button": hit_record(
                records,
                shape_bounds(index, records[0].character_id),
                button.matrix,
                origin,
            )["rect"],
            "next": jump.label,
            "box": box_strips[box_key],
            "pointer": pointer_strip,
        }
    layout = {
        "fps": index.frame_rate,
        "rest": rest,
        "start": start,
        "tips": {"first": first_tip, "count": tip_count},
        "steps": steps,
    }
    return layout, strips


def main():
    index = read_swf(WEB_SWF)
    layout, strips = hint_layout(index)
    jobs = [job for _name, strip in strips for job in strip]
    layout["strips"] = {}
    with render.frames(WEB_SWF, jobs) as rendered:
        at = 0
        for name, strip in strips:
            pieces = render.trim_union(rendered[at : at + len(strip)])
            at += len(strip)
            if pieces is None:
                raise RuntimeError(f"{name} rendered empty")
            rects = {piece.rect for piece in pieces}
            if len(rects) != 1:
                raise RuntimeError(f"{name} frames sit in {len(rects)} boxes")
            folder = OUT_DIR / name
            folder.mkdir(parents=True, exist_ok=True)
            for old in folder.glob("*.png"):
                old.unlink()
            pngs = []
            for n, piece in enumerate(pieces, start=1):
                png.save(piece.image, folder / f"{n}.png")
                pngs.append(f"{name}/{n}.png")
            layout["strips"][name] = {"frames": pngs, "rect": rect_entry(rects.pop())}
            print(f"  {name}: {len(pngs)} frames", file=sys.stderr)
    LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
    print(f"wrote {LAYOUT_JSON}", file=sys.stderr)


if __name__ == "__main__":
    main()
