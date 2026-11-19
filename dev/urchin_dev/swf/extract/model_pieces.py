# The art each doll model of extract_model_animations places with no part name,
# which dressChar does not dress and which CharacterVisual draws as it is:
# MODEL8's two body shapes at depths 9 and 10, MODEL2's orb (DefineSprite 1768)
# and MODEL9's bomb (DefineSprite 2468), the clips that MODEL2, MODEL7 and
# MODEL9 play on their cast, hit or dead frames, and the effect clips that
# MODEL1 places with no name and the other models place too: the swing trails
# (DefineSprites 149, 153 and 158), the cast glow (162) and the stun mark (165).
# Output:
#
#   resources/sprites/model_pieces/<name>.png  each piece's art at 2x
#   resources/sprites/<model>_pieces.json      for each model that has one
#     {"art": {name: {x, y, w, h}},
#      "clips": {id: {"frames": [name, ...], "tints": [name, ...], "hold": n}},
#      "frames": [ {depth: name or {"clip", "since", "matrix", "color"}}, ... ]}
#
# A piece is drawn one of two ways:
#
# - A clip piece plays on its own clock, which starts on the model frame that
#   placed it and which "since" gives. A goto does not restart it while the
#   frame it goes to shows the same placement, because Flash keeps that clip.
#   So the orb loops through the stand label's goto, and the stun mark loops
#   through stun2's. Its own frames are rendered around its origin and listed
#   under clips, as clip<id>_<frame>. A clip holds its "hold" frame, the first
#   whose script runs stop(), and a clip with no "hold" loops. Each model frame
#   gives the clip's matrix, translation in px, and its colour transform as the
#   red, green, blue and alpha multipliers over 256 and the four offsets over
#   255. The clips that MODEL1 places with no name, and any clip that a model
#   places on its frame 1 and that has more than one frame, are clip pieces.
# - Every other piece is rendered as the model frame shows it, with that
#   frame's matrix and colour transform, and a nested clip on the frame it has
#   reached since the model placed it. A nested clip holds the frame whose
#   script runs stop(), as sprite 884 does on its frame 20. The art's rect is
#   in the model's own space, and frames that look the same share one PNG.
#
# A part of a clip piece whose onClipEvent(load) runs setRGB with colortobe,
# such as 161 in the cast glow, takes the doll's colortobe as its colour when
# the clip is placed. Its frames are rendered alone, as clip<id>_tint_<frame>,
# and CharacterVisual draws them in that colour behind the rest of the clip.
#
# A model frame that lists no piece at a depth draws nothing there.
#
# Run: uv run extract_model_pieces
from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field

from urchin_dev import REPO_ROOT, WEB_SWF, png
from urchin_dev.swf import render, timeline
from urchin_dev.swf.extract.battle_screen import rect_entry
from urchin_dev.swf.extract.battle_screen_motion import CLIP_EVENT_LOAD
from urchin_dev.swf.extract.model_animations import MODELS, PART_NAMES, SHADOW
from urchin_dev.swf.swf_index import SwfIndex, read_swf

