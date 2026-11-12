# The clips the fighter rig (DefineSprite 2676) holds beside the doll, which
# the original plays on a unit through BATTLESCREEN["player" + id]:
#
#   assets/ui/battle/rig/<clip>/<n>.png   frame n of the clip, all of its
#                                         frames cut to one box
#   assets/ui/battle/rig/rig_clips.json   the frame rate, and for each clip
#                                         its frames and that box's rect
#                                         around the rig's origin
#
# Today the one clip is `shield` (DefineSprite 2675), which executeMove plays
# on a Shield block (frame_42/DoAction_8.as:73). buffTicker also calls it when a
# shield soaks a whole Buff tick (frame_42/DoAction_10.as:72), but through a name
# it never declares, so that call reaches no clip. The port plays the clip there
# anyway (ADR 0005). The clip's frame 1 runs stop() and shows nothing. Frame 2
# places the bubble (sprite 1709) at the rig's origin and BOOM_SPARK (sprite
# 1712) at (40.55, 3.65). A color transform turns the bubble white on frames 3,
# 5 to 6 and 8 to 9, and its alpha falls to 0 over frames 11 to 20. The spark
# steps through its own frames with the clip, and it draws on the clip's frames
# 2 to 18.
#
# EVERY FRAME IS RENDERED WHOLE. ffdec draws the bubble's glow, its white color
# transform and its fade, and steps the spark to the frame it shows on each
# frame of the clip. ffdec runs no script, and none would change a frame here:
# the spark's scripts, a stop() on frame 20 of the sprite 884 inside it and an
# unloadMovie(this) on frame 25 of sprite 1712, come after the clip has looped
# back to its frame 1. rig_clip() checks that through render.played_frames().
# The port then plays the frames one after the other.
#
# The art is rendered at 2x, the window's default scale, as the doll is.
#
# Run: uv run extract_rig_clips
from __future__ import annotations

import json
import sys

from urchin_dev import REPO_ROOT, WEB_SWF, png
from urchin_dev.swf import render, timeline
from urchin_dev.swf.extract.battle_screen import FIGHTER_RIG, rect_entry
from urchin_dev.swf.swf_index import SwfIndex, read_swf

OUT_DIR = REPO_ROOT / "assets" / "ui" / "battle" / "rig"
LAYOUT_JSON = OUT_DIR / "rig_clips.json"
ZOOM = 2.0
# The rig's clips the port plays, by the instance name the rig gives each.
CLIPS = ("shield",)


def rig_clip(index: SwfIndex, rig: int, name: str) -> int:
    """-> the sprite that `rig`'s frame 1 places under the instance name
    `name`. Raises unless that sprite's frame 1 shows nothing, its frame 1
    alone runs stop(), and render.played_frames() renders it from frame 2
    through its last frame. The port relies on it: it rests the clip on frame
    1 until play(), runs it to its last frame, and stops it again when it
    loops back to frame 1."""
    placed = [
        layer.character_id
        for layer in timeline.frames(index, rig)[0].values()
        if layer.name == name
    ]
    if len(placed) != 1:
        raise RuntimeError(
            f"rig {rig} places {len(placed)} clips named {name!r}, want 1"
        )
    sprite = placed[0]
    shown = len(timeline.frames(index, sprite)[0])
    if shown:
        raise RuntimeError(f"{sprite} frame 1 shows {shown} layer(s), want none")
    count = index.sprite_frames[sprite]
    stops = [
        frame for frame in range(1, count + 1) if render.runs_stop(index, sprite, frame)
    ]
    if stops != [1]:
        raise RuntimeError(
            f"{sprite} runs stop() on frames {stops}, where a rig clip runs it on"
            " frame 1 alone"
        )
    played = render.played_frames(index, sprite, start=2)
    if played != list(range(2, count + 1)):
        raise RuntimeError(
            f"{sprite} plays frames {played} after play(), where a rig clip plays"
            f" through its last frame, {count}"
        )
    return sprite


def main():
    index = read_swf(WEB_SWF)
    sprites = {name: rig_clip(index, FIGHTER_RIG, name) for name in CLIPS}
    jobs: list[render.Job] = []
    for sprite in sprites.values():
        # The rect comes out around the rig's origin, which is where the port
        # puts the clip's node. placement_origin() raises if the rig scales or
        # turns the clip, because a rect can't carry that.
        origin = render.placement_origin(index, FIGHTER_RIG, 1, sprite)
        jobs.extend(
            render.Job(sprite, frame, ZOOM, origin=origin)
            for frame in range(1, index.sprite_frames[sprite] + 1)
        )

    clips: dict[str, dict] = {}
    with render.frames(WEB_SWF, jobs) as rendered:
        at = 0
        for name, sprite in sprites.items():
            count = index.sprite_frames[sprite]
            pieces = render.trim_union(rendered[at : at + count])
            at += count
            if pieces is None:
                raise RuntimeError(f"{name} ({sprite}) rendered empty")
            rects = {piece.rect for piece in pieces}
            if len(rects) != 1:
                raise RuntimeError(
                    f"{name} ({sprite}) frames sit in {len(rects)} boxes"
                )
            (OUT_DIR / name).mkdir(parents=True, exist_ok=True)
            pngs = []
            for frame, piece in enumerate(pieces, start=1):
                file_name = f"{name}/{frame}.png"
                png.save(piece.image, OUT_DIR / file_name)
                pngs.append(file_name)
            clips[name] = {"frames": pngs, "rect": rect_entry(rects.pop())}
            print(f"  {name}: sprite {sprite}, {count} frames", file=sys.stderr)

    layout = {"fps": index.frame_rate, "clips": clips}
    LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
    print(f"wrote {LAYOUT_JSON}", file=sys.stderr)


if __name__ == "__main__":
    main()
