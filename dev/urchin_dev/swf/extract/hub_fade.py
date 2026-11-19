# The fade-in of the Hub: DefineSprite 2837, which the root frame Navigation
# places at depth 1660, above KRINMENU (3142) at depth 175, the Info card (2848)
# at depth 1651 and every Window:
#
#   assets/ui/hub_fade.json - the colour and the rect of the black, the frame
#                             rate, the alpha it starts at and how far the alpha
#                             falls each frame
#
# WHAT THE CLIP DOES. Its load handler sets _alpha to 99 and frameGo to
# undefined. Its enterFrame handler takes 15 off _alpha on each frame while
# _alpha is above 0. When frameGo is set, it adds 15 a frame up to 100 and then
# jumps the root to frameGo
# (frame_181/PlaceObject2_2837_1660/CLIPACTIONRECORD onClipEvent(load).as and
# onClipEvent(enterFrame).as). No script in the web build writes frameGo, and
# the clip has no instance name for one to write it through, so the port keeps
# only the fade-in.
#
# WHAT IT DRAWS. The sprite has one frame with shape 333, one solid colour,
# scaled to cover the stage except a strip at the bottom. The port draws that
# colour over the same rect and changes only its alpha, so this script refuses
# a sprite that draws more than that.
#
# Run: uv run extract_hub_fade
from __future__ import annotations

import json
import re
import sys

from urchin_dev import ACTION_SCRIPT, REPO_ROOT, WEB_SWF
from urchin_dev.swf import render, timeline
from urchin_dev.swf.extract.battle_screen import (
    IDENTITY_COLOR_TRANSFORM,
    placed_rect,
    rect_entry,
)
from urchin_dev.swf.swf_index import SwfIndex, first_fill_color, read_swf, shape_bounds

LAYOUT_JSON = REPO_ROOT / "assets" / "ui" / "hub_fade.json"

HUB_FRAME = "Navigation"
FADE_CLIP = 2837
CLIP_SCRIPTS = ACTION_SCRIPT / "frame_181" / "PlaceObject2_2837_1660"
LOAD_SCRIPT = CLIP_SCRIPTS / "CLIPACTIONRECORD onClipEvent(load).as"
ENTER_FRAME_SCRIPT = CLIP_SCRIPTS / "CLIPACTIONRECORD onClipEvent(enterFrame).as"


def one(pattern: str, text: str, where: str) -> str:
    """-> the one match of `pattern` in `text`. Raises unless there is one."""
    found = re.findall(pattern, text)
    if len(found) != 1:
        raise RuntimeError(f"{where}: {len(found)} matches of {pattern}, want 1")
    return found[0]


def script_numbers(load: str, enter_frame: str) -> dict:
    """-> the _alpha the load handler sets and the step the enterFrame handler
    takes off it each frame. Raises unless each is found once, and unless the
    step back up to black is the same, because the port records one step."""
    down = int(one(r"_alpha = _alpha - (\d+);", enter_frame, "enterFrame"))
    up = int(one(r"_alpha = _alpha \+ (\d+);", enter_frame, "enterFrame"))
    if down != up:
        raise RuntimeError(f"enterFrame steps _alpha down by {down} and up by {up}")
    return {
        "alpha_step": down,
        "start_alpha": int(one(r"_alpha = (\d+);", load, "load")),
    }


def fade_layout(index: SwfIndex) -> dict:
    """-> the colour and the rect in stage px that the Navigation frame shows
    the clip's shape at, and the SWF's frame rate. Raises unless the frame
    places the clip once with no colour transform, and the clip shows one solid
    shape on its one frame with no colour transform."""
    frame = timeline.frame_of(index, 0, HUB_FRAME)
    placed = [
        layer
        for layer in timeline.frames(index, 0)[frame - 1].values()
        if layer.character_id == FADE_CLIP
    ]
    if len(placed) != 1:
        raise RuntimeError(
            f"{HUB_FRAME} places {FADE_CLIP} {len(placed)} times, want 1"
        )
    clip_frames = timeline.frames(index, FADE_CLIP)
    if len(clip_frames) != 1 or len(clip_frames[0]) != 1:
        raise RuntimeError(
            f"{FADE_CLIP} has {len(clip_frames)} frames, and the first shows"
            f" {len(clip_frames[0]) if clip_frames else 0} layers, want 1 and 1"
        )
    (shape,) = clip_frames[0].values()
    for layer in (placed[0], shape):
        transform = layer.color_transform or IDENTITY_COLOR_TRANSFORM
        if transform != IDENTITY_COLOR_TRANSFORM:
            raise RuntimeError(
                f"{FADE_CLIP} is shown with colour transform {transform}"
            )
    color = first_fill_color(index, shape.character_id)
    if color is None or color[3] != 255:
        raise RuntimeError(
            f"{FADE_CLIP}'s shape {shape.character_id} fills with {color},"
            " want one opaque colour"
        )
    xmin, ymin, xmax, ymax = placed_rect(
        placed[0].matrix, shape.matrix, shape_bounds(index, shape.character_id)
    )
    twips = render.TWIPS
    return {
        "color": "#{:02x}{:02x}{:02x}".format(*color[:3]),
        "fps": index.frame_rate,
        "rect": rect_entry(
            (xmin / twips, ymin / twips, (xmax - xmin) / twips, (ymax - ymin) / twips)
        ),
    }


def main():
    index = read_swf(WEB_SWF)
    layout = {
        **fade_layout(index),
        **script_numbers(LOAD_SCRIPT.read_text(), ENTER_FRAME_SCRIPT.read_text()),
    }
    LAYOUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
    print(f"{FADE_CLIP}: {layout}", file=sys.stderr)
    print(f"wrote {LAYOUT_JSON}", file=sys.stderr)


if __name__ == "__main__":
    main()
