# The Floating number, the original's NumberFixer (DefineSprite 53), which
# KrinNumberShow attaches over a unit when a Move result lands on it
# (frame_42/DoAction_7.as):
#
#   assets/ui/battle/floating_number/<glyph>_depth<n>.png
#       one layer of one glyph, for the digits 0 to 9 and the miss and shield
#       words
#   assets/ui/battle/floating_number/floating_number.json
#       where each layer sits on its glyph and whether it takes the number's
#       color, and how the holder scales, rises, fades and turns white on
#       each frame of each of NumberFixer's four labels
#
# HOW THE CLIP PLAYS. NumberFixer has the labels normal, critical, miss and
# shield, and each one ends on a frame that runs removeMovieClip(this). Every
# frame shows one clip, "flasher", and only its scale, its height, its alpha
# and a color transform that tints it toward white change. The JSON keeps
# those four numbers for every frame, so the port plays exactly those. In
# normal and critical the holder is an empty clip that KrinNumberShow fills
# with one NumberSetter clip (DefineSprite 44) per digit. In miss and shield
# it is the MISS word (DefineSprite 50) or the SHIELDED word (DefineSprite 52).
#
# EACH GLYPH IS RENDERED LAYER BY LAYER. A digit and the MISS word are a black
# outline, then the KN fill, then a white shine. KrinNumberShow replaces the
# KN fill's color with the number's color through setRGB, so ffdec renders
# each layer alone and the port stacks them, with the KN layer in the number's
# color. The KN layer's PNG keeps the purple the SWF draws it in, and the
# port uses only its alpha. check_rebuild() proves that the stacked layers draw
# the whole glyph. SHIELDED is one layer with no KN child, so it never takes a
# color.
#
# The art is rendered at 4x, because the critical label starts at 2.84x and
# the others start at 1.78x.
#
# Run: uv run extract_floating_numbers
from __future__ import annotations

import json
import sys
from dataclasses import dataclass

from PIL import Image, ImageChops

from urchin_dev import REPO_ROOT, WEB_SWF
from urchin_dev.swf import render, timeline
from urchin_dev.swf.extract.battle_screen import IDENTITY_COLOR_TRANSFORM, rect_entry
from urchin_dev.swf.swf_index import SwfIndex, read_swf

OUT_DIR = REPO_ROOT / "assets" / "ui" / "battle" / "floating_number"
LAYOUT_JSON = OUT_DIR / "floating_number.json"
ZOOM = 4.0

# The instance KrinNumberShow attaches the digits to and tints the KN fill of
# (frame_42/DoAction_7.as:55 and 66).
HOLDER_NAME = "flasher"
# The instance whose color KrinNumberShow sets to the number's color
# (frame_42/DoAction_7.as:58-59 and 66-67).
TINTED_NAME = "KN"
# numberMatrixKrin, the NumberSetter label KrinNumberShow sends each digit to
# (frame_42/DoAction_7.as:2 and 57).
DIGIT_LABELS = (
    "Zero",
    "One",
    "Two",
    "Three",
    "Four",
    "Five",
    "Six",
    "Seven",
    "Eight",
    "Nine",
)
# How far a color transform may stray from a tint toward white, as the share
# its multiply and add terms leave between them. Flash rounds both terms to
# whole steps, so (51, 204) leaves 0.9992 where an exact tint leaves 1.
TINT_TOLERANCE = 1 / 128
# How far a glyph's layers, stacked, may stray from ffdec's render of the whole
# glyph, in levels of a premultiplied channel. Measured on every glyph at jpexs
# cde1cc21a it is 0, and leaving a layer out or stacking the layers in the wrong
# order moves it by 72 levels or more.
REBUILD_TOLERANCE = 1


@dataclass(frozen=True)
class NumberLabel:
    """One of NumberFixer's labels: the character its holder shows, and the
    holder's scale, height in design px, alpha and share of white on each frame
    from the label to the last frame before the clip removes itself."""

    holder: int
    frames: list[dict[str, float]]


def number_labels(index: SwfIndex, sprite: int) -> dict[str, NumberLabel]:
    """-> {label: NumberLabel} for every label of `sprite`. A label ends on the
    frame before the next frame script, which has to run removeMovieClip(this)
    on a frame that shows nothing. Anything else in the clip raises, because
    the port plays a label from these four numbers alone."""
    layers_by_frame = timeline.frames(index, sprite)
    ends = remove_frames(index, sprite)
    labels: dict[str, NumberLabel] = {}
    for name, start in sorted(
        timeline.labels(index, sprite).items(), key=lambda item: item[1]
    ):
        end = next((frame for frame in ends if frame > start), None)
        if end is None:
            raise RuntimeError(f"{sprite} label {name!r} never removes the clip")
        if layers_by_frame[end - 1]:
            raise RuntimeError(
                f"{sprite} frame {end} removes the clip but still shows it"
            )
        holders = set()
        frames = []
        for number in range(start, end):
            layer = _holder(layers_by_frame[number - 1], f"{sprite} frame {number}")
            holders.add(layer.character_id)
            frames.append(_holder_frame(layer, f"{sprite} frame {number}"))
        if len(holders) != 1:
            raise RuntimeError(
                f"{sprite} label {name!r} shows {sorted(holders)} in its holder"
            )
        labels[name] = NumberLabel(holders.pop(), frames)
    return labels


def digit_frames(index: SwfIndex, sprite: int) -> dict[str, int]:
    """-> {digit: the frame of `sprite` that shows it}, "0" to "9"."""
    return {
        str(digit): timeline.frame_of(index, sprite, name)
        for digit, name in enumerate(DIGIT_LABELS)
    }


