# CS_INTRO, the text screen the original opens the Tutorial on: four lines over
# a dark gradient. It is the one Cutscene that is not an animation, so
# extract_cutscenes cannot render it as a clip. This extractor writes what a
# Godot scene needs to build it again:
#
#   assets/cutscenes/cs_intro_background.png - the gradient, DefineShape 3475
#   assets/cutscenes/cs_intro.json           - the four lines, where each sits
#                                              and how it is styled, and how
#                                              long the screen holds
#
# WHAT THE ORIGINAL DRAWS. Root frame CS_INTRO (263) places the gradient at
# depth 1 and four edit texts above it, each with a Glow and a DropShadow
# filter. The frame's script puts MENU[86] to MENU[89] of the language in
# KLangChoosen in the four texts (frame_263/DoAction.as:2-5). The root frame
# scripts build the KrinLang table that holds those strings, and set
# KLangChoosen to ENGLISH.
#
# THE TEXTS' initialText IS NOT USED. Each field bakes in the author's text,
# which the script replaces at runtime. Only the first field's text differs from
# its MENU string, and the other three are the same words. The lines in the JSON
# are the MENU strings, and the gradient is rendered with every depth but the
# gradient's hidden, so no baked text reaches a render.
#
# HOW LONG IT HOLDS. DefineSprite 3470 is placed on the same frame. It shows
# nothing and plays no sound, and its last frame sets cutSceneEnd, which makes
# the controller on the frame fade the screen out and leave (frame_263/
# PlaceObject2_3466_80 enterFrame). So the screen holds for that sprite's frame
# count at the SWF's frame rate.
#
# THE LINES ARE LABELS. The texts use the bold Device font _sans, which the port
# draws in its Stand-in font, and the game fills them at runtime, so the port
# draws each as a Label at the field's own placement. The fields allow wrapping,
# but each MENU string fits on one line, which test_cutscene_player.gd checks.
#
# Run: uv run extract_cs_intro
from __future__ import annotations

import json
import math
import re
import sys

from urchin_dev import REPO_ROOT, WEB_SWF, png
from urchin_dev.swf import avm1, label_layout, render, timeline
from urchin_dev.swf.swf_index import (
    CodeBlock,
    Filter,
    Placement,
    SwfIndex,
    character_kind,
    edit_text,
    placement_filters,
    read_swf,
    sound_stream,
)

OUT_DIR = REPO_ROOT / "assets" / "cutscenes"
BACKGROUND_PNG = OUT_DIR / "cs_intro_background.png"
LAYOUT_JSON = OUT_DIR / "cs_intro.json"

FRAME_LABEL = "CS_INTRO"
BACKGROUND = 3475
TIMER = 3470
LANGUAGE_VARIABLE = "KLangChoosen"
END_VARIABLE = "cutSceneEnd"
# The start screens' backgrounds are rendered at 2x, as docs/agents/
# art-extraction.md sets out.
ZOOM = 2.0

MENU_ENTRY = re.compile(r"KrinLang\.(?P<language>\w+)\.MENU\.(?P<number>\d+)")

# `name = _root.KrinLang[KLangChoosen].MENU[number]` as AVM1 actions: push the
# name and _root, read _root, push KrinLang and read the member, push
# KLangChoosen, read it and use it as a member name, push MENU and read the
# member, push the number and read the member, then set the variable. PUSHES
# are the places in that list of the Push actions.
MENU_STATEMENT = (
    avm1.ACTION_PUSH,
    avm1.ACTION_GET_VARIABLE,
    avm1.ACTION_PUSH,
    avm1.ACTION_GET_MEMBER,
    avm1.ACTION_PUSH,
    avm1.ACTION_GET_VARIABLE,
    avm1.ACTION_GET_MEMBER,
    avm1.ACTION_PUSH,
    avm1.ACTION_GET_MEMBER,
    avm1.ACTION_PUSH,
    avm1.ACTION_GET_MEMBER,
    avm1.ACTION_SET_VARIABLE,
)
PUSHES = (0, 2, 4, 7, 9)


def assignments_up_to(index: SwfIndex, frame: int) -> list[avm1.Assignment]:
    """-> every assignment the root timeline's frame scripts make from frame 1
    to `frame`, in the order the scripts run."""
    return [
        assignment
        for block in index.code
        if block.kind == "frame" and block.owner == 0 and block.frame <= frame
        for assignment in avm1.statements(index, block)
    ]


