# The original item icon sheet: DefineSprite 2064, one labeled frame per
# item (the game does itemSlot.inner.gotoAndStop(ITEMNAME[id])). Writes
# assets/ui/items/<label>.png and nothing else. The Godot editor saves
# resources/items/*.tres in its own form, and scripts/editor/items.gd points
# each slot_image at these icons when it regenerates those files.
#
# Each frame is rendered by ffdec's own renderer through render.py, not
# reassembled shape-by-shape. An
# earlier version of this script pasted each frame's shapes onto a canvas by
# hand, reading only characterId/matrix off every PlaceObject tag - so any
# effect that lives on the PlaceObject instead of the raw shape (a
# colorTransform, a glow filter) silently vanished. Confirmed on item 592
# "Ancient Cage": the old output (assets/ui/items/Ancient_Cage.png before
# this rewrite) is missing the glowing yellow ward markings the live game
# shows, and ffdec's own render of that frame has them. Same root cause and
# fix as faces.py's portrait glow bug.
#
# Every frame in 2064 places DefineShape 1913 at depth 2 with
# clipDepth="15" - a real SWF clip mask, not editor scaffolding (an earlier
# version of this file assumed the latter and stripped it via
# -removeCharacter before export; that let ffdec render depths 2-15 fully
# unclipped, ballooning e.g. item 69 "A Broken Pipe" from a correctly-masked
# 63x63px to 101x140 - restoring the mask brought it straight back). Same
# clipping mechanic cutscenes.py's wrapper sprites use, just with the mask
# shape and the masked content siblings in one timeline instead of split
# across a wrapper/inner pair. Left untouched here so ffdec's own renderer
# applies it like every other placement.
#
# ffdec still sizes every frame's canvas to the whole sprite
# timeline's union bounding box (856 frames), so each frame comes back as
# an ~identical, mostly-transparent canvas with the masked icon - always
# ~62x62px at ZOOM=2, since the mask constrains every frame to the same
# size - in one small corner. Trimmed here to that frame's own opaque
# bounds before saving, same as faces.py does for its own (much smaller)
# per-frame canvas.
#
# Requires ffdec (~/.local/bin/ffdec), whose jars render.py's driver runs on.
# Run: uv run extract_item_icons
from __future__ import annotations

import re
import sys

from PIL import Image

from urchin_dev import REPO_ROOT, WEB_SWF, png
from urchin_dev.swf import render, timeline
from urchin_dev.swf.swf_index import read_swf

OUT_DIR = REPO_ROOT / "assets" / "ui" / "items"
ZOOM = 2.0
ICON_SPRITE = 2064


def sanitize(label: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_")


def main():
    labels = timeline.labels(read_swf(WEB_SWF), ICON_SPRITE)
    print(f"icon labels: {len(labels)}", file=sys.stderr)

    jobs = [render.Job(ICON_SPRITE, f, ZOOM) for f in sorted(set(labels.values()))]
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with render.frames(WEB_SWF, jobs) as rendered:
        by_frame = {frame.job.frame: frame for frame in rendered}
        for label, frame in labels.items():
            trimmed = render.trim(by_frame[frame])
            # Trim the mostly-transparent canvas down to this frame's own
            # content (see file header) - a couple of labels ("Nichts"/
            # "None") are the deliberately blank empty-slot icon and have no
            # content at all, so keep those as a minimal 1x1 transparent
            # pixel instead of the full untrimmed canvas.
            img = (
                trimmed.image
                if trimmed is not None
                else Image.new("RGBA", (1, 1), (0, 0, 0, 0))
            )
            png.save(img, OUT_DIR / (sanitize(label) + ".png"))
    print(f"icons written: {len(labels)}", file=sys.stderr)


if __name__ == "__main__":
    main()
