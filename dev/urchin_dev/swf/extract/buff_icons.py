# The original per-buff icon sheet: DefineSprite 100 (nested inside
# DefineSprite 104, "KrinBuffShower", at depth 4 named "buffIcon" -
# frame42/sonny2_addNewBuffKrin.txt:365's buffIcon.gotoAndStop(buffId)),
# labeled by the buff's own internal_name. Writes
# assets/ui/buffs/<internal_name>.png.
#
# The buffId handed to that gotoAndStop() is a name string, so Flash
# resolves it as a frame label. It is not a frame number, and buffs.json's
# numeric `id` never reaches the sheet at all - that id is only the order
# the game's 470 addNewBuffKrin calls run in. Three citations, since the
# call reads like a numeric one:
#   1. Buffs are registered under their name -
#      addNewBuffKrin("TWINGUARDIANS", ...) at
#      frame42/sonny2_addNewBuffKrin.txt:543 and 469 more calls like it,
#      each doing _root["KRINBUFF" + a] = new Array().
#   2. Moves hand that same string to applyBuffKrin - frame217's
#      applyBuffKrin(mToBeBuffed, mAry2[13], 1, mCaster), where mAry2[13]
#      is 13_status_effect_id in converted_json/moves_abilities.json: a
#      buff internal_name for 453 of 479 moves, plain 0 (no buff) for the
#      remaining 26.
#   3. applyBuffKrin stores it verbatim (buffId = bn, line 161), and every
#      later read concatenates instead of indexing -
#      _root["KRINBUFF" + buffId][0] is the tooltip title, [1] the element
#      (lines 368-376).
#
# The sheet's own shape agrees: 400 frames hold 33 distinct drawings, 144
# frames carry labels, and every frame where the drawing changes is one of
# the labeled ones. The author labeled the buffs that share each drawing
# (8 share frame 1) rather than drawing 470 separate icons. Reading the id
# as a frame number instead lands on the same drawing the author's own
# label picked for 9 of 410 buffs, which is chance, and sends every id past
# 400 to the last frame, a "?" placeholder.
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


# Same sanitize step as item_icons.py's own sanitize() - named here (it used
# to be inlined) so buff_icons.gd's BuffIcons._sanitize() has one place to
# cite as the source of truth instead of two languages agreeing by luck.
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
            file_name = sanitize(label) + ".png"
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
