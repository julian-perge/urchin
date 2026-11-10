# The Combat text banner, the original's KrinCombatText (DefineSprite 2852),
# which the battle frame places at (400, 148.5):
#
#   assets/ui/battle/combat_text_backdrop.png - the band behind the text
#   assets/ui/battle/combat_text.json         - where the banner, its band and
#                                               its text go, and how far the
#                                               band and text have slid and
#                                               faded on each of its frames
#
# HOW THE CLIP PLAYS. Frame 1 runs stop() and shows nothing. The game starts it
# with gotoAndPlay("GO"), and the GO frame, frame 2, copies combatTexter into
# the text field and places the inner clip 10 px down and clear. By frame 12
# the inner clip has slid up into place and faded in, it holds there, frame
# 125 empties the text field, and frames 126 to 136 slide it back down as it
# fades out. Then the clip loops to frame 1 and stops (DefineSprite_2852/
# frame_1, frame_2 and frame_125). The JSON keeps every frame's alpha and
# offset, so the port replays exactly those.
#
# THE BAND IS RENDERED WITH ITS GLOW. The battle frame places the clip with a
# red Glow filter, which turns the translucent white band pink and haloes the
# text. The band is rendered from root frame KRINBATTLESCENE with every other
# depth hidden and the clip moved to its first frame at rest, so ffdec bakes
# the glow in. The placeholder text, "combat text goes here", is stripped
# first, so the text's own share of the glow is left out of the band.
#
# THE TEXT IS DRAWN BY THE PORT. Edit text 2849 is filled at runtime, so the
# JSON carries its rect, size, colour and alignment for a Label instead. Its
# font, DefineFont3 65, is the bold _sans with no glyphs, a Device font, so the
# port draws it in the Stand-in font the project theme gives every Label. The
# orb's cooldown count, edit text 2245, uses the same font.
#
# Run: uv run extract_combat_text
from __future__ import annotations

import json
import sys

from urchin_dev import REPO_ROOT, WEB_SWF
from urchin_dev.swf import render, strip, timeline
from urchin_dev.swf.extract.battle_screen import (
    FRAME_LABEL,
    IDENTITY_COLOR_TRANSFORM,
    rect_entry,
)
from urchin_dev.swf.swf_index import (
    EditText,
    SwfIndex,
    character_kind,
    edit_text,
    font,
    read_swf,
)

OUT_DIR = REPO_ROOT / "assets" / "ui" / "battle"
BACKDROP_PNG = OUT_DIR / "combat_text_backdrop.png"
LAYOUT_JSON = OUT_DIR / "combat_text.json"

BANNER = 2852
# The instance name the clip's frame scripts set the text through.
INNER_NAME = "inner"
# The variable of the text field the GO frame fills and frame 125 empties.
TEXT_VARIABLE = "combatText"
GO_LABEL = "GO"
STOP_FRAME = 1
CLEAR_FRAME = 125
# Battle chrome is rendered at 4x, as docs/agents/art-extraction.md sets out.
ZOOM = 4.0
TWIPS = 20
# Flash lays a text field's text out 2 px inside its bounds on every side.
# unit_overlay.gd measures the buff counter, edit text 66, the same way.
GUTTER = 2.0
ALIGNMENTS = {0: "left", 1: "right", 2: "center", 3: "justify"}


def motion(index: SwfIndex, sprite: int) -> tuple[list[float], list[float]]:
    """-> (alphas, offsets), one of each per frame of `sprite`: how opaque its
    inner clip is, and how far below its resting place it sits in design px.
    A frame that shows nothing reads as alpha 0.0 at offset 0.0. A frame that
    does more than slide the inner clip down and fade it raises, because the
    port plays the banner from these two numbers alone."""
    alphas, offsets = [], []
    for number, layers in enumerate(timeline.frames(index, sprite), start=1):
        if not layers:
            alphas.append(0.0)
            offsets.append(0.0)
            continue
        where = f"{sprite} frame {number}"
        if len(layers) != 1:
            raise RuntimeError(f"{where} shows {len(layers)} layers, want 1")
        (layer,) = layers.values()
        if layer.name != INNER_NAME:
            raise RuntimeError(f"{where} shows {layer.name!r}, want {INNER_NAME!r}")
        if layer.matrix[:5] != (1.0, 0.0, 0.0, 1.0, 0):
            raise RuntimeError(f"{where} places {INNER_NAME} with {layer.matrix}")
        transform = layer.color_transform or IDENTITY_COLOR_TRANSFORM
        if transform[:3] != (256, 256, 256) or transform[4:] != (0, 0, 0, 0):
            raise RuntimeError(f"{where} transforms more than the alpha: {transform}")
        alphas.append(max(0, min(transform[3], 256)) / 256)
        offsets.append(layer.matrix[5] / TWIPS)
    return alphas, offsets


def text_rect(field: EditText, placed: tuple[float, float]) -> dict[str, float]:
    """-> the rect Flash lays `field`'s text out in, in design px from the
    origin of the clip that places the field at `placed`."""
    xmin, ymin, xmax, ymax = (v / TWIPS for v in field.bounds)
    return {
        "x": round(placed[0] + xmin + GUTTER, 2),
        "y": round(placed[1] + ymin + GUTTER, 2),
        "w": round(xmax - xmin - 2 * GUTTER, 2),
        "h": round(ymax - ymin - 2 * GUTTER, 2),
    }


