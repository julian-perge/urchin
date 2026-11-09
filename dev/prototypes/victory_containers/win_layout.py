# PROTOTYPE for julian-perge/urchin#108, throwaway. Lives on the branch
# prototype/victory-containers and is never merged.
#
# Reads KRINMENU's (DefineSprite 3142) win frame out of the web SWF through
# swf_index.py and timeline.py and writes win_layout.json beside this file:
# every piece's stage rect, the panel shapes' fill and stroke, the placement
# filters, the edit text formats, and the column specs that variants B and C
# of scenes/battle/victory_screen_prototype.tscn build their containers from.
# The tag bodies swf_index.py doesn't parse (DefineEditText, shape styles,
# button records, filter records) are read here from the bytes it keeps.
#
# Run from the repo root:
#   uv run python dev/prototypes/victory_containers/win_layout.py
from __future__ import annotations

import json
import struct
from pathlib import Path

from urchin_dev import WEB_SWF
from urchin_dev.swf import timeline
from urchin_dev.swf.swf_index import (
    SHAPE_TAGS,
    TAG_DEFINE_SHAPE,
    TAG_DEFINE_SHAPE4,
    TAG_PLACE_OBJECT3,
    _cstring,
    _read_cxform_with_alpha,
    _read_matrix,
    _read_rect,
    _skip_rect,
    character_kind,
    read_swf,
    shape_bounds,
)

OUT = Path(__file__).with_name("win_layout.json")
KRINMENU = 3142
TWIPS = 20

# Which depth of the win frame is which piece. The rows' roles are from their
# onClipEvent(load) handlers: 1197 sets prx = 0, the player, and 1111 and 1154
# read friendlySlotsFFTT[0] and [1]
# (AS/DefineSprite_3142/frame_9/PlaceObject3_3002_<depth>/).
PANEL_DEPTHS = {"left": 11, "centre": 21, "right": 7, "bar": 5}
BACKDROP_DEPTH = 2
ROW_DEPTHS = {"player": 1197, "friend1": 1111, "friend2": 1154}
PROCEED_DEPTH = 1108
DELETE_DEPTH = 1428
DELETE_ART_DEPTH = 1425


def px(twips: float) -> float:
    return twips / TWIPS


def r2(value: float) -> float:
    return round(value, 3)


def compose(parent, child):
    """-> parent * child, both (scaleX, rotateSkew0, rotateSkew1, scaleY, tx,
    ty) with the translation in twips."""
    a, b, c, d, tx, ty = parent
    a2, b2, c2, d2, tx2, ty2 = child
    return (
        a * a2 + c * b2,
        b * a2 + d * b2,
        a * c2 + c * d2,
        b * c2 + d * d2,
        a * tx2 + c * ty2 + tx,
        b * tx2 + d * ty2 + ty,
    )


def rect_through(matrix, bounds_px, origin):
    """-> [x, y, w, h] in stage px of `bounds_px` (xmin, ymin, xmax, ymax in
    the character's own px) placed by `matrix` under a timeline whose (0, 0)
    sits at `origin` on the stage."""
    a, b, c, d, tx, ty = matrix
    xs, ys = [], []
    for x, y in (
        (bounds_px[0], bounds_px[1]),
        (bounds_px[2], bounds_px[1]),
        (bounds_px[0], bounds_px[3]),
        (bounds_px[2], bounds_px[3]),
    ):
        xs.append(a * x + c * y + px(tx) + origin[0])
        ys.append(b * x + d * y + px(ty) + origin[1])
    return [r2(min(xs)), r2(min(ys)), r2(max(xs) - min(xs)), r2(max(ys) - min(ys))]


def hex_rgba(rgba) -> str:
    return "#" + "".join(f"{v:02x}" for v in rgba)


