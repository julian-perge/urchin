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
# A piece is one of six kinds:
#   "panel" - a flat Panel (Part 3): a sprite whose one shape has a solid fill
#             and a line, under an inner DropShadow. Its rect is the fill rect
#             grown by half the border. The fill rect is ShapeBounds through
#             the placement matrix, shrunk on each side by half the line width
#             times that axis's scale.
#   "text"  - an edit text, recorded as the rect Flash lays its text out in
#             (label_layout.text_rect), with its font height and colour.
#   "art"   - a piece drawn from a zoom 4 PNG of extract_window_chrome, which
#             a TextureRect shows at the rect that render measured, with the
#             PNG's path. Its depth is the one window_chrome renders, so the
#             two extractors cannot name different placements.
#   "hit"   - a button that draws nothing, only a hit square, recorded as the
#             hit shape's bounds through the placement matrix.
#   "button" - a button that draws art, which the port draws as a native
#             Button. It is recorded as the bounds of the shapes its up state
#             draws, through the placement matrix.
#   "box"   - a shape of one solid fill and no line, which the port draws as a
#             ColorRect, recorded as its ShapeBounds through the placement
#             matrix with its fill colour.
#
# An "art" piece whose render is measured from a sprite of its own is placed
# by where that sprite sits: the sprite at `depth`, or the sprite at
# `inner_depth` inside it.
#
# A piece that a sprite places on its own first frame names the sprite's depth
# and its own inner_depth, and it is measured from where the sprite sits.
# When the sprite's placement carries a DropShadow, Flash shadows every text
# field inside it, so a text piece there records the shadow too.
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
from urchin_dev.swf.extract import window_chrome
from urchin_dev.swf.swf_index import (
    ButtonRecord,
    DropShadow,
    EditText,
    StyleSet,
    SwfIndex,
    button_records,
    character_kind,
    drop_shadow,
    edit_text,
    first_fill_color,
    first_line_style,
    read_swf,
    shape_bounds,
    shape_styles,
)

RECORD = REPO_ROOT / "test" / "fixtures" / "screen_rects.json"
CHROME_TEXTURES = "res://assets/ui/window"
KRINMENU = 3142
HUB_FRAME = "Navigation"


@dataclass(frozen=True)
class Piece:
    kind: str
    # The depth that places the piece, or None when `instance` finds it.
    depth: int | None
    art: str | None = None
    # The instance name of the placement, for a piece that the SWF names
    # instead of a depth the record has to type, such as itemSlot0.
    instance: str | None = None
    # The depth of the piece inside the sprite at `depth`, on the sprite's
    # first frame, for a piece that the scene's timeline does not place itself.
    inner_depth: int | None = None

    def __post_init__(self) -> None:
        if (self.depth is None) == (self.instance is None):
            raise ValueError(
                f"A piece needs a depth or an instance name, not both or neither:"
                f" depth {self.depth}, instance {self.instance}"
            )
        if self.kind == "art" and self.art is None:
            raise ValueError(
                f"An art piece needs the name of its art: depth {self.depth},"
                f" instance {self.instance}"
            )


@dataclass(frozen=True)
class Scene:
    timeline: int
    frame: str
    pieces: dict[str, Piece]
    port_only: tuple[str, ...] = field(default=())


# The victory frame's experience rows, top to bottom, by the depth that
# places each, and the pieces inside sprite 3002 by their own depth.
VICTORY_ROWS = {"PlayerSlot": 1197, "CompanionSlot0": 1111, "CompanionSlot1": 1154}
VICTORY_ROW_PIECES: dict[str, tuple[str, int, str | None]] = {
    "Frame": ("art", 2, "victory_row"),
    "NameLabel": ("text", 37, None),
    "LevelLabel": ("text", 38, None),
    "Bar": ("art", 39, "xp_bar"),
    "Gloss": ("art", 41, "xp_gloss_victory"),
    "PercentLabel": ("text", 42, None),
}

