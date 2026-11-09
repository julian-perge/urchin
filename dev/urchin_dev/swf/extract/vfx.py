# Battle VFX extraction: 15 Missile bolt clips + KrinTrail + every real
# BOOM_*/ex_* impact clip referenced by moves_abilities.json's
# 13_impact_effect_name (frame_42/DoAction_4.as's krinBoltMake) - all
# shape/tween DefineSprites with no ActionScript of their own (except
# KrinTrail's inner clip - see TRAIL_SPRITE_ID below).
#
# Each clip's frames are copied as-is into their own per-clip folder
# (1.png, 2.png, ..., N.png, exactly as ffdec names them) - no packing,
# no cropping, no resizing, no recoloring. Packing into one spritesheet
# per clip was tried first and abandoned: BOOM1 (36 frames, 1225px wide)
# and BOOM2 (36 frames, 956px wide) would pack to 44100px/34416px wide
# images, past Godot's texture importer's 32768px width cap, which
# silently rescales the whole image on import and desyncs every packed
# frame's region from its own recorded size. Per-clip folders of
# individually-sized frames can't hit that limit for any clip.
#
# Clip names are resolved against the SWF's ExportAssetsTag table
# case-insensitively - two of the 15 bolt names (KRIN.MAGICBOLT,
# KRIN.POISONBOLT) are just differently-cased references to
# Krin.Magicbolt/Krin.Poisonbolt (Flash's attachMovie linkage lookup is
# case-insensitive; both variants resolve to the same sprite id).
# sanitize()+lower() collapses both casings onto one output folder -
# BuffIcons._sanitize()'s exact GDScript mirror of this convention is
# the template; Projectile/ImpactEffect (via the shared VfxFrames
# helper) apply the identical transform at runtime so a move's own
# (possibly differently-cased) animation_label/impact_effect_name
# string always resolves to the folder this script wrote.
#
# 5 impact_effect_name values referenced by real moves don't exist in
# this SWF's export table at all: BOOM_DARK2, BOOM_DOWN_BLUE,
# BOOM_DOWN_PURPLE, BOOM_PURPLE, BOOM_SUN. A real content gap in the
# source, not a bug here - printed as unresolved and skipped; those
# moves simply show no impact effect (ImpactEffect.play() already
# no-ops on a missing folder).
#
# OFFSETS. The same render also writes assets/vfx/vfx_offsets.json: one
# {"x", "y", "w", "h"} entry per clip in natural, unzoomed px (the
# convention resources/sprites/doll_offsets.json uses), keyed by the same
# sanitize()d name as the clip's folder. A glow filter's footprint is baked
# into ffdec's canvas, so w and h are the canvas size, and x and y put that
# canvas around the centre of the clip's whole-timeline displayRect, which
# the driver reports with the canvas. The padding is symmetric: Krin.Firebolt's
# opaque core has its centroid at (97.9, 98.0) in a 196x196 canvas centred on
# (98.0, 98.0). Until julian-perge/urchin#43 the bounds came from
# make_timeline_bounds, a Python walk of the XML dump, and the frames had to
# be extracted before a separate script could measure them.
#
# Requires ffdec (~/.local/bin/ffdec), whose jars render.py's driver runs on.
# Run: uv run extract_vfx
from __future__ import annotations

import json
import re
import shutil
import sys

from urchin_dev import REPO_ROOT, WEB_SWF
from urchin_dev.swf import render
from urchin_dev.swf.swf_index import read_swf

ZOOM = 2.0
VFX_DIR = REPO_ROOT / "assets" / "vfx"
OFFSETS = VFX_DIR / "vfx_offsets.json"

BOLT_NAMES = [
    "KRIN.BLADEWHITE",
    "KRIN.POISONBOLT2",
    "KRIN.REDBLADE",
    "KRIN.REDBOLT",
    "KRIN.SHADOWBLADE",
    "KRIN.SHADOWSHOCK",
    "KRIN.YELLOWBLADE",
    "Krin.Electrobolt",
    "Krin.Electrobolt2",
    "Krin.Firebolt",
    "Krin.Iceball",
    "Krin.Iceblade",
    "Krin.Icebolt",
    "Krin.Magicbolt",
    "Krin.Poisonbolt",
]
TRAIL_CLIP_NAME = "KrinTrail"
# "KrinTrail" (the export-table name) resolves to sprite id 3 - a 1-frame
# wrapper whose single frame only ever shows its child's (sprite id 2)
# own alpha=0 starting keyframe. The real 33-frame fade-in/fade-out
# content is sprite id 2 itself, which has no export name of its own
# (only reachable by id, not by name) - fetched directly rather than
# through resolve(), since this is the only clip needing that.
TRAIL_SPRITE_ID = 2