def glyph_layers(index: SwfIndex, sprite: int, frame: int) -> list[tuple[int, bool]]:
    """-> (depth, tinted) for each layer `sprite` shows on `frame`, bottom
    first, where tinted marks the layer the number's color replaces."""
    layers = timeline.frames(index, sprite)[frame - 1]
    return [
        (depth, layer.name == TINTED_NAME) for depth, layer in sorted(layers.items())
    ]


def check_rebuild(name: str, whole: Image.Image, layers: list[Image.Image]) -> None:
    """Raise unless `layers`, stacked bottom first, draw the same picture as
    `whole` to within REBUILD_TOLERANCE in every premultiplied channel. The
    port draws a glyph layer by layer, so this proves no layer is missing and
    none is out of order."""
    stack = Image.new("RGBA", whole.size, (0, 0, 0, 0))
    for layer in layers:
        stack.alpha_composite(layer)
    worst = max(
        ImageChops.difference(drawn, rebuilt).getextrema()[1]
        for drawn, rebuilt in zip(
            _premultiplied(whole), _premultiplied(stack), strict=True
        )
    )
    if worst > REBUILD_TOLERANCE:
        raise RuntimeError(
            f"{name}: its layers stacked are {worst} levels off the whole glyph"
        )


def _premultiplied(image: Image.Image) -> list[Image.Image]:
    *color, alpha = image.split()
    return [ImageChops.multiply(channel, alpha) for channel in color] + [alpha]


def remove_frames(index: SwfIndex, sprite: int) -> list[int]:
    """-> the frames `sprite` runs code on, in order. Raises unless each one
    pushes only "this", which is all removeMovieClip(this) pushes."""
    frames = []
    for block in index.code:
        if block.kind == "frame" and block.owner == sprite:
            if block.strings != ("this",):
                raise RuntimeError(
                    f"{sprite} frame {block.frame} pushes {block.strings}"
                )
            frames.append(block.frame)
    return sorted(frames)


def _holder(layers: dict[int, timeline.Layer], where: str) -> timeline.Layer:
    if len(layers) != 1:
        raise RuntimeError(f"{where} shows {len(layers)} layers, want 1")
    (layer,) = layers.values()
    if layer.name != HOLDER_NAME:
        raise RuntimeError(f"{where} shows {layer.name!r}, want {HOLDER_NAME!r}")
    return layer


def _holder_frame(layer: timeline.Layer, where: str) -> dict[str, float]:
    scale_x, skew_0, skew_1, scale_y, tx, ty = layer.matrix
    if scale_x != scale_y or skew_0 or skew_1 or tx:
        raise RuntimeError(f"{where} places {HOLDER_NAME} with {layer.matrix}")
    transform = layer.color_transform or IDENTITY_COLOR_TRANSFORM
    rm, gm, bm, am, ra, ga, ba, aa = transform
    if not (
        rm == gm == bm
        and ra == ga == ba
        and aa == 0
        and abs(rm / 256 + ra / 255 - 1) <= TINT_TOLERANCE
    ):
        raise RuntimeError(
            f"{where} transforms {HOLDER_NAME} by more than a tint toward white: {transform}"
        )
    return {
        "scale": scale_x,
        "y": ty / render.TWIPS,
        "alpha": max(0, min(am, 256)) / 256,
        "white": ra / 255,
    }


def main():
    index = read_swf(WEB_SWF)
    fixer = index.exports["NumberFixer"]
    setter = index.exports["NumberSetter"]
    labels = number_labels(index, fixer)
    glyphs = {
        digit: (setter, frame) for digit, frame in digit_frames(index, setter).items()
    }
    # A word label's holder is the word itself. A digit label's holder is
    # empty until KrinNumberShow attaches the digits to it.
    words = {
        name: label.holder
        for name, label in labels.items()
        if timeline.frames(index, label.holder)[0]
    }
    for name, holder in words.items():
        if index.sprite_frames[holder] != 1:
            raise RuntimeError(
                f"the {name} word {holder} has {index.sprite_frames[holder]} frames, want 1"
            )
        glyphs[name] = (holder, 1)

    jobs: list[render.Job] = []
    plan: list[tuple[str, list[tuple[int, bool]]]] = []
    for name, (sprite, frame) in glyphs.items():
        layers = glyph_layers(index, sprite, frame)
        jobs.append(render.Job(sprite, frame, ZOOM))
        jobs.extend(
            render.Job(sprite, frame, ZOOM, only_depths=(depth,)) for depth, _ in layers
        )
        plan.append((name, layers))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    glyph_entries: dict[str, list[dict]] = {}
    with render.frames(WEB_SWF, jobs) as rendered:
        at = 0
        for name, layers in plan:
            whole, *parts = rendered[at : at + 1 + len(layers)]
            at += 1 + len(layers)
            check_rebuild(name, whole.image(), [part.image() for part in parts])
            entries = []
            for (depth, tinted), part in zip(layers, parts, strict=True):
                trimmed = render.trim(part)
                if trimmed is None:
                    raise RuntimeError(f"{name} depth {depth} rendered empty")
                png = f"{name}_depth{depth}.png"
                trimmed.image.save(OUT_DIR / png)
                entries.append(
                    {"png": png, "rect": rect_entry(trimmed.rect), "tinted": tinted}
                )
            glyph_entries[name] = entries
            print(f"  {name}: depths {[depth for depth, _ in layers]}", file=sys.stderr)

    layout = {
        "fps": index.frame_rate,
        "glyphs": glyph_entries,
        "labels": {
            name: {"frames": label.frames, **({"word": name} if name in words else {})}
            for name, label in labels.items()
        },
    }
    LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
    print(
        f"wrote {LAYOUT_JSON} with labels "
        + ", ".join(
            f"{name} {len(label.frames)} frames" for name, label in labels.items()
        ),
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
