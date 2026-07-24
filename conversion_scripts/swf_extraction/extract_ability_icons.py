# extract_ability_icons.py
# The original ability/move icon sheet: DefineSprite 2427, one labeled frame
# per move (equipped bar, unequipped pool, AND skill-tree nodes all draw
# from this one clip) PLUS one labeled frame per passive-node buff family
# (e.g. "SAVAGERY", "INTEGRITY") - the talent tree's passive nodes use the
# same sheet, keyed by buff family name instead of move display name.
# Composites every labeled frame at 2x into assets/ui/abilities/<label>.png.
# Confirmed 2026-07-23: all 69 active move ids and all 14 passive buff
# families actually used in TalentTree.TREES have a matching label - no
# fallback-art path is needed for anything currently in the trees.
#
# Requires ffdec for the shape exports.
# Run: uv run python3 -m conversion_scripts.swf_extraction.extract_ability_icons
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

from .. import FFDEC, REPO_ROOT, WEB_SWF_XML
from .swf_xml_lib import make_char_bounds, parse_swf_xml, snapshot_timeline

OUT_DIR = REPO_ROOT / "assets" / "ui" / "abilities"

ZOOM = 2.0
ICON_SPRITE = 2427
# The slot viewport is 31x31 design px; icons are drawn centered on (0,0).
ICON_HALF = 15.5
# Shape 1913 is the green editor-backing square behind every icon frame -
# never visible in game (the slot art sits behind the icon instead).
# Sprite 2241 is a fully-opaque black disc placed at depth 11 on every
# single labeled frame (confirmed 2026-07-23: present, identical, at the
# same depth in 103/104 labels - the one exception, "Empty2", is an unused
# utility label with no real content at all) - it sits ON TOP of the actual
# per-label icon art (depth 4/5/6) and paints over nearly all of it, which
# is why every extracted icon looked like a black circle. Never visible as
# distinct art in its own right; skip it like 1913.
SKIP_CIDS = {1913, 2241}


def sanitize(label: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_")


def main():
    xml = WEB_SWF_XML.read_text()
    shapes, sprites, _exports = parse_swf_xml(WEB_SWF_XML)
    char_bounds = make_char_bounds(shapes, sprites)

    # find total frames by snapshotting a big range; labels come along
    snaps, labels = snapshot_timeline(xml, ICON_SPRITE, set(range(1, 990)))
    print("icon frames:", len(snaps), "labels:", len(labels), file=sys.stderr)

    needed = set()

    def collect(cid):
        if cid in SKIP_CIDS:
            return
        if cid in shapes:
            needed.add(cid)
        elif cid in sprites:
            for child, _mat in sprites[cid]:
                collect(child)

    label_frames = {}
    for label, frame in labels.items():
        snap = snaps.get(frame)
        if not snap:
            continue
        label_frames[label] = snap
        for entry in snap.values():
            collect(entry["cid"])
    print("shapes needed:", len(needed), file=sys.stderr)

    shape_dir = Path(tempfile.mkdtemp(prefix="ability_icon_shapes_"))
    ids = sorted(needed)
    for i in range(0, len(ids), 400):  # keep the CLI arg length sane
        subprocess.run(
            [
                str(FFDEC),
                "-zoom",
                str(ZOOM),
                "-format",
                "shape:png",
                "-selectid",
                ",".join(str(c) for c in ids[i : i + 400]),
                "-export",
                "shape",
                str(shape_dir),
                str(REPO_ROOT / "sonny-2-2900.swf"),
            ],
            check=True,
            capture_output=True,
        )

    def paste_char(canvas, cid, mat, origin):
        if cid in SKIP_CIDS:
            return
        sx, r0, r1, sy, tx, ty = mat
        if cid in sprites:
            for child, child_mat in sprites[cid]:
                csx, _cr0, _cr1, csy, ctx, cty = child_mat
                combined = (sx * csx, 0.0, 0.0, sy * csy, tx + ctx * sx, ty + cty * sy)
                paste_char(canvas, child, combined, origin)
            return
        b = char_bounds(cid)
        path = shape_dir / ("%d.png" % cid)
        if b is None or not path.exists():
            return
        img = Image.open(path).convert("RGBA")
        if abs(sx) != 1.0 or abs(sy) != 1.0:
            img = img.resize(
                (max(1, int(img.width * abs(sx))), max(1, int(img.height * abs(sy))))
            )
        px = (b[0] / 20.0 * sx + tx / 20.0 - origin[0]) * ZOOM
        py = (b[1] / 20.0 * sy + ty / 20.0 - origin[1]) * ZOOM
        canvas.alpha_composite(img, (int(round(px)), int(round(py))))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    size = (int(ICON_HALF * 2 * ZOOM), int(ICON_HALF * 2 * ZOOM))
    written = {}
    for label, snap in label_frames.items():
        canvas = Image.new("RGBA", size, (0, 0, 0, 0))
        for depth in sorted(snap):
            entry = snap[depth]
            paste_char(
                canvas,
                entry["cid"],
                entry.get("mat", (1, 0, 0, 1, 0, 0)),
                (-ICON_HALF, -ICON_HALF),
            )
        file_name = sanitize(label) + ".png"
        canvas.save(OUT_DIR / file_name)
        written[label] = file_name
    print("icons written:", len(written), file=sys.stderr)


if __name__ == "__main__":
    main()
