# Computes real per-clip registration offsets for every VFX clip
# (dev/urchin_dev/swf/extract/vfx.py's own bolt/trail/impact categories),
# correcting for glow-filter padding that raw shapeBounds XML data can't
# see: ffdec's PNG exporter bakes a glow filter's rendered footprint into
# its canvas, but neither shapeBounds tags nor ffdec's own SVG exporter
# account for it. Confirmed the padding is symmetric around the computed
# shape's own center by measuring real pixel data directly: Krin.Firebolt's
# solid core (opaque pixels, excluding the soft glow halo) has its
# centroid at (97.9, 98.0) in a 196x196 canvas centered on (98.0, 98.0) -
# a match to within 0.1 px. Correcting for this only needs the real
# canvas size (trivially measurable from the already-extracted PNG) - no
# attempt to replicate Flash's exact blur-filter rendering math.
#
# Writes assets/vfx/vfx_offsets.json: one {"x", "y", "w", "h"} entry per
# clip (natural, unzoomed px - matching resources/sprites/doll_offsets.json's
# own convention), keyed by the same sanitize()d name vfx.py already uses
# for its PNG folder names.
#
# See docs/superpowers/specs/2026-08-19-vfx-registration-scenes-design.md.
# Run: uv run extract_vfx_offsets
from __future__ import annotations

import json
import sys

from PIL import Image

from urchin_dev import REPO_ROOT, WEB_SWF_XML
from urchin_dev.swf import make_timeline_bounds, parse_swf_xml
from urchin_dev.swf.extract.vfx import (
    BOLT_NAMES,
    TRAIL_CLIP_NAME,
    TRAIL_SPRITE_ID,
    ZOOM,
    _impact_names,
    sanitize,
)

VFX_DIR = REPO_ROOT / "assets" / "vfx"
OUT = VFX_DIR / "vfx_offsets.json"

# How far apart the horizontal and the vertical half-padding may fall, in
# natural px, before a clip is reported as an outlier. The padding is the
# glow footprint ffdec baked into the canvas, and a glow spreads the same
# distance on both axes, so the two halves should agree; when they don't,
# the computed bounds are wrong for that clip rather than the padding
# being lopsided. Every clip agrees to within 0.14 px today, so 1.0 px is
# well clear of the rounding noise - and it would have caught the 13 clips
# whose bounds came out wrong before make_timeline_bounds learned to read
# morph shapes and to stop borrowing the next tag's matrix (those 13
# diverged by 4.3 to 38.0 px).
PAD_SYMMETRY_TOLERANCE = 1.0


def _clip_offset(bounds_fn, name: str, cid: int, category: str):
    """-> ({"x", "y", "w", "h"}, pad_x, pad_y) or None. The two paddings
    are the symmetry self-check's input, not part of the written record."""
    bounds = bounds_fn(cid)
    if bounds is None:
        return None
    frame1 = VFX_DIR / category / sanitize(name) / "1.png"
    if not frame1.exists():
        return None
    real_w_px, real_h_px = Image.open(frame1).size
    real_w = real_w_px / ZOOM
    real_h = real_h_px / ZOOM
    computed_w = (bounds[2] - bounds[0]) / 20.0
    computed_h = (bounds[3] - bounds[1]) / 20.0
    computed_cx = (bounds[0] + bounds[2]) / 2.0 / 20.0
    computed_cy = (bounds[1] + bounds[3]) / 2.0 / 20.0
    offset = {
        "x": round(computed_cx - real_w / 2.0, 2),
        "y": round(computed_cy - real_h / 2.0, 2),
        "w": round(real_w, 2),
        "h": round(real_h, 2),
    }
    return offset, (real_w - computed_w) / 2.0, (real_h - computed_h) / 2.0


def main():
    xml = WEB_SWF_XML.read_text()
    shape_bounds, _sprites, exports = parse_swf_xml(WEB_SWF_XML)
    bounds_fn = make_timeline_bounds(shape_bounds, xml)
    ci_exports = {k.lower(): v for k, v in exports.items()}

    def resolve(name: str):
        return ci_exports.get(name.lower())

    result = {}
    unresolved = []
    outliers = []
    seen_ids: dict[int, str] = {}

    def record(name: str, cid: int, category: str) -> bool:
        computed = _clip_offset(bounds_fn, name, cid, category)
        if computed is None:
            return False
        offset, pad_x, pad_y = computed
        if abs(pad_x - pad_y) > PAD_SYMMETRY_TOLERANCE:
            outliers.append(f"{sanitize(name)} (pad_x={pad_x:.2f}, pad_y={pad_y:.2f})")
        result[sanitize(name)] = offset
        return True

    for name in BOLT_NAMES:
        cid = resolve(name)
        if cid is None:
            unresolved.append(name)
            continue
        if cid in seen_ids:
            continue  # KRIN.MAGICBOLT/Krin.Magicbolt etc. - same clip, already recorded
        seen_ids[cid] = name
        if not record(name, cid, "bolts"):
            unresolved.append(name)

    if not record(TRAIL_CLIP_NAME, TRAIL_SPRITE_ID, "trail"):
        unresolved.append(TRAIL_CLIP_NAME)

    for name in _impact_names():
        cid = resolve(name)
        if cid is None:
            unresolved.append(name)
            continue
        if cid in seen_ids:
            continue
        seen_ids[cid] = name
        if not record(name, cid, "impacts"):
            unresolved.append(name)

    OUT.write_text(json.dumps(result, indent=1, sort_keys=True))
    print(f"clips resolved: {len(result)}", file=sys.stderr)
    if unresolved:
        print(f"unresolved: {unresolved}", file=sys.stderr)
    if outliers:
        print(
            f"asymmetric glow padding - computed bounds look wrong for: {outliers}",
            file=sys.stderr,
        )


if __name__ == "__main__":
    main()
