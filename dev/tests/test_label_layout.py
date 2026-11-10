# label_layout's reading of where a Label draws an edit text's line, on fields
# built by hand, so no test needs the gitignored SWF.
from __future__ import annotations

from urchin_dev.swf import label_layout
from urchin_dev.swf.swf_index import EditText


def test_the_text_rect_is_the_fields_bounds_inside_flashs_two_pixel_gutter():
    # Edit text 2849's bounds, placed inside the inner clip at (-372.5, -7.8).
    field = EditText(
        bounds=(-40, -40, 14939, 352),
        font_id=65,
        font_height=240,
        color=(0, 0, 0, 255),
        align=2,
        left_margin=0,
        right_margin=0,
        indent=0,
        leading=40,
        multiline=False,
        word_wrap=False,
        html=False,
        variable_name="combatText",
        initial_text="combat text goes here",
    )
    assert label_layout.text_rect(field, (-372.5, -7.8)) == {
        "x": -372.5,
        "y": -7.8,
        "w": 744.95,
        "h": 15.6,
    }