def check_scripts(index: SwfIndex, go_frame: int) -> None:
    """Raise unless the clip runs code on its stop frame, its GO frame and its
    clear frame and nowhere else, the GO frame copies combatTexter into the
    text field, and the clear frame sets it to the empty string."""
    scripts = {
        block.frame: block.strings
        for block in index.code
        if block.kind == "frame" and block.owner == BANNER
    }
    if sorted(scripts) != [STOP_FRAME, go_frame, CLEAR_FRAME]:
        raise RuntimeError(
            f"{BANNER} runs code on frames {sorted(scripts)},"
            f" want {STOP_FRAME}, {go_frame} and {CLEAR_FRAME}"
        )
    if not {TEXT_VARIABLE, "combatTexter"} <= set(scripts[go_frame]):
        raise RuntimeError(f"{BANNER} frame {go_frame} pushes {scripts[go_frame]}")
    if not {TEXT_VARIABLE, ""} <= set(scripts[CLEAR_FRAME]):
        raise RuntimeError(
            f"{BANNER} frame {CLEAR_FRAME} pushes {scripts[CLEAR_FRAME]}"
        )


def text_layout(field: EditText, placed: tuple[float, float]) -> dict:
    """-> what a Label needs to draw `field`'s line where Flash would: the
    rect text_rect() gives, and the field's alignment, colour and size."""
    return {
        "align": ALIGNMENTS[field.align],
        "color": "#{:02x}{:02x}{:02x}".format(*field.color[:3]),
        "rect": text_rect(field, placed),
        "size": field.font_height / TWIPS,
    }


def text_field(index: SwfIndex, inner: int) -> tuple[int, EditText]:
    """-> the id and fields of the edit text the inner clip shows the message
    in, checked by plain_device_line()."""
    (field_id,) = [
        layer.character_id
        for layer in timeline.frames(index, inner)[0].values()
        if character_kind(index, layer.character_id) == "edittext"
        and edit_text(index, layer.character_id).variable_name == TEXT_VARIABLE
    ]
    return field_id, plain_device_line(index, field_id)


def plain_device_line(index: SwfIndex, field_id: int) -> EditText:
    """-> the fields of edit text `field_id`. Raises unless it is one line of
    a bold Device font with no margins, which is what the port's Label stands
    in for."""
    field = edit_text(index, field_id)
    face = font(index, field.font_id)
    if not (face.device and face.bold):
        raise RuntimeError(
            f"edit text {field_id}'s font {field.font_id} is {face}, and the port"
            " only has a Stand-in font for a bold Device font"
        )
    if field.multiline or field.word_wrap or field.html:
        raise RuntimeError(f"edit text {field_id} is not one plain line: {field}")
    if (field.left_margin, field.right_margin, field.indent) != (0, 0, 0):
        raise RuntimeError(f"edit text {field_id} has margins: {field}")
    return field


def main():
    index = read_swf(WEB_SWF)
    battle_frame = timeline.frame_of(index, 0, FRAME_LABEL)
    layers = timeline.frames(index, 0)[battle_frame - 1]
    (depth,) = [d for d, layer in layers.items() if layer.character_id == BANNER]
    position = render.placement_origin(index, 0, battle_frame, BANNER)

    go_frame = timeline.frame_of(index, BANNER, GO_LABEL)
    check_scripts(index, go_frame)
    alphas, offsets = motion(index, BANNER)
    rest = next(
        n
        for n in range(go_frame, len(alphas) + 1)
        if alphas[n - 1] == 1.0 and offsets[n - 1] == 0.0
    )
    inner = timeline.frames(index, BANNER)[go_frame - 1][1].character_id
    field_id, field = text_field(index, inner)
    print(
        f"{BANNER} at {position} on root frame {battle_frame}, at rest from"
        f" frame {rest}; text in edit text {field_id}, font {field.font_id}"
        f" {font(index, field.font_id)}",
        file=sys.stderr,
    )

    stripped = strip.strip_list(
        WEB_SWF,
        {field_id: "the author's placeholder text, which the game fills at runtime"},
    )
    # A clip mask has to stay shown, because hiding one unclips everything it
    # covers. None of the battle frame's masks covers the banner's depth.
    masks = [d for d, layer in layers.items() if layer.clip_depth is not None]
    job = render.Job(
        0,
        battle_frame,
        ZOOM,
        strip=tuple(stripped),
        only_depths=tuple(sorted([*masks, depth])),
        goto=((depth, rest),),
    )
    with render.frames(WEB_SWF, [job]) as (frame,):
        trimmed = render.trim(frame)
        if trimmed is None:
            raise RuntimeError(f"{BANNER} frame {rest} rendered empty")
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        trimmed.image.save(BACKDROP_PNG)
    x, y, w, h = trimmed.rect
    print(f"  backdrop -> {BACKDROP_PNG.name} {trimmed.image.size}", file=sys.stderr)

    placed = render.placement_origin(index, inner, 1, field_id)
    layout = {
        "alphas": alphas,
        "art_zoom": ZOOM,
        "backdrop": rect_entry((x - position[0], y - position[1], w, h)),
        "clear_frame": CLEAR_FRAME,
        "fps": index.frame_rate,
        "go_frame": go_frame,
        "offsets": offsets,
        "position": {"x": position[0], "y": position[1]},
        "text": text_layout(field, placed),
    }
    LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
    print(f"wrote {LAYOUT_JSON}", file=sys.stderr)


if __name__ == "__main__":
    main()
