# The Speech box, the original's combatScript (DefineSprite 3367), which the
# battle frame places at depth 634 and the conductor moves to x 473.3 or 21.8 at
# y 460.7 for each line (frame_217/PlaceObject2_3389_480 enterFrame, lines
# 819-828):
#
#   assets/ui/battle/speech_box_frame.png - the box's outer frame
#   assets/ui/battle/speech_box.json      - where the frame, the speaker's name,
#                                           the line, the face and the skip
#                                           hint go, and how the hint pulses
#
# WHAT THE CLIP HOLDS. Sprite 3367 places `inner` (3366) at (152.75, 47) and the
# skip hint (3359) at (33, -48.65). `inner` holds the frame art (3365), the
# frame's own shape for the face (333), the face clip `inner2` (2978), the speaker's
# name (edit text 3360, variable combatTextName) and the line (edit text 3361,
# variable combatText). The conductor fills the two variables and sends `inner2`
# to the frame named after the speaker (conductor lines 829-831).
#
# THE FRAME IS RENDERED WITH ITS FILTERS. The art is rendered from the battle
# frame with every other depth hidden, the way extract_combat_text does it, so
# ffdec bakes in the clip's own filters. The face clip, the two text fields and
# the hint are left out, because the port draws them.
#
# THE FACE IS NOT RENDERED HERE. extract_faces cuts every frame of clip 2978 to
# one box and writes it to face_crop.json, so this script only works out where
# that box lands in the Speech box: where `inner` places `inner2`, and the scale
# it places it with.
#
# THE TEXT IS DRAWN BY THE PORT. Edit text 3361 is placed at 1.0384 scale, so
# its rect and its size are scaled the same way before they go to a Label.
#
# THE HINT PULSES. The hint's text is MENU[53] and its clip, 3359, brightens and
# dims through a color transform on each of its frames. The JSON keeps each
# frame's multiply and add, and the port colors the Label from them.
#
# Run: uv run extract_speech_box
from __future__ import annotations

import dataclasses
import json
import re
import sys

from urchin_dev import REPO_ROOT, WEB_SWF, png
from urchin_dev.swf import label_layout, render, strip, timeline
from urchin_dev.swf.extract.battle_screen import (
    FRAME_LABEL,
    IDENTITY_COLOR_TRANSFORM,
    rect_entry,
)
from urchin_dev.swf.swf_index import edit_text, read_swf

OUT_DIR = REPO_ROOT / "assets" / "ui" / "battle"
FRAME_PNG = OUT_DIR / "speech_box_frame.png"
LAYOUT_JSON = OUT_DIR / "speech_box.json"
FACE_CROP_JSON = REPO_ROOT / "assets" / "ui" / "menu" / "portraits" / "face_crop.json"

BOX = 3367
INNER = 3366
FACE_CLIP = 2978
HINT_CLIP = 3359
HINT_TEXT = 3357
NAME_FIELD = 3360
# The pixel font, DefineFont3 3307, which the member bar's names use too.
PIXEL_FONT = 3307
LINE_FIELD = 3361
# Battle chrome is rendered at 4x, as docs/agents/art-extraction.md sets out.
ZOOM = 4.0


def placed(index, owner: int, character: int):
    """-> the one layer of `owner`'s frame 1 that places `character`."""
    (layer,) = [
        layer
        for layer in timeline.frames(index, owner)[0].values()
        if layer.character_id == character
    ]
    return layer


def hint_colors(index) -> list[dict]:
    """-> the hint clip's color transform on each frame, as the multiply and
    the add of each channel on a 0 to 1 scale. Raises unless every frame shows
    the one text clip at one place, because the port colors one Label."""
    frames = timeline.frames(index, HINT_CLIP)
    out = []
    for number, layers in enumerate(frames, start=1):
        (layer,) = layers.values()
        if layer.matrix != frames[0][1].matrix:
            raise RuntimeError(f"{HINT_CLIP} frame {number} moves the text")
        t = layer.color_transform or IDENTITY_COLOR_TRANSFORM
        out.append(
            {
                "add": [round(v / 255, 4) for v in t[4:7]],
                "alpha": round(t[3] / 256, 4),
                "mult": [round(v / 256, 4) for v in t[:3]],
            }
        )
    return out


