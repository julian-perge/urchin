# The pass button on the battle frame (root label KRINBATTLESCENE) and the
# picked ability's icon under it:
#
#   assets/ui/battle/pass_button_up.png   - what the button draws in its up state
#   assets/ui/battle/pass_button_over.png - what it draws in its over and down
#                                           states
#   assets/ui/battle/pass_button.json     - where each state's art and the icon
#                                           go on the Stage, and where each
#                                           state's art goes on each orb of
#                                           the Radial menu
#
# The frame places button 3383 as krinToMove2 at depth 498, over krinToMove,
# the ability icon sheet 2427 at depth 484. The button's up state is a thin
# black ring, shape 2434, and its over and down states are a thick one, shape
# 2435. The port draws them as the Button's styles, so each state's rect here
# is where its PNG goes, and the up state's rect is the Button's own rect.
#
# krinToMove shows the frame of the picked ability, so the port puts the
# ability's icon from extract_ability_icons in its place. Those icons are
# centred on the orb's clip mask 2242, so the icon's rect is the placement's
# centre plus and minus ability_icons.ICON_HALF at the placement's scale. This
# raises unless the mask is centred on its own origin and every labelled
# frame of 2427 that places the mask places it at the sprite's origin.
#
# The Radial menu's buttons thingo0 to thingo7 draw the same two rings over
# their icons, so the port draws each orb with these PNGs too. For each orb,
# "orbs" holds each state's rect in the Radial menu clip's own px, as
# battle_layout.json's orb_rects does. This raises unless every orb draws the
# same shape in each state as the pass button, and unless no orb draws them
# larger on the Stage than the pass button does, so each PNG holds at least
# ZOOM pixels for each Stage px on an orb too.
#
# Requires ffdec.
# Run: uv run extract_pass_button
from __future__ import annotations

import json
import shutil
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import FFDEC, WEB_SWF, png
from urchin_dev.run import run
from urchin_dev.swf import render, timeline
from urchin_dev.swf.extract import ability_icons
from urchin_dev.swf.extract.battle_screen import (
    BATTLE_UI_DIR,
    FRAME_LABEL,
    ORB_BUTTON_NAME,
    ORB_COUNT,
    SELECTOR,
    SELECTOR_NAME,
    ZOOM,
    placed_rect,
    px_rect,
)
from urchin_dev.swf.swf_index import (
    ButtonRecord,
    SwfIndex,
    button_records,
    character_kind,
    read_swf,
    shape_bounds,
)

LAYOUT_JSON = BATTLE_UI_DIR / "pass_button.json"
TEXTURES = "res://assets/ui/battle"

BUTTON = 3383
BUTTON_NAME = "krinToMove2"
ICON_NAME = "krinToMove"
ICON_MASK = 2242
# The states a player sees, in the order that names a PNG: a shape that two
# states draw is named for the first of them.
STATES = ("up", "over", "down")


def placement(layers: dict, character: int, name: str) -> timeline.Layer:
    """-> the one layer of a frame that shows `character` under the instance
    name `name`. Raises unless there is one, or when it skews."""
    found = [
        layer
        for layer in layers.values()
        if layer.character_id == character and layer.name == name
    ]
    if len(found) != 1:
        raise RuntimeError(
            f"the battle frame places {character} as {name!r} {len(found)} times, want 1"
        )
    (layer,) = found
    if layer.matrix[1] or layer.matrix[2]:
        raise RuntimeError(f"{name} is placed with a skew: {layer.matrix}")
    return layer


def state_shapes(
    records: list[ButtonRecord], is_shape, button: int = BUTTON
) -> dict[str, int]:
    """-> the shape each visible state of `button` draws, from its records.
    Raises unless each state draws one shape with no matrix of its own."""
    shapes = {}
    for state in STATES:
        drawn = [r for r in records if state in r.states]
        if len(drawn) != 1:
            raise RuntimeError(f"button {button} draws {len(drawn)} records in {state}")
        (record,) = drawn
        if record.matrix != timeline.IDENTITY:
            raise RuntimeError(
                f"button {button} moves its {state} art: {record.matrix}"
            )
        if not is_shape(record.character_id):
            raise RuntimeError(
                f"button {button} draws {record.character_id} in {state}, not a shape"
            )
        shapes[state] = record.character_id
    return shapes


def texture_names(shapes: dict[str, int]) -> dict[int, str]:
    """-> the PNG name of each shape, after the first state that draws it."""
    names: dict[int, str] = {}
    for state in STATES:
        names.setdefault(shapes[state], f"pass_button_{state}.png")
    return names


def state_rects(
    matrix, shapes: dict[str, int], bounds: dict[int, tuple], names: dict[int, str]
) -> dict[str, dict]:
    """-> the rect and the texture of each state, for a button that `matrix`
    places and whose states draw `shapes`. `bounds` holds each shape's
    bounds in twips."""
    return {
        state: {
            "rect": px_rect(placed_rect(matrix, timeline.IDENTITY, bounds[cid])),
            "texture": f"{TEXTURES}/{names[cid]}",
        }
        for state, cid in shapes.items()
    }


def check_orb(
    button: int,
    shapes: dict[str, int],
    pass_shapes: dict[str, int],
    stage_scale: float,
    pass_scale: float,
) -> None:
    """Raises unless the orb's button draws the pass button's shape in each
    state, at a Stage scale no larger than the pass button's."""
    if shapes != pass_shapes:
        raise RuntimeError(
            f"orb button {button} draws {shapes}, the pass button {pass_shapes}"
        )
    if stage_scale > pass_scale:
        raise RuntimeError(
            f"orb button {button} draws its art at {stage_scale},"
            f" larger than the pass button's {pass_scale}"
        )


