# The SKIP button on every cutscene frame: button 3468, with the "SKIP" text
# 3469 beside it. Root frame 263, the frame of CS_INTRO, places them at depths
# 77 and 76, and frame 449 removes them. Every frame from 263 to 448 shows both,
# and the seven CS_ labels, CS_INTRO, CS_INTRO2 and CS_CUT1 to CS_CUT5, all sit
# in that range.
#
#   assets/cutscenes/skip_button.json - where the button's hit area and its text
#                                       go, and how the text is drawn
#
# THE BUTTON HAS NO ART. Its one record draws shape 291, a 30 px square, in the
# hit-test state and in no other, so the player sees no button at all. The port
# keeps a flat Button over the same rectangle. The frame places the button with
# a scale of 2.63 across and 0.89 down, which makes the square 79 by 27 px.
#
# THE TEXT IS DRAWN BY THE PORT. Edit text 3469 is white, 12 px and right-aligned
# in DefineFont3 65, the bold _sans Device font with no glyphs. The port draws
# that font as a Label in the Stand-in font the project theme gives every Label,
# so the JSON carries the text, its rect, size, colour and alignment, and no PNG
# is rendered. The combat text banner and the orb's cooldown count are laid out
# the same way. The field has the WasStatic flag. All 28 such fields in the web
# build are multiline with no variable, and 27 of them end their text with a
# paragraph mark, as "SKIP\r" does. label_layout.plain_device_line() accepts that.
#
# The button's release stops all sounds and sets cutSceneEnd
# (DefineButton2_3468/BUTTONCONDACTION on(release).as), and the fade clip that
# every cutscene frame places then fades out and jumps to gotoSceneKrin
# (frame_263/PlaceObject2_3466_80/CLIPACTIONRECORD onClipEvent(enterFrame).as).
# cutscene_player.gd does that part.
#
# Run: uv run extract_cutscene_skip
from __future__ import annotations

import json
import sys

from urchin_dev import REPO_ROOT, WEB_SWF
from urchin_dev.swf import label_layout, render, timeline
from urchin_dev.swf.extract.battle_screen import rect_entry
from urchin_dev.swf.swf_index import SwfIndex, button_records, read_swf, shape_bounds

LAYOUT_JSON = REPO_ROOT / "assets" / "cutscenes" / "skip_button.json"

BUTTON = 3468
CAPTION = 3469
# The root timeline labels of the cutscenes, CS_INTRO and CS_CUT1 to CS_CUT5.
CUTSCENE_PREFIX = "CS_"


def placements(index: SwfIndex) -> dict[str, dict[int, tuple[int, timeline.Layer]]]:
    """-> for each cutscene label, the depth and layer the label's root frame
    shows the button and the caption with, by character id. Raises when a
    frame shows either of them other than once, and when it shows the caption
    with a colour transform or a filter, which a Label does not draw."""
    root = timeline.frames(index, 0)
    shown = {}
    for name, frame in timeline.labels(index, 0).items():
        if not name.startswith(CUTSCENE_PREFIX):
            continue
        row = {}
        for character in (BUTTON, CAPTION):
            at = [
                (depth, layer)
                for depth, layer in root[frame - 1].items()
                if layer.character_id == character
            ]
            if len(at) != 1:
                raise RuntimeError(
                    f"{name}, root frame {frame}, shows {character} {len(at)} times"
                )
            row[character] = at[0]
        _, caption = row[CAPTION]
        if caption.color_transform or caption.filters:
            raise RuntimeError(
                f"{name} shows the caption {CAPTION} with a colour transform or"
                f" a filter, which the port's Label does not draw: {caption}"
            )
        shown[name] = row
    if not shown:
        raise RuntimeError(f"the root timeline has no {CUTSCENE_PREFIX} label")
    return shown


def hit_rect(index: SwfIndex, matrix: tuple) -> tuple[float, float, float, float]:
    """-> the (x, y, w, h) in design px the button's hit area covers when a
    frame places the button with `matrix`. Raises unless the button draws one
    shape, in the hit-test state only, and the frame scales it without a skew,
    because the port keeps only a rectangle."""
    records = button_records(index, BUTTON)
    drawn = [(sorted(r.states), r.character_id) for r in records]
    if len(records) != 1 or records[0].states != {"hit"}:
        raise RuntimeError(
            f"button {BUTTON} draws {drawn}, and the port only keeps a hit area"
        )
    (record,) = records
    if record.matrix != timeline.IDENTITY:
        raise RuntimeError(f"button {BUTTON} moves its hit shape: {record.matrix}")
    scale_x, skew_x, skew_y, scale_y, tx, ty = matrix
    if skew_x or skew_y:
        raise RuntimeError(f"button {BUTTON} is placed with a skew: {matrix}")
    xmin, ymin, xmax, ymax = shape_bounds(index, record.character_id)
    left, right = sorted((xmin * scale_x + tx, xmax * scale_x + tx))
    top, bottom = sorted((ymin * scale_y + ty, ymax * scale_y + ty))
    twips = render.TWIPS
    return (left / twips, top / twips, (right - left) / twips, (bottom - top) / twips)


def skip_layout(index: SwfIndex) -> dict:
    """-> the JSON layout of the button's hit area and its text. Raises unless
    every cutscene frame places both the same way."""
    shown = placements(index)
    (first, row), *rest = shown.items()
    for name, other in rest:
        if other != row:
            raise RuntimeError(
                f"{name} places the SKIP button differently from {first}:"
                f" {other} against {row}"
            )
    frame = timeline.labels(index, 0)[first]
    field = label_layout.plain_device_line(index, CAPTION)
    string = (field.initial_text or "").removesuffix("\r")
    if not string:
        raise RuntimeError(f"edit text {CAPTION} has no text")
    origin = render.placement_origin(index, 0, frame, CAPTION)
    return {
        "button": rect_entry(hit_rect(index, row[BUTTON][1].matrix)),
        "text": {**label_layout.text_layout(field, origin), "string": string},
    }


def main():
    index = read_swf(WEB_SWF)
    layout = skip_layout(index)
    LAYOUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
    print(
        f"{len(placements(index))} cutscene frames place the button at"
        f" {layout['button']} and the text at {layout['text']['rect']}",
        file=sys.stderr,
    )
    print(f"wrote {LAYOUT_JSON}", file=sys.stderr)


if __name__ == "__main__":
    main()