SPRITES = REPO_ROOT / "resources" / "sprites"
ART = SPRITES / "model_pieces"
ZOOM = 2.0
EFFECTS_MODEL = "MODEL1"
NO_COLOR = (256, 256, 256, 256, 0, 0, 0, 0)
# The names a load script pushes when it runs my_color.setRGB(...colortobe).
TINT_STRINGS = {"setRGB", "colortobe"}


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
    maps each distinct look to the frames that use it. clips holds the sprite
    id of each clip piece. frames holds, for each model frame, each depth's
    Look or its clip entry."""

    looks: dict[tuple, Look] = field(default_factory=dict)
    clips: set[int] = field(default_factory=set)
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


def clip_hold(index: SwfIndex, sprite: int) -> int | None:
    """-> the frame a clip piece holds, the first whose script runs stop(), or
    None when the clip loops."""
    held = last_played_frame(index, sprite)
    return held if render.runs_stop(index, sprite, held) else None


def _depths(index: SwfIndex, owner: int) -> set[int]:
    return {depth for snap in timeline.frames(index, owner) for depth in snap}


def tint_path(index: SwfIndex, clip: int) -> tuple[tuple[int, int, int], ...]:
    """-> each (owner, depth, character) placement from `clip` down to the one
    whose onClipEvent(load) runs setRGB with colortobe, or () when no part of
    `clip` does. Raises when two parts do, or when the tinted part draws above
    another depth of its owner, since the port draws it behind the clip."""
    found = []
    if clip not in index.sprite_frames:
        return ()

    def walk(owner: int, path: tuple) -> None:
        for block in index.code:
            if (
                block.kind == "clip"
                and block.owner == owner
                and block.events & CLIP_EVENT_LOAD
                and TINT_STRINGS <= set(block.strings)
            ):
                found.append((*path, (owner, block.depth, block.placed_id)))
        placed = {
            (depth, layer.character_id)
            for snap in timeline.frames(index, owner)
            for depth, layer in snap.items()
        }
        for depth, cid in sorted(placed):
            if cid in index.sprite_frames:
                walk(cid, (*path, (owner, depth, cid)))

    walk(clip, ())
    if len(found) > 1:
        raise ValueError(f"clip {clip} tints {len(found)} parts with colortobe")
    if not found:
        return ()
    path = found[0]
    for owner, depth, _cid in path:
        if any(other < depth for other in _depths(index, owner)):
            raise ValueError(
                f"clip {clip}: the tinted part at depth {depth} of {owner} draws"
                " above another depth"
            )
    return path


def plain_hides(path: tuple[tuple[int, int, int], ...]) -> tuple[tuple[int, int], ...]:
    """-> the (owner, depth) that a render of a clip without its tinted part
    hides."""
    owner, depth, _cid = path[-1]
    return ((owner, depth),)


def tint_hides(
    index: SwfIndex, path: tuple[tuple[int, int, int], ...]
) -> tuple[tuple[int, int], ...]:
    """-> every (owner, depth) that a render of a clip's tinted part alone
    hides: each other depth of each owner on the path."""
    return tuple(
        (owner, other)
        for owner, depth, _cid in path
        for other in sorted(_depths(index, owner))
        if other != depth
    )


def plan(index: SwfIndex, sprite: int, effects: set[int]) -> Plan:
    """-> the Plan for the model sprite `sprite`, which draws the clips in
    `effects` as clip pieces."""
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
            started = run_start.get(depth)
            if started is None or started[0] != cid:
                started = (cid, number)
            run_start[depth] = started
            color = layer.color_transform or NO_COLOR
            if (
                cid in effects
                or cid in result.clips
                or (started[1] == 1 and index.sprite_frames.get(cid, 0) > 1)
            ):
                result.clips.add(cid)
                a, b, c, d, tx, ty = layer.matrix
                shown[depth] = {
                    "clip": str(cid),
                    "since": started[1],
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


def clip_name(clip: int, frame: int) -> str:
    return f"clip{clip}_{frame}"


def tint_name(clip: int, frame: int) -> str:
    return f"clip{clip}_tint_{frame}"


def out_path(model: str):
    return SPRITES / f"{model.lower()}_pieces.json"


def render_model(index: SwfIndex, model: str, planned: Plan) -> dict | None:
    """-> the JSON for `model`, after it writes the model's PNGs, or None when
    the model has no piece."""
    sprite = MODELS[model]
    if not planned.looks and not planned.clips:
        return None
    names: dict[Look, str] = {}
    jobs: dict[render.Job, str] = {}
    for look in planned.looks.values():
        name = art_name(model, len(names))
        names[look] = name
        goto = ((look.depth, look.child_frame),) if look.child_frame else ()
        job = render.Job(sprite, look.frame, ZOOM, only_depths=(look.depth,), goto=goto)
        jobs[job] = name
    clips: dict[str, dict] = {}
    for clip in sorted(planned.clips):
        path = tint_path(index, clip)
        entry: dict = {"frames": []}
        if path:
            entry["tints"] = []
        held = clip_hold(index, clip)
        if held is not None:
            entry["hold"] = held
        snaps = timeline.frames(index, clip)
        top_depth, holder = path[0][1:] if path else (None, None)
        for frame in range(1, index.sprite_frames[clip] + 1):
            name = clip_name(clip, frame)
            entry["frames"].append(name)
            hides = plain_hides(path) if path else ()
            jobs[render.Job(clip, frame, ZOOM, hide_depths=hides)] = name
            if not path:
                continue
            # A frame on which the tinted part's holder is not at its depth has
            # no tinted part, and its name stays out of the art like any frame
            # that draws nothing.
            name = tint_name(clip, frame)
            entry["tints"].append(name)
            layer = snaps[frame - 1].get(top_depth)
            if layer is not None and layer.character_id == holder:
                jobs[
                    render.Job(clip, frame, ZOOM, hide_depths=tint_hides(index, path))
                ] = name
        clips[str(clip)] = entry
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
        "clips": clips,
        "frames": frames,
    }


def main():
    index = read_swf(WEB_SWF)
    effects = effect_clips(index)
    # Every model is planned and every clip's tinted part found before any art
    # is written, so a model that fails its checks leaves the committed art as
    # it was.
    plans = {model: plan(index, sprite, effects) for model, sprite in MODELS.items()}
    for planned in plans.values():
        for clip in planned.clips:
            tint_path(index, clip)
            clip_hold(index, clip)
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
