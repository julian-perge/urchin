# Art and constants for the Battle screen's top status bar (spec/67-battle-hud.md,
# Part 3). The battle frame (root frame 217, label KRINBATTLESCENE) places the
# bar sprite 3414 six times, as p1BAR to p6BAR. Everything is written to
#
#   assets/ui/battle/top_bar/<NAME>.png   the pieces, at zoom 4
#   assets/ui/battle/top_bar/top_bar.json the rects, placements, text fields,
#                                         widths, colours, smoother frames,
#                                         shadow and buff row constants
#
# THE BAR IS BUILT FROM PARTS. Sprite 3414 holds `inner` (3407), which has the
# bar backing and the text fields, on three frames: the first, `second` for the
# right-hand bars and `third`, which is empty and which the dying smoother jumps
# to. It also holds `inner2` (3413), which has the bars. Each bar is a sprite
# placed at x -2000 twips with scale 0.787, and lifeBarUpdate sets its _width,
# so the port scales the fill the same way. A fill's full width is `wsaver`,
# which each bar's load script reads from its own _width.
#
# THE FILLS ARE ONE SHAPE EACH. The life bar's color clip LCC (sprite 55) has 101
# frames, and every one places shape 54 with a color transform that turns it into
# one flat colour. So this writes the shape once, as white with its own alpha, and
# lists the 101 colours. The smoother clips (sprites 56 and 57) are the same
# shape under a changing x and x scale, so they have no art of their own, only
# the frames in the JSON.
#
# Every rect is in the design px of the sprite that places the piece: `inner`
# pieces are in the bar sprite 3414, the fills are in their own bar sprite and
# the rest are in `inner2`. The placements give where the bar sprite sits on the
# Stage.
#
# Run: uv run extract_top_bar
from __future__ import annotations

import json
import re
import sys
from collections.abc import Callable

from PIL import Image

from urchin_dev import ACTION_SCRIPT, REPO_ROOT, WEB_SWF, png
from urchin_dev.swf import render, timeline
from urchin_dev.swf.extract import battle_screen, screen_rects
from urchin_dev.swf.swf_index import (
    DropShadow,
    SwfIndex,
    character_kind,
    edit_text,
    read_swf,
    shape_bounds,
)

OUT_DIR = REPO_ROOT / "assets" / "ui" / "battle" / "top_bar"
RECORD = OUT_DIR / "top_bar.json"
ZOOM = 4.0

BAR = 3414
INNER = 3407
INNER2 = 3413
LIFE_BAR = 3410
FOCUS_BAR = 3412
LIFE_COLOR_CLIP = 55
LIFE_COLOR_SHAPE = 54
SMOOTHERS = ("LifeBarSmoother", "LifeBarSmoother2")
BUFF_SHOWER = "KrinBuffShower"
BAR_NAME = re.compile(r"p([1-6])BAR")
# The depths of `inner2` that draw a part of their own. The two bar clips at each
# of lB, lB2, fB and fB2 are the fills, and lB3 and fB3 are empty holders that
# the smoothers attach into.
INNER2_ART = {"Shade": 5, "Black": 10, "Frame": 15}

LIFE_BAR_SCRIPT = ACTION_SCRIPT / "frame_42" / "DoAction_8.as"
BUFF_ROW_SCRIPT = ACTION_SCRIPT / "frame_42" / "DoAction_10.as"
BATTLE_FRAME_SCRIPTS = ACTION_SCRIPT / "frame_217"


def load_script_flags(script: str) -> dict:
    """-> what one bar's onClipEvent(load) does to the bar: the frame label it
    sends `inner` to, or None, and the x scale it gives `inner2`, or None."""
    frame = re.search(r'this\.inner\.gotoAndStop\("(\w+)"\)', script)
    scale = re.search(r"this\.inner2\._xscale\s*=\s*(-?\d+(?:\.\d+)?)", script)
    return {
        "inner_frame": frame[1] if frame else None,
        "inner2_xscale": float(scale[1]) if scale else None,
    }


