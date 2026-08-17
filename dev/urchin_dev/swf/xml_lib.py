# xml_lib.py
# Shared parsing for the ffdec -swf2xml dumps in source_files/swf_xml/:
# shape bounds, sprite timelines, export names, matrices, and recursive
# rendered-bounds math. Coordinates are SWF twips (divide by 20 for px).
from __future__ import annotations

import re
from pathlib import Path

# NOTE: a single regex with optional named groups silently matched them all
# empty (translate anchors the match on its own) and dropped every scale/
# rotation - parse the tag's attributes individually instead.
MATRIX_TAG_RE = re.compile(r'<matrix type="MATRIX"[^>]*>')
_MATRIX_ATTR_RES = {
    name: re.compile(rf'{name}="(-?[\d.eE+-]+)"')
    for name in (
        "scaleX",
        "scaleY",
        "rotateSkew0",
        "rotateSkew1",
        "translateX",
        "translateY",
    )
}

IDENTITY = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def _matrix_attr(tag: str, name: str, default: float) -> float:
    m = _MATRIX_ATTR_RES[name].search(tag)
    return float(m.group(1)) if m else default


def find_matrix(text: str) -> tuple:
    """Parses the first <matrix .../> in text -> (a, b, c, d, tx, ty)
    with translations in twips. Missing attributes mean identity/zero."""
    tag_match = MATRIX_TAG_RE.search(text)
    if tag_match is None:
        return IDENTITY
    tag = tag_match.group(0)
    return (
        _matrix_attr(tag, "scaleX", 1.0),
        _matrix_attr(tag, "rotateSkew0", 0.0),
        _matrix_attr(tag, "rotateSkew1", 0.0),
        _matrix_attr(tag, "scaleY", 1.0),
        _matrix_attr(tag, "translateX", 0.0),
        _matrix_attr(tag, "translateY", 0.0),
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
        r"(?:<edgeBounds[^>]*/>\s*)?"
        r'<shapeBounds type="RECT" Xmax="(-?\d+)" Xmin="(-?\d+)" '
        r'Ymax="(-?\d+)" Ymin="(-?\d+)"',
        xml,
    ):
        sid, xmax, xmin, ymax, ymin = (int(g) for g in m.groups())
        shape_bounds[sid] = (xmin, ymin, xmax, ymax)
    sprite_children = {}
    for m in re.finditer(
        r'<item type="DefineSpriteTag"[^>]*spriteId="(\d+)"[^>]*>', xml
    ):
        sid = int(m.group(1))
        end = xml.find("</subTags>", m.end())
        body = xml[m.end() : end if end != -1 else m.end() + 200000]
        # ffdec exports render the FIRST frame - ignore later placements
        # (animated clips would otherwise union all frames' bounds).
        first_frame_end = body.find('<item type="ShowFrameTag"')
        if first_frame_end != -1:
            body = body[:first_frame_end]
        children = []
        for pm in re.finditer(
            r'<item type="PlaceObject2?3?Tag"[^>]*characterId="(\d+)"[^>]*>(.*?)</item>',
            body,
            re.DOTALL,
        ):
            children.append((int(pm.group(1)), find_matrix(pm.group(2))))
        sprite_children[sid] = children
    export_name_to_id = {}
    for m in re.finditer(
        r'<item type="ExportAssetsTag"[^>]*>\s*<tags>\s*(.*?)</tags>\s*<names>\s*(.*?)</names>',
        xml,
        re.DOTALL,
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
    return min(xs), min(ys), max(xs), max(ys)


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
            acc: list | None = None
            for child_id, mat in sprite_children[cid]:
                cb = char_bounds(child_id, depth + 1)
                if cb is None:
                    continue
                tb = transform_rect(mat, cb)
                if acc is None:
                    acc = list(tb)
                else:
                    acc = [
                        min(acc[0], tb[0]),
                        min(acc[1], tb[1]),
                        max(acc[2], tb[2]),
                        max(acc[3], tb[3]),
                    ]
            memo[cid] = tuple(acc) if acc else None
            return memo[cid]
        return None

    return char_bounds


def sprite_body(xml: str, sprite_id: int) -> str:
    m = re.search(
        rf'<item type="DefineSpriteTag"[^>]*spriteId="{sprite_id:d}"[^>]*>', xml
    )
    if m is None:
        raise KeyError(f"sprite {sprite_id:d} not found")
    end = xml.find("</subTags>", m.end())
    return xml[m.end() : end]


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
        entry = state.get(depth, {})
        if cid:
            entry["cid"] = int(cid.group(1))
        if name:
            entry["name"] = name.group(1)
        window = body[t.end() : t.end() + 1200]
        if MATRIX_TAG_RE.search(window):
            entry["mat"] = find_matrix(window)
        state[depth] = entry
    return snaps, labels
