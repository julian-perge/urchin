#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
# Walks every Screen, Window and HUD frame and lists each rectangular or panel
# like shape with its stage rect, the filters on its placement chain and where
# it is used.
from __future__ import annotations

import json
import struct
import sys
from collections import defaultdict
from pathlib import Path

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

IDENT = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
idx = sr.load()
data = idx.data

ROOT_LABELS = [
    "mainMenu",
    "subMenu",
    "nameMenu",
    "dataMenu",
    "classMenu",
    "optionsMenu",
    "gameOverMenu",
    "endMenu",
    "designMenu",
    "creditMenu",
    "IntroSeq",
    "CS_INTRO",
    "CS_INTRO2",
    "Navigation",
    "KRINBATTLESCENE",
    "overMap",
]
KRINMENU = 3142
KRINMENU_LABELS = [
    "inventory",
    "normal",
    "win",
    "shop",
    "skills",
    "data",
    "options",
    "ach",
]
SKIP_DESCENT = {
    2064,  # item icons
    2427,  # ability icons
    100,  # buff icons
    2978,  # portraits
    3036,  # shop keeper scenes
    3287,  # hub art
    2676,  # fighter rig
    4172,  # world map art
    KRINMENU,  # walked per label instead
}
MAX_FRAMES = 80


def twips_to_px(m):
    a, b, c, d, tx, ty = m
    return (a, b, c, d, tx / 20.0, ty / 20.0)


def compose(p, c):
    pa, pb, pc, pd, ptx, pty = p
    ca, cb, cc, cd, ctx, cty = c
    return (
        pa * ca + pc * cb,
        pb * ca + pd * cb,
        pa * cc + pc * cd,
        pb * cc + pd * cd,
        pa * ctx + pc * cty + ptx,
        pb * ctx + pd * cty + pty,
    )


def apply(m, x, y):
    a, b, c, d, tx, ty = m
    return a * x + c * y + tx, b * x + d * y + ty


def stage_rect(m, r):
    pts = [apply(m, x, y) for x in (r[0], r[2]) for y in (r[1], r[3])]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return (min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys))


def decode_filter(p):
    kind = data[p]
    q = p + 1
    if kind == 2:
        r, g, b, a = data[q : q + 4]
        bx, by = struct.unpack_from("<ii", data, q + 4)
        strength = struct.unpack_from("<H", data, q + 12)[0] / 256
        flags = data[q + 14]
        return (
            f"Glow #{r:02x}{g:02x}{b:02x}@{a} blur {bx / 65536:g}x{by / 65536:g} str {strength:.2f}"
            f"{' inner' if flags & 0x80 else ''}{' knockout' if flags & 0x40 else ''}"
        )
    if kind == 0:
        r, g, b, a = data[q : q + 4]
        bx, by, ang, dist = struct.unpack_from("<iiii", data, q + 4)
        strength = struct.unpack_from("<H", data, q + 20)[0] / 256
        flags = data[q + 22]
        return (
            f"DropShadow #{r:02x}{g:02x}{b:02x}@{a} blur {bx / 65536:g}x{by / 65536:g}"
            f" angle {ang / 65536 * 57.29578:.0f} dist {dist / 65536:g} str {strength:.2f}"
            f"{' inner' if flags & 0x80 else ''}{' knockout' if flags & 0x40 else ''}"
        )
    if kind == 3:
        sr_, sg, sb, sa = data[q : q + 4]
        hr, hg, hb, ha = data[q + 4 : q + 8]
        bx, by, ang, dist = struct.unpack_from("<iiii", data, q + 8)
        strength = struct.unpack_from("<H", data, q + 24)[0] / 256
        return (
            f"Bevel shadow #{sr_:02x}{sg:02x}{sb:02x}@{sa} highlight #{hr:02x}{hg:02x}{hb:02x}@{ha}"
            f" blur {bx / 65536:g}x{by / 65536:g} dist {dist / 65536:g} str {strength:.2f}"
        )
    if kind == 1:
        bx, by = struct.unpack_from("<ii", data, q)
        return f"Blur {bx / 65536:g}x{by / 65536:g}"
    if kind == 6:
        return "ColorMatrix"
    if kind == 4:
        return "GradientGlow"
    if kind == 7:
        return "GradientBevel"
    return f"filter{kind}"


