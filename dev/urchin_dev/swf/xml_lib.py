# xml_lib.py
# What vfx_offsets.py still reads from the ffdec -swf2xml dump in
# source_files/swf_xml/, until julian-perge/urchin#43 moves it onto the
# render: shape and morph shape bounds, export names, and the full-timeline
# bounds walk, which takes each frame's display list from timeline.py.
# Coordinates are SWF twips (divide by 20 for px).
from __future__ import annotations

import re
from pathlib import Path

from urchin_dev.swf import timeline


def parse_swf_xml(path):
    """-> (shape_bounds {id: (xmin,ymin,xmax,ymax) twips},
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
    return shape_bounds, export_name_to_id


# DefineMorphShape2 puts its stroke-only edge bounds before the real ones,
# the same ordering quirk parse_swf_xml already allows for DefineShape4.
_MORPH_SHAPE_RE = re.compile(
    r'<item type="DefineMorphShape\d?Tag"[^>]*characterId="(\d+)"[^>]*>\s*'
    r"(?:<startEdgeBounds[^>]*/>\s*<endEdgeBounds[^>]*/>\s*)?"
    r'<startBounds type="RECT" Xmax="(-?\d+)" Xmin="(-?\d+)" '
    r'Ymax="(-?\d+)" Ymin="(-?\d+)"[^>]*/>\s*'
    r'<endBounds type="RECT" Xmax="(-?\d+)" Xmin="(-?\d+)" '
    r'Ymax="(-?\d+)" Ymin="(-?\d+)"'
)


def _morph_shape_bounds(xml: str) -> dict:
    """-> {morph_shape_id: (xmin, ymin, xmax, ymax) twips}.

    A morph shape carries two rectangles, one per endpoint of the tween
    (startBounds and endBounds). Which endpoint a given placement renders
    depends on its own ratio, so this unions both and reports the widest
    footprint the shape can ever occupy. Only make_timeline_bounds uses
    this; parse_swf_xml's shape_bounds deliberately stays shape-only.
    """
    bounds = {}
    for m in _MORPH_SHAPE_RE.finditer(xml):
        sid = int(m.group(1))
        s_xmax, s_xmin, s_ymax, s_ymin = (int(g) for g in m.groups()[1:5])
        e_xmax, e_xmin, e_ymax, e_ymin = (int(g) for g in m.groups()[5:9])
        bounds[sid] = (
            min(s_xmin, e_xmin),
            min(s_ymin, e_ymin),
            max(s_xmax, e_xmax),
            max(s_ymax, e_ymax),
        )
    return bounds


def transform_rect(mat, rect):
    sx, r0, r1, sy, tx, ty = mat
    xmin, ymin, xmax, ymax = rect
    xs, ys = [], []
    for x, y in ((xmin, ymin), (xmax, ymin), (xmin, ymax), (xmax, ymax)):
        # SWF matrix: x' = sx*x + r1*y + tx ; y' = r0*x + sy*y + ty
        xs.append(sx * x + r1 * y + tx)
        ys.append(r0 * x + sy * y + ty)
    return min(xs), min(ys), max(xs), max(ys)


def make_timeline_bounds(shape_bounds, xml, index):
    """Recursive FULL-TIMELINE rendered bounds (twips), memoized per sprite
    id. It walks every frame of a sprite's own timeline through
    timeline.frames(), and recurses with the SAME full-timeline treatment
    for whatever's placed at each depth - not just the first frame of
    nested children. Needed because some clips' placed children are
    themselves independently-animating sub-timelines: KRIN.SHADOWSHOCK's
    placed child (sprite id 2432) has its own 3-frame timeline, and
    first-frame-only recursion for it missed 2 of those 3 frames -
    confirmed by cross-checking against ffdec's own SVG-per-frame export
    (an independent renderer), which agreed with the corrected computation
    to within rounding.

    Placed morph shapes count as real content here, so this works from
    shape_bounds plus _morph_shape_bounds() combined into a dict of its
    own - the caller's shape_bounds is never touched."""
    memo = {}
    bounds = {**shape_bounds, **_morph_shape_bounds(xml)}

    def timeline_bounds(cid, depth=0):
        if cid in memo:
            return memo[cid]
        if depth > 12:
            return None
        if cid in bounds:
            memo[cid] = bounds[cid]
            return memo[cid]
        if cid not in index.sprite_frames:
            # cid is not a sprite (e.g., placed text or button)
            memo[cid] = None
            return None
        acc: list | None = None
        for frame_state in timeline.frames(index, cid):
            for layer in frame_state.values():
                cb = timeline_bounds(layer.character_id, depth + 1)
                if cb is None:
                    continue
                tb = transform_rect(layer.matrix, cb)
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

    return timeline_bounds