def buff_row_constants(script: str) -> dict:
    """-> the constants of buffTicker's buff icon row: the offset and the spacing
    of the icons, how many it shows, and the sign each team side puts on x."""
    values = {}
    for name in ("buffSpaceGF", "buffOffsetGF"):
        found = re.findall(rf"\b{name}\s*=\s*(\d+(?:\.\d+)?);", script)
        if len(found) != 1:
            raise ValueError(f"{name} is set {len(found)} times, want 1")
        values[name] = float(found[0])
    slots = re.findall(
        r"\bh\s*=\s*0;\s*(?:var\s+\w+;\s*)?while\(h\s*<\s*(\d+)\)", script
    )
    if len(slots) != 1:
        raise ValueError(f"the buff row loop is found {len(slots)} times, want 1")
    sides = re.search(
        r"if\(ukcb\.teamSide\s*==\s*1\)\s*\{\s*buffMultiGF\s*=\s*(-?\d+);\s*\}"
        r"\s*else\s*\{\s*buffMultiGF\s*=\s*(-?\d+);\s*\}",
        script,
    )
    if sides is None:
        raise ValueError("buffMultiGF is not set by an if on teamSide == 1")
    return {
        "offset": values["buffOffsetGF"],
        "space": values["buffSpaceGF"],
        "slots": int(slots[0]),
        "player_side": int(sides[1]),
        "enemy_side": int(sides[2]),
    }


def smoother_factors(script: str) -> dict:
    """-> the factor and the offset lifeBarUpdate places a smoother with:
    `LBS._x = bar._width * factor - offset`. The life and focus lines have to
    agree."""
    found = set(
        re.findall(
            r"LBS\._x\s*=\s*[\w.\[\]\"+ ]+\._width\s*\*\s*(\d+\.\d+)\s*-\s*(\d+);",
            script,
        )
    )
    if len(found) != 1:
        raise ValueError(f"the smoother's _x is set with {len(found)} formulas, want 1")
    factor, offset = found.pop()
    return {"x_factor": float(factor), "x_offset": float(offset)}


def content_width(
    character: int,
    layers_of: Callable[[int], dict | None],
    shape_box: Callable[[int], tuple[int, int, int, int]],
) -> float:
    """-> the width in twips of everything `character` draws on its first frame,
    which is what Flash reports as its _width. `layers_of` gives a sprite's first
    frame, or None for a shape. A matrix may only scale and translate."""
    box = _content_box(character, layers_of, shape_box)
    if box is None:
        raise ValueError(f"character {character} draws nothing")
    return box[2] - box[0]


def _content_box(character, layers_of, shape_box):
    layers = layers_of(character)
    if layers is None:
        return shape_box(character)
    boxes = []
    for layer in layers.values():
        sx, skew0, skew1, sy, tx, ty = layer.matrix
        if skew0 or skew1:
            raise ValueError(f"matrix {layer.matrix} rotates or skews")
        inner = _content_box(layer.character_id, layers_of, shape_box)
        if inner is None:
            continue
        xs = sorted((inner[0] * sx + tx, inner[2] * sx + tx))
        ys = sorted((inner[1] * sy + ty, inner[3] * sy + ty))
        boxes.append((xs[0], ys[0], xs[1], ys[1]))
    if not boxes:
        return None
    return (
        min(b[0] for b in boxes),
        min(b[1] for b in boxes),
        max(b[2] for b in boxes),
        max(b[3] for b in boxes),
    )


def flat_color(transform: tuple[int, ...] | None, where: str) -> str:
    """-> the colour, as `#rrggbb`, that a color transform turns a shape into.
    The transform has to set a flat colour: multipliers 0, 0, 0 and 256 for the
    alpha, adds for the colour and none for the alpha."""
    if transform is None or tuple(transform[:4]) != (0, 0, 0, 256) or transform[7] != 0:
        raise ValueError(f"{where} does more than set a flat colour: {transform}")
    return "#{:02x}{:02x}{:02x}".format(*(max(0, min(v, 255)) for v in transform[4:7]))


