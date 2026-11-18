# The Speech bubble (DefineSprite 2674), the "!" bubble that the fighter rig
# (DefineSprite 2676) holds over the doll's head under the instance name
# `speech`, and that the conductor plays on the speaker for each line
# (frame_217/PlaceObject2_3389_480 enterFrame, line 842):
#
#   assets/ui/battle/speech_bubble/<n>.png            frame n of the clip, all
#                                                     of its frames cut to one box
#   assets/ui/battle/speech_bubble/speech_bubble.json the frame rate, the frames,
#                                                     that box's rect around the
#                                                     clip's own origin and where
#                                                     the rig places the clip
#
# The clip works as the Shield clip does: frame 1 shows nothing and runs stop(),
# and play() runs it through its 57 frames before it loops back to frame 1. The
# bubble grows in over frames 2 to 8, the "!" flashes as it grows over frames 8
# to 14, and the whole bubble fades out over frames 39 to 57. rig_clip() checks
# the stop() and the frames the playhead covers, and every frame is rendered
# whole, as extract_shield_clip does.
#
# THE RIG MIRRORS THE CLIP. The rig places the clip at (-10.65, -64.3) with an
# x scale of -1, which a rect cannot carry. So the frames are rendered around
# the clip's own origin and the JSON gives the place and the mirror, and the
# Fighter presenter puts the node there.
#
# Run: uv run extract_speech_bubble
from __future__ import annotations

import json
import sys

from urchin_dev import REPO_ROOT, WEB_SWF, png
from urchin_dev.swf import render, timeline
from urchin_dev.swf.extract.battle_screen import FIGHTER_RIG, rect_entry
from urchin_dev.swf.extract.shield_clip import rig_clip
from urchin_dev.swf.swf_index import read_swf

OUT_DIR = REPO_ROOT / "assets" / "ui" / "battle" / "speech_bubble"
LAYOUT_JSON = OUT_DIR / "speech_bubble.json"
ZOOM = 2.0
CLIP = "speech"


def rig_placement(index, rig: int, name: str) -> tuple[float, float]:
    """-> where `rig`'s frame 1 places its clip `name`, in design px. Raises
    unless the clip is mirrored in x and not scaled or turned otherwise, which
    is what the Fighter presenter reproduces."""
    (layer,) = [
        layer for layer in timeline.frames(index, rig)[0].values() if layer.name == name
    ]
    a, b, c, d, tx, ty = layer.matrix
    if (a, b, c, d) != (-1.0, 0.0, 0.0, 1.0):
        raise RuntimeError(f"rig {rig} places {name} with {layer.matrix}")
    return tx / render.TWIPS, ty / render.TWIPS


def main():
    index = read_swf(WEB_SWF)
    sprite = rig_clip(index, FIGHTER_RIG, CLIP)
    count = index.sprite_frames[sprite]
    place = rig_placement(index, FIGHTER_RIG, CLIP)

    jobs = [render.Job(sprite, frame, ZOOM) for frame in range(1, count + 1)]
    with render.frames(WEB_SWF, jobs) as rendered:
        pieces = render.trim_union(rendered)
        if pieces is None:
            raise RuntimeError(f"{CLIP} ({sprite}) rendered empty")
        rects = {piece.rect for piece in pieces}
        if len(rects) != 1:
            raise RuntimeError(f"{CLIP} ({sprite}) frames sit in {len(rects)} boxes")
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        pngs = []
        for frame, piece in enumerate(pieces, start=1):
            file_name = f"{frame}.png"
            png.save(piece.image, OUT_DIR / file_name)
            pngs.append(file_name)
        print(f"  {CLIP}: sprite {sprite}, {count} frames", file=sys.stderr)

    layout = {
        "fps": index.frame_rate,
        "frames": pngs,
        "mirrored": True,
        "place": {"x": place[0], "y": place[1]},
        "rect": rect_entry(rects.pop()),
    }
    LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
    print(f"wrote {LAYOUT_JSON}", file=sys.stderr)


if __name__ == "__main__":
    main()
