# Art for the new-game class-select screen (main-timeline frame label
# "classMenu"): the three class cards in both of their states, plus the blue
# splatter background every menu screen sits on.
#
#   assets/ui/menu/class_cards/<class>_gray.png  - resting card
#   assets/ui/menu/class_cards/<class>.png       - hovered card, full color
#   assets/ui/menu/start_background.png          - the shared menu background
#
# The class name under each card is NOT part of these textures. The original
# draws it as a separate DefineEditText above the card and fills it from
# KrinLang at runtime, so scenes/main_menu.tscn carries a Label per card
# instead, and the card art stays just the card.
#
# WHICH CARD IS WHICH CLASS. The main timeline names the three card instances
# bioDis, psychoDis and hydroDis, and two of those three names are wrong. The
# button beside each card is the authority, because it sets the class the
# player actually gets: DefineButton2_2735 sets Krin.Class = 0 (CLASS[0],
# "Biological") and plays bioDis; 2737 sets 1 ("Psychological") and plays
# hydroDis; 2736 sets 2 ("Hydraulic") and plays psychoDis. CARDS below follows
# the buttons, so it reads swapped against the instance names on purpose.
#
# WHICH FRAME IS WHICH STATE. Each card is a 26-frame sprite whose art sits in
# a nested sprite, and the gray-to-color transition is a COLORMATRIXFILTER on
# that nested placement, interpolating between a luminance matrix and identity.
# The sprite has stop() on frames 1, 7 and 26, and each button's rollOver plays
# the "START" label (frame 2) while rollOut plays "STOP" (frame 8):
#
#   frame 1     resting gray, where the sprite sits until the mouse arrives
#   frames 2-6  fading in
#   frame 7     full color, where gotoAndPlay("START") stops
#   frames 8-26 fading back out to gray again
#
# So the two states to export are frames 1 and 7, not the two label frames.
# Nothing in between needs exporting: a matrix lerp applied to fixed pixels is
# the same thing as crossfading its two endpoint images, so main_menu.gd's
# _fade_card() reproduces the animation from these two PNGs alone.
#
# WHERE EACH CARD GOES. A card sprite renders onto a canvas bigger than the
# card, because the art is placed through a bevel, a glow and a drop shadow,
# and ffdec grows the canvas by the filter's dimension on both sides of the
# timeline's displayRect. Symmetric growth means the canvas keeps the
# displayRect's centre, so the centre plus the canvas size locates every
# rendered pixel without any filter math here - the same recovery doll_art.py
# does. Each PNG is then trimmed to its own opaque content and the printed
# rect says where that trimmed image belongs on the 800x575 stage.
#
# This needs an ffdec built from the jpexs master branch. Nightly build 3544
# mis-renders exactly these sprites: the biological card comes out 136 design
# px wide instead of 191 with its art leaking past its clip mask, which is a
# bevel-over-clip-mask bug rather than anything about this SWF.
#
# Run: uv run extract_start_screens
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import root_placements

OUT_MENU = REPO_ROOT / "assets" / "ui" / "menu"
CARDS_DIR = OUT_MENU / "class_cards"

# The cards are sketch art the player looks straight at, so they are rendered
# well above the window's 2x default scale. The background is a slow gradient
# stretched across the whole window and gains nothing from the same treatment.
CARD_ZOOM = 5.0
BACKGROUND_ZOOM = 2.0

FRAME_LABEL = "classMenu"
BASE_CARD_FRAME = 1
HOVER_CARD_FRAME = 7

# Class to card sprite. Read the header before "fixing" these: the sprite ids
# disagree with the instance names the SWF gives them.
CARDS = {"psychological": 2746, "biological": 2766, "hydraulic": 2755}

# Depths 1, 2 and 5 hold the background: a gradient fill, the swirl decoration
# and the paint splatter. All six menu screens (mainMenu, subMenu, nameMenu,
# dataMenu, classMenu, optionsMenu) place exactly those three characters there,
# and everything above depth 5 is that screen's own foreground.
BACKGROUND_MAX_DEPTH = 5

# The first matrix() in an exported SVG is the root group's, which carries the
# displayRect's negated minimums scaled by the export zoom.
_ROOT_MATRIX = re.compile(
    r'<g transform="matrix\('
    r"[-0-9.]+, [-0-9.]+, [-0-9.]+, [-0-9.]+, ([-0-9.]+), ([-0-9.]+)\)\""
)
_SVG_WIDTH = re.compile(r'\bwidth="([0-9.]+)px"')
_SVG_HEIGHT = re.compile(r'\bheight="([0-9.]+)px"')


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed (exit {proc.returncode}): {' '.join(cmd)}\n"
            f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
        )
    return proc


def export_cards(out_root: Path, fmt: str, frames) -> Path:
    ids = ",".join(str(c) for c in CARDS.values())
    run(
        [
            str(FFDEC),
            "-zoom",
            str(CARD_ZOOM),
            "-format",
            f"sprite:{fmt}",
            "-selectid",
            ids,
            "-select",
            ",".join(f"{c}:{f}" for c in CARDS.values() for f in frames),
            "-export",
            "sprite",
            str(out_root),
            str(WEB_SWF),
        ]
    )
    return out_root


