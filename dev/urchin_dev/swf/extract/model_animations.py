# The keyframe animations of the doll models in MODELS: per-frame full affine
# matrices for the 15 named doll parts across every frame of the model's
# timeline (classic tweens are baked into per-frame PlaceObject matrices by the
# Flash exporter). Output: resources/sprites/<model>_animations.json, such as
# model4_animations.json, each
#   {"fps": 30, "labels": {name: {"start": 1-based, "end": inclusive}},
#    "frames": [ {part: [a, b, c, d, tx_px, ty_px]}, ... ],
#    "alphas": [ {part: alpha}, ... ], "depths": {part: depth}}
# where the matrix columns are Godot Transform2D's x=(a,b), y=(c,d),
# origin=(tx,ty) - translations converted from twips to px.
#
# alphas has one entry per frame, listing each part whose colour transform
# fades it below full alpha. The dead label fades every part this way on
# frames 361 to 371. The red, green and blue multipliers are left out, so the
# back limbs that MODEL1 darkens to 154/256 on every frame draw at full
# brightness in the port.
#
# depths holds the depth each part has on frame 1, which is its draw order: a
# higher depth draws in front. No part of MODEL1 or MODEL4 changes its depth
# on a later frame, and animations() fails if one does.
#
# MODEL5 to MODEL8 are left out. They have fewer named parts than the 15 that
# CharacterVisual draws (MODEL8 also places unnamed clips), and MODEL2 and
# MODEL9 name no parts at all, so drawing them needs more than their timelines.
#
# Run: uv run extract_model_animations
from __future__ import annotations

import json
import sys

from urchin_dev import REPO_ROOT, WEB_SWF
from urchin_dev.swf import timeline
from urchin_dev.swf.swf_index import SwfIndex, read_swf

SPRITES = REPO_ROOT / "resources" / "sprites"
# Each model's DefineSprite in the web SWF.
MODELS = {"MODEL1": 166, "MODEL4": 2668}
FPS = 30.0

PART_NAMES = {
    "head",
    "chest",
    "arm1",
    "arm2",
    "hand1",
    "hand2",
    "leg1",
    "leg2",
    "leg3",
    "leg4",
    "foot1",
    "foot2",
    "weapon1",
    "weapon2",
    "shoulder",
}


def animations(index: SwfIndex, sprite: int) -> dict:
    """-> the JSON this writes for one sprite's timeline."""
    snaps = timeline.frames(index, sprite)
    labels = timeline.labels(index, sprite)
    frame_count = len(snaps)

    # A label ends just before the next label that starts on a later frame,
    # because MODEL4 starts three labels on one frame.
    starts = sorted(set(labels.values()))
    label_ranges = {}
    for name, start in sorted(labels.items(), key=lambda kv: kv[1]):
        later = [frame for frame in starts if frame > start]
        end = later[0] - 1 if later else frame_count
        label_ranges[name] = {"start": start, "end": end}

    depths = {
        layer.name: depth
        for depth, layer in snaps[0].items()
        if layer.name in PART_NAMES
    }

    frames = []
    alphas = []
    for snap in snaps:
        pose = {}
        faded = {}
        for depth, layer in snap.items():
            part = layer.name
            if part not in PART_NAMES:
                continue
            if depths.get(part, depth) != depth:
                raise ValueError(
                    f"frame {len(frames) + 1}: {part} moved from depth"
                    f" {depths[part]} to {depth}"
                )
            a, b, c, d, tx, ty = layer.matrix
            pose[part] = [
                round(a, 4),
                round(b, 4),
                round(c, 4),
                round(d, 4),
                round(tx / 20.0, 2),
                round(ty / 20.0, 2),
            ]
            if layer.color_transform is not None:
                alpha_multiplier = max(0, min(layer.color_transform[3], 256))
                if alpha_multiplier < 256:
                    faded[part] = round(alpha_multiplier / 256, 4)
        frames.append(pose)
        alphas.append(faded)
    return {
        "fps": FPS,
        "labels": label_ranges,
        "frames": frames,
        "alphas": alphas,
        "depths": depths,
    }


def out_path(model: str):
    return SPRITES / f"{model.lower()}_animations.json"


def main():
    index = read_swf(WEB_SWF)
    for model, sprite in MODELS.items():
        result = animations(index, sprite)
        label_ranges = result["labels"]
        print(
            model,
            "frames:",
            len(result["frames"]),
            "labels:",
            label_ranges,
            file=sys.stderr,
        )
        out = out_path(model)
        out.write_text(json.dumps(result))
        print("wrote", out, file=sys.stderr)


if __name__ == "__main__":
    main()