# The frame names the grid's slots itemSlot0 to itemSlot35, row by row.
INVENTORY_SLOTS = 36
INVENTORY_COLUMNS = 6

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
    ),
    # One ShellPanel of each fill, where the inventory frame places them, so
    # the test checks each fill against its sprite: 2990 is tall, 2992 is bar
    # and 2988 is centre.
    "res://test/fixtures/screen_rects/shell_panel_fills.tscn": Scene(
        timeline=KRINMENU,
        frame="inventory",
        pieces={
            "Tall": Piece("panel", 11),
            "Bar": Piece("panel", 5),
            "Centre": Piece("panel", 21),
        },
    ),
    # The 1 px line 2995 at depth 1 is not drawn (spec/107-window-shell.md).
    "res://scenes/ui/window/window_shell.tscn": Scene(
        timeline=KRINMENU,
        frame="inventory",
        pieces={
            "Backdrop": Piece("art", window_chrome.BACKDROP_DEPTH, art="backdrop"),
            "CloseArt": Piece("art", window_chrome.CLOSE_X_DEPTH, art="close_x"),
            "CloseButton": Piece("hit", 1434),
        },
    ),
    # The victory frame's three experience rows, each a placement of sprite
    # 3002: the player's at depth 1197, then friendlySlotsFFTT[0] and [1] at
    # 1111 and 1154. The rest of the Victory screen is port only until the
    # Victory Window replaces it (spec/107-victory.md). The face has no record,
    # because extract_faces does not write where its crop sits in sprite 2978.
    # The row's shape 3001 has no fill across the row: it strokes a 1 px line
    # around it and fills only the box under the bar. The port draws it as the
    # victory_row art, which holds the shape under the row's DropShadow.
    "res://scenes/battle/victory_screen.tscn": Scene(
        timeline=KRINMENU,
        frame="win",
        pieces={
            f"ExpRows/{slot}/Row/{node}": Piece(kind, depth, art=art, inner_depth=inner)
            for slot, depth in VICTORY_ROWS.items()
            for node, (kind, inner, art) in VICTORY_ROW_PIECES.items()
        },
        port_only=(
            "Backdrop",
            "LeftPanel",
            "ExperienceLabel",
            "MiddlePanel",
            "DropsLabel",
            "ClickHintLabel",
            "MoneyLabel",
            "MoneyValue",
            "ExpLabel",
            "ExpValue",
            "ProceedHintLabel",
            "InventoryPanel",
            *(f"ExpRows/{slot}/Row/Face" for slot in VICTORY_ROWS),
        ),
    ),
    # The right column of 36 item slots and the money bar
    # (spec/107-window-shell.md, RightColumn). The shop frame is the one frame
    # that places all of it, the sell slot included, and the inventory frame
    # places the other pieces at the same depths. The euro sign and the amount
    # carry a Glow and a DropShadow filter. A Label can't draw either, so the
    # record leaves the two filters out and the port draws neither.
    "res://scenes/ui/window/right_column.tscn": Scene(
        timeline=KRINMENU,
        frame="shop",
        pieces={
            "TallPanel": Piece("panel", 7),
            "Title": Piece("text", 1430),
            **{
                f"Grid/Row{i // INVENTORY_COLUMNS}/Slot{i % INVENTORY_COLUMNS}": Piece(
                    "art", None, art="slot_inventory", instance=f"itemSlot{i}"
                )
                for i in range(INVENTORY_SLOTS)
            },
            "BarPanel": Piece("panel", 5),
            "EuroSign": Piece("text", 1424),
            "Amount": Piece("text", 1423),
            "SellSlot/Art": Piece("art", window_chrome.SELL_SLOT_DEPTH, art="sell_slot"),
            "DeleteSlot/Art": Piece(
                "art", window_chrome.DELETE_SLOT_DEPTH, art="delete_slot"
            ),
        },
        port_only=tuple(
            f"Grid/Row{i // INVENTORY_COLUMNS}/Slot{i % INVENTORY_COLUMNS}/{node}"
            for i in range(INVENTORY_SLOTS)
            for node in ("ItemIcon", "Highlight")
        ),
    ),
    # The skills frame (spec/107-abilities.md). The tree nodes and the pool
    # are port only here until #237 and #238 record them. StatusLabel has no
    # piece in the SWF.
    "res://scenes/ui/menu/abilities_window.tscn": Scene(
        timeline=KRINMENU,
        frame="skills",
        pieces={
            "WindowShell/Backdrop": Piece(
                "art", window_chrome.BACKDROP_DEPTH, art="backdrop"
            ),
            "WindowShell/CloseArt": Piece(
                "art", window_chrome.CLOSE_X_DEPTH, art="close_x"
            ),
            "WindowShell/CloseButton": Piece("hit", 1434),
            "TreePanel": Piece("panel", 7),
            "PointsPanel": Piece("panel", 23),
            "AttributesPanel": Piece("panel", 21),
            "ActionPanel": Piece("panel", 5),
            "TreeTitle": Piece("text", 673),
            "ActionBarTitle": Piece("text", 672),
            "PoolTitle": Piece("text", 674),
            "AttributesTitle": Piece("text", 671),
            "NameLabel": Piece("text", 653),
            "LevelLabel": Piece("text", 654),
            "AbilityPointsLabel": Piece("text", 651),
            "AbilityPointsValue": Piece("text", 655),
            "AttributePointsLabel": Piece("text", 652),
            "AttributePointsValue": Piece("text", 656),
            "HintLabel": Piece("text", 675, inner_depth=1),
            "PlusColumn/VitalitySlot/VitalityPlus": Piece("button", 668),
            "PlusColumn/StrengthSlot/StrengthPlus": Piece("button", 659),
            "PlusColumn/InstinctSlot/InstinctPlus": Piece("button", 662),
            "PlusColumn/SpeedSlot/SpeedPlus": Piece("button", 665),
            "AttributeRows/VitalityRow/VitalityLabel": Piece("text", 643),
            "AttributeRows/StrengthRow/StrengthLabel": Piece("text", 644),
            "AttributeRows/InstinctRow/InstinctLabel": Piece("text", 645),
            "AttributeRows/SpeedRow/SpeedLabel": Piece("text", 646),
            "AttributeRows/VitalityRow/VitalityValue": Piece("text", 647),
            "AttributeRows/StrengthRow/StrengthValue": Piece("text", 648),
            "AttributeRows/InstinctRow/InstinctValue": Piece("text", 649),
            "AttributeRows/SpeedRow/SpeedValue": Piece("text", 650),
        },
        port_only=("StatusLabel", "TreeNodes", "PoolBackdrop", "PoolRows"),
    ),
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
    entry = {
        "kind": "text",
        "rect": [rect["x"], rect["y"], rect["w"], rect["h"]],
        "font_size": text.font_height / render.TWIPS,
        "color": color_hex(text.color),
    }
    # Flash puts the lines of a field one font height plus the field's leading
    # apart. A field that wraps, or a multiline field that is not one line of
    # static text, can show more than one line, so its pitch is recorded. A
    # field of one line has no pitch to check.
    if text.word_wrap or (
        text.multiline and not label_layout.one_static_line(text)
    ):
        entry["line_pitch"] = (text.font_height + (text.leading or 0)) / render.TWIPS
    return entry


