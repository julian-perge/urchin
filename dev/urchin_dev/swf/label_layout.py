# label_layout.py
# What a Godot Label needs to draw an edit text's line where Flash draws it:
# the rect Flash lays the text out in, and the field's alignment, colour and
# size. The extractors write it to JSON, and scripts/ui/label_layout.gd maps
# the alignment names back to Godot's.
#
# The port draws a bold Device font in the Stand-in font the project theme
# gives every Label, so plain_device_line() refuses any other field.
from __future__ import annotations

from urchin_dev.swf import render
from urchin_dev.swf.swf_index import EditText, SwfIndex, edit_text, font

# Flash lays a text field's text out 2 px inside its bounds on every side.
# unit_overlay.gd measures the buff counter, edit text 66, the same way.
GUTTER = 2.0
ALIGNMENTS = {0: "left", 1: "right", 2: "center", 3: "justify"}


def text_rect(field: EditText, placed: tuple[float, float]) -> dict[str, float]:
    """-> the rect Flash lays `field`'s text out in, in design px from the
    origin of the clip that places the field at `placed`."""
    xmin, ymin, xmax, ymax = (v / render.TWIPS for v in field.bounds)
    return {
        "x": round(placed[0] + xmin + GUTTER, 2),
        "y": round(placed[1] + ymin + GUTTER, 2),
        "w": round(xmax - xmin - 2 * GUTTER, 2),
        "h": round(ymax - ymin - 2 * GUTTER, 2),
    }


def text_layout(field: EditText, placed: tuple[float, float]) -> dict:
    """-> what a Label needs to draw `field`'s line where Flash would: the
    rect text_rect() gives, and the field's alignment, colour and size."""
    return {
        "align": ALIGNMENTS[field.align],
        "color": "#{:02x}{:02x}{:02x}".format(*field.color[:3]),
        "rect": text_rect(field, placed),
        "size": field.font_height / render.TWIPS,
    }


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
