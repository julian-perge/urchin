# The chrome the Windows and the Hub share that a StyleBoxFlat can't draw, as
# zoom 4 art, from KRINMENU (DefineSprite 3142) and the Navigation frame:
#
#   assets/ui/window/<piece>.png        - one trimmed render per piece
#   assets/ui/window/window_chrome.json - each piece's rect, zoom and the
#                                         origin its rect is measured from
#
# Every piece is rendered by ffdec with the filters on its own placement
# drawn, because the Bevel, Glow and DropShadow of a placement are part of the
# look and a render of the bare shape leaves them out. That is why most pieces
# are rendered "as placed": the job renders the timeline that places the
# piece and keeps only the piece's depth. The zone fill is the one exception,
# see below.
#
# THE BACKDROP is KRINMENU's own depth 2 (DefineSprite 2994), and its Bevel,
# Glow and DropShadow are on KRINMENU's placement on the root frame, not on
# the backdrop. The root frame is rendered with only KRINMENU kept, and every
# depth of KRINMENU except depth 2 hidden on every frame, so those filters
# draw over the backdrop alone. KRINMENU places no clip mask today. If a later
# SWF does, the driver refuses to hide it, because hiding a mask unclips what
# it covers.
#
# THE ITEM SLOT 2986 is rendered as a sprite of its own. Its inner DropShadow
# is on a placement inside the slot, so it is drawn whatever places the slot.
# Every ItemSlot uses this art. The equip slot 2984 and the drop slot 3013
# differ from it only in the DropShadow's angle, which is too small to see, so
# they are not rendered.
#
# THE HOTBAR SQUARES are DefineButton2s placed on the root frame at three
# sizes. Six are the same square at 0.671, at x positions that are not whole
# zoom 4 pixels, so each render has to match the first within same_art() or the
# extractor stops, and one PNG per size is enough. The hit buttons and their
# hover Glows are not here. Quit's red square is the separate shape 3172, which
# the hub places at depth 152 with no filter, so it is its own piece.
#
# THE ZONE FILL AND ITS TRACK are both inside sprite 3149, and the DropShadow
# is on 3149's placement, so in the game it draws around the track and the fill
# together. The track render has it, from the root frame with the fill hidden.
# The fill is rendered from inside 3149, so it has no DropShadow of its own and
# no render draws the shadow of the two together. The game also sets the fill's
# _width to the progress (frame_181/DoAction.as:11), so zone_fill.png is the
# full width and a scene crops or stretches it.
#
# WHAT RECTS MEAN. A piece rendered as a sprite of its own has a rect measured
# from that sprite's origin, "relative_to": "sprite <id>", because the game
# places the sprite in more than one spot. Every other piece is placed on the
# stage once the origin of the timeline that places it is added, and its rect
# is in Stage design px. The rect times the zoom is the PNG's pixel size.
#
# Run: uv run extract_window_chrome
from __future__ import annotations

import json
import sys

from PIL import Image, ImageChops, ImageStat

from urchin_dev import REPO_ROOT, WEB_SWF, png
from urchin_dev.swf import render, strip, timeline
from urchin_dev.swf.swf_index import SwfIndex, read_swf

OUT_DIR = REPO_ROOT / "assets" / "ui" / "window"
RECORD = OUT_DIR / "window_chrome.json"
ZOOM = 4.0

