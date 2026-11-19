# The Ground shadow under each doll. Every model sprite (MODEL1, MODEL2, ...)
# places the clip DefineSprite 144 at depth 1 under the instance name
# `shadower`, below its parts, so the shadow moves, turns and fades with the doll:
#
#   resources/sprites/doll_shadow.png   the clip, rendered alone
#   resources/sprites/doll_shadow.json  the clip's rect around its own origin,
#                                       and each model's placement matrix
#
# The matrix is (scaleX, skew0, skew1, scaleY, tx, ty), with the translation in
# design px. MODEL1 places the clip with no scale and no skew. The others scale
# and skew it, so the port places the clip with the whole matrix.
#
# MODEL5 and MODEL8 and MODEL7 move the shadow on later frames of their own
# clips (frames 71 and 108, and frame 174). This file holds the frame 1
# placement, and extract_model_animations writes the matrix of every frame.
#
# Frame 360 of MODEL1 and frame 295 of MODEL4 run `_parent.shadower._visible =
# false`. `_parent` is the unit's rig (DefineSprite 2676), which holds no clip
# named `shadower`, so that script hides nothing. The shadow lasts until the
# script on the last frame removes the whole doll, as the doll's own parts do.
#
# The art is rendered at 2x, the window's default scale, as the doll is.
#
# Run: uv run extract_doll_shadow
from __future__ import annotations

import json
import re
import sys

from urchin_dev import REPO_ROOT, WEB_SWF, png
from urchin_dev.swf import render, timeline
from urchin_dev.swf.extract.battle_screen import rect_entry
from urchin_dev.swf.swf_index import SwfIndex, read_swf

SPRITES = REPO_ROOT / "resources" / "sprites"
PNG_FILE = SPRITES / "doll_shadow.png"
LAYOUT_JSON = SPRITES / "doll_shadow.json"
ZOOM = 2.0
CLIP = "shadower"
MODEL_NAME = re.compile(r"MODEL\d+")


def shadow_placements(
    index: SwfIndex,
) -> tuple[int, dict[str, tuple[float, float, float, float, float, float]]]:
    """-> the one sprite that every model places as `shadower`, and each model's
    frame 1 matrix for it, with the translation in design px. Raises unless
    each model places exactly one such clip and all of them place the same
    sprite."""
    sprites: set[int] = set()
    matrices: dict[str, tuple[float, float, float, float, float, float]] = {}
    for name, model in sorted(index.exports.items()):
        if not MODEL_NAME.fullmatch(name):
            continue
        placed = [
            layer
            for layer in timeline.frames(index, model)[0].values()
            if layer.name == CLIP
        ]
        if len(placed) != 1:
            raise RuntimeError(
                f"{name} ({model}) frame 1 places {len(placed)} clips named {CLIP!r},"
                " want 1"
            )
        layer = placed[0]
        sprites.add(layer.character_id)
        a, b, c, d, tx, ty = layer.matrix
        matrices[name] = (a, b, c, d, tx / render.TWIPS, ty / render.TWIPS)
    if len(sprites) != 1:
        raise RuntimeError(f"the models place {len(sprites)} different clips as {CLIP}")
    return sprites.pop(), matrices


def main():
    index = read_swf(WEB_SWF)
    clip, matrices = shadow_placements(index)
    with render.frames(WEB_SWF, [render.Job(clip, 1, ZOOM)]) as rendered:
        trimmed = render.trim(rendered[0])
        if trimmed is None:
            raise RuntimeError(f"{CLIP} ({clip}) rendered empty")
        png.save(trimmed.image, PNG_FILE)
        rect = rect_entry(trimmed.rect)
    layout = {
        "rect": rect,
        "models": {
            name: [round(value, 4) for value in matrix]
            for name, matrix in matrices.items()
        },
    }
    LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
    print(f"{CLIP}: sprite {clip}, {len(matrices)} models", file=sys.stderr)
    print(f"wrote {LAYOUT_JSON}", file=sys.stderr)


if __name__ == "__main__":
    main()