def life_colors(frames: list[dict[int, timeline.Layer]]) -> list[str]:
    """-> the colour of each frame of the life color clip. Every frame has to
    place shape 54 alone."""
    colors = []
    for number, layers in enumerate(frames, start=1):
        if len(layers) != 1:
            raise ValueError(f"frame {number} places {len(layers)} layers, want 1")
        (layer,) = layers.values()
        if layer.character_id != LIFE_COLOR_SHAPE:
            raise ValueError(f"frame {number} does not place shape 54")
        colors.append(flat_color(layer.color_transform, f"frame {number}"))
    return colors


def smoother_record(
    frames: list[dict[int, timeline.Layer]],
    labels: dict[str, int],
    script_frames: list[int],
) -> dict:
    """-> one smoother clip: its labels, the frames that run a script, and what
    each frame shows. A smoother frame shows the colour clip under an x and an x
    scale, or nothing. `ratio` is set on the frames that follow a gap."""
    shown = []
    for number, layers in enumerate(frames, start=1):
        if not layers:
            shown.append({"frame": number, "shown": False})
            continue
        if len(layers) != 1:
            raise ValueError(f"frame {number} places {len(layers)} layers, want 1")
        (layer,) = layers.values()
        if layer.character_id != LIFE_COLOR_CLIP or layer.name != "LCC":
            raise ValueError(f"frame {number} does not place the clip LCC")
        sx, skew0, skew1, sy, tx, ty = layer.matrix
        if skew0 or skew1 or sy != 1.0 or ty:
            raise ValueError(f"frame {number} places LCC with {layer.matrix}")
        entry = {
            "frame": number,
            "shown": True,
            "x": round(tx / render.TWIPS, 4),
            "x_scale": round(sx, 6),
        }
        if layer.color_transform is not None:
            entry["color"] = flat_color(layer.color_transform, f"frame {number}")
        if layer.ratio is not None:
            entry["ratio"] = layer.ratio
        shown.append(entry)
    return {
        "frames": len(frames),
        "labels": dict(sorted(labels.items())),
        "script_frames": script_frames,
        "shown": shown,
    }


def text_fields(
    index: SwfIndex, layers: dict[int, timeline.Layer], offset
) -> list[dict]:
    """-> the edit texts of one frame of `inner`, placed at `offset` (twips) in
    the bar sprite, with the rect Flash lays each out in."""
    found = []
    for layer in layers.values():
        if character_kind(index, layer.character_id) != "edittext":
            continue
        field = edit_text(index, layer.character_id)
        matrix = (
            layer.matrix[0],
            layer.matrix[1],
            layer.matrix[2],
            layer.matrix[3],
            layer.matrix[4] + offset[0],
            layer.matrix[5] + offset[1],
        )
        entry = screen_rects.text_record(field, matrix, (0.0, 0.0))
        entry.pop("kind")
        entry["character"] = layer.character_id
        entry["variable"] = field.variable_name
        found.append(entry)
    return sorted(found, key=lambda e: e["variable"])


def shadow_record(shadow: DropShadow) -> dict:
    return {
        "angle": shadow.angle,
        "blur_x": shadow.blur_x,
        "blur_y": shadow.blur_y,
        "color": screen_rects.color_hex(shadow.color),
        "distance": shadow.distance,
        "inner": shadow.inner,
        "knockout": shadow.knockout,
        "strength": shadow.strength,
    }