# How far apart the horizontal and the vertical half-padding may fall, in
# natural px, before a clip is reported as an outlier. The padding is the
# glow footprint ffdec baked into the canvas, and a glow spreads the same
# distance on both axes, so the two halves should agree; when they don't,
# the clip's bounds are wrong rather than the padding being lopsided. 13
# clips diverged by 4.3 to 38.0 px before make_timeline_bounds learned to
# read morph shapes and to stop borrowing the next tag's matrix.
PAD_SYMMETRY_TOLERANCE = 1.0


def sanitize(label: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_").lower()


def _impact_names() -> list[str]:
    moves = json.loads(
        (REPO_ROOT / "dev" / "converted_json" / "moves_abilities.json").read_text()
    )
    names = set()
    for move in moves:
        name = move.get("13_impact_effect_name")
        if isinstance(name, str) and name:
            names.add(name)
    return sorted(names)


def clip_offset(frame: render.Frame):
    """-> ({"x", "y", "w", "h"}, pad_x, pad_y) for a clip from its frame 1,
    or None when its displayRect is empty. The two paddings are the symmetry
    self-check's input, not part of the written record."""
    x0, y0, x1, y1 = frame.display_rect
    if x1 == x0 or y1 == y0:
        return None
    real_w = frame.size[0] / ZOOM
    real_h = frame.size[1] / ZOOM
    computed_w = (x1 - x0) / 20.0
    computed_h = (y1 - y0) / 20.0
    computed_cx = (x0 + x1) / 2.0 / 20.0
    computed_cy = (y0 + y1) / 2.0 / 20.0
    offset = {
        "x": round(computed_cx - real_w / 2.0, 2),
        "y": round(computed_cy - real_h / 2.0, 2),
        "w": round(real_w, 2),
        "h": round(real_h, 2),
    }
    return offset, (real_w - computed_w) / 2.0, (real_h - computed_h) / 2.0


def main():
    index = read_swf(WEB_SWF)
    ci_exports = {k.lower(): (k, v) for k, v in index.exports.items()}

    def resolve(name: str):
        hit = ci_exports.get(name.lower())
        return hit[1] if hit else None

    clips: list[tuple[str, int, str]] = []
    unresolved = []

    def collect(names, category, resolve_id=resolve):
        seen_ids: dict[int, str] = {}
        for name in names:
            cid = resolve_id(name)
            if cid is None or not index.sprite_frames.get(cid):
                unresolved.append(name)
                continue
            if cid in seen_ids:
                # Same clip already listed under a different casing (e.g.
                # KRIN.MAGICBOLT after Krin.Magicbolt) - sanitize()+lower()
                # would write the same folder anyway.
                continue
            seen_ids[cid] = name
            clips.append((name, cid, category))

    collect(BOLT_NAMES, "bolts")
    collect([TRAIL_CLIP_NAME], "trail", resolve_id=lambda _name: TRAIL_SPRITE_ID)
    collect(_impact_names(), "impacts")

    jobs = [
        render.Job(cid, frame, ZOOM)
        for cid in dict.fromkeys(cid for _name, cid, _category in clips)
        for frame in range(1, index.sprite_frames[cid] + 1)
    ]
    offsets = {}
    outliers = []
    offset_ids: set[int] = set()
    with render.frames(WEB_SWF, jobs) as rendered:
        by_clip: dict[int, list[render.Frame]] = {}
        for frame in rendered:
            by_clip.setdefault(frame.job.timeline, []).append(frame)
        for name, cid, category in clips:
            out_dir = VFX_DIR / category / sanitize(name)
            out_dir.mkdir(parents=True, exist_ok=True)
            for n, frame in enumerate(by_clip[cid], start=1):
                shutil.copyfile(frame.path, out_dir / f"{n}.png")
            # A clip that a bolt name and an impact name both resolve to gets
            # an offset under its first name only, as vfx_offsets.py did, so
            # vfx_scenes.py skips the second folder.
            if cid in offset_ids and category != "trail":
                continue
            offset_ids.add(cid)
            computed = clip_offset(by_clip[cid][0])
            if computed is None:
                unresolved.append(name)
                continue
            offset, pad_x, pad_y = computed
            if abs(pad_x - pad_y) > PAD_SYMMETRY_TOLERANCE:
                outliers.append(
                    f"{sanitize(name)} (pad_x={pad_x:.2f}, pad_y={pad_y:.2f})"
                )
            offsets[sanitize(name)] = offset

    OFFSETS.write_text(json.dumps(offsets, indent=1, sort_keys=True))
    print(f"clips written: {len(clips)}", file=sys.stderr)
    print(f"clip offsets: {len(offsets)}", file=sys.stderr)
    if unresolved:
        print(f"unresolved: {unresolved}", file=sys.stderr)
    if outliers:
        print(
            f"asymmetric glow padding - the clip bounds look wrong for: {outliers}",
            file=sys.stderr,
        )


if __name__ == "__main__":
    main()
