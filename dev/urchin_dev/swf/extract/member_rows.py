# The inactive frame of the Battle screen's member row (spec/67-battle-hud.md,
# Part 4). The member bar 3311 has two frames: `active`, with the name and the
# five stance buttons, which battle_screen.py extracts, and `inactive`, which
# shows the panel and one edit text, `say`, with the text of MENU[52]. This
# writes where that edit text sits and how it is drawn to
#
#   assets/ui/battle/member_rows.json
#
# The field's rect is in design px from the top left of the row's panel, the
# shape 3309 that both frames draw. That is the origin StanceRow places its
# parts from. Nothing here renders, so it needs no ffdec.
#
# Run: uv run extract_member_rows
from __future__ import annotations

import json
import re
import sys

from urchin_dev import ACTION_SCRIPT, REPO_ROOT, WEB_SWF
from urchin_dev.swf import label_layout, render, timeline
from urchin_dev.swf.extract import battle_screen
from urchin_dev.swf.swf_index import (
    EditText,
    SwfIndex,
    edit_text,
    read_swf,
    shape_bounds,
)

RECORD = REPO_ROOT / "assets" / "ui" / "battle" / "member_rows.json"
PANEL_SHAPE = battle_screen.MEMBER_BAR_PANEL
LABELS = ("active", "inactive")
INACTIVE_SCRIPT = ACTION_SCRIPT / "DefineSprite_3311" / "frame_9" / "DoAction.as"


def menu_index(script: str) -> int:
    """-> the MENU index that the inactive frame's script sets `say` from."""
    found = re.findall(
        r"\bsay\s*=\s*_root\.KrinLang\[_root\.KLangChoosen\]\.MENU\[(\d+)\];", script
    )
    if len(found) != 1:
        raise ValueError(
            f"the inactive frame sets say from MENU {len(found)} times, want 1"
        )
    return int(found[0])


def inactive_record(index: SwfIndex) -> dict:
    """-> where the inactive frame of the member bar 3311 draws its text, from the
    top left of the panel, and how."""
    labels = timeline.labels(index, battle_screen.MEMBER_BAR)
    if sorted(labels) != sorted(LABELS):
        raise ValueError(f"3311 has the labels {sorted(labels)}, not {sorted(LABELS)}")
    layers = timeline.frames(index, battle_screen.MEMBER_BAR)[labels["inactive"] - 1]
    fields = [layer for layer in layers.values() if layer.character_id != PANEL_SHAPE]
    if len(layers) != 2 or len(fields) != 1:
        raise ValueError(
            f"the inactive frame draws {len(layers)} things, want the panel and one text"
        )
    (field,) = fields
    return inactive_from(
        field,
        edit_text(index, field.character_id),
        shape_bounds(index, PANEL_SHAPE),
        labels["inactive"],
        menu_index(INACTIVE_SCRIPT.read_text("utf-8")),
    )


def inactive_from(
    field: timeline.Layer,
    text: EditText,
    panel: tuple[int, int, int, int],
    frame: int,
    menu: int,
) -> dict:
    """-> the record of the edit text `field` places, with the rect Flash lays it
    out in from the top left of the panel shape whose bounds are `panel`. The
    text's matrix may only translate."""
    if tuple(field.matrix[:4]) != (1.0, 0.0, 0.0, 1.0):
        raise ValueError(f"the text is placed with {field.matrix}, not a translate")
    placed = label_layout.text_rect(
        text, (field.matrix[4] / render.TWIPS, field.matrix[5] / render.TWIPS)
    )
    return {
        "character": field.character_id,
        "rect": [
            round(placed["x"] - panel[0] / render.TWIPS, 4),
            round(placed["y"] - panel[1] / render.TWIPS, 4),
            placed["w"],
            placed["h"],
        ],
        "font_size": text.font_height / render.TWIPS,
        "color": "#{:02x}{:02x}{:02x}".format(*text.color[:3]),
        "align": label_layout.ALIGNMENTS[text.align],
        "frame": frame,
        "initial_text": text.initial_text,
        "menu_index": menu,
    }


def main():
    index = read_swf(WEB_SWF)
    record = {"inactive": inactive_record(index)}
    RECORD.write_text(json.dumps(record, indent=1, sort_keys=True) + "\n")
    print(f"wrote {RECORD}", file=sys.stderr)


if __name__ == "__main__":
    main()