def text_shadow(shadow: DropShadow) -> dict:
    """-> the shadow a Label draws for a DropShadow on the sprite that holds
    its field: the offset in px, and the colour with the strength in its
    alpha. A Label can't blur its shadow, so the blur is recorded but the
    rect test does not check it."""
    if shadow.inner:
        raise ValueError(f"{shadow} is an inner shadow, and a Label's is outer")
    if shadow.knockout:
        raise ValueError(f"{shadow} is a knockout")
    if shadow.blur_x != shadow.blur_y:
        raise ValueError(f"{shadow} has two blur values")
    angle = math.radians(shadow.angle)
    r, g, b, a = shadow.color
    return {
        "offset": [
            round(shadow.distance * math.cos(angle), 4),
            round(shadow.distance * math.sin(angle), 4),
        ],
        "color": color_hex((r, g, b, min(255, round(a * shadow.strength)))),
        "blur": shadow.blur_x,
    }


def _shadow_of(layer: timeline.Layer) -> DropShadow | None:
    shadows = [
        drop_shadow(record)
        for name, record in zip(layer.filters, layer.filter_records, strict=True)
        if name == "DropShadow"
    ]
    if len(shadows) > 1:
        raise ValueError(f"character {layer.character_id} has {len(shadows)} DropShadows")
    return shadows[0] if shadows else None


