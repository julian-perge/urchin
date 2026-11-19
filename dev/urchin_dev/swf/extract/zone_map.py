# Art for the World map, the root frame overMap (449), which places only
# krinMapper (DefineSprite 4173) and the tooltip:
#
#   assets/ui/zone_map/zone_map.png           - the map art
#   assets/ui/zone_map/zone_button_open.png   - a zone button with its open face
#   assets/ui/zone_map/zone_button_locked.png - a zone button on its blank face
#   assets/ui/zone_map/zone_map.json          - where each PNG sits, and the
#                                               DropShadow of the links
#
# THE MAP ART is sprite 4172. Its mask 4163 clips the background, the terrain
# and the highlight under their blend modes, and the 1 px frame 4162 at depth 51
# sits outside the mask. The render hides depth 51, because the rect record
# places the frame as an outline that the port draws as a Panel
# (spec/107-world-map.md). The rect is measured from sprite 4172's origin.
#
# THE ZONE BUTTONS are the seven placements mb1 to mb7 of sprite 4160, each
# under one DropShadow, with no scale. The render draws krinMapper's mb1 alone,
# so the shadow on the placement is in the PNG, and measures the rect from
# sprite 4160's origin, so the one rect holds for every placement. A locked zone
# moves the face underGF (4159) to its label "blank" (frame_449/DoAction.as).
# The driver's nested goto reaches it, because underGF sits one level down,
# inside 4160. Both states are cut to one box, so they share one rect and size.
#
# THE LINKS are drawn by frame_449/DoAction.as into lineMC (4161), which carries
# a DropShadow of its own. The record keeps that shadow for
# scripts/zones/zone_map_connectors.gd.
#
# Run: uv run extract_zone_map
from __future__ import annotations

import json
import sys

from urchin_dev import REPO_ROOT, WEB_SWF, png
from urchin_dev.swf import render, timeline
from urchin_dev.swf.swf_index import DropShadow, SwfIndex, drop_shadow, read_swf

OUT_DIR = REPO_ROOT / "assets" / "ui" / "zone_map"
RECORD = OUT_DIR / "zone_map.json"

MAP_HOLDER = 4173
MAP_SPRITE = 4172
MAP_DEPTH = 1
FRAME_DEPTH = 51
LINES_DEPTH = 53
BUTTON_SPRITE = 4160
BUTTON_DEPTH = 55
BUTTON_NAME = "mb1"
FACE_DEPTH = 1
FACE_SPRITE = 4159
BLANK_LABEL = "blank"
# The map fills most of the window, as hub art does, and the buttons are small,
# as the orbs are, so each gets the zoom of its family in
# docs/agents/art-extraction.md.
MAP_ZOOM = 4.0
BUTTON_ZOOM = 5.0


def jobs(blank_frame: int) -> list[render.Job]:
    """-> the map art, the open button and the locked button, in that order.
    blank_frame is the frame of sprite 4159 that carries the label "blank"."""
    button = render.Job(MAP_HOLDER, 1, BUTTON_ZOOM, only_depths=(BUTTON_DEPTH,))
    return [
        render.Job(MAP_SPRITE, 1, MAP_ZOOM, hide_depths=((MAP_SPRITE, FRAME_DEPTH),)),
        button,
        render.Job(
            MAP_HOLDER,
            1,
            BUTTON_ZOOM,
            only_depths=(BUTTON_DEPTH,),
            nested_goto=((BUTTON_SPRITE, FACE_DEPTH, blank_frame),),
        ),
    ]


def in_sprite(rect, matrix) -> list[float]:
    """-> `rect` (x, y, w, h), measured on a timeline that places a sprite
    with `matrix`, measured from that sprite's own origin instead."""
    if tuple(matrix[:4]) != render.IDENTITY_LINEAR:
        raise ValueError(f"matrix {matrix} scales or turns the sprite")
    x, y, w, h = rect
    return [
        round(x - matrix[4] / render.TWIPS, 4),
        round(y - matrix[5] / render.TWIPS, 4),
        round(w, 4),
        round(h, 4),
    ]


def art_entry(rect, size, zoom: float, sprite: int) -> dict:
    return {
        "rect": [round(v, 4) for v in rect],
        "size": list(size),
        "zoom": zoom,
        "relative_to": f"sprite {sprite}",
    }


def shadow_entry(shadow: DropShadow) -> dict:
    """-> the DropShadow as the connectors read it: the colour without its
    alpha, and the alpha, blur, angle in degrees, distance in px and strength."""
    if shadow.inner or shadow.knockout:
        raise ValueError(f"the links' shadow is not a plain outer shadow: {shadow}")
    r, g, b, a = shadow.color
    return {
        "color": f"#{r:02x}{g:02x}{b:02x}",
        "alpha": round(a / 255, 4),
        "blur": [shadow.blur_x, shadow.blur_y],
        "angle": shadow.angle,
        "distance": shadow.distance,
        "strength": shadow.strength,
    }


def checked_layers(index: SwfIndex) -> dict[int, timeline.Layer]:
    """-> krinMapper's first frame, after checking that it holds the map, the
    links and mb1 at the depths this extractor names."""
    layers = timeline.frames(index, MAP_HOLDER)[0]
    expected = {
        MAP_DEPTH: (MAP_SPRITE, None),
        LINES_DEPTH: (4161, "lineMC"),
        BUTTON_DEPTH: (BUTTON_SPRITE, BUTTON_NAME),
    }
    for depth, (character, name) in expected.items():
        layer = layers.get(depth)
        if layer is None or layer.character_id != character or layer.name != name:
            raise ValueError(
                f"sprite {MAP_HOLDER} depth {depth} is not {character} {name}: {layer}"
            )
    if tuple(layers[MAP_DEPTH].matrix) != timeline.IDENTITY:
        raise ValueError("krinMapper moves the map art, so its origin is not 4173's")
    return layers


def main():
    index = read_swf(WEB_SWF)
    layers = checked_layers(index)
    blank = timeline.frame_of(index, FACE_SPRITE, BLANK_LABEL)
    shadow = drop_shadow(layers[LINES_DEPTH].filter_records[0])
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with render.frames(WEB_SWF, jobs(blank)) as rendered:
        art = render.trim(rendered[0])
        buttons = render.trim_union(rendered[1:])
        if art is None or buttons is None:
            raise RuntimeError("the map art or the zone button rendered empty")
        open_button, locked_button = buttons
        if open_button.image.tobytes() == locked_button.image.tobytes():
            raise RuntimeError("the locked button rendered the open face")
        record = {
            "art": {
                "zone_map": art_entry(art.rect, art.image.size, MAP_ZOOM, MAP_SPRITE)
            },
            "line_shadow": shadow_entry(shadow),
        }
        png.save(art.image, OUT_DIR / "zone_map.png")
        for name, trimmed in (
            ("zone_button_open", open_button),
            ("zone_button_locked", locked_button),
        ):
            record["art"][name] = art_entry(
                in_sprite(trimmed.rect, layers[BUTTON_DEPTH].matrix),
                trimmed.image.size,
                BUTTON_ZOOM,
                BUTTON_SPRITE,
            )
            png.save(trimmed.image, OUT_DIR / f"{name}.png")
    RECORD.write_text(json.dumps(record, indent=1, sort_keys=True) + "\n")
    for name, entry in record["art"].items():
        print(f"{name}: {entry['size']} at {entry['rect']}", file=sys.stderr)


if __name__ == "__main__":
    main()
