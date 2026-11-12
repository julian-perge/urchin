# Re-renders every doll art sprite in resources/sprites/ at exactly 2x the
# design size (the window's default scale), and writes the render bounds each
# one needs to be placed with to resources/sprites/doll_offsets.json. The
# Steam SWF fills names the web SWF lacks (DOG/WOLF/... art).
#
# Each sprite is exported through ffdec's own sprite renderer, not reassembled
# shape-by-shape. A hand-rolled compositor reads only characterId and matrix
# off each PlaceObject tag, so anything else living on that tag is silently
# dropped: 159 of these 789 sprites carry a surface filter and 56 carry a
# colorTransform. Same root cause and fix as item_icons.py and faces.py.
#
# Positioning these needs care, because a filter makes ffdec's canvas bigger
# than the art's own bounds - F_SHEAD_FIR's shape bounds are 12.05x19.45
# design px but its exported canvas is 32.5x39.5, since the glow is drawn
# outside the shape. So the recorded rect has to describe what was rendered,
# not what the shape geometry says, or every filtered part would be scaled
# down and shifted by the width of its own glow.
#
# render.py works out where each part goes. ffdec grows the canvas by the
# filter margin on both sides of the timeline's displayRect, so the canvas
# keeps the displayRect's centre, and the driver reports that displayRect
# with every frame, so the rect needs no filter math of its own. Before
# julian-perge/urchin#43 this file read the displayRect off a second ffdec
# pass in SVG, and before that it walked the XML dump in Python, which took
# 28.2s against the SVG pass's 4.1s.
#
# Run: uv run extract_doll_art
from __future__ import annotations

import json
import sys
from pathlib import Path

from urchin_dev import REPO_ROOT, STEAM_SWF, WEB_SWF, png
from urchin_dev.swf import render
from urchin_dev.swf.swf_index import read_swf

SPRITES = REPO_ROOT / "resources" / "sprites"
OFFSETS = SPRITES / "doll_offsets.json"
ZOOM = 2.0
# ffdec rounds each canvas dimension up to a whole pixel, so a canvas can read
# as very slightly larger than its own displayRect with no filter involved.
# Anything past this much growth is a real filter.
ROUNDING_SLACK_PX = 0.75


def render_swf(swf_path: Path, names: list[str]):
    """-> (rects, unresolved, grown). rects maps name to its design-px rect."""
    index = read_swf(swf_path)

    wanted: dict[int, str] = {}
    unresolved: list[str] = []
    for name in names:
        cid = index.exports.get(name)
        if cid is None or not index.sprite_frames.get(cid):
            unresolved.append(name)
            continue
        wanted[cid] = name

    if not wanted:
        return {}, unresolved, []

    rects: dict[str, tuple[float, float, float, float]] = {}
    grown: list[str] = []
    jobs = [render.Job(cid, 1, ZOOM) for cid in sorted(wanted)]
    with render.frames(swf_path, jobs) as rendered:
        for frame in rendered:
            name = wanted[frame.job.timeline]
            trimmed = render.trim(frame)
            if trimmed is None or trimmed.image.width <= 1 or trimmed.image.height <= 1:
                # A deliberately empty part. Leave whatever placeholder PNG is
                # already on disk alone and record no rect, which is how
                # character_visual.gd's _add_layer() detects and skips one.
                unresolved.append(name)
                continue
            x0, y0, x1, y1 = frame.display_rect
            if (
                frame.size[0] / ZOOM - (x1 - x0) / 20 > ROUNDING_SLACK_PX
                or frame.size[1] / ZOOM - (y1 - y0) / 20 > ROUNDING_SLACK_PX
            ):
                grown.append(name)
            rects[name] = trimmed.rect
            png.save(trimmed.image, SPRITES / (name + ".png"))
    return rects, unresolved, grown


def main():
    names = sorted(p.stem for p in SPRITES.glob("*.png"))
    print(f"doll sprites on disk: {len(names)}", file=sys.stderr)

    rects, unresolved, grown = render_swf(WEB_SWF, names)
    print(
        f"web SWF: {len(rects)} rendered, {len(grown)} grown by a filter",
        file=sys.stderr,
    )

    if unresolved:
        steam_rects, unresolved, steam_grown = render_swf(STEAM_SWF, sorted(unresolved))
        rects.update(steam_rects)
        grown.extend(steam_grown)
        print(
            f"steam SWF: {len(steam_rects)} rendered, "
            f"{len(steam_grown)} grown by a filter",
            file=sys.stderr,
        )

    OFFSETS.write_text(
        json.dumps(
            {
                name: {
                    "x": round(rect[0], 2),
                    "y": round(rect[1], 2),
                    "w": round(rect[2], 2),
                    "h": round(rect[3], 2),
                }
                for name, rect in sorted(rects.items())
            },
            indent=1,
            sort_keys=True,
        )
    )
    print(f"wrote {OFFSETS} ({len(rects)} entries)", file=sys.stderr)
    print(
        f"skipped (placeholders / not in either SWF): {len(unresolved)}",
        file=sys.stderr,
    )
    if unresolved:
        print(f"skipped: {sorted(unresolved)}", file=sys.stderr)


if __name__ == "__main__":
    main()