def art_record(name: str, chrome: dict, sprite_origins: dict | None = None) -> dict:
    """-> the record of the window_chrome.json entry `chrome` of piece `name`.
    A rect measured from a sprite is moved to the stage by that sprite's
    origin in `sprite_origins`, keyed as "sprite <id>"."""
    relative_to = chrome["relative_to"]
    shift = (0.0, 0.0)
    if relative_to != "stage":
        if relative_to not in (sprite_origins or {}):
            raise ValueError(
                f"{name}'s rect is measured from {relative_to}, which does not"
                " place this piece"
            )
        shift = sprite_origins[relative_to]
    x, y, w, h = chrome["rect"]
    return {
        "kind": "art",
        "rect": [round(x + shift[0], 4), round(y + shift[1], 4), w, h],
        "texture": f"{CHROME_TEXTURES}/{name}.png",
    }


def box_record(bounds, matrix, origin, fill: tuple[int, int, int, int]) -> dict:
    """-> the record of a shape of one solid fill and no line, which the port
    draws as a ColorRect."""
    return {
        "kind": "box",
        "rect": [round(v, 4) for v in stage_rect(bounds, matrix, origin)],
        "fill": color_hex(fill),
    }


def hit_record(records: list[ButtonRecord], bounds, matrix, origin) -> dict:
    """-> the record of a button that `records` describe, whose one hit shape
    has `bounds`, placed with `matrix`."""
    drawn = [(sorted(r.states), r.character_id) for r in records]
    if len(records) != 1 or records[0].states != {"hit"}:
        raise ValueError(
            f"the button draws {drawn}, and the port keeps a hit area only"
        )
    if records[0].matrix != timeline.IDENTITY:
        raise ValueError(f"the button moves its hit shape: {records[0].matrix}")
    return {
        "kind": "hit",
        "rect": [round(v, 4) for v in stage_rect(bounds, matrix, origin)],
    }


def button_record(records: list[ButtonRecord], bounds: dict, matrix, origin) -> dict:
    """-> the record of a button that draws art, as the rect of the shapes its
    up state draws, placed with `matrix`. `bounds` maps each shape to its
    ShapeBounds."""
    up = [r for r in records if "up" in r.states]
    if not up:
        raise ValueError("the button draws nothing in its up state")
    for r in up:
        if r.matrix != timeline.IDENTITY:
            raise ValueError(f"the button moves shape {r.character_id}: {r.matrix}")
    shapes = [bounds[r.character_id] for r in up]
    union = (
        min(b[0] for b in shapes),
        min(b[1] for b in shapes),
        max(b[2] for b in shapes),
        max(b[3] for b in shapes),
    )
    return {
        "kind": "button",
        "rect": [round(v, 4) for v in stage_rect(union, matrix, origin)],
    }


def _button(index: SwfIndex, layer: timeline.Layer, origin) -> dict:
    records = button_records(index, layer.character_id)
    bounds = {
        r.character_id: shape_bounds(index, r.character_id)
        for r in records
        if character_kind(index, r.character_id) == "shape"
    }
    return button_record(records, bounds, layer.matrix, origin)


def inner_origin(matrix, origin) -> tuple[float, float]:
    """-> the origin of a sprite's own timeline, when the sprite is placed with
    `matrix` on a timeline whose origin is `origin`."""
    if _scale(matrix) != (1.0, 1.0):
        raise ValueError(f"matrix {matrix} scales the sprite, and an origin can't")
    return (
        origin[0] + matrix[4] / render.TWIPS,
        origin[1] + matrix[5] / render.TWIPS,
    )