def language(assigned: list[avm1.Assignment]) -> str:
    """-> the language the scripts leave in KLangChoosen. Raises unless they
    set it to one text only."""
    values = {a.value for a in assigned if a.target == LANGUAGE_VARIABLE}
    if len(values) != 1 or not all(isinstance(v, str) for v in values):
        raise RuntimeError(f"want one text in {LANGUAGE_VARIABLE}, found {values}")
    (value,) = values
    return value


def menu_strings(assigned: list[avm1.Assignment], chosen: str) -> dict[int, str]:
    """-> {n: the text of MENU[n]} for language `chosen`. Raises when a script
    assigns an entry something other than text, or two scripts assign one entry
    different text, because the line the player sees would then depend on which
    script ran last."""
    strings: dict[int, str] = {}
    for assignment in assigned:
        match = MENU_ENTRY.fullmatch(assignment.target)
        if match is None or match["language"] != chosen:
            continue
        number, text = int(match["number"]), assignment.value
        if not isinstance(text, str):
            raise TypeError(f"MENU[{number}] is set to {text!r}, not text")
        if strings.setdefault(number, text) != text:
            raise RuntimeError(
                f"MENU[{number}] is set to {strings[number]!r} and to {text!r}"
            )
    return strings


def menu_numbers(index: SwfIndex, block: CodeBlock) -> dict[str, int]:
    """-> {variable: n} for each `variable = _root.KrinLang[KLangChoosen].
    MENU[n]` in the frame script. Raises on any other action in the script,
    apart from the constant pool and stop(), so a script that did more would
    not pass for these four lines."""
    actions = [
        a
        for a in avm1.actions(index, block)
        if a.code not in (avm1.ACTION_CONSTANT_POOL, avm1.ACTION_STOP)
    ]
    size = len(MENU_STATEMENT)
    if not actions or len(actions) % size:
        raise RuntimeError(
            f"the frame script is not a list of MENU statements: {actions}"
        )
    numbers: dict[str, int] = {}
    for start in range(0, len(actions), size):
        statement = actions[start : start + size]
        if tuple(a.code for a in statement) != MENU_STATEMENT:
            raise RuntimeError(f"not a MENU statement: {statement}")
        (variable, root), (krin_lang,), (chosen,), (menu,), (number,) = (
            statement[at].args for at in PUSHES
        )
        if (root, krin_lang, chosen, menu) != (
            "_root",
            "KrinLang",
            LANGUAGE_VARIABLE,
            "MENU",
        ):
            raise RuntimeError(f"not a read of _root.KrinLang[...].MENU: {statement}")
        numbers[variable] = int(number)
    return numbers


def hold_frames(index: SwfIndex, layers: dict) -> int:
    """-> how many frames the screen holds, which is the frame count of the
    timer sprite. Raises unless the frame places the sprite, the sprite runs
    one script, on its last frame, that sets cutSceneEnd to true, and it draws
    nothing and plays no sound."""
    if TIMER not in {layer.character_id for layer in layers.values()}:
        raise RuntimeError(f"{FRAME_LABEL} does not place sprite {TIMER}")
    frames = index.sprite_frames[TIMER]
    scripts = [b for b in index.code if b.kind == "frame" and b.owner == TIMER]
    if [b.frame for b in scripts] != [frames]:
        raise RuntimeError(
            f"sprite {TIMER} runs scripts on frames {[b.frame for b in scripts]},"
            f" want its last frame, {frames}"
        )
    sets = [(a.target, a.value) for a in avm1.statements(index, scripts[0])]
    if sets != [(f"_root.{END_VARIABLE}", True)]:
        raise RuntimeError(f"sprite {TIMER}'s last frame sets {sets}")
    if any(timeline.frames(index, TIMER)):
        raise RuntimeError(f"sprite {TIMER} draws something")
    if sound_stream(index, TIMER):
        raise RuntimeError(f"sprite {TIMER} plays a sound")
    return frames


def placement_at(index: SwfIndex, frame: int, depth: int, character: int) -> Placement:
    """-> the root timeline's Placement that puts `character` at `depth` on
    `frame`. Raises unless exactly one tag does, and it is a place, not a move."""
    found = [
        p
        for p in index.display[0]
        if isinstance(p, Placement) and p.frame == frame and p.depth == depth
    ]
    if len(found) != 1 or found[0].character_id != character or found[0].move:
        raise RuntimeError(f"frame {frame} depth {depth} does not place {character}")
    return found[0]


def filter_entry(filt: Filter) -> dict:
    """-> a filter as JSON. Raises for one a Label's outline or shadow cannot
    stand for: an inner or knockout filter, or one that leaves out the text."""
    if filt.inner or filt.knockout or not filt.composite_source:
        raise RuntimeError(f"{filt.kind} is not an outer filter over the text: {filt}")
    red, green, blue, alpha = filt.color
    return {
        "alpha": alpha / 255,
        "angle": filt.angle,
        "blur_x": filt.blur_x,
        "blur_y": filt.blur_y,
        "color": f"#{red:02x}{green:02x}{blue:02x}",
        "distance": filt.distance,
        "passes": filt.passes,
        "strength": filt.strength,
    }


