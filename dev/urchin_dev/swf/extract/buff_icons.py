# The original per-buff icon sheet: DefineSprite 100 (nested inside
# DefineSprite 104, "KrinBuffShower", at depth 4 named "buffIcon" -
# frame42/sonny2_addNewBuffKrin.txt's buffIcon.gotoAndStop(buffId)), one
# labeled frame per buff, labeled by the buff's own internal_name (e.g.
# frame label "FIRESAM" matches buff id 1's internal_name in buffs.json
# exactly - confirmed by hand before writing this script). Writes
# assets/ui/buffs/<internal_name>.png.
#
# Same rendering approach as item_icons.py/faces.py: export the sprite
# directly via ffdec's own renderer (not reassembled shape-by-shape), then
# trim each frame to its own opaque bounds. 400 ShowFrameTags carry 419
# FrameLabelTags - some frames have more than one label (aliases); every
# label found gets its own output file pointing at that frame's content,
# so an aliased buff still gets a real icon rather than being skipped.
#
# Requires ffdec (~/.local/bin/ffdec). Run: uv run extract_buff_icons
from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import snapshot_timeline

OUT_DIR = REPO_ROOT / "assets" / "ui" / "buffs"
BUFF_ICON_SPRITE = 100
ZOOM = 2.0


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed (exit {proc.returncode}): {' '.join(cmd)}\n"
            f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
        )
    return proc


def main():
    xml = WEB_SWF_XML.read_text()
    _snaps, labels = snapshot_timeline(xml, BUFF_ICON_SPRITE, set())
    print(f"buff icon labels: {len(labels)}", file=sys.stderr)

    work_dir = Path(tempfile.mkdtemp(prefix="buff_icons_"))
    try:
        frames_dir = work_dir / "frames"
        run(
            [
                str(FFDEC),
                "-zoom",
                str(ZOOM),
                "-format",
                "sprite:png",
                "-selectid",
                str(BUFF_ICON_SPRITE),
                "-export",
                "sprite",
                str(frames_dir),
                str(WEB_SWF),
            ]
        )
        sprite_frames_dir = frames_dir / f"DefineSprite_{BUFF_ICON_SPRITE}"

        OUT_DIR.mkdir(parents=True, exist_ok=True)
        written: dict[str, str] = {}
        missing = []
        for label, frame in labels.items():
            src = sprite_frames_dir / f"{frame}.png"
            if not src.exists():
                missing.append((label, frame))
                continue
            file_name = re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_") + ".png"
            img = Image.open(src)
            bbox = img.getchannel("A").getbbox()
            img = (
                img.crop(bbox)
                if bbox is not None
                else Image.new("RGBA", (1, 1), (0, 0, 0, 0))
            )
            img.save(OUT_DIR / file_name)
            written[label] = file_name
        print(f"buff icons written: {len(written)}", file=sys.stderr)
        if missing:
            print(f"missing source frames: {missing}", file=sys.stderr)
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
