# The original ability/move icon sheet: DefineSprite 2427, one labeled frame
# per move (equipped bar, unequipped pool, AND skill-tree nodes all draw
# from this one clip) PLUS one labeled frame per passive-node buff family
# (e.g. "SAVAGERY", "INTEGRITY") - the talent tree's passive nodes use the
# same sheet, keyed by buff family name instead of move display name.
# Writes assets/ui/abilities/<label>.png at 2x.
# Confirmed 2026-07-23: all 69 active move ids and all 14 passive buff
# families actually used in TalentTree.TREES have a matching label - no
# fallback-art path is needed for anything currently in the trees.
#
# Each frame is exported through ffdec's own sprite renderer, not
# reassembled shape-by-shape. An earlier version of this script pasted each
# frame's shapes onto a canvas by hand and lost three separate things that
# live on the PlaceObject tags rather than on the raw shapes:
#
#   1. The clip mask. Every labeled frame places DefineShape 2242 - a 23x23px
#      circle - with a clipDepth covering the depths the icon art sits on
#      (depth 3 covering depths 4-8 on most frames; a second arrangement at
#      depth 1 covering depth 2 also appears). The art itself is much larger
#      than that circle - "Break"'s streak, DefineShape 2256, measures 47x30px
#      - so without the mask it visibly spilled outside the orb.
#   2. The surface filters. "Break"'s depth-6 placement carries a white
#      GLOWFILTER (blurX/blurY 5.0, strength 1.0) that draws the streak's halo.
#   3. The radial gradient fills that shade the orb, its rim and its highlight.
#
# Same root cause and fix as item_icons.py and faces.py, both of which were
# converted away from hand-compositing for exactly these reasons.
#
# Renders against the prepared extraction SWF rather than the original,
# because two characters on this sheet are opaque in the tag data but hidden
# by ActionScript at runtime and would otherwise paint over every icon. See
# prepare_extract_swf.py for which ones and the evidence.
#
# ffdec sizes every exported frame to the whole sprite timeline's union
# bounding box, so each frame comes back as a large, mostly-transparent canvas
# with the icon in one corner. The mask constrains every frame to the same
# 23.75px orb, so all 104 frames share one identical opaque region; each is
# trimmed to its own content and recentered on a 62x62 canvas, which is what
# every consumer already expects (scripts/ui/menu/abilities_window.gd and
# scripts/battle/battle_scene.gd load these by name).
#
# Requires ffdec, and the prepared SWF: uv run prepare_extract_swf
# Run: uv run extract_ability_icons
from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF_XML
from urchin_dev.swf import snapshot_timeline
from urchin_dev.swf.prepare_extract_swf import require_extract_swf

OUT_DIR = REPO_ROOT / "assets" / "ui" / "abilities"

ZOOM = 2.0
ICON_SPRITE = 2427
# The slot viewport is 31x31 design px; icons are drawn centered on (0,0).
ICON_HALF = 15.5


def sanitize(label: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_")


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed (exit {proc.returncode}): {' '.join(cmd)}\n"
            f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
        )
    return proc


def main():
    swf = require_extract_swf()
    xml = WEB_SWF_XML.read_text()
    _snaps, labels = snapshot_timeline(xml, ICON_SPRITE, set())
    print(f"icon labels: {len(labels)}", file=sys.stderr)

    size = (int(ICON_HALF * 2 * ZOOM), int(ICON_HALF * 2 * ZOOM))
    work_dir = Path(tempfile.mkdtemp(prefix="ability_icons_"))
    try:
        frames_dir = work_dir / "frames"
        # Naming every wanted frame keeps ffdec from rendering all 986 of them.
        # The "<characterId>:" prefix is required - a bare frame number selects
        # main-timeline frames instead, and this sprite's own selection is then
        # ignored. Do not use the documented "all:" prefix here: it throws a
        # NullPointerException in ffdec 26.2.1 (CommandLineArgumentParser's
        # Selection.contains unboxes a null prefix before its own null check
        # can run).
        wanted = ",".join(f"{ICON_SPRITE}:{frame}" for frame in sorted(labels.values()))
        run(
            [
                str(FFDEC),
                "-zoom",
                str(ZOOM),
                "-format",
                "sprite:png",
                "-selectid",
                str(ICON_SPRITE),
                "-select",
                wanted,
                "-export",
                "sprite",
                str(frames_dir),
                str(swf),
            ]
        )
        sprite_frames_dir = frames_dir / f"DefineSprite_{ICON_SPRITE}"

        OUT_DIR.mkdir(parents=True, exist_ok=True)
        written: dict[str, str] = {}
        missing = []
        blank = []
        oversized = []
        for label, frame in labels.items():
            src = sprite_frames_dir / f"{frame}.png"
            if not src.exists():
                missing.append((label, frame))
                continue
            img = Image.open(src).convert("RGBA")
            bbox = img.getchannel("A").getbbox()
            canvas = Image.new("RGBA", size, (0, 0, 0, 0))
            if bbox is None:
                # The empty-slot labels ("None", "Empty", "Empty2") draw
                # nothing at all; they stay a blank canvas of the usual size so
                # every consumer keeps getting one predictable icon size.
                blank.append(label)
            else:
                content = img.crop(bbox)
                if content.width > size[0] or content.height > size[1]:
                    # Nothing on this sheet is expected to outgrow the slot,
                    # so report it rather than silently trimming an icon that
                    # the mask should already have constrained.
                    oversized.append((label, content.size))
                    left = max(0, (content.width - size[0]) // 2)
                    top = max(0, (content.height - size[1]) // 2)
                    content = content.crop(
                        (
                            left,
                            top,
                            left + min(content.width, size[0]),
                            top + min(content.height, size[1]),
                        )
                    )
                canvas.alpha_composite(
                    content,
                    (
                        (size[0] - content.width) // 2,
                        (size[1] - content.height) // 2,
                    ),
                )
            file_name = sanitize(label) + ".png"
            canvas.save(OUT_DIR / file_name)
            written[label] = file_name
        print(f"icons written: {len(written)}", file=sys.stderr)
        if blank:
            print(f"blank (empty-slot labels): {blank}", file=sys.stderr)
        if missing:
            print(f"missing source frames: {missing}", file=sys.stderr)
        if oversized:
            print(f"content larger than {size}: {oversized}", file=sys.stderr)
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