def intro_lines(
    index: SwfIndex,
    frame: int,
    layers: dict,
    numbers: dict[str, int],
    strings: dict[int, str],
) -> list[dict]:
    """-> one entry per MENU line, in MENU order: its text, and the rect,
    alignment, colour, size, Glow and DropShadow of the text field the frame
    script fills with it."""
    fields = [
        (edit_text(index, layer.character_id).variable_name, depth, layer)
        for depth, layer in layers.items()
        if character_kind(index, layer.character_id) == "edittext"
    ]
    placed = {variable: (depth, layer) for variable, depth, layer in fields}
    if len(placed) != len(fields):
        raise RuntimeError(f"two edit texts on frame {frame} show one variable")
    lines = []
    for variable, number in sorted(numbers.items(), key=lambda item: item[1]):
        if variable not in placed:
            raise RuntimeError(f"no edit text on frame {frame} shows {variable}")
        if number not in strings:
            raise RuntimeError(f"{variable} is MENU[{number}], which no script sets")
        depth, layer = placed[variable]
        field_id = layer.character_id
        field = label_layout.plain_device_line(index, field_id, wrapping=True)
        position = render.placement_origin(index, 0, frame, field_id)
        filters = placement_filters(index, placement_at(index, frame, depth, field_id))
        if [f.kind for f in filters] != ["Glow", "DropShadow"]:
            raise RuntimeError(f"edit text {field_id} has filters {filters}")
        glow, shadow = (filter_entry(f) for f in filters)
        print(
            f"  {variable} = MENU[{number}] in edit text {field_id} at depth {depth},"
            f" initialText {field.initial_text!r} not used",
            file=sys.stderr,
        )
        lines.append(
            {
                **label_layout.text_layout(field, position),
                "glow": glow,
                "menu": number,
                "shadow": shadow,
                "text": strings[number],
                "wrap": field.word_wrap,
            }
        )
    return lines


def write_background(index: SwfIndex, frame: int, layers: dict) -> None:
    """Render the gradient alone from the CS_INTRO frame, and write it. Raises
    unless it fills the stage, which is what the scene stretches over the
    window."""
    (depth,) = [d for d, layer in layers.items() if layer.character_id == BACKGROUND]
    if character_kind(index, BACKGROUND) != "shape":
        raise RuntimeError(f"character {BACKGROUND} is not a shape")
    job = render.Job(0, frame, ZOOM, only_depths=(depth,))
    with render.frames(WEB_SWF, [job]) as (rendered,):
        trimmed = render.trim(rendered)
    if trimmed is None:
        raise RuntimeError(f"shape {BACKGROUND} rendered empty")
    left, top, right, bottom = (v / render.TWIPS for v in index.stage)
    if not all(
        math.isclose(a, b)
        for a, b in zip(trimmed.rect, (left, top, right - left, bottom - top))
    ):
        raise RuntimeError(f"the gradient is {trimmed.rect}, not the whole stage")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    png.save(trimmed.image, BACKGROUND_PNG)
    print(f"wrote {BACKGROUND_PNG} {trimmed.image.size}", file=sys.stderr)


def main():
    index = read_swf(WEB_SWF)
    frame = timeline.frame_of(index, 0, FRAME_LABEL)
    layers = timeline.frames(index, 0)[frame - 1]
    print(f"{FRAME_LABEL}: root frame {frame}", file=sys.stderr)

    assigned = assignments_up_to(index, frame)
    chosen = language(assigned)
    strings = menu_strings(assigned, chosen)
    (script,) = [
        b for b in index.code if b.kind == "frame" and b.owner == 0 and b.frame == frame
    ]
    numbers = menu_numbers(index, script)
    print(f"language {chosen}, lines {numbers}", file=sys.stderr)

    frames = hold_frames(index, layers)
    print(
        f"holds {frames} frames at {index.frame_rate} fps, or"
        f" {frames / index.frame_rate:.2f} s",
        file=sys.stderr,
    )
    layout = {
        "fps": index.frame_rate,
        "hold_frames": frames,
        "lines": intro_lines(index, frame, layers, numbers, strings),
    }
    write_background(index, frame, layers)
    LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
    print(f"wrote {LAYOUT_JSON}", file=sys.stderr)


if __name__ == "__main__":
    main()
