# The rect record (spec/107-ui-foundation.md, Part 4): where each piece of a
# Screen or Window sits on the Stage in the SWF, written to
#
#   test/fixtures/screen_rects.json
#
# test/unit/test_screen_rects.gd instantiates every scene in the record and
# checks that each piece lands where the record says, after the containers lay
# it out. So a scene can type its numbers into its .tscn, and this record keeps
# them honest.
#
# SCENES is the per-scene config. Each Window or Screen build issue adds its
# scene, the timeline and frame that place its pieces, and one entry for each
# node that draws a piece. port_only names the nodes the port draws and the
# SWF does not, so the test skips them.
#
# A piece is one of two kinds:
#   "panel" - a flat Panel (Part 3): a sprite whose one shape has a solid fill
#             and a line, under an inner DropShadow. Its rect is the fill rect
#             grown by half the border. The fill rect is ShapeBounds through
#             the placement matrix, shrunk on each side by half the line width
#             times that axis's scale.
#   "text"  - an edit text, recorded as the rect Flash lays its text out in
#             (label_layout.text_rect), with its font height and colour.
#
# A timeline other than the root is measured from where the root's Navigation
# frame places it, which for KRINMENU is (400.50, 222.40).
#
# Run: uv run extract_screen_rects
from __future__ import annotations

import json
import math
from dataclasses import dataclass, field

from urchin_dev import REPO_ROOT, WEB_SWF
from urchin_dev.swf import label_layout, render, timeline
from urchin_dev.swf.swf_index import (
    DropShadow,
    EditText,
    SwfIndex,
    character_kind,
    drop_shadow,
    edit_text,
    first_fill_color,
    first_line_style,
    read_swf,
    shape_bounds,
)

RECORD = REPO_ROOT / "test" / "fixtures" / "screen_rects.json"
KRINMENU = 3142
HUB_FRAME = "Navigation"


@dataclass(frozen=True)
class Piece:
    kind: str
    depth: int


@dataclass(frozen=True)
class Scene:
    timeline: int
    frame: str
    pieces: dict[str, Piece]
    port_only: tuple[str, ...] = field(default=())


SCENES: dict[str, Scene] = {
    # The victory frame's left Panel and the field at its top. It is a test
    # scene, so the generic test and its must-fail control have a scene to run.
    "res://test/fixtures/screen_rects/victory_left_panel.tscn": Scene(
        timeline=KRINMENU,
        frame="win",
        pieces={
            "LeftPanel": Piece("panel", 11),
            "LeftPanel/Heading": Piece("text", 1240),
        },
    )
}


def color_hex(color: tuple[int, int, int, int]) -> str:
    """-> "rrggbbaa", as Godot's Color.to_html() writes it."""
    return "{:02x}{:02x}{:02x}{:02x}".format(*color)


def _scale(matrix) -> tuple[float, float]:
    scale_x, skew0, skew1, scale_y, _tx, _ty = matrix
    if skew0 or skew1:
        raise ValueError(f"matrix {matrix} rotates or skews, and a rect can't hold it")
    return scale_x, scale_y


def stage_rect(bounds, matrix, origin) -> tuple[float, float, float, float]:
    """-> (x, y, w, h) in design px of `bounds` (twips) placed with `matrix`
    on a timeline whose origin is `origin`."""
    scale_x, scale_y = _scale(matrix)
    xs = sorted(v * scale_x for v in (bounds[0], bounds[2]))
    ys = sorted(v * scale_y for v in (bounds[1], bounds[3]))
    x = origin[0] + (xs[0] + matrix[4]) / render.TWIPS
    y = origin[1] + (ys[0] + matrix[5]) / render.TWIPS
    return x, y, (xs[1] - xs[0]) / render.TWIPS, (ys[1] - ys[0]) / render.TWIPS


def fill_rect(bounds, line_width, matrix, origin):
    half = line_width / 2
    inner = (bounds[0] + half, bounds[1] + half, bounds[2] - half, bounds[3] - half)
    return stage_rect(inner, matrix, origin)


def border_width(line_width: int, scale: tuple[float, float]) -> int:
    """-> PanelRecipe.border_width() for a line of `line_width` twips."""
    mean = math.sqrt((scale[0] ** 2 + scale[1] ** 2) / 2)
    return round(line_width / render.TWIPS * mean)


