# Portrait faces from the face clip (DefineSprite 2978 - one labeled frame
# per named character; 40 labels total, covering the 5 companions + the
# player plus every named story NPC, e.g. "Doctor Hedger", "The Warden").
# Renders assets/ui/menu/portraits/<name>.png at 5x.
#
# Each frame is exported directly via ffdec's own sprite renderer
# (`-format sprite:png -selectid 2978`), not reassembled shape-by-shape.
# 2978's per-frame content includes filters/color transforms (the glow on
# some characters' eyes, e.g. Veradux) that only exist on the PlaceObject
# tags placing each shape into a composited frame, not on the raw shapes
# themselves - a shape-by-shape compositor can only carry position/scale,
# so those effects silently vanished and every portrait rendered as a
# flat, nearly-black silhouette. ffdec's own renderer bakes them in
# correctly - the same fix that turned out to apply to the cutscene
# extraction too.
#
# No further compositing needed: the decorative slot border/background
# comes from item_slot.tscn (the same reusable bordered-slot scene used
# for items/abilities everywhere else), not from anything in this clip -
# confirmed via inventory_window.tscn, where each portrait is a plain
# TextureRect (stretch_mode 5 = STRETCH_KEEP_ASPECT_CENTERED) nested inside
# an item_slot.tscn instance. An earlier version of this script pasted the
# frame chrome (sprites 333/2896/2895) onto the face directly, which just
# double-drew an unrelated decorative element on top of the face.
#
# Multiple names can label the same visual frame (e.g. "Doctor Hedger" and
# "Doctor Leath" both sit at frame 86, holding until the next label) - each
# gets its own output file, duplicated from the same source frame.
#
# ffdec sizes the export canvas to the clip's whole-timeline bounds, so a face
# lands in the middle of a canvas that is mostly transparent - at 2x that was
# a 56x76 face inside 247x237, about 93% empty. Every portrait is cropped to
# the union of all 40 frames' opaque bounds, not to its own, so all of them
# come out the same size and one slot rect renders every face at one scale.
# The scenes showing them stretch to fill (stretch_mode 0), which only holds
# while the outputs share a size.
#
# Requires ffdec (~/.local/bin/ffdec) for the sprite PNG export.
# Run: uv run extract_faces
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import parse_swf_xml, snapshot_timeline

OUT_DIR = REPO_ROOT / "assets" / "ui" / "menu" / "portraits"
ZOOM = 5.0
FACE_CLIP = 2978


def sanitize(label: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_").lower()


def union_bbox(images):
    """-> the smallest box holding every image's opaque pixels, or None when
    they are all fully transparent."""
    box = None
    for image in images:
        found = image.getchannel("A").getbbox()
        if found is None:
            continue
        box = (
            found
            if box is None
            else (
                min(box[0], found[0]),
                min(box[1], found[1]),
                max(box[2], found[2]),
                max(box[3], found[3]),
            )
        )
    return box


def main():
    xml = WEB_SWF_XML.read_text()
    _shapes, _sprites, _exports = parse_swf_xml(WEB_SWF_XML)
    _snaps, labels = snapshot_timeline(xml, FACE_CLIP, set(range(1, 400)))
    print(
        f"labels found: {len(labels)}, unique frames: {len(set(labels.values()))}",
        file=sys.stderr,
    )

    face_dir = Path(tempfile.mkdtemp(prefix="face_frames_"))
    subprocess.run(
        [
            str(FFDEC),
            "-zoom",
            str(ZOOM),
            "-format",
            "sprite:png",
            "-selectid",
            str(FACE_CLIP),
            "-export",
            "sprite",
            str(face_dir),
            str(WEB_SWF),
        ],
        check=True,
        capture_output=True,
    )
    face_frames_dir = face_dir / f"DefineSprite_{FACE_CLIP}"

    faces, missing = {}, []
    for label, frame in labels.items():
        src = face_frames_dir / f"{frame}.png"
        if not src.exists():
            missing.append((label, frame))
            continue
        faces[label] = Image.open(src).convert("RGBA")

    crop = union_bbox(faces.values())
    if crop is None:
        raise RuntimeError("every exported face frame is fully transparent")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for label, image in faces.items():
        image.crop(crop).save(OUT_DIR / f"{sanitize(label)}.png")
    print(
        f"wrote {len(faces)} portraits, cropped to {crop[2] - crop[0]}x"
        f"{crop[3] - crop[1]} from {next(iter(faces.values())).size}",
        file=sys.stderr,
    )
    if missing:
        print(f"missing source frames: {missing}", file=sys.stderr)


if __name__ == "__main__":
    main()
