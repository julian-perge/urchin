# Art for the zone hub screen (main-timeline frame label "Navigation", which
# places DefineSprite 3287 at stage (400.00, 222.90)):
#
#   assets/backgrounds/hub/<LABEL>.png  - one hub scene per zone
#   assets/ui/orbs/orb_arc_inner.png    - the orb's inner arc pair
#   assets/ui/orbs/orb_arc_outer.png    - the orb's outer arc pair
#
# WHICH FRAME IS WHICH ZONE. 3287 holds 190 frames under 12 labels, and the
# root maps a zone onto one of them by name, not by order:
#
#   Krin.zoneName = ["EMPTY","PRISON","VILLAGE","TRAIN","TUNNELS","CITY",
#                    "ROME","JAPAN","UTOPIA","JAPAN","STORM","EDEN","DOME",
#                    "BETA"]                      (frame_41/DoAction_2.as)
#
# indexed by Krin.sectionIn, so zone 5 is CITY and not the third label, and
# zones 6 and 7 are ROME and JAPAN. ZONE_LABELS below is that array's first
# eight entries. The other labels (CASINO, UTOPIA, EDEN, STORM) render empty
# in the web build - no zone reaches them - and BETA is a debug screen.
#
# WHY THE ORBS ARE STRIPPED. Each hub frame places DefineSprite 3196, the
# spinning orb, once per interactive spot, plus a DefineButton2 for each one.
# Godot draws those as its own orb.tscn nodes at positions the zone scenes
# already carry, so the background has to come out without them. Deleting the
# orb and its buttons before the render leaves ffdec drawing the
# scene art alone - the same approach start_screens.py uses for the menu
# background.
#
# THE ORB ITSELF is two shapes, not three: 3196 places DefineShape3 3195 twice
# (a large arc pair, once upright and once turned a quarter turn) and 3194
# once (a smaller arc pair) on top. scenes/orb.tscn had the two shapes the
# wrong way round, so main() prints 3196's first frame and the scene can be
# checked against the source.
#
# Run: uv run extract_zone_hub
from __future__ import annotations

import math
import shutil
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF
from urchin_dev.run import run
from urchin_dev.swf import render, strip, timeline
from urchin_dev.swf.swf_index import SwfIndex, read_swf

HUB_DIR = REPO_ROOT / "assets" / "backgrounds" / "hub"
ORB_DIR = REPO_ROOT / "assets" / "ui" / "orbs"

HUB_SPRITE = 3287
ORB_SPRITE = 3196
# The hub fills the window behind everything else, so it is rendered well
# above the window's 2x default scale. The orb arcs are small and spin, so
# they get more still.
HUB_ZOOM = 4.0
ORB_ZOOM = 5.0

# Zone number to the frame label the root selects for it, from Krin.zoneName
# (see the header). Index 0 of that array is "EMPTY" and is not a zone.
ZONE_LABELS: dict[int, str] = {
    1: "PRISON",
    2: "VILLAGE",
    3: "TRAIN",
    4: "TUNNELS",
    5: "CITY",
    6: "ROME",
    7: "JAPAN",
}

# The orb and the buttons sitting on each of its spots. Deleted from the
# render so the hub comes out as bare scene art.
ORB_BUTTONS = tuple(range(3186, 3194))
HUB_STRIP: dict[int, str] = {
    ORB_SPRITE: "the spinning orb, which scenes/orb.tscn draws instead",
    **{cid: "the button on an orb spot" for cid in ORB_BUTTONS},
}

# The two shapes 3196 stacks, bottom layer first, named for what they become
# in scenes/orb.tscn.
ORB_SHAPES: dict[int, str] = {3194: "orb_arc_inner", 3195: "orb_arc_outer"}


def zone_frames(index: SwfIndex) -> dict[int, int]:
    """-> {zone number: the frame of 3287 that zone's label sits on}."""
    return {
        zone: timeline.frame_of(index, HUB_SPRITE, label)
        for zone, label in ZONE_LABELS.items()
    }


def render_hubs(frames: dict[int, int]) -> None:
    """Draw each zone's hub frame with the orb and its buttons deleted,
    trimmed to the scene art."""
    stripped = tuple(strip.strip_list(WEB_SWF, HUB_STRIP))
    wanted = sorted(set(frames.values()))
    jobs = [render.Job(HUB_SPRITE, frame, HUB_ZOOM, strip=stripped) for frame in wanted]
    HUB_DIR.mkdir(parents=True, exist_ok=True)
    with render.frames(WEB_SWF, jobs) as rendered:
        by_frame = dict(zip(wanted, rendered, strict=True))
        for zone, frame in sorted(frames.items()):
            trimmed = render.trim(by_frame[frame])
            if trimmed is None:
                raise RuntimeError(
                    f"zone {zone} ({ZONE_LABELS[zone]}, frame {frame}) rendered empty"
                )
            path = HUB_DIR / f"{ZONE_LABELS[zone]}.png"
            trimmed.image.save(path)
            print(
                f"zone {zone} {ZONE_LABELS[zone]:<8} frame {frame:>3} -> "
                f"{path.name} {trimmed.image.size}",
                file=sys.stderr,
            )


def export_orb_shapes() -> None:
    work = Path(tempfile.mkdtemp(prefix="zone_orb_"))
    try:
        run(
            [
                str(FFDEC),
                "-zoom",
                str(ORB_ZOOM),
                "-format",
                "shape:png",
                "-selectid",
                ",".join(str(c) for c in ORB_SHAPES),
                "-export",
                "shape",
                str(work),
                str(WEB_SWF),
            ]
        )
        ORB_DIR.mkdir(parents=True, exist_ok=True)
        for cid, name in sorted(ORB_SHAPES.items()):
            image = Image.open(work / f"{cid}.png").convert("RGBA")
            bbox = image.getchannel("A").getbbox()
            if bbox is None:
                raise RuntimeError(f"orb shape {cid} rendered empty")
            cropped = image.crop(bbox)
            cropped.save(ORB_DIR / f"{name}.png")
            print(f"shape {cid} -> {name}.png {cropped.size}", file=sys.stderr)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    index = read_swf(WEB_SWF)
    render_hubs(zone_frames(index))
    export_orb_shapes()

    print("\norb layers, bottom first (scenes/orb.tscn must match):", file=sys.stderr)
    for depth, layer in sorted(timeline.frames(index, ORB_SPRITE)[0].items()):
        cid, matrix = layer.character_id, layer.matrix
        scale = (matrix[0] ** 2 + matrix[1] ** 2) ** 0.5
        print(
            f"  depth {depth}  {ORB_SHAPES[cid]:<14} scale {scale:.4f}  "
            f"rotation {math.degrees(math.atan2(matrix[1], matrix[0])):>7.2f} deg  "
            f"offset ({matrix[4] / 20:.2f}, {matrix[5] / 20:.2f}) px",
            file=sys.stderr,
        )


if __name__ == "__main__":
    main()