def _check_shadow(shadow: DropShadow) -> None:
    """Raises unless the shared ShaderMaterial can draw `shadow`. It takes only
    a blur, a distance and an angle, and multiplies towards black."""
    if not shadow.inner:
        raise ValueError(f"{shadow} is not an inner shadow")
    if shadow.knockout:
        raise ValueError(f"{shadow} is a knockout")
    if shadow.blur_x != shadow.blur_y:
        raise ValueError(f"{shadow} has two blur values")
    if shadow.color != (0, 0, 0, 255):
        raise ValueError(f"{shadow} has a colour other than opaque black")
    if shadow.strength != 1.0:
        raise ValueError(f"{shadow} has a strength other than 1")


def panel_record(*, bounds, line_width, matrix, origin, fill, line, shadow) -> dict:
    _check_shadow(shadow)
    border = border_width(line_width, _scale(matrix))
    x, y, w, h = fill_rect(bounds, line_width, matrix, origin)
    grow = border / 2
    return {
        "kind": "panel",
        "rect": [round(v, 4) for v in (x - grow, y - grow, w + border, h + border)],
        "fill": color_hex(fill),
        "line": color_hex(line),
        "border": border,
        "shadow": {
            "angle": shadow.angle,
            "blur": shadow.blur_x,
            "distance": shadow.distance,
        },
    }


def text_record(text: EditText, matrix, origin) -> dict:
    if _scale(matrix) != (1.0, 1.0):
        raise ValueError(f"matrix {matrix} scales the field, and a Label can't")
    placed = (
        origin[0] + matrix[4] / render.TWIPS,
        origin[1] + matrix[5] / render.TWIPS,
    )
    rect = label_layout.text_rect(text, placed)
    return {
        "kind": "text",
        "rect": [rect["x"], rect["y"], rect["w"], rect["h"]],
        "font_size": text.font_height / render.TWIPS,
        "color": color_hex(text.color),
    }


def _panel(index: SwfIndex, layer: timeline.Layer, origin) -> dict:
    where = f"panel sprite {layer.character_id}"
    shapes = list(timeline.frames(index, layer.character_id)[0].values())
    if len(shapes) != 1 or character_kind(index, shapes[0].character_id) != "shape":
        raise ValueError(f"{where} does not hold exactly one shape")
    inner = shapes[0]
    if inner.matrix != timeline.IDENTITY:
        raise ValueError(f"{where} places its shape with {inner.matrix}")
    shadows = [
        drop_shadow(record)
        for name, record in zip(layer.filters, layer.filter_records, strict=True)
        if name == "DropShadow"
    ]
    if len(shadows) != 1 or len(layer.filters) != 1:
        raise ValueError(f"{where} has filters {layer.filters}, not one DropShadow")
    line_style = first_line_style(index, inner.character_id)
    fill = first_fill_color(index, inner.character_id)
    if line_style is None or fill is None:
        raise ValueError(f"{where}'s shape has no solid fill or no line")
    return panel_record(
        bounds=shape_bounds(index, inner.character_id),
        line_width=line_style[0],
        matrix=layer.matrix,
        origin=origin,
        fill=fill,
        line=line_style[1],
        shadow=shadows[0],
    )


def origin_of(index: SwfIndex, owner: int) -> tuple[float, float]:
    if owner == 0:
        return 0.0, 0.0
    hub = timeline.frame_of(index, 0, HUB_FRAME)
    return render.placement_origin(index, 0, hub, owner)


def scene_record(index: SwfIndex, scene: Scene) -> dict:
    origin = origin_of(index, scene.timeline)
    frame = timeline.frame_of(index, scene.timeline, scene.frame)
    layers = timeline.frames(index, scene.timeline)[frame - 1]
    pieces = {}
    for path, piece in scene.pieces.items():
        layer = layers.get(piece.depth)
        if layer is None:
            raise ValueError(f"{path}: frame {scene.frame} has no depth {piece.depth}")
        if piece.kind == "panel":
            pieces[path] = _panel(index, layer, origin)
        elif piece.kind == "text":
            text = edit_text(index, layer.character_id)
            pieces[path] = text_record(text, layer.matrix, origin)
        else:
            raise ValueError(f"{path}: unknown piece kind {piece.kind!r}")
    return {
        "timeline": scene.timeline,
        "frame": scene.frame,
        "origin": [round(v, 4) for v in origin],
        "port_only": list(scene.port_only),
        "pieces": pieces,
    }


def main():
    index = read_swf(WEB_SWF)
    record = {
        "scenes": {path: scene_record(index, scene) for path, scene in SCENES.items()}
    }
    RECORD.parent.mkdir(parents=True, exist_ok=True)
    RECORD.write_text(json.dumps(record, indent=1, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