KRINMENU = 3142
HUB_FRAME = "Navigation"
BACKDROP_DEPTH = 2
CLOSE_X_DEPTH = 1431
KRINMENU_ROOT_DEPTH = 175
ZONE_BAR_ROOT_DEPTH = 169
ZONE_BAR_SPRITE = 3149
ZONE_BAR_FILL_DEPTH = 2
# KRINMENU's frame labels: "inventory" is frame 1, "shop" is frame 16 and "ach"
# is frame 45. Each piece below is placed on the first frame that holds it, and
# the placement is the same on every frame that does.
INVENTORY_FRAME = 1
SHOP_FRAME = 16
ACHIEVEMENTS_FRAME = 45
# The "ach" frame places the plate ten times, in two columns of five rows
# (x -1649 and 1651 twips), all the same clip. Depth 7 is the first of them.
PLATE_DEPTH = 7
PLATE_SPRITE = 3141
PLATE_TEXT = 3138
VICTORY_ROW_SPRITE = 3002
VICTORY_GLOSS_DEPTH = 41
# The six hotbar squares at 0.671, in the depths that place them on the hub
# frame, and the depths of the two other sizes.
SQUARE_DEPTHS = (126, 128, 130, 136, 138, 165)
WORLD_MAP_DEPTH = 142
QUIT_DEPTH = 140
QUIT_RED_DEPTH = 152

PIECES: dict[str, str] = {
    "backdrop": "KRINMENU's backdrop under its Bevel, Glow and DropShadow",
    "slot_inventory": "the 36-slot grid's slot (2986), inner shadow at angle 52",
    "close_x": "the close X (2855), as placed at depth 1431",
    "delete_slot": "the delete slot (2860), as placed at depth 1425",
    "sell_slot": "the sell slot (3017), as placed at depth 1281",
    "xp_gloss": "the experience gloss (2864), as placed at depth 1421",
    "xp_gloss_victory": "the victory row's experience gloss (2998 in 3002)",
    "achievement_plate_1": "the achievement plate (3141), frame 1, text stripped",
    "achievement_plate_2": "the achievement plate (3141), frame 2, text stripped",
    "hotbar_square": "a hotbar square at scale 0.671, under its Bevel and Glows",
    "hotbar_world_map": "the World Map square, scale 0.812",
    "hotbar_quit": "the Quit square, scale 0.3",
    "hotbar_quit_red": "Quit's red square (3172), with no filter",
    "zone_track": "the Hub's zone progress track (3149), under its DropShadow",
    "zone_fill": "the Hub's zone progress bar (3147), full width, no DropShadow",
}


def hub_frame(index: SwfIndex) -> int:
    return timeline.frame_of(index, 0, HUB_FRAME)


def backdrop_hides(index: SwfIndex) -> tuple[tuple[int, int], ...]:
    """-> (KRINMENU, depth) for every depth any frame of it places, other than
    the backdrop's."""
    depths = {depth for layers in timeline.frames(index, KRINMENU) for depth in layers}
    return tuple((KRINMENU, depth) for depth in sorted(depths - {BACKDROP_DEPTH}))


def jobs(index: SwfIndex, plate_strip: tuple[int, ...]) -> dict[str, render.Job]:
    """-> the render job for each piece in PIECES, in that order."""
    hub = hub_frame(index)
    menu_origin = render.placement_origin(index, 0, hub, KRINMENU)
    bar_origin = render.placement_origin(index, 0, hub, ZONE_BAR_SPRITE)

    def on_menu(frame: int, depth: int, **more) -> render.Job:
        return render.Job(
            KRINMENU, frame, ZOOM, menu_origin, only_depths=(depth,), **more
        )

    def on_hub(depth: int, **more) -> render.Job:
        return render.Job(0, hub, ZOOM, only_depths=(depth,), **more)

    return {
        "backdrop": on_hub(KRINMENU_ROOT_DEPTH, hide_depths=backdrop_hides(index)),
        "slot_inventory": render.Job(2986, 1, ZOOM),
        "close_x": on_menu(INVENTORY_FRAME, CLOSE_X_DEPTH),
        "delete_slot": on_menu(INVENTORY_FRAME, 1425),
        "sell_slot": on_menu(SHOP_FRAME, 1281),
        "xp_gloss": on_menu(INVENTORY_FRAME, 1421),
        "xp_gloss_victory": render.Job(
            VICTORY_ROW_SPRITE, 1, ZOOM, only_depths=(VICTORY_GLOSS_DEPTH,)
        ),
        "achievement_plate_1": on_menu(
            ACHIEVEMENTS_FRAME, PLATE_DEPTH, strip=plate_strip, goto=((PLATE_DEPTH, 1),)
        ),
        "achievement_plate_2": on_menu(
            ACHIEVEMENTS_FRAME, PLATE_DEPTH, strip=plate_strip, goto=((PLATE_DEPTH, 2),)
        ),
        "hotbar_square": on_hub(SQUARE_DEPTHS[0]),
        "hotbar_world_map": on_hub(WORLD_MAP_DEPTH),
        "hotbar_quit": on_hub(QUIT_DEPTH),
        "hotbar_quit_red": on_hub(QUIT_RED_DEPTH),
        "zone_track": on_hub(
            ZONE_BAR_ROOT_DEPTH, hide_depths=((ZONE_BAR_SPRITE, ZONE_BAR_FILL_DEPTH),)
        ),
        "zone_fill": render.Job(
            ZONE_BAR_SPRITE, 1, ZOOM, bar_origin, only_depths=(ZONE_BAR_FILL_DEPTH,)
        ),
    }