def edit_text(index, cid) -> dict:
    code, body, _end = index.characters[cid]
    if code != 37:
        raise ValueError(f"{cid} is not a DefineEditText")
    data = index.data
    bounds = [px(v) for v in _read_rect(data, body + 2)]
    p = _skip_rect(data, body + 2)
    f1, f2 = data[p], data[p + 1]
    p += 2
    out = {
        "bounds": bounds,
        "word_wrap": bool(f1 & 0x40),
        "multiline": bool(f1 & 0x20),
        "html": bool(f2 & 0x02),
        "device_font": not f2 & 0x01,
    }
    if f1 & 0x01:
        (out["font_id"],) = struct.unpack_from("<H", data, p)
        p += 2
    if f2 & 0x80:
        out["font_class"], p = _cstring(data, p)
    if f1 & 0x01 or f2 & 0x80:
        (height,) = struct.unpack_from("<H", data, p)
        out["font_height"] = px(height)
        p += 2
    if f1 & 0x04:
        out["color"] = hex_rgba(data[p : p + 4])
        p += 4
    if f1 & 0x02:
        p += 2
    if f2 & 0x20:
        out["align"] = ["left", "right", "center", "justify"][data[p]]
        p += 9
    out["variable"], p = _cstring(data, p)
    out["initial_text"] = ""
    if f1 & 0x80:
        out["initial_text"], p = _cstring(data, p)
    return out


def shape_styles(index, cid):
    """-> (fills, lines) from a shape's first style arrays. A fill is
    {"type": "solid", "color"} or {"type": "linear"/"radial", "stops"}, a line
    is {"width", "color", "scales"}."""
    code, body, _end = index.characters[cid]
    if code not in SHAPE_TAGS:
        raise ValueError(f"{cid} is not a shape")
    data = index.data
    pos = _skip_rect(data, body + 2)
    if code == TAG_DEFINE_SHAPE4:
        pos = _skip_rect(data, pos) + 1
    alpha = code in (32, 83)
    width = 4 if alpha else 3

    def color(at):
        rgba = list(data[at : at + width]) + ([] if alpha else [255])
        return hex_rgba(rgba)

    count = data[pos]
    pos += 1
    if count == 0xFF and code != TAG_DEFINE_SHAPE:
        (count,) = struct.unpack_from("<H", data, pos)
        pos += 2
    fills = []
    for _ in range(count):
        kind = data[pos]
        pos += 1
        if kind == 0x00:
            fills.append({"type": "solid", "color": color(pos)})
            pos += width
        elif kind in (0x10, 0x12):
            _matrix, pos = _read_matrix(data, pos)
            stops = []
            for _ in range(data[pos] & 0x0F):
                stops.append([data[pos + 1], color(pos + 2)])
                pos += 1 + width
            pos += 1
            fills.append(
                {"type": "linear" if kind == 0x10 else "radial", "stops": stops}
            )
        else:
            raise ValueError(f"shape {cid}: fill type {kind:#x} not handled")
    count = data[pos]
    pos += 1
    lines = []
    for _ in range(count):
        (line_width,) = struct.unpack_from("<H", data, pos)
        pos += 2
        line = {"width": px(line_width)}
        if code == TAG_DEFINE_SHAPE4:
            f1, f2 = data[pos], data[pos + 1]
            pos += 2
            if (f1 >> 4) & 0x03 == 2:
                pos += 2
            if f1 & 0x08:
                raise ValueError(f"shape {cid}: filled line style")
            line["scales"] = not (f2 & 0x04 or f2 & 0x02)
        line["color"] = color(pos)
        pos += width
        lines.append(line)
    return fills, lines


def button_hit_bounds(index, cid):
    """-> the bounds of the shape a DefineButton2's hit record draws."""
    code, body, end = index.characters[cid]
    if code != 34:
        raise ValueError(f"{cid} is not a DefineButton2")
    data = index.data
    p = body + 5
    while p < end:
        flags = data[p]
        if flags == 0:
            break
        char, _depth = struct.unpack_from("<HH", data, p + 1)
        matrix, p = _read_matrix(data, p + 5)
        _cx, p = _read_cxform_with_alpha(data, p)
        if flags & 0x10:
            raise ValueError(f"button {cid}: record filters not handled")
        if flags & 0x20:
            p += 1
        if flags & 0x08:
            if matrix[:4] != (1.0, 0.0, 0.0, 1.0) or matrix[4:] != (0, 0):
                raise ValueError(f"button {cid}: hit record is transformed")
            return char, [px(v) for v in shape_bounds(index, char)]
    raise ValueError(f"button {cid} has no hit record")


def _fixed(data, at):
    return struct.unpack_from("<i", data, at)[0] / 65536