def _hit(index: SwfIndex, layer: timeline.Layer, origin) -> dict:
    records = button_records(index, layer.character_id)
    shape = records[0].character_id if records else None
    if shape is None or character_kind(index, shape) != "shape":
        raise ValueError(f"button {layer.character_id} has no hit shape")
    return hit_record(records, shape_bounds(index, shape), layer.matrix, origin)


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


def one_solid_fill(sets: list[StyleSet], shape: int) -> tuple[int, int, int, int]:
    """-> the colour of a shape that fills with one solid fill and strokes no
    line. Its first style set alone can't say so, because a shape can declare
    new styles partway through and draw more with them."""
    only = sets[0] if len(sets) == 1 else None
    if (
        only is None
        or only.line_bounds
        or only.used_fills != {1}
        or only.fills[0] is None
    ):
        raise ValueError(f"shape {shape} is not one solid fill with no line")
    return only.fills[0]


def _box(index: SwfIndex, layer: timeline.Layer, origin) -> dict:
    shape = layer.character_id
    if character_kind(index, shape) != "shape":
        raise ValueError(f"box {shape} is not a shape")
    fill = one_solid_fill(shape_styles(index, shape), shape)
    return box_record(shape_bounds(index, shape), layer.matrix, origin, fill)


def origin_of(index: SwfIndex, owner: int) -> tuple[float, float]:
    if owner == 0:
        return 0.0, 0.0
    hub = timeline.frame_of(index, 0, HUB_FRAME)
    return render.placement_origin(index, 0, hub, owner)


def scene_record(index: SwfIndex, scene: Scene) -> dict:
    origin = origin_of(index, scene.timeline)
    frame = timeline.frame_of(index, scene.timeline, scene.frame)
    layers = timeline.frames(index, scene.timeline)[frame - 1]
    chrome = json.loads(window_chrome.RECORD.read_text())
    pieces = {}
    for path, piece in scene.pieces.items():
        if piece.instance is None:
            layer = layers.get(piece.depth)
            if layer is None:
                raise ValueError(f"{path}: frame {scene.frame} has no depth {piece.depth}")
        else:
            named = [layer for layer in layers.values() if layer.name == piece.instance]
            if len(named) != 1:
                raise ValueError(
                    f"{path}: frame {scene.frame} places {len(named)} instances"
                    f" named {piece.instance}"
                )
            layer = named[0]
        piece_origin = origin
        sprite_origins = {}
        holder_shadow = None
        if piece.inner_depth is None:
            sprite = f"sprite {layer.character_id}"
            if piece.kind == "art" and chrome[piece.art]["relative_to"] == sprite:
                sprite_origins[sprite] = inner_origin(layer.matrix, origin)
        else:
            holder_shadow = _shadow_of(layer)
            piece_origin = inner_origin(layer.matrix, origin)
            sprite_origins[f"sprite {layer.character_id}"] = piece_origin
            first = timeline.frames(index, layer.character_id)[0]
            if piece.inner_depth not in first:
                raise ValueError(
                    f"{path}: sprite {layer.character_id} has no depth"
                    f" {piece.inner_depth} on its first frame"
                )
            layer = first[piece.inner_depth]
            if character_kind(index, layer.character_id) == "sprite":
                sprite_origins[f"sprite {layer.character_id}"] = inner_origin(
                    layer.matrix, piece_origin
                )
        if piece.kind == "panel":
            pieces[path] = _panel(index, layer, piece_origin)
        elif piece.kind == "text":
            text = edit_text(index, layer.character_id)
            pieces[path] = text_record(text, layer.matrix, piece_origin)
            if holder_shadow is not None:
                pieces[path]["shadow"] = text_shadow(holder_shadow)
        elif piece.kind == "button":
            pieces[path] = _button(index, layer, piece_origin)
        elif piece.kind == "art":
            pieces[path] = art_record(piece.art, chrome[piece.art], sprite_origins)
        elif piece.kind == "box":
            pieces[path] = _box(index, layer, piece_origin)
        elif piece.kind == "hit":
            pieces[path] = _hit(index, layer, piece_origin)
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
