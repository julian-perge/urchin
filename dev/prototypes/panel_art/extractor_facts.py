#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
# Pulls the placement facts the extractor issue names: slot shadow angles,
# hotbar square filters and sizes, and where each chrome sprite is placed.
from __future__ import annotations

import struct
import sys

sys.path.insert(0, "/Users/sweetjp/tmp/2026-11-09-panel-art")
import shape_records as sr
from urchin_dev.swf import timeline
from urchin_dev.swf.swf_index import (
    _cstring,
    _filter_size,
    _read_cxform_with_alpha,
    _read_matrix,
    character_kind,
)

idx = sr.load()
data = idx.data


def decode(p):
    kind = data[p]
    q = p + 1
    if kind == 0:
        r, g, b, a = data[q : q + 4]
        bx, by, ang, dist = struct.unpack_from("<iiii", data, q + 4)
        s = struct.unpack_from("<H", data, q + 20)[0] / 256
        fl = data[q + 22]
        return f"DropShadow #{r:02x}{g:02x}{b:02x} blur {bx / 65536:g} angle {ang / 65536 * 57.2958:.0f} dist {dist / 65536:g} str {s:.2f}{' inner' if fl & 0x80 else ''}"
    if kind == 2:
        r, g, b, a = data[q : q + 4]
        bx, by = struct.unpack_from("<ii", data, q + 4)
        s = struct.unpack_from("<H", data, q + 12)[0] / 256
        fl = data[q + 14]
        return f"Glow #{r:02x}{g:02x}{b:02x} blur {bx / 65536:g} str {s:.2f}{' inner' if fl & 0x80 else ''}"
    if kind == 3:
        sr_, sg, sb, sa = data[q : q + 4]
        hr, hg, hb, ha = data[q + 4 : q + 8]
        bx, by, ang, dist = struct.unpack_from("<iiii", data, q + 8)
        s = struct.unpack_from("<H", data, q + 24)[0] / 256
        return f"Bevel #{sr_:02x}{sg:02x}{sb:02x}/#{hr:02x}{hg:02x}{hb:02x} blur {bx / 65536:g} dist {dist / 65536:g} str {s:.2f}"
    return f"kind{kind}"


def tags(owner):
    if owner == 0:
        bits = sr._Bits(data, 8)
        n = bits.ub(5)
        bits.ub(4 * n)
        p = bits.align() + 4
        end = len(data)
    else:
        _c, b, end = idx.characters[owner]
        p = b + 4
    frame = 1
    out = []
    while p < end:
        (h,) = struct.unpack_from("<H", data, p)
        p += 2
        t, l = h >> 6, h & 0x3F
        if l == 0x3F:
            (l,) = struct.unpack_from("<I", data, p)
            p += 4
        b = p
        p += l
        if t == 1:
            frame += 1
        elif t == 70:
            fl = data[b]
            f3 = data[b + 1]
            q = b + 2
            (d,) = struct.unpack_from("<H", data, q)
            q += 2
            if f3 & 8 or (f3 & 0x10 and fl & 2):
                _, q = _cstring(data, q)
            cid = None
            if fl & 2:
                (cid,) = struct.unpack_from("<H", data, q)
                q += 2
            if fl & 4:
                m, q = _read_matrix(data, q)
            if fl & 8:
                _, q = _read_cxform_with_alpha(data, q)
            if fl & 0x10:
                q += 2
            if fl & 0x20:
                _, q = _cstring(data, q)
            if fl & 0x40:
                q += 2
            fs = []
            if f3 & 1:
                n = data[q]
                q += 1
                for _ in range(n):
                    fs.append(decode(q))
                    q += _filter_size(data, q)
            if fs:
                out.append((frame, d, cid, fs))
        elif t == 0:
            break
    return out


for sprite in (2986, 2984, 3013):
    print("slot sprite", sprite, "->", [(f, d, c, fs) for f, d, c, fs in tags(sprite)])
    print(
        "   layers",
        {d: l.character_id for d, l in timeline.frames(idx, sprite)[0].items()},
    )
km = tags(3142)
for cid in (2855, 2860, 3017):
    print(cid, [(f, d, fs) for f, d, c, fs in km if c == cid])
    print(
        "   placed at",
        [
            (i + 1, d)
            for i, fr in enumerate(timeline.frames(idx, 3142))
            for d, l in fr.items()
            if l.character_id == cid
        ][:6],
    )
print(
    "3141 layers f1",
    {d: (l.character_id, l.filters) for d, l in timeline.frames(idx, 3141)[0].items()},
    "frames",
    len(timeline.frames(idx, 3141)),
)
print("3141 filter tags", tags(3141)[:6])
nav = timeline.frame_of(idx, 0, "Navigation")
root = timeline.frames(idx, 0)[nav - 1]
rootf = tags(0)
for d, l in sorted(root.items()):
    if character_kind(idx, l.character_id) == "button" and 126 <= d <= 167:
        fs = [x for x in rootf if x[1] == d and x[0] <= nav]
        print(
            "hotbar depth",
            d,
            "button",
            l.character_id,
            "scale",
            round(l.matrix[0], 3),
            "filters",
            fs[-1][3] if fs else None,
        )
for d, l in sorted(root.items()):
    if l.character_id in (3149, 3147, 3144, 3143, 3145) or (169 <= d <= 174):
        print("zone", d, l.character_id, l.filters, l.name)
print(
    "2998 parent:",
    [
        (s, d)
        for s in (3002,)
        for d, l in timeline.frames(idx, s)[0].items()
        if l.character_id == 2998
    ],
    "row filters",
    tags(3002)[:5],
)
print(
    "2864 in KRINMENU:",
    [
        (i + 1, d)
        for i, fr in enumerate(timeline.frames(idx, 3142))
        for d, l in fr.items()
        if l.character_id == 2864
    ][:3],
)
