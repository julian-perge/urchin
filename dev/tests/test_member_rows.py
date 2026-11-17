# The member row extractor's arithmetic on a text and a panel built by hand, so no
# test needs the gitignored SWF, and the committed record's invariants.
from __future__ import annotations

import json
from dataclasses import replace

import pytest
from urchin_dev.swf import timeline
from urchin_dev.swf.extract import member_rows
from urchin_dev.swf.swf_index import EditText

# DefineEditText 3310 and the panel shape 3309, as the SWF holds them.
SAY = EditText(
    bounds=(-40, -40, 5430, 400),
    font_id=3307,
    font_height=180,
    color=(153, 153, 153, 255),
    align=2,
    left_margin=0,
    right_margin=0,
    indent=0,
    leading=40,
    multiline=False,
    word_wrap=False,
    html=False,
    variable_name="say",
    initial_text="< Team Member Inactive >",
)
PANEL = (-2850, -256, 2850, 370)
FIELD = timeline.Layer(character_id=3310, matrix=(1.0, 0.0, 0.0, 1.0, -2690, -113))


def test_the_text_rect_is_measured_from_the_panels_top_left():
    entry = member_rows.inactive_from(FIELD, SAY, PANEL, 9)
    assert entry["rect"] == pytest.approx([8.0, 7.15, 269.5, 18.0])
    assert entry["align"] == "center"
    assert entry["color"] == "#999999"
    assert entry["font_size"] == 9.0
    assert entry["frame"] == 9


def test_a_scaled_text_is_refused():
    scaled = replace(FIELD, matrix=(2.0, 0.0, 0.0, 1.0, -2690, -113))
    with pytest.raises(ValueError, match="not a translate"):
        member_rows.inactive_from(scaled, SAY, PANEL, 9)


def test_the_committed_record_holds_the_text_of_menu_52():
    entry = json.loads(member_rows.RECORD.read_text())["inactive"]
    assert entry["initial_text"] == "< Team Member Inactive >"
    assert entry["frame"] == 9
