"""Every filter placement that draws an inner shadow or inner glow, in both SWFs.

Run from the repo root: uv run python ~/tmp/2026-11-09-inner-shadow/inventory.py <web.swf> <steam.swf>
"""

import json
import struct
import sys
from collections import Counter, defaultdict
from pathlib import Path

from urchin_dev.swf import timeline
from urchin_dev.swf.swf_index import (
    TAG_PLACE_OBJECT3,
    _cstring,
    _read_cxform_with_alpha,
    _read_matrix,
    _skip_rect,
    character_kind,
    read_swf,
    shape_bounds,
)

KRINMENU = 3142


def fixed(data, at):
    return struct.unpack_from("<i", data, at)[0] / 65536


def parse_filter(data, pos):
    kind = data[pos]
    p = pos + 1
    if kind == 0:
        flags = data[p + 22]
        return {
            "type": "DropShadow",
            "color": data[p : p + 4].hex(),
            "blur": (fixed(data, p + 4), fixed(data, p + 8)),
            "angle": round(fixed(data, p + 12), 4),
            "distance": fixed(data, p + 16),
            "strength": struct.unpack_from("<h", data, p + 20)[0] / 256,
            "inner": bool(flags & 0x80),
            "knockout": bool(flags & 0x40),
            "composite": bool(flags & 0x20),
            "passes": flags & 0x1F,
        }, 24
    if kind == 2:
        flags = data[p + 14]
        return {
            "type": "Glow",
            "color": data[p : p + 4].hex(),
            "blur": (fixed(data, p + 4), fixed(data, p + 8)),
            "strength": struct.unpack_from("<h", data, p + 12)[0] / 256,
            "inner": bool(flags & 0x80),
            "knockout": bool(flags & 0x40),
            "composite": bool(flags & 0x20),
            "passes": flags & 0x1F,
        }, 16
    sizes = {1: 9, 3: 27, 6: 80}
    if kind in sizes:
        return {"type": {1: "Blur", 3: "Bevel", 6: "ColorMatrix"}[kind]}, 1 + sizes[
            kind
        ]
    if kind in (4, 7):
        return {
            "type": {4: "GradientGlow", 7: "GradientBevel"}[kind]
        }, 1 + 1 + 5 * data[pos + 1] + 19
    if kind == 5:
        return {"type": "Convolution"}, 1 + 2 + 8 + 4 * data[pos + 1] * data[
            pos + 2
        ] + 5
    raise ValueError(kind)


def walk(data, pos, end, owner, out):
    frame = 1
    while pos < end:
        (header,) = struct.unpack_from("<H", data, pos)
        pos += 2
        code, length = header >> 6, header & 0x3F
        if length == 0x3F:
            (length,) = struct.unpack_from("<I", data, pos)
            pos += 4
        body, pos = pos, pos + length
        if code == 0:
            break
        if code == 1:
            frame += 1
        elif code == 39:
            (sprite,) = struct.unpack_from("<H", data, body)
            walk(data, body + 4, pos, sprite, out)
        elif code == TAG_PLACE_OBJECT3:
            p = body
            flags, flags3 = data[p], data[p + 1]
            (depth,) = struct.unpack_from("<H", data, p + 2)
            p += 4
            if flags3 & 0x08 or (flags3 & 0x10 and flags & 0x02):
                _, p = _cstring(data, p)
            cid = matrix = name = None
            if flags & 0x02:
                (cid,) = struct.unpack_from("<H", data, p)
                p += 2
            if flags & 0x04:
                matrix, p = _read_matrix(data, p)
            if flags & 0x08:
                _, p = _read_cxform_with_alpha(data, p)
            if flags & 0x10:
                p += 2
            if flags & 0x20:
                name, p = _cstring(data, p)
            if flags & 0x40:
                p += 2
            if flags3 & 0x01:
                count = data[p]
                p += 1
                filters = []
                for _ in range(count):
                    f, n = parse_filter(data, p)
                    filters.append(f)
                    p += n
                out.append(
                    {
                        "owner": owner,
                        "frame": frame,
                        "depth": depth,
                        "cid": cid,
                        "name": name,
                        "matrix": matrix,
                        "move": bool(flags & 1),
                        "filters": filters,
                    }
                )


def main():
    for label, path in (("web", sys.argv[1]), ("steam", sys.argv[2])):
        index = read_swf(Path(path))
        data = index.data
        pos = _skip_rect(data, 8) + 4
        found = []
        walk(data, pos, len(data), 0, found)
        print(f"== {label}: {len(found)} PlaceObject3 tags carry filters")
        kinds = Counter()
        for f in found:
            for x in f["filters"]:
                kinds[(x["type"], x.get("inner"))] += 1
        print("  by type/inner:", dict(kinds))
        inner = [
            f
            for f in found
            if any(
                x["type"] in ("DropShadow", "Glow") and x.get("inner")
                for x in f["filters"]
            )
        ]
        print(f"  placements with an inner shadow or inner glow: {len(inner)}")
        params = Counter()
        for f in inner:
            for x in f["filters"]:
                if x.get("inner"):
                    params[
                        json.dumps({k: v for k, v in x.items()}, sort_keys=True)
                    ] += 1
        for k, v in params.most_common():
            print(f"   {v:4d} {k}")
        by_owner = defaultdict(list)
        for f in inner:
            by_owner[f["owner"]].append(f)
        for owner, items in sorted(by_owner.items(), key=lambda kv: -len(kv[1])):
            chars = Counter(i["cid"] for i in items)
            print(f"  owner {owner}: {len(items)} placements, chars {dict(chars)}")
        # KRINMENU's inner shadow placements with label and final rect.
        labels = sorted(
            ((l.frame, l.name) for l in index.labels if l.owner == KRINMENU)
        )
        print("  KRINMENU labels:", labels)

        def label_at(frame):
            name = None
            for f, n in labels:
                if f <= frame:
                    name = n
            return name

        rows = []
        for f in by_owner.get(KRINMENU, []):
            cid = f["cid"]
            frames = timeline.frames(index, KRINMENU)
            layer = frames[f["frame"] - 1].get(f["depth"])
            child = None
            shape = None
            if layer is not None:
                cid = layer.character_id
                if character_kind(index, cid) == "sprite":
                    inner_layers = timeline.frames(index, cid)[0]
                    if len(inner_layers) == 1:
                        child = next(iter(inner_layers.values()))
                        shape = child.character_id
                else:
                    shape = cid
            rect = None
            if shape is not None and character_kind(index, shape) == "shape":
                b = shape_bounds(index, shape)
                m = layer.matrix
                c = child.matrix if child is not None else (1, 0, 0, 1, 0, 0)
                sx, sy = m[0] * c[0], m[3] * c[3]
                x0 = (m[4] + m[0] * c[4]) / 20 + b[0] * sx / 20
                y0 = (m[5] + m[3] * c[5]) / 20 + b[1] * sy / 20
                w = (b[2] - b[0]) * sx / 20
                h = (b[3] - b[1]) * sy / 20
                rect = (
                    round(x0, 2),
                    round(y0, 2),
                    round(w, 2),
                    round(h, 2),
                    round(sx, 4),
                    round(sy, 4),
                )
            rows.append(
                (
                    f["frame"],
                    label_at(f["frame"]),
                    f["depth"],
                    cid,
                    shape,
                    f["name"],
                    rect,
                )
            )
        for r in sorted(rows):
            print("   ", r)


main()
