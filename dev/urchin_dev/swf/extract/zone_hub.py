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
# orb and its buttons from a working copy of the SWF leaves ffdec drawing the
# scene art alone - the same approach start_screens.py uses for the menu
# background.
#
# THE ORB ITSELF is two shapes, not three: 3196 places DefineShape3 3195 twice
# (a large arc pair, once upright and once turned a quarter turn) and 3194
# once (a smaller arc pair) on top. scenes/orb.tscn had the two shapes the
# wrong way round; ORB_LAYERS below records what the SWF actually does, and
# main() prints it so the scene can be checked against the source.
#
# Run: uv run extract_zone_hub
from __future__ import annotations

import math
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import snapshot_timeline
from urchin_dev.swf.xml_lib import find_matrix, sprite_body

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
# working copy so the hub renders as bare scene art.
ORB_BUTTONS = tuple(range(3186, 3194))

# The two shapes 3196 stacks, bottom layer first, named for what they become
# in scenes/orb.tscn.
ORB_SHAPES: dict[int, str] = {3194: "orb_arc_inner", 3195: "orb_arc_outer"}

_ITEM_TOKENS = re.compile(r"<item\b[^>]*?(/?)>|</item>")


def attribute(name: str, element: str) -> str | None:
    found = re.search(rf'{name}="([^"]*)"', element)
    return found.group(1) if found else None


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed (exit {proc.returncode}): {' '.join(cmd)}\n"
            f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
        )
    return proc


def zone_frames(xml: str) -> dict[int, int]:
    """-> {zone number: the frame of 3287 that zone's label sits on}."""
    _snaps, labels = snapshot_timeline(xml, HUB_SPRITE, set())
    missing = sorted(set(ZONE_LABELS.values()) - set(labels))
    if missing:
        raise RuntimeError(f"3287 has no frame labelled {missing}")
    return {zone: labels[label] for zone, label in ZONE_LABELS.items()}


def render_hubs(frames: dict[int, int]) -> None:
    """Draw each zone's hub frame from a copy of the SWF with the orb and its
    buttons deleted, trimmed to the scene art."""
    work = Path(tempfile.mkdtemp(prefix="zone_hub_"))
    try:
        stripped = work / "hub.swf"
        run(
            [str(FFDEC), "-removeCharacter", str(WEB_SWF), str(stripped)]
            + [str(ORB_SPRITE)]
            + [str(c) for c in ORB_BUTTONS]
        )
        wanted = sorted(set(frames.values()))
        out = work / "frames"
        run(
            [
                str(FFDEC),
                "-zoom",
                str(HUB_ZOOM),
                "-format",
                "sprite:png",
                "-selectid",
                str(HUB_SPRITE),
                "-select",
                ",".join(f"{HUB_SPRITE}:{f}" for f in wanted),
                "-export",
                "sprite",
                str(out),
                str(stripped),
            ]
        )

        HUB_DIR.mkdir(parents=True, exist_ok=True)
        rendered = out / f"DefineSprite_{HUB_SPRITE}"
        for zone, frame in sorted(frames.items()):
            image = Image.open(rendered / f"{frame}.png").convert("RGBA")
            bbox = image.getchannel("A").getbbox()
            if bbox is None:
                raise RuntimeError(
                    f"zone {zone} ({ZONE_LABELS[zone]}, frame {frame}) rendered empty"
                )
            cropped = image.crop(bbox)
            path = HUB_DIR / f"{ZONE_LABELS[zone]}.png"
            cropped.save(path)
            print(
                f"zone {zone} {ZONE_LABELS[zone]:<8} frame {frame:>3} -> "
                f"{path.name} {cropped.size}",
                file=sys.stderr,
            )
    finally:
        shutil.rmtree(work, ignore_errors=True)


def orb_layers(xml: str) -> list[tuple[int, int, tuple]]:
    """-> [(depth, characterId, matrix)] for the orb's own shapes, bottom
    layer first, read off 3196's first frame."""
    body = sprite_body(xml, ORB_SPRITE)
    layers = []
    depth = 0
    start = None
    for token in _ITEM_TOKENS.finditer(body):
        text = token.group(0)
        if text == "</item>":
            depth -= 1
            if depth == 0 and start is not None:
                element = body[start : token.end()]
                cid = attribute("characterId", element)
                place_depth = attribute("depth", element)
                if cid is not None and place_depth is not None:
                    layers.append((int(place_depth), int(cid), find_matrix(element)))
                start = None
            continue
        self_closing = bool(token.group(1))
        if depth == 0:
            if 'type="ShowFrameTag"' in text:
                break
            if "PlaceObject" in text and not self_closing:
                start = token.start()
        if not self_closing:
            depth += 1
    return sorted(layers)


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
    xml = WEB_SWF_XML.read_text()
    render_hubs(zone_frames(xml))
    export_orb_shapes()

    print("\norb layers, bottom first (scenes/orb.tscn must match):", file=sys.stderr)
    for depth, cid, matrix in orb_layers(xml):
        scale = (matrix[0] ** 2 + matrix[1] ** 2) ** 0.5
        print(
            f"  depth {depth}  {ORB_SHAPES[cid]:<14} scale {scale:.4f}  "
            f"rotation {math.degrees(math.atan2(matrix[1], matrix[0])):>7.2f} deg  "
            f"offset ({matrix[4] / 20:.2f}, {matrix[5] / 20:.2f}) px",
            file=sys.stderr,
        )


if __name__ == "__main__":
    main()