def main():
    index = read_swf(WEB_SWF)
    battle_frame = timeline.frame_of(index, 0, FRAME_LABEL)
    root_layers = timeline.frames(index, 0)[battle_frame - 1]
    (depth,) = [d for d, layer in root_layers.items() if layer.character_id == BOX]
    origin = render.placement_origin(index, 0, battle_frame, BOX)

    inner = placed(index, BOX, INNER)
    hint = placed(index, BOX, HINT_CLIP)
    face = placed(index, INNER, FACE_CLIP)
    name = placed(index, INNER, NAME_FIELD)
    line = placed(index, INNER, LINE_FIELD)
    box_depths = {
        d: layer.character_id for d, layer in timeline.frames(index, BOX)[0].items()
    }
    inner_depths = {
        d: layer.character_id for d, layer in timeline.frames(index, INNER)[0].items()
    }
    (face_depth,) = [d for d, c in inner_depths.items() if c == FACE_CLIP]
    (hint_depth,) = [d for d, c in box_depths.items() if c == HINT_CLIP]
    if inner.matrix[:4] != render.IDENTITY_LINEAR:
        raise RuntimeError(f"{BOX} places {INNER} with {inner.matrix}")
    if hint.matrix[:4] != render.IDENTITY_LINEAR:
        raise RuntimeError(f"{BOX} places {HINT_CLIP} with {hint.matrix}")
    inner_at = (inner.matrix[4] / render.TWIPS, inner.matrix[5] / render.TWIPS)
    hint_at = (hint.matrix[4] / render.TWIPS, hint.matrix[5] / render.TWIPS)
    print(
        f"{BOX} on root frame {battle_frame} at {origin}; inner at {inner_at},"
        f" hint at {hint_at}",
        file=sys.stderr,
    )

    stripped = strip.strip_list(
        WEB_SWF,
        {
            NAME_FIELD: "the speaker's name, which the game fills at runtime",
            LINE_FIELD: "the line, which the game fills at runtime",
        },
    )
    masks = [d for d, layer in root_layers.items() if layer.clip_depth is not None]
    job = render.Job(
        0,
        battle_frame,
        ZOOM,
        strip=tuple(stripped),
        only_depths=tuple(sorted([*masks, depth])),
        hide_depths=((BOX, hint_depth), (INNER, face_depth)),
    )
    with render.frames(WEB_SWF, [job]) as (frame,):
        trimmed = render.trim(frame)
        if trimmed is None:
            raise RuntimeError(f"{BOX} rendered empty")
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        png.save(trimmed.image, FRAME_PNG)
    x, y, w, h = trimmed.rect
    print(f"  frame -> {FRAME_PNG.name} {trimmed.image.size}", file=sys.stderr)

    # The face's box in clip 2978, and where `inner` places that clip.
    crop = json.loads(FACE_CROP_JSON.read_text())["rect"]
    sx, sy = face.matrix[0], face.matrix[3]
    if face.matrix[1] != 0 or face.matrix[2] != 0:
        raise RuntimeError(f"{INNER} turns {FACE_CLIP}: {face.matrix}")
    face_rect = (
        inner_at[0] + face.matrix[4] / render.TWIPS + crop[0] * sx,
        inner_at[1] + face.matrix[5] / render.TWIPS + crop[1] * sy,
        crop[2] * sx,
        crop[3] * sy,
    )

    name_field = label_layout.plain_device_line(index, NAME_FIELD)
    line_field = edit_text(index, LINE_FIELD)
    scale = line.matrix[0]
    if line.matrix[1] != 0 or line.matrix[2] != 0 or abs(scale - line.matrix[3]) > 1e-3:
        raise RuntimeError(f"{INNER} places {LINE_FIELD} with {line.matrix}")
    scaled_line = dataclasses.replace(
        line_field,
        bounds=tuple(round(v * scale) for v in line_field.bounds),
        font_height=round(line_field.font_height * scale),
    )
    name_at = (
        inner_at[0] + name.matrix[4] / render.TWIPS,
        inner_at[1] + name.matrix[5] / render.TWIPS,
    )
    line_at = (
        inner_at[0] + line.matrix[4] / render.TWIPS,
        inner_at[1] + line.matrix[5] / render.TWIPS,
    )
    hint_text = edit_text(index, HINT_TEXT)
    # The hint is HTML text in the pixel font 3307, with a letterSpacing that no
    # field of the tag carries, so it is read from the text.
    spacing = re.search(r'letterSpacing="([0-9.]+)"', hint_text.initial_text or "")
    if hint_text.font_id != PIXEL_FONT or spacing is None:
        raise RuntimeError(f"edit text {HINT_TEXT} is not pixel font text: {hint_text}")
    hint_text_at = placed(index, 3358, HINT_TEXT)
    hint_text_origin = (
        hint_at[0] + hint_text_at.matrix[4] / render.TWIPS,
        hint_at[1] + hint_text_at.matrix[5] / render.TWIPS,
    )

    layout = {
        "face": rect_entry(face_rect),
        "fps": index.frame_rate,
        "frame": rect_entry((x - origin[0], y - origin[1], w, h)),
        "hint": {
            "colors": hint_colors(index),
            "letter_spacing": float(spacing.group(1)),
            "text": label_layout.text_layout(hint_text, hint_text_origin),
        },
        "line": label_layout.text_layout(scaled_line, line_at),
        "name": label_layout.text_layout(name_field, name_at),
    }
    LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
    print(f"wrote {LAYOUT_JSON}", file=sys.stderr)


if __name__ == "__main__":
    main()