def orb_layouts(
    index: SwfIndex,
    layers: dict,
    pass_shapes: dict[str, int],
    names: dict[int, str],
    pass_scale: float,
) -> list[dict]:
    """-> state_rects() for each orb button of the Radial menu clip, in the
    clip's own px, in orb order."""
    selector = placement(layers, SELECTOR, SELECTOR_NAME)
    if selector.matrix[0] != selector.matrix[3]:
        raise RuntimeError(f"{SELECTOR_NAME} is scaled unevenly: {selector.matrix}")
    by_name = {
        layer.name: layer for layer in timeline.frames(index, SELECTOR)[0].values()
    }
    bounds = {cid: shape_bounds(index, cid) for cid in names}
    orbs = []
    for n in range(ORB_COUNT):
        button = by_name[f"{ORB_BUTTON_NAME}{n}"]
        if button.matrix[1] or button.matrix[2] or button.matrix[0] != button.matrix[3]:
            raise RuntimeError(f"{button.name} is not scaled evenly: {button.matrix}")
        cid = button.character_id
        shapes = state_shapes(
            button_records(index, cid),
            lambda c: character_kind(index, c) == "shape",
            cid,
        )
        check_orb(
            cid, shapes, pass_shapes, selector.matrix[0] * button.matrix[0], pass_scale
        )
        orbs.append(state_rects(button.matrix, shapes, bounds, names))
    return orbs


def icon_rect(matrix, half: float) -> dict[str, float]:
    """-> the Stage rect of an icon `half` px from its centre on each side,
    which `matrix` places and scales."""
    if matrix[0] != matrix[3]:
        raise RuntimeError(f"{ICON_NAME} is scaled unevenly: {matrix}")
    twips = half * render.TWIPS
    return px_rect(
        placed_rect(matrix, timeline.IDENTITY, (-twips, -twips, twips, twips))
    )


def check_mask_centred(index: SwfIndex) -> None:
    """Raises unless every labelled frame of the icon sheet that places the
    mask places it at the origin, and the mask is centred on its own origin."""
    xmin, ymin, xmax, ymax = shape_bounds(index, ICON_MASK)
    if xmin != -xmax or ymin != -ymax:
        raise RuntimeError(
            f"mask {ICON_MASK} is not centred: {(xmin, ymin, xmax, ymax)}"
        )
    frames = timeline.frames(index, ability_icons.ICON_SPRITE)
    for label, frame in timeline.labels(index, ability_icons.ICON_SPRITE).items():
        for layer in frames[frame - 1].values():
            if layer.character_id == ICON_MASK and layer.matrix != timeline.IDENTITY:
                raise RuntimeError(f"{label} moves the mask: {layer.matrix}")


def pass_layout(index: SwfIndex) -> tuple[dict, dict[int, str], float]:
    """-> the JSON layout of the button's states and the icon, the PNG name of
    each shape the states draw, and the zoom to export the shapes at, so that
    each PNG holds ZOOM pixels for each Stage px at the button's scale."""
    frame = timeline.frame_of(index, 0, FRAME_LABEL)
    layers = timeline.frames(index, 0)[frame - 1]
    button = placement(layers, BUTTON, BUTTON_NAME)
    icon = placement(layers, ability_icons.ICON_SPRITE, ICON_NAME)
    check_mask_centred(index)
    shapes = state_shapes(
        button_records(index, BUTTON), lambda cid: character_kind(index, cid) == "shape"
    )
    names = texture_names(shapes)
    bounds = {cid: shape_bounds(index, cid) for cid in names}
    if button.matrix[0] != button.matrix[3]:
        raise RuntimeError(f"{BUTTON_NAME} is scaled unevenly: {button.matrix}")
    layout = {
        "icon": icon_rect(icon.matrix, ability_icons.ICON_HALF),
        "orbs": orb_layouts(index, layers, shapes, names, button.matrix[0]),
        "states": state_rects(button.matrix, shapes, bounds, names),
        "zoom": ZOOM,
    }
    return layout, names, ZOOM * button.matrix[0]


def render_shapes(names: dict[int, str], zoom: float, layout: dict) -> None:
    """Export each shape through ffdec at `zoom` and write it as its PNG.
    Raises unless each PNG is its state's Stage rect at ZOOM, to within the
    pixel that ffdec rounds a fractional size up by, so the rect that the
    layout gives a state is the rect its PNG covers."""
    work = Path(tempfile.mkdtemp(prefix="pass_button_"))
    try:
        ids = ",".join(str(cid) for cid in sorted(names))
        run([FFDEC, "-zoom", str(zoom), "-format", "shape:png", "-selectid", ids,
             "-export", "shape", work, WEB_SWF])  # fmt: skip
        BATTLE_UI_DIR.mkdir(parents=True, exist_ok=True)
        rects = {
            state["texture"].rsplit("/", 1)[1]: state["rect"]
            for state in layout["states"].values()
        }
        for cid, name in sorted(names.items()):
            image = Image.open(work / f"{cid}.png").convert("RGBA")
            want = (rects[name]["w"] * ZOOM, rects[name]["h"] * ZOOM)
            if any(not 0 <= got - size < 1 for got, size in zip(image.size, want)):
                raise RuntimeError(f"shape {cid} rendered {image.size}, want {want}")
            png.save(image, BATTLE_UI_DIR / name)
            print(f"  {cid} -> {name} {image.size}", file=sys.stderr)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    index = read_swf(WEB_SWF)
    layout, names, zoom = pass_layout(index)
    render_shapes(names, zoom, layout)
    LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
    print(f"wrote {LAYOUT_JSON}", file=sys.stderr)


if __name__ == "__main__":
    main()