def bar_placements(index: SwfIndex) -> tuple[dict, dict]:
    """-> ({name: placement}, shadow): where the battle frame places the six
    bars, which frame of `inner` each load script chooses, and whether it mirrors
    `inner2`. The six share one DropShadow."""
    frame = timeline.frame_of(index, 0, battle_screen.FRAME_LABEL)
    layers = timeline.frames(index, 0)[frame - 1]
    placements = {}
    shadows = set()
    for depth, layer in sorted(layers.items()):
        if layer.character_id != BAR:
            continue
        found = BAR_NAME.fullmatch(layer.name or "")
        if found is None:
            raise ValueError(f"depth {depth} places the bar as {layer.name!r}")
        scripts = list(
            BATTLE_FRAME_SCRIPTS.glob(
                f"PlaceObject3_{BAR}_{depth}/*onClipEvent(load).as"
            )
        )
        flags = (
            load_script_flags(scripts[0].read_text("utf-8"))
            if scripts
            else {"inner_frame": None, "inner2_xscale": None}
        )
        sx, skew0, skew1, sy, tx, ty = layer.matrix
        if skew0 or skew1:
            raise ValueError(f"{layer.name} is placed with {layer.matrix}")
        shadow = screen_rects._shadow_of(layer)
        if shadow is None:
            raise ValueError(f"{layer.name} has no DropShadow")
        shadows.add(shadow)
        placements[layer.name] = {
            "depth": depth,
            "slot": int(found[1]),
            "x": round(tx / render.TWIPS, 4),
            "y": round(ty / render.TWIPS, 4),
            "scale": [round(sx, 6), round(sy, 6)],
            **flags,
        }
    if sorted(placements) != [f"p{n}BAR" for n in range(1, 7)]:
        raise ValueError(f"the frame places the bars {sorted(placements)}")
    if len(shadows) != 1:
        raise ValueError(f"the six bars have {len(shadows)} different DropShadows")
    return placements, shadow_record(shadows.pop())


def white_with_alpha(image: Image.Image) -> Image.Image:
    """-> `image` as white pixels under its own alpha, which a colour then
    multiplies."""
    white = Image.new("RGBA", image.size, (255, 255, 255, 0))
    white.putalpha(image.getchannel("A"))
    return white


def rect_of(trimmed: render.Trimmed) -> list[float]:
    return [round(v, 4) for v in trimmed.rect]