def _filter(data, pos):
    """-> (filter dict, length) for one FILTER record."""
    kind = data[pos]
    p = pos + 1
    if kind == 0:
        flags = data[p + 22]
        return {
            "type": "DropShadow",
            "color": hex_rgba(data[p : p + 4]),
            "blur": [_fixed(data, p + 4), _fixed(data, p + 8)],
            "angle": round(_fixed(data, p + 12), 4),
            "distance": _fixed(data, p + 16),
            "strength": struct.unpack_from("<h", data, p + 20)[0] / 256,
            "inner": bool(flags & 0x80),
            "knockout": bool(flags & 0x40),
            "passes": flags & 0x1F,
        }, 24
    if kind == 2:
        flags = data[p + 14]
        return {
            "type": "Glow",
            "color": hex_rgba(data[p : p + 4]),
            "blur": [_fixed(data, p + 4), _fixed(data, p + 8)],
            "strength": struct.unpack_from("<h", data, p + 12)[0] / 256,
            "inner": bool(flags & 0x80),
            "knockout": bool(flags & 0x40),
            "passes": flags & 0x1F,
        }, 16
    if kind in (1, 3, 6):
        return {"type": {1: "Blur", 3: "Bevel", 6: "ColorMatrix"}[kind]}, 1 + {
            1: 9,
            3: 27,
            6: 80,
        }[kind]
    raise ValueError(f"filter type {kind} not handled")


def placement_filters(index, owner):
    """-> {(frame, depth): [filters]} for every PlaceObject3 that carries
    filters on one DefineSprite's own timeline."""
    _code, body, end = index.characters[owner]
    data = index.data
    pos, frame, found = body + 4, 1, {}
    while pos < end:
        (header,) = struct.unpack_from("<H", data, pos)
        pos += 2
        code, length = header >> 6, header & 0x3F
        if length == 0x3F:
            (length,) = struct.unpack_from("<I", data, pos)
            pos += 4
        p, pos = pos, pos + length
        if code == 0:
            break
        if code == 1:
            frame += 1
            continue
        if code != TAG_PLACE_OBJECT3:
            continue
        flags, flags3 = data[p], data[p + 1]
        (depth,) = struct.unpack_from("<H", data, p + 2)
        p += 4
        if flags3 & 0x08 or (flags3 & 0x10 and flags & 0x02):
            _name, p = _cstring(data, p)
        if flags & 0x02:
            p += 2
        if flags & 0x04:
            _m, p = _read_matrix(data, p)
        if flags & 0x08:
            _c, p = _read_cxform_with_alpha(data, p)
        if flags & 0x10:
            p += 2
        if flags & 0x20:
            _n, p = _cstring(data, p)
        if flags & 0x40:
            p += 2
        if flags3 & 0x01:
            filters = []
            count = data[p]
            p += 1
            for _ in range(count):
                parsed, length = _filter(data, p)
                filters.append(parsed)
                p += length
            found[(frame, depth)] = filters
    return found


def filters_at(found, frame, depth):
    """-> the filters a depth carries on `frame`, from the last tag that set
    them at or before it."""
    result = []
    for (f, d), filters in sorted(found.items()):
        if d == depth and f <= frame:
            result = filters
    return result


def union(rects):
    x0 = min(r[0] for r in rects)
    y0 = min(r[1] for r in rects)
    x1 = max(r[0] + r[2] for r in rects)
    y1 = max(r[1] + r[3] for r in rects)
    return [r2(x0), r2(y0), r2(x1 - x0), r2(y1 - y0)]


def column(panel_rect, children, axis="y", separation=None):
    """-> one column spec: the content box inside the panel, the panel's
    content margins (the gaps between the two), and each child's offset and
    extent inside the box. Along the axis each child gets the pitch to the
    next child less the separation, so the gap rides on the child, and the
    last child keeps its own extent. separation=None means the children have
    no common gap and the separation is 0."""
    box = union([c["rect"] for c in children])
    margins = [
        r2(box[0] - panel_rect[0]),
        r2(box[1] - panel_rect[1]),
        r2(panel_rect[0] + panel_rect[2] - box[0] - box[2]),
        r2(panel_rect[1] + panel_rect[3] - box[1] - box[3]),
    ]
    along, cross = (1, 0) if axis == "y" else (0, 1)
    sep = separation or 0.0
    spec_children = []
    for i, child in enumerate(children):
        r = child["rect"]
        if i + 1 < len(children):
            extent = children[i + 1]["rect"][along] - r[along] - sep
        else:
            extent = r[along + 2]
        spec_children.append(
            {
                "id": child["id"],
                "offset": r2(r[along] - box[along]),
                "extent": r2(extent),
                "cross_offset": r2(r[cross] - box[cross]),
                "cross_extent": r2(r[cross + 2]),
            }
        )
    return {
        "axis": axis,
        "box": box,
        "content_margins": margins,
        "separation": r2(sep),
        "children": spec_children,
    }