FILTERS: dict[tuple[int, int], list[tuple[int, list[str]]]] = defaultdict(list)


def scan_filters(owner):
    if owner == 0:
        bits = sr._Bits(data, 8)
        n = bits.ub(5)
        bits.ub(4 * n)
        p = bits.align() + 4
        end = len(data)
    else:
        _code, body, end = idx.characters[owner]
        p = body + 4
    frame = 1
    while p < end:
        (header,) = struct.unpack_from("<H", data, p)
        p += 2
        tcode, length = header >> 6, header & 0x3F
        if length == 0x3F:
            (length,) = struct.unpack_from("<I", data, p)
            p += 4
        tbody, after = p, p + length
        p = after
        if tcode == 1:
            frame += 1
        elif tcode == 70:
            flags = data[tbody]
            flags3 = data[tbody + 1]
            q = tbody + 2
            (depth,) = struct.unpack_from("<H", data, q)
            q += 2
            if flags3 & 0x08 or (flags3 & 0x10 and flags & 0x02):
                _, q = _cstring(data, q)
            if flags & 0x02:
                q += 2
            if flags & 0x04:
                _m, q = _read_matrix(data, q)
            if flags & 0x08:
                _c, q = _read_cxform_with_alpha(data, q)
            if flags & 0x10:
                q += 2
            if flags & 0x20:
                _, q = _cstring(data, q)
            if flags & 0x40:
                q += 2
            if flags3 & 0x01:
                count = data[q]
                q += 1
                out = []
                for _ in range(count):
                    out.append(decode_filter(q))
                    q += _filter_size(data, q)
                FILTERS[(owner, depth)].append((frame, out))
        elif tcode == 0:
            break


SCANNED = set()


def filters_at(owner, frame, depth):
    if owner not in SCANNED:
        scan_filters(owner)
        SCANNED.add(owner)
    best = []
    for f, out in FILTERS.get((owner, depth), []):
        if f <= frame:
            best = out
    return best


def button_records(cid):
    code, body, end = idx.characters[cid]
    if code != 34:
        return []
    p = body + 2
    p += 1
    (action_offset,) = struct.unpack_from("<H", data, p)
    p += 2
    out = []
    while data[p] != 0:
        flags = data[p]
        p += 1
        (ch,) = struct.unpack_from("<H", data, p)
        p += 2
        (depth,) = struct.unpack_from("<H", data, p)
        p += 2
        m, p = _read_matrix(data, p)
        _c, p = _read_cxform_with_alpha(data, p)
        states = [
            n
            for n, bit in (("up", 1), ("over", 2), ("down", 4), ("hit", 8))
            if flags & bit
        ]
        if flags & 0x10:
            count = data[p]
            p += 1
            for _ in range(count):
                p += _filter_size(data, p)
        if flags & 0x20:
            p += 1
        out.append((states, ch, depth, m))
    return out


USES: dict[int, list[dict]] = defaultdict(list)
SEEN_PATH: set[tuple] = set()


def walk(owner, frame, m_parent, chain, where, depth_limit):
    frames = timeline.frames(idx, owner)
    if frame - 1 >= len(frames):
        return
    for depth, layer in sorted(frames[frame - 1].items()):
        cid = layer.character_id
        m_local = twips_to_px(layer.matrix)
        m_stage = compose(m_parent, m_local)
        own = filters_at(owner, frame, depth)
        clip = layer.clip_depth
        record(cid, m_stage, own, chain, where, clip, layer, owner, depth)