def main():
    index = read_swf(WEB_SWF)
    placements, shadow = bar_placements(index)

    bar_first = timeline.frames(index, BAR)[0]
    inner_layer = next(
        placed for placed in bar_first.values() if placed.character_id == INNER
    )
    inner2_layer = next(
        placed for placed in bar_first.values() if placed.character_id == INNER2
    )
    inner_origin = (
        inner_layer.matrix[4] / render.TWIPS,
        inner_layer.matrix[5] / render.TWIPS,
    )
    inner_labels = timeline.labels(index, INNER)
    inner_frames = timeline.frames(index, INNER)
    frame_numbers = {
        "first": 1,
        "second": inner_labels["second"],
        "third": inner_labels["third"],
    }

    inner2_frames = timeline.frames(index, INNER2)[0]
    life_origin = _origin_in(index, LIFE_BAR, LIFE_COLOR_CLIP)
    jobs = {
        "inner_first": render.Job(
            INNER, frame_numbers["first"], ZOOM, origin=inner_origin, only_depths=(1,)
        ),
        "inner_second": render.Job(
            INNER, frame_numbers["second"], ZOOM, origin=inner_origin, only_depths=(1,)
        ),
        "focus_fill": render.Job(FOCUS_BAR, 1, ZOOM),
        "life_fill": render.Job(LIFE_COLOR_CLIP, 1, ZOOM, origin=life_origin),
        **{
            f"inner2_{name.lower()}": render.Job(INNER2, 1, ZOOM, only_depths=(depth,))
            for name, depth in INNER2_ART.items()
        },
    }
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    art = {}
    with render.frames(WEB_SWF, list(jobs.values())) as rendered:
        for name, frame in zip(jobs, rendered, strict=True):
            trimmed = render.trim(frame)
            if trimmed is None:
                raise RuntimeError(f"{name} rendered empty")
            image = (
                white_with_alpha(trimmed.image)
                if name == "life_fill"
                else trimmed.image
            )
            png.save(image, OUT_DIR / f"{name}.png")
            art[name] = {
                "file": f"{name}.png",
                "rect": rect_of(trimmed),
                "size": list(image.size),
            }
            print(f"  {name}.png {image.size}", file=sys.stderr)

    colors = life_colors(timeline.frames(index, LIFE_COLOR_CLIP))

    def layers_of(character: int):
        if character_kind(index, character) != "sprite":
            return None
        return timeline.frames(index, character)[0]

    widths = {}
    for name, sprite, art_name in (
        ("life", LIFE_BAR, "life_fill"),
        ("focus", FOCUS_BAR, "focus_fill"),
    ):
        pieces = [
            placed for placed in inner2_frames.values() if placed.character_id == sprite
        ]
        scales = {
            (placed.matrix[0], placed.matrix[4], placed.matrix[5])
            for placed in pieces
            if placed.name in _fill_names(name)
        }
        if len(scales) != 1:
            raise ValueError(f"the {name} fill is placed with {scales}")
        scale_x, x, y = scales.pop()
        # Flash's _width is in the parent's space, so it carries the placement scale.
        wsaver = (
            content_width(sprite, layers_of, lambda c: shape_bounds(index, c))
            / render.TWIPS
            * scale_x
        )
        widths[name] = {
            "art": art_name,
            "scale_x": round(scale_x, 6),
            "x": round(x / render.TWIPS, 4),
            "y": round(y / render.TWIPS, 4),
            "wsaver": round(wsaver, 4),
        }

    code = {(b.kind, b.owner): [] for b in index.code}
    for block in index.code:
        code[(block.kind, block.owner)].append(block.frame)
    smoothers = {}
    for name in SMOOTHERS:
        sprite = index.exports[name]
        smoothers[name] = {
            "character": sprite,
            **smoother_record(
                timeline.frames(index, sprite),
                timeline.labels(index, sprite),
                sorted(code.get(("frame", sprite), [])),
            ),
        }

    inner2_pieces = {
        layer.name or f"depth{depth}": {
            "depth": depth,
            "character": layer.character_id,
            "scale_x": round(layer.matrix[0], 6),
            "x": round(layer.matrix[4] / render.TWIPS, 4),
            "y": round(layer.matrix[5] / render.TWIPS, 4),
        }
        for depth, layer in sorted(inner2_frames.items())
    }

    record = {
        "zoom": ZOOM,
        "placements": placements,
        "shadow": shadow,
        "inner": {
            "origin": [round(v, 4) for v in inner_origin],
            "frames": {
                name: {
                    "frame": number,
                    "art": art.get(f"inner_{name}"),
                    "fields": text_fields(
                        index,
                        inner_frames[number - 1],
                        (inner_layer.matrix[4], inner_layer.matrix[5]),
                    ),
                }
                for name, number in frame_numbers.items()
            },
        },
        "inner2": {
            "origin": [
                round(inner2_layer.matrix[4] / render.TWIPS, 4),
                round(inner2_layer.matrix[5] / render.TWIPS, 4),
            ],
            "pieces": inner2_pieces,
            "art": {name: art[f"inner2_{name.lower()}"] for name in INNER2_ART},
        },
        "bars": widths,
        "art": {"life_fill": art["life_fill"], "focus_fill": art["focus_fill"]},
        "life_color_frames": len(colors),
        "life_colors": colors,
        "smoothers": smoothers,
        "smoother_factors": smoother_factors(LIFE_BAR_SCRIPT.read_text("utf-8")),
        "buff_row": {
            **buff_row_constants(BUFF_ROW_SCRIPT.read_text("utf-8")),
            "shower": index.exports[BUFF_SHOWER],
        },
    }
    RECORD.write_text(json.dumps(record, indent=1, sort_keys=True) + "\n")
    print(f"wrote {RECORD}", file=sys.stderr)


def _fill_names(kind: str) -> tuple[str, ...]:
    """-> the instance names of the clips that draw the fill of `kind`: the bar
    itself and its backing copy."""
    return ("lB", "lB2") if kind == "life" else ("fB", "fB2")


def _origin_in(index: SwfIndex, owner: int, character: int) -> tuple[float, float]:
    """-> where `owner`'s first frame places `character`, in design px."""
    return render.placement_origin(index, owner, 1, character)


if __name__ == "__main__":
    main()