def main():
    index = read_swf(WEB_SWF)
    (stage,) = [p for p in index.placements if p.character_id == KRINMENU]
    if stage.owner != 0 or stage.matrix[:4] != (1.0, 0.0, 0.0, 1.0):
        raise SystemExit(
            f"KRINMENU placement is not a pure translate on the root: {stage}"
        )
    origin = (px(stage.matrix[4]), px(stage.matrix[5]))
    frame = timeline.frame_of(index, KRINMENU, "win")
    display = timeline.frames(index, KRINMENU)[frame - 1]
    found = placement_filters(index, KRINMENU)

    def shape_piece(depth, inner_depth=None):
        layer = display[depth]
        matrix = layer.matrix
        cid = layer.character_id
        if inner_depth is not None or character_kind(index, cid) == "sprite":
            child = timeline.frames(index, cid)[0]
            inner = (
                child[inner_depth]
                if inner_depth is not None
                else next(iter(child.values()))
            )
            if len(child) != 1 and inner_depth is None:
                raise SystemExit(
                    f"sprite {cid} holds {len(child)} layers, not one shape"
                )
            matrix = compose(matrix, inner.matrix)
            shape = inner.character_id
        else:
            shape = cid
        bounds = [px(v) for v in shape_bounds(index, shape)]
        fills, lines = shape_styles(index, shape)
        return {
            "depth": depth,
            "sprite": cid,
            "shape": shape,
            "rect": rect_through(matrix, bounds, origin),
            "scale": [round(matrix[0], 4), round(matrix[3], 4)],
            "fills": fills,
            "lines": lines,
            "filters": filters_at(found, frame, depth),
        }

    panels = {name: shape_piece(depth) for name, depth in PANEL_DEPTHS.items()}
    backdrop = shape_piece(BACKDROP_DEPTH)

    texts = {}
    for depth, layer in sorted(display.items()):
        if character_kind(index, layer.character_id) != "edittext":
            continue
        et = edit_text(index, layer.character_id)
        key = et["variable"] or "euro_sign"
        texts[key] = {
            "depth": depth,
            "id": layer.character_id,
            "rect": rect_through(layer.matrix, et["bounds"], origin),
            "origin": [
                r2(px(layer.matrix[4]) + origin[0]),
                r2(px(layer.matrix[5]) + origin[1]),
            ],
            "font_id": et.get("font_id"),
            "font_height": et.get("font_height"),
            "color": et.get("color"),
            "align": et.get("align", "left"),
            "multiline": et["multiline"],
            "word_wrap": et["word_wrap"],
            "initial_text": et["initial_text"],
            "filters": filters_at(found, frame, depth),
        }

    def slots(prefix):
        result = []
        for _depth, layer in sorted(display.items()):
            if layer.name and layer.name.startswith(prefix):
                n = int(layer.name[len(prefix) :])
                result.append(
                    (
                        n,
                        [
                            r2(px(layer.matrix[4]) + origin[0]),
                            r2(px(layer.matrix[5]) + origin[1]),
                        ],
                        layer.character_id,
                    )
                )
        result.sort()
        return result

    drop = slots("dropSlot")
    item = slots("itemSlot")
    slot_sprite = drop[0][2]
    slot_layers = timeline.frames(index, slot_sprite)[0]
    art = slot_layers[1]
    art_inner = next(iter(timeline.frames(index, art.character_id)[0].values()))
    slot_bounds = [px(v) for v in shape_bounds(index, art_inner.character_id)]
    slot_size = [
        r2(slot_bounds[2] - slot_bounds[0]),
        r2(slot_bounds[3] - slot_bounds[1]),
    ]

    def grid(entries, columns):
        centres = [c for _n, c, _cid in entries]
        xs = sorted({c[0] for c in centres})
        ys = sorted({c[1] for c in centres})
        if len(xs) != columns or len(centres) != columns * len(ys):
            raise SystemExit(f"slots don't form a {columns}-column grid: {xs} {ys}")
        pitch = [r2(xs[1] - xs[0]), r2(ys[1] - ys[0])]
        rect = [
            r2(xs[0] + slot_bounds[0]),
            r2(ys[0] + slot_bounds[1]),
            r2(xs[-1] - xs[0] + slot_size[0]),
            r2(ys[-1] - ys[0] + slot_size[1]),
        ]
        return {
            "columns": columns,
            "rows": len(ys),
            "pitch": pitch,
            "separation": [r2(pitch[0] - slot_size[0]), r2(pitch[1] - slot_size[1])],
            "rect": rect,
            "centres": centres,
        }

    drop_grid = grid(drop, 5)
    item_grid = grid(item, 6)

    rows = {}
    for role, depth in ROW_DEPTHS.items():
        layer = display[depth]
        rows[role] = {
            "depth": depth,
            "origin": [
                r2(px(layer.matrix[4]) + origin[0]),
                r2(px(layer.matrix[5]) + origin[1]),
            ],
            "filters": filters_at(found, frame, depth),
        }
    row_sprite = display[ROW_DEPTHS["player"]].character_id
    row_layers = timeline.frames(index, row_sprite)[0]
    backing_layer = row_layers[2]
    backing_bounds = [px(v) for v in shape_bounds(index, backing_layer.character_id)]
    fills, lines = shape_styles(index, backing_layer.character_id)
    for role, row in rows.items():
        row["rect"] = [
            r2(row["origin"][0] + backing_bounds[0]),
            r2(row["origin"][1] + backing_bounds[1]),
            r2(backing_bounds[2] - backing_bounds[0]),
            r2(backing_bounds[3] - backing_bounds[1]),
        ]

    def local(rect_px, matrix):
        """A child rect relative to the backing's top-left corner."""
        r = rect_through(matrix, rect_px, (0.0, 0.0))
        return [r2(r[0] - backing_bounds[0]), r2(r[1] - backing_bounds[1]), r[2], r[3]]

    face = row_layers[3]
    bar = row_layers[39]
    bar_shape = next(iter(timeline.frames(index, bar.character_id)[0].values()))
    bar_bounds = [px(v) for v in shape_bounds(index, bar_shape.character_id)]
    overlay = row_layers[41]
    overlay_bounds = [px(v) for v in shape_bounds(index, overlay.character_id)]
    overlay_fills, _ = shape_styles(index, overlay.character_id)
    row_pieces = {
        "sprite": row_sprite,
        "backing": {
            "shape": backing_layer.character_id,
            "size": [
                r2(backing_bounds[2] - backing_bounds[0]),
                r2(backing_bounds[3] - backing_bounds[1]),
            ],
            "fills": fills,
            "lines": lines,
        },
        "face": {
            "sprite": face.character_id,
            "offset": [
                r2(px(face.matrix[4]) - backing_bounds[0]),
                r2(px(face.matrix[5]) - backing_bounds[1]),
            ],
            "scale": round(face.matrix[0], 4),
        },
        "bar": {
            "sprite": bar.character_id,
            "rect": local(bar_bounds, bar.matrix),
            # bar._width = exp / 100 * 95.10000000000001
            # (AS/DefineSprite_3142/frame_9/PlaceObject3_3002_1111/CLIPACTIONRECORD onClipEvent(enterFrame).as:12),
            # so a full bar is the shape's own width.
            "full_width": r2(bar_bounds[2] - bar_bounds[0]),
        },
        "overlay": {
            "shape": overlay.character_id,
            "rect": local(overlay_bounds, overlay.matrix),
            "fills": overlay_fills,
        },
    }
    for depth, key in ((37, "name"), (38, "level"), (42, "percent")):
        layer = row_layers[depth]
        et = edit_text(index, layer.character_id)
        row_pieces[key] = {
            "id": layer.character_id,
            "variable": et["variable"],
            "rect": local(et["bounds"], layer.matrix),
            "font_height": et.get("font_height"),
            "color": et.get("color"),
            "align": et.get("align", "left"),
            "initial_text": et["initial_text"],
            "filters": filters_at(placement_filters(index, row_sprite), 1, depth),
        }

    proceed_layer = display[PROCEED_DEPTH]
    hit_shape, hit_bounds = button_hit_bounds(index, proceed_layer.character_id)
    proceed = {
        "button": proceed_layer.character_id,
        "hit_shape": hit_shape,
        "scale": [round(proceed_layer.matrix[0], 4), round(proceed_layer.matrix[3], 4)],
        "rect": rect_through(proceed_layer.matrix, hit_bounds, origin),
    }
    delete_layer = display[DELETE_DEPTH]
    _shape, delete_bounds = button_hit_bounds(index, delete_layer.character_id)
    delete = {
        "button": delete_layer.character_id,
        "rect": rect_through(delete_layer.matrix, delete_bounds, origin),
        "art": shape_piece(DELETE_ART_DEPTH),
    }

    row_list = sorted(rows.values(), key=lambda r: r["rect"][1])
    gaps = {
        r2(row_list[i + 1]["rect"][1] - row_list[i]["rect"][1] - row_list[i]["rect"][3])
        for i in range(len(row_list) - 1)
    }
    if len(gaps) != 1:
        raise SystemExit(f"the experience rows are not evenly spaced: {gaps}")
    row_gap = gaps.pop()
    by_role = {r["depth"]: role for role, r in rows.items()}
    # The title field is wider than the rows. The rows set the box, and the
    # title is centred text, so it is drawn across the box's width instead.
    left = column(
        panels["left"]["rect"],
        [
            {
                "id": "vbbc1",
                "rect": [
                    row_list[0]["rect"][0],
                    texts["vbbc1"]["rect"][1],
                    row_list[0]["rect"][2],
                    texts["vbbc1"]["rect"][3],
                ],
            }
        ]
        + [{"id": by_role[r["depth"]], "rect": r["rect"]} for r in row_list],
        separation=row_gap,
    )
    centre = column(
        panels["centre"]["rect"],
        [
            {"id": "vb1", "rect": texts["vb1"]["rect"]},
            {"id": "drops", "rect": union([drop_grid["rect"], texts["vb99"]["rect"]])},
            {"id": "vb2", "rect": texts["vb2"]["rect"]},
            {
                "id": "money",
                "rect": union([texts["vb3"]["rect"], texts["vb5"]["rect"]]),
            },
            {"id": "exp", "rect": union([texts["vb4"]["rect"], texts["vb6"]["rect"]])},
            {"id": "vb7", "rect": texts["vb7"]["rect"]},
            {"id": "proceed", "rect": union([texts["vb8"]["rect"], proceed["rect"]])},
        ],
    )
    right = column(
        panels["right"]["rect"],
        [
            {"id": "vbbc0", "rect": texts["vbbc0"]["rect"]},
            {"id": "items", "rect": item_grid["rect"]},
        ],
    )
    bar_row = column(
        panels["bar"]["rect"],
        [
            {"id": "euro_sign", "rect": texts["euro_sign"]["rect"]},
            {"id": "dumbEuro", "rect": texts["dumbEuro"]["rect"]},
            {"id": "delete", "rect": union([delete["rect"], delete["art"]["rect"]])},
        ],
        axis="x",
    )

    layout = {
        "source": (
            f"{WEB_SWF.name}, DefineSprite {KRINMENU} frame {frame} (win), placed at"
            f" {origin} on root frame {stage.frame} depth {stage.depth}"
        ),
        "krinmenu_origin": list(origin),
        "backdrop": backdrop,
        "panels": panels,
        "rows": rows,
        "row_gap": row_gap,
        "row_pieces": row_pieces,
        "slot_size": slot_size,
        "drop_grid": drop_grid,
        "item_grid": item_grid,
        "texts": texts,
        "proceed": proceed,
        "delete": delete,
        "columns": {"left": left, "centre": centre, "right": right, "bar": bar_row},
    }
    OUT.write_text(json.dumps(layout, indent=1) + "\n")
    print(f"wrote {OUT}")
    for name, piece in panels.items():
        print(
            f"panel {name}: depth {piece['depth']} rect {piece['rect']} scale {piece['scale']}"
        )
    for name, spec in layout["columns"].items():
        print(
            f"column {name}: margins {spec['content_margins']} separation {spec['separation']}"
            f" children {[(c['id'], c['offset'], c['extent']) for c in spec['children']]}"
        )


if __name__ == "__main__":
    main()