def read_display_rect(svg_path: Path):
    """-> (x, y, w, h) of the sprite's displayRect in design px, relative to
    the sprite's own origin."""
    head = svg_path.read_text()[:2000]
    matrix = _ROOT_MATRIX.search(head)
    width = _SVG_WIDTH.search(head)
    height = _SVG_HEIGHT.search(head)
    if matrix is None or width is None or height is None:
        raise RuntimeError(f"no displayRect in {svg_path}")
    return (
        -float(matrix.group(1)) / CARD_ZOOM,
        -float(matrix.group(2)) / CARD_ZOOM,
        float(width.group(1)) / CARD_ZOOM,
        float(height.group(1)) / CARD_ZOOM,
    )


def stage_origins(placements) -> dict[str, tuple[float, float]]:
    """-> {class: (x, y)} where the main timeline places each card sprite."""
    origins = {}
    for name, cid in CARDS.items():
        placed = [e for e in placements.values() if e.get("cid") == cid]
        if len(placed) != 1:
            raise RuntimeError(f"{name} (cid {cid}) placed {len(placed)} times")
        matrix = placed[0]["mat"]
        origins[name] = (matrix[4] / 20.0, matrix[5] / 20.0)
    return origins


def content_rect(origin, display_rect, canvas, bbox):
    """The trimmed card's rect on the stage in design px, given where the sprite
    is placed, its displayRect, the canvas ffdec produced and the canvas-pixel
    bbox of what it drew there."""
    centre_x = origin[0] + display_rect[0] + display_rect[2] / 2
    centre_y = origin[1] + display_rect[1] + display_rect[3] / 2
    canvas_x = centre_x - canvas[0] / CARD_ZOOM / 2
    canvas_y = centre_y - canvas[1] / CARD_ZOOM / 2
    return (
        canvas_x + bbox[0] / CARD_ZOOM,
        canvas_y + bbox[1] / CARD_ZOOM,
        (bbox[2] - bbox[0]) / CARD_ZOOM,
        (bbox[3] - bbox[1]) / CARD_ZOOM,
    )


def write_cards(placements) -> dict[str, tuple[float, float, float, float]]:
    """Write both states of all three cards, trimmed to the card itself, and
    return each one's rect on the stage."""
    origins = stage_origins(placements)
    work = Path(tempfile.mkdtemp(prefix="class_cards_"))
    try:
        frames = (BASE_CARD_FRAME, HOVER_CARD_FRAME)
        export_cards(work / "svg", "svg", (BASE_CARD_FRAME,))
        export_cards(work / "png", "png", frames)

        CARDS_DIR.mkdir(parents=True, exist_ok=True)
        rects = {}
        for name, cid in sorted(CARDS.items()):
            display_rect = read_display_rect(
                work / "svg" / f"DefineSprite_{cid}" / f"{BASE_CARD_FRAME}.svg"
            )
            # Both states draw the same card through the same filters, so one
            # bbox keeps the two PNGs the same size and the same rect.
            source = {
                frame: Image.open(
                    work / "png" / f"DefineSprite_{cid}" / f"{frame}.png"
                ).convert("RGBA")
                for frame in frames
            }
            base = source[BASE_CARD_FRAME]
            bbox = base.getchannel("A").getbbox()
            if bbox is None:
                raise RuntimeError(f"{name} (cid {cid}) rendered empty")
            rects[name] = content_rect(origins[name], display_rect, base.size, bbox)
            for frame, suffix in ((BASE_CARD_FRAME, "_gray"), (HOVER_CARD_FRAME, "")):
                out = CARDS_DIR / f"{name}{suffix}.png"
                image = source[frame].crop(bbox)
                image.save(out)
                print(f"wrote {out} {image.size}", file=sys.stderr)
        return rects
    finally:
        shutil.rmtree(work, ignore_errors=True)


def render_background(placements, frame_number: int, out_path: Path) -> None:
    """Draw the classMenu frame from a copy of the SWF with every foreground
    character deleted, leaving the background the menu screens share."""
    foreground = sorted(
        {
            entry["cid"]
            for depth, entry in placements.items()
            if depth > BACKGROUND_MAX_DEPTH and "cid" in entry
        }
    )
    work = Path(tempfile.mkdtemp(prefix="start_background_"))
    try:
        stripped = work / "background.swf"
        run(
            [str(FFDEC), "-removeCharacter", str(WEB_SWF), str(stripped)]
            + [str(c) for c in foreground]
        )
        frames = work / "frames"
        run(
            [
                str(FFDEC),
                "-zoom",
                str(BACKGROUND_ZOOM),
                "-format",
                "frame:png",
                "-select",
                str(frame_number),
                "-export",
                "frame",
                str(frames),
                str(stripped),
            ]
        )
        image = Image.open(frames / f"{frame_number}.png").convert("RGBA")
        image.save(out_path)
        print(
            f"wrote {out_path} {image.size} "
            f"({len(foreground)} foreground characters stripped)",
            file=sys.stderr,
        )
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    xml = WEB_SWF_XML.read_text()
    frame_number, placements = root_placements(xml, FRAME_LABEL)
    print(f"{FRAME_LABEL}: main-timeline frame {frame_number}", file=sys.stderr)

    render_background(placements, frame_number, OUT_MENU / "start_background.png")
    rects = write_cards(placements)

    print("card rects on the 800x575 stage, in design px:", file=sys.stderr)
    print(
        json.dumps(
            {
                name: {
                    "x": round(rect[0], 2),
                    "y": round(rect[1], 2),
                    "w": round(rect[2], 2),
                    "h": round(rect[3], 2),
                }
                for name, rect in sorted(rects.items())
            },
            indent=1,
            sort_keys=True,
        ),
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
