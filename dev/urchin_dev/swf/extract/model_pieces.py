# The art each doll model of extract_model_animations places with no part name,
# which dressChar does not dress and which CharacterVisual draws as it is:
# MODEL8's two body shapes at depths 9 and 10, MODEL2's orb (DefineSprite 1768)
# and MODEL9's bomb (DefineSprite 2468), and the clips that MODEL2, MODEL7 and
# MODEL9 play on their cast, hit or dead frames. Output:
#
#   resources/sprites/model_pieces/<model>_<n>.png  each piece's art at 2x
#   resources/sprites/<model>_pieces.json           for each model that has one
#     {"art": {name: {x, y, w, h}}, "loops": {depth: [name, ...]},
#      "frames": [ {depth: name or {"matrix": [...], "color": [...]}}, ... ]}
#
# A piece is drawn one of two ways:
#
# - A clip that the model places on frame 1 and keeps (the orb and the bomb)
#   loops on its own clock. The model's gotos do not restart it, because Flash
#   keeps a clip that the frame it goes to places at the same depth. Its own
#   frames are rendered around its origin and listed under loops. Each model
#   frame gives the clip's matrix, translation in px, and its colour
#   transform as the red, green, blue and alpha multipliers over 256 and the
#   four offsets over 255.
# - Every other piece is rendered as the model frame shows it, with that
#   frame's matrix and colour transform, and a nested clip on the frame it has
#   reached since the model placed it. A nested clip holds the frame whose
#   script runs stop(), as sprite 884 does on its frame 20. The art's rect is
#   in the model's own space, and frames that look the same share one PNG.
#
# A model frame that lists no piece at a depth draws nothing there.
#
# The clips that MODEL1 places with no name (DefineSprites 149, 153 and 158,
# the swing trails, 162, the cast glow, and 165, the stun mark) are left out.
# Every model places them, the port draws none of them yet, and #456 tracks
# them.
#
# Run: uv run extract_model_pieces
from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field

from urchin_dev import REPO_ROOT, WEB_SWF, png
from urchin_dev.swf import render, timeline
from urchin_dev.swf.extract.battle_screen import rect_entry
from urchin_dev.swf.extract.model_animations import MODELS, PART_NAMES, SHADOW
from urchin_dev.swf.swf_index import SwfIndex, read_swf

SPRITES = REPO_ROOT / "resources" / "sprites"
ART = SPRITES / "model_pieces"
ZOOM = 2.0
EFFECTS_MODEL = "MODEL1"
NO_COLOR = (256, 256, 256, 256, 0, 0, 0, 0)


@dataclass(frozen=True)
class Look:
    """One piece as a model frame shows it: the model frame to render, the
    depth to render alone, and the frame of the nested clip to show there, or
    0 for a shape."""

    frame: int
    depth: int
    child_frame: int


@dataclass
class Plan:
    """What to render for one model and how its frames use the renders. looks
    maps each distinct look to the frames that use it. loops maps a looping
    clip's depth to its sprite id. frames holds, for each model frame, each
    depth's Look or its loop entry."""

    looks: dict[tuple, Look] = field(default_factory=dict)
    loops: dict[int, int] = field(default_factory=dict)
    frames: list[dict[int, object]] = field(default_factory=list)


def effect_clips(index: SwfIndex) -> set[int]:
    """-> the clips that EFFECTS_MODEL places with no name."""
    return {
        layer.character_id
        for snap in timeline.frames(index, MODELS[EFFECTS_MODEL])
        for layer in snap.values()
        if layer.name is None
    }


def last_played_frame(index: SwfIndex, sprite: int) -> int:
    """-> the frame a clip that plays once holds: the first whose script runs
    stop(), or its last frame."""
    count = index.sprite_frames[sprite]
    return next(
        (
            frame
            for frame in range(1, count + 1)
            if render.runs_stop(index, sprite, frame)
        ),
        count,
    )


