# extract_model1_animations.py
# The original MODEL1 keyframe animations: per-frame full affine matrices
# for the 15 named doll parts across all 371 timeline frames (classic
# tweens are baked into per-frame PlaceObject matrices by the Flash
# exporter). Output: resources/sprites/model1_animations.json
#   {"fps": 30, "labels": {name: {"start": 1-based, "end": inclusive}},
#    "frames": [ {part: [a, b, c, d, tx_px, ty_px]}, ... ]}
# where the matrix columns are Godot Transform2D's x=(a,b), y=(c,d),
# origin=(tx,ty) - translations converted from twips to px.
#
# Run: uv run python3 conversion_scripts/swf_extraction/extract_model1_animations.py
from __future__ import annotations

import json
import sys

from swf_xml_lib import snapshot_timeline

from .. import REPO_ROOT, WEB_SWF_XML

OUT = REPO_ROOT / "resources" / "sprites" / "model1_animations.json"
MODEL_SPRITE = 166
TOTAL_FRAMES = 371
FPS = 30.0

PART_NAMES = {
    "head",
    "chest",
    "arm1",
    "arm2",
    "hand1",
    "hand2",
    "leg1",
    "leg2",
    "leg3",
    "leg4",
    "foot1",
    "foot2",
    "weapon1",
    "weapon2",
    "shoulder",
}


def main():
    xml = WEB_SWF_XML.read_text()
    snaps, labels = snapshot_timeline(
        xml, MODEL_SPRITE, set(range(1, TOTAL_FRAMES + 1))
    )
    frame_count = max(snaps)
    print("frames:", frame_count, "labels:", labels, file=sys.stderr)

    ordered = sorted(labels.items(), key=lambda kv: kv[1])
    label_ranges = {}
    for i, (name, start) in enumerate(ordered):
        end = (ordered[i + 1][1] - 1) if i + 1 < len(ordered) else frame_count
        label_ranges[name] = {"start": start, "end": end}

    frames = []
    for frame in range(1, frame_count + 1):
        snap = snaps.get(frame, {})
        pose = {}
        for entry in snap.values():
            part = entry.get("name", "")
            if part not in PART_NAMES:
                continue
            a, b, c, d, tx, ty = entry.get("mat", (1.0, 0.0, 0.0, 1.0, 0.0, 0.0))
            pose[part] = [
                round(a, 4),
                round(b, 4),
                round(c, 4),
                round(d, 4),
                round(tx / 20.0, 2),
                round(ty / 20.0, 2),
            ]
        frames.append(pose)

    OUT.write_text(json.dumps({"fps": FPS, "labels": label_ranges, "frames": frames}))
    sizes = {name: r["end"] - r["start"] + 1 for name, r in label_ranges.items()}
    print("label frame counts:", sizes, file=sys.stderr)
    print("wrote", OUT, file=sys.stderr)


if __name__ == "__main__":
    main()
