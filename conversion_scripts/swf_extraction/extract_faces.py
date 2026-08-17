# extract_faces.py
# Portrait faces from the face clip (DefineSprite 2978 - one labeled frame
# per character: party ids 1-5 are frames 1-5, the player is 'mainPlayer')
# composited with the portrait chrome (sprite 2979: bg shape 333, frame
# shapes 2895/2896). Renders assets/ui/menu/portraits/<name>.png at 2x.
#
# Requires ffdec (~/.local/bin/ffdec) for the shape PNG exports.
# Run: uv run extract_faces
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image
from swf_xml_lib import make_char_bounds, parse_swf_xml, snapshot_timeline

from conversion_scripts import FFDEC, REPO_ROOT, WEB_SWF, WEB_SWF_XML

OUT_DIR = REPO_ROOT / "assets" / "ui" / "menu" / "portraits"
ZOOM = 2.0

FACE_CLIP = 2978
CHROME = (333, 2896, 2895)  # bg, frame, frame overlay
# face clip frame -> portrait name (party ids 1-5 + the player)
FACE_FRAMES = {
    1: "veradux",
    2: "roald",
    3: "felicity",
    4: "wolfgang",
    5: "amber",
    6: "sonny",
}


def main():
    xml = WEB_SWF_XML.read_text()
    shapes, sprites, _exports = parse_swf_xml(WEB_SWF_XML)
    char_bounds = make_char_bounds(shapes, sprites)
    snaps, labels = snapshot_timeline(xml, FACE_CLIP, set(FACE_FRAMES))
    print("labels sample:", dict(list(labels.items())[:8]), file=sys.stderr)

    needed = set()

    def collect(cid):
        if cid in shapes:
            needed.add(cid)
        elif cid in sprites:
            for child, _mat in sprites[cid]:
                collect(child)

    for snap in snaps.values():
        for entry in snap.values():
            collect(entry["cid"])
    for cid in CHROME:
        collect(cid)

    shape_dir = Path(tempfile.mkdtemp(prefix="face_shapes_"))
    subprocess.run(
        [
            str(FFDEC),
            "-zoom",
            str(ZOOM),
            "-format",
            "shape:png",
            "-selectid",
            ",".join(str(c) for c in sorted(needed)),
            "-export",
            "shape",
            str(shape_dir),
            str(WEB_SWF),
        ],
        check=True,
        capture_output=True,
    )

    def paste_char(canvas, cid, mat, origin):
        sx, _r0, _r1, sy, tx, ty = mat
        if cid in sprites:
            for child, child_mat in sprites[cid]:
                csx, _cr0, _cr1, csy, ctx, cty = child_mat
                combined = (sx * csx, 0.0, 0.0, sy * csy, tx + ctx * sx, ty + cty * sy)
                paste_char(canvas, child, combined, origin)
            return
        b = char_bounds(cid)
        path = shape_dir / f"{cid:d}.png"
        if b is None or not path.exists():
            return
        img = Image.open(path).convert("RGBA")
        if sx != 1.0 or sy != 1.0:
            img = img.resize(
                (max(1, int(img.width * abs(sx))), max(1, int(img.height * abs(sy))))
            )
        px = (b[0] / 20.0 * sx + tx - origin[0]) * ZOOM
        py = (b[1] / 20.0 * sy + ty - origin[1]) * ZOOM
        canvas.alpha_composite(img, (int(round(px)), int(round(py))))

    frame_bounds = char_bounds(2896)
    origin = (frame_bounds[0] / 20.0, frame_bounds[1] / 20.0)
    size = (
        int((frame_bounds[2] - frame_bounds[0]) / 20.0 * ZOOM),
        int((frame_bounds[3] - frame_bounds[1]) / 20.0 * ZOOM),
    )

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for frame, name in FACE_FRAMES.items():
        canvas = Image.new("RGBA", size, (0, 0, 0, 255))
        paste_char(canvas, CHROME[0], (1, 0, 0, 1, 0, 0), origin)
        for depth in sorted(snaps.get(frame, {})):
            entry = snaps[frame][depth]
            paste_char(
                canvas, entry["cid"], entry.get("mat", (1, 0, 0, 1, 0, 0)), origin
            )
        paste_char(canvas, CHROME[1], (1, 0, 0, 1, 0, 0), origin)
        paste_char(canvas, CHROME[2], (1, 0, 0, 1, 0, 0), origin)
        out = OUT_DIR / f"{name}.png"
        canvas.save(out)
        print("wrote", out, size, file=sys.stderr)


if __name__ == "__main__":
    main()