def record(cid, m_stage, own, chain, where, clip, layer, owner, depth):
    kind = character_kind(idx, cid)
    if kind == "shape":
        add_shape(cid, m_stage, own, chain, where, clip, layer)
    elif kind == "button":
        for states, ch, _d, bm in button_records(cid):
            states_vis = [s for s in states if s != "hit"]
            if not states_vis:
                continue
            mb = compose(m_stage, twips_to_px(bm))
            w = f"{where} > button {cid}[{'/'.join(states_vis)}]"
            record(ch, mb, [], chain + own, w, None, None, cid, _d)
    elif kind == "sprite":
        if cid in SKIP_DESCENT:
            return
        n = len(timeline.frames(idx, cid))
        if n > MAX_FRAMES:
            return
        sprite_where = f"{where} > {cid}" + (
            f"({layer.name})" if layer is not None and layer.name else ""
        )
        key = (cid, tuple(round(v, 3) for v in m_stage), where.split(" > ")[0])
        if key in SEEN_PATH:
            return
        SEEN_PATH.add(key)
        for f in range(1, n + 1):
            walk(
                cid,
                f,
                m_stage,
                chain + own,
                sprite_where + (f"@f{f}" if n > 1 else ""),
                0,
            )


def add_shape(cid, m_stage, own, chain, where, clip, layer):
    screen = where.split(" > ")[0]
    USES[cid].append(
        {
            "screen": screen,
            "where": where,
            "m": m_stage,
            "own": list(own),
            "chain": list(chain),
            "clip": clip,
            "name": layer.name if layer else None,
            "cx": layer.color_transform if layer else None,
            "blend": layer.blend_mode if layer else None,
        }
    )


def main():
    for label in ROOT_LABELS:
        f = timeline.frame_of(idx, 0, label)
        walk(0, f, IDENT, [], label, 0)
    root_nav = timeline.frame_of(idx, 0, "Navigation")
    layer = timeline.frames(idx, 0)[root_nav - 1]
    km_depth = next(d for d, l in layer.items() if l.character_id == KRINMENU)
    km_layer = layer[km_depth]
    km_m = twips_to_px(km_layer.matrix)
    km_filters = filters_at(0, root_nav, km_depth)
    print("KRINMENU placement filters:", km_filters)
    for label in KRINMENU_LABELS:
        f = timeline.frame_of(idx, KRINMENU, label)
        walk(KRINMENU, f, km_m, list(km_filters), f"KRINMENU:{label}", 0)
    # Tooltip frames are walked as part of the root frames that place it.

    rows = []
    for cid, uses in sorted(USES.items()):
        s = sr.parse(idx, cid)
        v = sr.classify(s)
        info = {
            "cid": cid,
            "category": v.category,
            "detail": v.detail,
            "bounds": s.bounds,
            "fills": [f.text() for fs in s.fills for f in fs],
            "lines": [l.text() for ls in s.lines for l in ls],
            "fill_rect": v.fill_rect,
            "line_rect": v.line_rect,
            "n_edges": v.n_edges,
            "n_curves": v.n_curves,
            "uses": [],
        }
        for u in uses:
            r = stage_rect(u["m"], s.bounds)
            info["uses"].append(
                {
                    "screen": u["screen"],
                    "where": u["where"],
                    "rect": [round(x, 3) for x in r],
                    "scale": [round(u["m"][0], 4), round(u["m"][3], 4)],
                    "skew": [round(u["m"][1], 4), round(u["m"][2], 4)],
                    "own": u["own"],
                    "chain": u["chain"],
                    "clip": u["clip"],
                    "name": u["name"],
                    "cx": u["cx"],
                    "blend": u["blend"],
                }
            )
        rows.append(info)
    Path("/Users/sweetjp/tmp/2026-11-09-panel-art/panels.json").write_text(
        json.dumps(rows, indent=1)
    )
    print("shapes", len(rows))
    cats = defaultdict(int)
    for r in rows:
        cats[r["category"]] += 1
    print(dict(cats))


main()
