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


def make_timeline_bounds(shape_bounds, xml):
    """Recursive FULL-TIMELINE rendered bounds (twips), memoized per sprite
    id. Unlike make_char_bounds (first frame only), this walks every frame
    of a sprite's own timeline via snapshot_timeline(), and recurses with
    the SAME full-timeline treatment for whatever's placed at each depth -
    not just the first frame of nested children. Needed because some
    clips' placed children are themselves independently-animating
    sub-timelines: KRIN.SHADOWSHOCK's placed child (sprite id 2432) has
    its own 3-frame timeline, and first-frame-only recursion for it missed
    2 of those 3 frames - confirmed by cross-checking against ffdec's own
    SVG-per-frame export (an independent renderer), which agreed with the
    corrected computation to within rounding.

    Placed morph shapes count as real content here, so this works from
    shape_bounds plus _morph_shape_bounds() combined into a dict of its
    own - the caller's shape_bounds is never touched. Walking is done by
    _snapshot_timeline_bounded() rather than snapshot_timeline() so a
    placement with no matrix of its own keeps its depth's previous matrix
    instead of borrowing a nearby one; see that function for why the
    shared snapshot_timeline stays as it is."""
    memo = {}
    bounds = {**shape_bounds, **_morph_shape_bounds(xml)}

    def frame_count(cid):
        return sprite_body(xml, cid).count("ShowFrameTag")

    def timeline_bounds(cid, depth=0):
        if cid in memo:
            return memo[cid]
        if depth > 12:
            return None
        if cid in bounds:
            memo[cid] = bounds[cid]
            return memo[cid]
        try:
            fc = frame_count(cid)
        except KeyError:
            # cid is not a sprite (e.g., placed text or button)
            memo[cid] = None
            return None
        if fc == 0:
            memo[cid] = None
            return None
        snaps = _snapshot_timeline_bounded(xml, cid, set(range(1, fc + 1)))
        acc: list | None = None
        for frame_state in snaps.values():
            for entry in frame_state.values():
                child_cid = entry.get("cid")
                if child_cid is None:
                    continue
                cb = timeline_bounds(child_cid, depth + 1)
                if cb is None:
                    continue
                mat = entry.get("mat", IDENTITY)
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

    return timeline_bounds


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


_TIMELINE_TAG_RE = re.compile(
    r'<item type="(PlaceObject2Tag|PlaceObject3Tag|RemoveObject2Tag'
    r'|RemoveObjectTag|ShowFrameTag|FrameLabelTag)"([^>]*?)>'
)


def _snapshot_timeline_bounded(xml: str, sprite_id: int, wanted_frames: set[int]):
    """-> {frame: {depth: {cid, mat}}}, the same depth-state walk
    snapshot_timeline does, with one difference that matters for bounds
    math: a placement's matrix is searched for only up to the start of the
    next timeline tag, instead of a fixed 1200-character slice.

    SWF semantics say a PlaceObject that carries no matrix of its own keeps
    whatever matrix its depth already had. The fixed slice can reach past
    the end of such a tag and borrow a LATER tag's matrix - confirmed in
    BOOM_SLASH's inner sprite 1269, where a matrix-less depth-1 placement
    picked up the shrinking, rotating matrix belonging to depth 2 on the
    next frame. snapshot_timeline is deliberately left as it is: five other
    extraction scripts already depend on its exact current behavior, and
    only make_timeline_bounds needs the stricter reading.
    """
    body = sprite_body(xml, sprite_id)
    tags = list(_TIMELINE_TAG_RE.finditer(body))
    frame, state, snaps = 1, {}, {}
    for i, t in enumerate(tags):
        tag, attrs = t.group(1), t.group(2)
        if tag == "ShowFrameTag":
            if frame in wanted_frames:
                snaps[frame] = {d: dict(v) for d, v in state.items()}
            frame += 1
            continue
        if tag == "FrameLabelTag":
            continue  # matched only so it can end the window before it
        d = re.search(r'depth="(\d+)"', attrs)
        depth = int(d.group(1)) if d else -1
        if tag.startswith("RemoveObject"):
            state.pop(depth, None)
            continue
        cid = re.search(r'characterId="(\d+)"', attrs)
        entry = state.get(depth, {})
        if cid:
            entry["cid"] = int(cid.group(1))
        stop = tags[i + 1].start() if i + 1 < len(tags) else len(body)
        window = body[t.end() : stop]
        if MATRIX_TAG_RE.search(window):
            entry["mat"] = find_matrix(window)
        state[depth] = entry
    return snaps
