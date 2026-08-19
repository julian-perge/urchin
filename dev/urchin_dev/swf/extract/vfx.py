# Battle VFX extraction: 15 Missile bolt clips + KrinTrail + every real
# BOOM_*/ex_* impact clip referenced by moves_abilities.json's
# 13_impact_effect_name (frame_42/DoAction_4.as's krinBoltMake) - all
# shape/tween DefineSprites with no ActionScript of their own.
#
# Every frame of a clip renders onto ffdec's own consistent per-clip
# canvas (confirmed: a real 25-frame BOOM_SPARKBLUE export came back as
# 382x317 on every single frame), so packing is pure relocation - paste
# each already-identical-size frame side by side into one wider strip.
# No cropping, no resizing, no recoloring of any frame's pixel content.
#
# Clip names are resolved against the SWF's ExportAssetsTag table
# case-insensitively - two of the 15 bolt names (KRIN.MAGICBOLT,
# KRIN.POISONBOLT) are just differently-cased references to
# Krin.Magicbolt/Krin.Poisonbolt (Flash's attachMovie linkage lookup is
# case-insensitive; both variants resolve to the same sprite id).
# sanitize()+lower() collapses both casings onto one output file -
# BuffIcons._sanitize()'s exact GDScript mirror of this convention is
# the template; Projectile/ImpactEffect apply the identical transform
# at runtime so a move's own (possibly differently-cased)
# animation_label/impact_effect_name string always resolves to the
# file this script wrote.
#
# 5 impact_effect_name values referenced by real moves don't exist in
# this SWF's export table at all: BOOM_DARK2, BOOM_DOWN_BLUE,
# BOOM_DOWN_PURPLE, BOOM_PURPLE, BOOM_SUN. A real content gap in the
# source, not a bug here - printed as unresolved and skipped; those
# moves simply show no impact effect (ImpactEffect.play() already
# no-ops on a missing file).
#
# Requires ffdec (~/.local/bin/ffdec). Run: uv run extract_vfx
from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import parse_swf_xml

ZOOM = 2.0
FPS = 30.0

BOLT_NAMES = [
    "KRIN.BLADEWHITE", "KRIN.POISONBOLT2", "KRIN.REDBLADE", "KRIN.REDBOLT",
    "KRIN.SHADOWBLADE", "KRIN.SHADOWSHOCK", "KRIN.YELLOWBLADE",
    "Krin.Electrobolt", "Krin.Electrobolt2", "Krin.Firebolt", "Krin.Iceball",
    "Krin.Iceblade", "Krin.Icebolt", "Krin.Magicbolt", "Krin.Poisonbolt",
]
TRAIL_CLIP_NAME = "KrinTrail"
# "KrinTrail" (the export-table name) resolves to sprite id 3 - a 1-frame
# wrapper whose single frame only ever shows its child's (sprite id 2)
# own alpha=0 starting keyframe. The real 33-frame fade-in/fade-out
# content is sprite id 2 itself, which has no export name of its own
# (only reachable by id, not by name) - fetched directly rather than
# through resolve(), since this is the only clip needing that.
TRAIL_SPRITE_ID = 2


def sanitize(label: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_").lower()


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed (exit {proc.returncode}): {' '.join(cmd)}\n"
            f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
        )
    return proc


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


def _extract_clip(name: str, cid: int, work_dir: Path, out_dir: Path) -> bool:
    frames_dir = work_dir / f"frames_{cid}"
    run(
        [
            str(FFDEC),
            "-zoom",
            str(ZOOM),
            "-format",
            "sprite:png",
            "-selectid",
            str(cid),
            "-export",
            "sprite",
            str(frames_dir),
            str(WEB_SWF),
        ]
    )
    sprite_dirs = list(frames_dir.glob(f"DefineSprite_{cid}*"))
    if not sprite_dirs:
        return False
    frame_files = sorted(sprite_dirs[0].glob("*.png"), key=lambda p: int(p.stem))
    if not frame_files:
        return False
    first = Image.open(frame_files[0])
    frame_width, frame_height = first.size
    sheet = Image.new(
        "RGBA", (frame_width * len(frame_files), frame_height), (0, 0, 0, 0)
    )
    for i, path in enumerate(frame_files):
        frame = Image.open(path).convert("RGBA")
        sheet.paste(frame, (i * frame_width, 0))
    out_dir.mkdir(parents=True, exist_ok=True)
    key = sanitize(name)
    sheet.save(out_dir / f"{key}.png")
    (out_dir / f"{key}.json").write_text(
        json.dumps(
            {
                "frame_count": len(frame_files),
                "frame_width": frame_width,
                "frame_height": frame_height,
                "fps": FPS,
            },
            indent=2,
        )
    )
    return True


def main():
    _shapes, _sprites, exports = parse_swf_xml(WEB_SWF_XML)
    ci_exports = {k.lower(): (k, v) for k, v in exports.items()}

    def resolve(name: str):
        hit = ci_exports.get(name.lower())
        return hit[1] if hit else None

    work_dir = Path(tempfile.mkdtemp(prefix="vfx_"))
    unresolved = []
    written = 0

    def extract_category(names, out_dir, resolve_id=resolve):
        nonlocal written
        seen_ids: dict[int, str] = {}
        for name in names:
            cid = resolve_id(name)
            if cid is None:
                unresolved.append(name)
                continue
            if cid in seen_ids:
                # Same clip already extracted this run under a different
                # casing (e.g. KRIN.MAGICBOLT after Krin.Magicbolt) -
                # sanitize()+lower() would write the same filename anyway,
                # so re-running ffdec on it is wasted work, not a bug.
                continue
            seen_ids[cid] = name
            if _extract_clip(name, cid, work_dir, out_dir):
                written += 1
            else:
                unresolved.append(name)

    extract_category(BOLT_NAMES, REPO_ROOT / "assets" / "vfx" / "bolts")
    extract_category(
        [TRAIL_CLIP_NAME],
        REPO_ROOT / "assets" / "vfx" / "trail",
        resolve_id=lambda _name: TRAIL_SPRITE_ID,
    )
    extract_category(_impact_names(), REPO_ROOT / "assets" / "vfx" / "impacts")

    print(f"clips written: {written}", file=sys.stderr)
    if unresolved:
        print(f"unresolved: {unresolved}", file=sys.stderr)


if __name__ == "__main__":
    main()
