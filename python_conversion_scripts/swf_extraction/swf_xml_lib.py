# swf_xml_lib.py
# Shared parsing for the ffdec -swf2xml dumps in source_files/swf_xml/:
# shape bounds, sprite timelines, export names, matrices, and recursive
# rendered-bounds math. Coordinates are SWF twips (divide by 20 for px).
from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from swf_models import (  # noqa: E402,F401
    ACTION_SCRIPT, ACTION_SCRIPT_CURATED, SOURCE_FILES,
    STEAM_SWF_XML, WEB_SWF_XML,
)

MATRIX_RE = re.compile(
    r'<matrix type="MATRIX"[^>]*?'
    r'(?:rotateSkew0="(?P<r0>-?[\d.E-]+)")?[^>]*?'
    r'(?:rotateSkew1="(?P<r1>-?[\d.E-]+)")?[^>]*?'
    r'(?:scaleX="(?P<sx>-?[\d.E-]+)")?[^>]*?'
    r'(?:scaleY="(?P<sy>-?[\d.E-]+)")?[^>]*?'
    r'translateX="(?P<tx>-?\d+)" translateY="(?P<ty>-?\d+)"'
)

IDENTITY = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def matrix_from_match(mm) -> tuple:
    if mm is None:
        return IDENTITY
    return (
        float(mm.group("sx") or 1.0), float(mm.group("r0") or 0.0),
        float(mm.group("r1") or 0.0), float(mm.group("sy") or 1.0),
        float(mm.group("tx")), float(mm.group("ty")),
    )


def parse_swf_xml(path):
    """-> (shape_bounds {id: (xmin,ymin,xmax,ymax) twips},
           sprite_children {id: [(childId, matrix), ...]} (first frame only),
           export_name_to_id {name: id})"""
    xml = Path(path).read_text()
    shape_bounds = {}
    # DefineShape4 puts <edgeBounds> before <shapeBounds> - allow it.
    for m in re.finditer(
        r'<item type="DefineShape\d?Tag"[^>]*shapeId="(\d+)"[^>]*>\s*'
        r'(?:<edgeBounds[^>]*/>\s*)?'
        r'<shapeBounds type="RECT" Xmax="(-?\d+)" Xmin="(-?\d+)" '
        r'Ymax="(-?\d+)" Ymin="(-?\d+)"',
        xml,
    ):
        sid, xmax, xmin, ymax, ymin = (int(g) for g in m.groups())
        shape_bounds[sid] = (xmin, ymin, xmax, ymax)
    sprite_children = {}
    for m in re.finditer(r'<item type="DefineSpriteTag"[^>]*spriteId="(\d+)"[^>]*>', xml):
        sid = int(m.group(1))
        end = xml.find("</subTags>", m.end())
        body = xml[m.end():end if end != -1 else m.end() + 200000]
        # ffdec exports render the FIRST frame - ignore later placements
        # (animated clips would otherwise union all frames' bounds).
        first_frame_end = body.find('<item type="ShowFrameTag"')
        if first_frame_end != -1:
            body = body[:first_frame_end]
        children = []
        for pm in re.finditer(
            r'<item type="PlaceObject2?3?Tag"[^>]*characterId="(\d+)"[^>]*>(.*?)</item>',
            body,
            re.S,
        ):
            children.append((int(pm.group(1)), matrix_from_match(MATRIX_RE.search(pm.group(2)))))
        sprite_children[sid] = children
    export_name_to_id = {}
    for m in re.finditer(
        r'<item type="ExportAssetsTag"[^>]*>\s*<tags>\s*(.*?)</tags>\s*<names>\s*(.*?)</names>',
        xml,
        re.S,
    ):
        ids = re.findall(r"<item>(\d+)</item>", m.group(1))
        names = re.findall(r"<item>(.*?)</item>", m.group(2))
        for cid, name in zip(ids, names):
            export_name_to_id[name] = int(cid)
    return shape_bounds, sprite_children, export_name_to_id


def transform_rect(mat, rect):
    sx, r0, r1, sy, tx, ty = mat
    xmin, ymin, xmax, ymax = rect
    xs, ys = [], []
    for x, y in ((xmin, ymin), (xmax, ymin), (xmin, ymax), (xmax, ymax)):
        # SWF matrix: x' = sx*x + r1*y + tx ; y' = r0*x + sy*y + ty
        xs.append(sx * x + r1 * y + tx)
        ys.append(r0 * x + sy * y + ty)
    return (min(xs), min(ys), max(xs), max(ys))


def make_char_bounds(shape_bounds, sprite_children):
    """Recursive first-frame rendered bounds (twips) with memoization."""
    memo = {}

    def char_bounds(cid, depth=0):
        if cid in memo:
            return memo[cid]
        if depth > 12:
            return None
        if cid in shape_bounds:
            memo[cid] = shape_bounds[cid]
            return memo[cid]
        if cid in sprite_children:
            acc = None
            for child_id, mat in sprite_children[cid]:
                cb = char_bounds(child_id, depth + 1)
                if cb is None:
                    continue
                tb = transform_rect(mat, cb)
                if acc is None:
                    acc = list(tb)
                else:
                    acc = [
                        min(acc[0], tb[0]), min(acc[1], tb[1]),
                        max(acc[2], tb[2]), max(acc[3], tb[3]),
                    ]
            memo[cid] = tuple(acc) if acc else None
            return memo[cid]
        return None

    return char_bounds


def sprite_body(xml: str, sprite_id: int) -> str:
    m = re.search(r'<item type="DefineSpriteTag"[^>]*spriteId="%d"[^>]*>' % sprite_id, xml)
    if m is None:
        raise KeyError("sprite %d not found" % sprite_id)
    end = xml.find("</subTags>", m.end())
    return xml[m.end():end]


def snapshot_timeline(xml: str, sprite_id: int, wanted_frames: set[int]):
    """Simulate a sprite's timeline (PlaceObject/RemoveObject by depth) and
    return {frame: {depth: {cid, name, mat}}} snapshots plus {label: frame}."""
    body = sprite_body(xml, sprite_id)
    frame, state, snaps, labels = 1, {}, {}, {}
    for t in re.finditer(
        r'<item type="(PlaceObject2Tag|PlaceObject3Tag|RemoveObject2Tag|RemoveObjectTag|ShowFrameTag|FrameLabelTag)"([^>]*?)>',
        body,
    ):
        tag, attrs = t.group(1), t.group(2)
        if tag == "ShowFrameTag":
            if frame in wanted_frames:
                snaps[frame] = {d: dict(v) for d, v in state.items()}
            frame += 1
            continue
        if tag == "FrameLabelTag":
            nm = re.search(r'name="([^"]*)"', attrs)
            if nm:
                labels[nm.group(1)] = frame
            continue
        d = re.search(r'depth="(\d+)"', attrs)
        depth = int(d.group(1)) if d else -1
        if tag.startswith("RemoveObject"):
            state.pop(depth, None)
            continue
        cid = re.search(r'characterId="(\d+)"', attrs)
        name = re.search(r'name="([^"]*)"', attrs)
        mm = MATRIX_RE.search(body[t.end():t.end() + 1200])
        entry = state.get(depth, {})
        if cid:
            entry["cid"] = int(cid.group(1))
        if name:
            entry["name"] = name.group(1)
        if mm:
            entry["mat"] = matrix_from_match(mm)
        state[depth] = entry
    return snaps, labels