def same_art(a: Image.Image, b: Image.Image) -> bool:
    """-> whether two trims are one square drawn at two stage positions. The
    squares sit at x positions that are not whole pixels at zoom 4, so ffdec's
    anti-aliased edges differ by a few levels and sometimes by one column.
    Sizes within one pixel and a mean difference under 1 level count as the
    same."""
    if abs(a.width - b.width) > 1 or abs(a.height - b.height) > 1:
        return False
    box = (0, 0, min(a.width, b.width), min(a.height, b.height))
    difference = ImageChops.difference(a.crop(box), b.crop(box))
    return max(ImageStat.Stat(difference).mean) < 1.0


def relative_to(job: render.Job) -> str:
    """-> what a piece's rect is measured from: the stage when the job renders
    the root, or a sprite given the origin where the root places it, or the
    sprite's own origin otherwise."""
    if job.timeline == 0 or job.origin != (0.0, 0.0):
        return "stage"
    return f"sprite {job.timeline}"


def record_of(job: render.Job, cut: render.Trimmed) -> dict:
    return {
        "rect": [round(v, 4) for v in cut.rect],
        "relative_to": relative_to(job),
        "size": list(cut.image.size),
        "zoom": job.zoom,
    }


def main():
    index = read_swf(WEB_SWF)
    plate_strip = tuple(
        strip.strip_list(WEB_SWF, {PLATE_TEXT: "the achievement plate's text field"})
    )
    by_name = jobs(index, plate_strip)
    if set(by_name) != set(PIECES):
        raise RuntimeError(f"jobs() and PIECES disagree: {set(by_name) ^ set(PIECES)}")
    # The other five 0.671 squares are only rendered to prove they are the same
    # art as the first.
    twins = {
        depth: render.Job(0, hub_frame(index), ZOOM, only_depths=(depth,))
        for depth in SQUARE_DEPTHS[1:]
    }

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    record = {}
    with render.frames(WEB_SWF, [*by_name.values(), *twins.values()]) as rendered:
        cuts: dict[str, render.Trimmed] = {}
        for name, frame in zip(by_name, rendered[: len(by_name)], strict=True):
            cut = render.trim(frame)
            if cut is None:
                raise RuntimeError(f"{name} rendered fully transparent")
            cuts[name] = cut
        first = cuts["hotbar_square"].image
        for depth, frame in zip(twins, rendered[len(by_name) :], strict=True):
            cut = render.trim(frame)
            if cut is None or not same_art(first, cut.image):
                raise RuntimeError(
                    f"the hotbar square at depth {depth} is not the first one's art"
                )
    for name, job in by_name.items():
        cut = cuts[name]
        png.save(cut.image, OUT_DIR / f"{name}.png")
        record[name] = record_of(job, cut)
        print(f"{name} {record[name]['rect']} {cut.image.size}", file=sys.stderr)
    RECORD.write_text(json.dumps(record, indent=1, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