def plan(index: SwfIndex, sprite: int, effects: set[int]) -> Plan:
    """-> the Plan for the model sprite `sprite`, leaving out the clips in
    `effects`."""
    snaps = timeline.frames(index, sprite)
    result = Plan()
    run_start: dict[int, tuple[int, int]] = {}
    for number, snap in enumerate(snaps, start=1):
        shown: dict[int, object] = {}
        run_start = {depth: run for depth, run in run_start.items() if depth in snap}
        for depth, layer in sorted(snap.items()):
            if layer.name in PART_NAMES or layer.name == SHADOW:
                continue
            if layer.name is not None:
                raise ValueError(
                    f"frame {number} depth {depth}: {layer.name} is neither a doll"
                    " part nor the shadow"
                )
            cid = layer.character_id
            if cid in effects:
                continue
            started = run_start.get(depth)
            if started is None or started[0] != cid:
                started = (cid, number)
            run_start[depth] = started
            color = layer.color_transform or NO_COLOR
            if depth in result.loops or (
                started[1] == 1 and index.sprite_frames.get(cid, 0) > 1
            ):
                if result.loops.setdefault(depth, cid) != cid:
                    raise ValueError(
                        f"frame {number} depth {depth}: {cid} replaces the clip"
                        f" {result.loops[depth]} that loops there"
                    )
                a, b, c, d, tx, ty = layer.matrix
                shown[depth] = {
                    "matrix": [
                        round(a, 4),
                        round(b, 4),
                        round(c, 4),
                        round(d, 4),
                        round(tx / render.TWIPS, 2),
                        round(ty / render.TWIPS, 2),
                    ],
                    "color": [round(v / 256, 4) for v in color[:4]]
                    + [round(v / 255, 4) for v in color[4:]],
                }
                continue
            child_frame = 0
            if cid in index.sprite_frames:
                age = number - started[1] + 1
                held = last_played_frame(index, cid)
                looping = index.sprite_frames[cid] > 1 and not render.runs_stop(
                    index, cid, held
                )
                if age > held and looping:
                    raise ValueError(
                        f"frame {number} depth {depth}: clip {cid} has played its"
                        f" {held} frames and runs no stop(), so Flash would loop it"
                    )
                child_frame = min(age, held)
            key = (cid, layer.matrix, color, child_frame)
            look = result.looks.setdefault(key, Look(number, depth, child_frame))
            shown[depth] = look
        result.frames.append(shown)
    return result


def art_name(model: str, number: int) -> str:
    return f"{model.lower()}_{number}"


def loop_name(model: str, depth: int, frame: int) -> str:
    return f"{model.lower()}_d{depth}_{frame}"


def out_path(model: str):
    return SPRITES / f"{model.lower()}_pieces.json"


def render_model(index: SwfIndex, model: str, planned: Plan) -> dict | None:
    """-> the JSON for `model`, after it writes the model's PNGs, or None when
    the model has no piece."""
    sprite = MODELS[model]
    if not planned.looks and not planned.loops:
        return None
    names: dict[Look, str] = {}
    jobs: dict[render.Job, str] = {}
    for look in planned.looks.values():
        name = art_name(model, len(names))
        names[look] = name
        goto = ((look.depth, look.child_frame),) if look.child_frame else ()
        job = render.Job(sprite, look.frame, ZOOM, only_depths=(look.depth,), goto=goto)
        jobs[job] = name
    loops: dict[str, list[str]] = {}
    for depth, clip in planned.loops.items():
        loops[str(depth)] = []
        for frame in range(1, index.sprite_frames[clip] + 1):
            name = loop_name(model, depth, frame)
            loops[str(depth)].append(name)
            jobs[render.Job(clip, frame, ZOOM)] = name
    art: dict[str, dict | None] = {}
    with render.frames(WEB_SWF, list(jobs)) as rendered:
        for frame in rendered:
            name = jobs[frame.job]
            trimmed = render.trim(frame)
            if trimmed is None:
                art[name] = None
                continue
            png.save(trimmed.image, ART / f"{name}.png")
            art[name] = rect_entry(trimmed.rect)
    frames = []
    for shown in planned.frames:
        entry = {}
        for depth, piece in shown.items():
            if isinstance(piece, Look):
                if art[names[piece]] is None:
                    continue
                entry[str(depth)] = names[piece]
            else:
                entry[str(depth)] = piece
        frames.append(entry)
    return {
        "art": {name: rect for name, rect in sorted(art.items()) if rect is not None},
        "loops": loops,
        "frames": frames,
    }


def main():
    index = read_swf(WEB_SWF)
    effects = effect_clips(index)
    # Every model is planned before any art is written, so a model that fails
    # its checks leaves the committed art as it was.
    plans = {model: plan(index, sprite, effects) for model, sprite in MODELS.items()}
    ART.mkdir(parents=True, exist_ok=True)
    written: set[str] = set()
    for model in MODELS:
        out = out_path(model)
        result = render_model(index, model, plans[model])
        if result is None:
            out.unlink(missing_ok=True)
            print(model, "has no pieces", file=sys.stderr)
            continue
        written.update(result["art"])
        out.write_text(json.dumps(result, sort_keys=True) + "\n")
        print(model, len(result["art"]), "renders, wrote", out, file=sys.stderr)
    # A PNG that no model uses any more goes with its .import file. The .import
    # files of the PNGs that stay keep their uids, which Godot's scenes and
    # caches refer to.
    for stale in ART.glob("*.png"):
        if stale.stem not in written:
            stale.unlink()
            stale.with_name(stale.name + ".import").unlink(missing_ok=True)


if __name__ == "__main__":
    main()
