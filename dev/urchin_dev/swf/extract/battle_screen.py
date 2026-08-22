# Art for the battle screen (main-timeline frame label "KRINBATTLESCENE", root
# frame 217):
#
#   assets/backgrounds/battle/<LABEL>.png        - one hall per label of 3435
#   assets/backgrounds/sky/SKY_<LABEL>.png       - one sky per label of 3454
#   assets/ui/battle/<NAME>.png                  - the four chrome characters
#   assets/backgrounds/battle/battle_layout.json - where those sit on the stage
#
# THE HALL AND THE SKY ARE INDEPENDENT. The original drives DefineSprite 3435
# from Krin.ZoneBG and DefineSprite 3454 from Krin.SkyBG, two separate
# per-battle fields, and 16 of its 99 battles set them to different labels -
# zone 6 fights in the CHURCH hall under the ROME sky. The two label sets are
# not the same, which is why each sprite is rendered against its own labels
# rather than one shared list.
#
# WHY 2676 IS STRIPPED. Every hall label places DefineSprite 2676 six times, at
# depths 40 through 240. It is the character rig: three slots per side, the
# right side mirrored. Rendered as-is, each hall bakes in six placeholder
# fighters holding swords under "!" speech bubbles, authoring scaffolding the
# game never draws. Deleting it from a working copy leaves ffdec drawing the
# scene art alone, the same approach zone_hub.py uses for the orb.
#
# Run: uv run extract_battle_screen
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
from urchin_dev.swf import root_placements, snapshot_timeline

HALL_DIR = REPO_ROOT / "assets" / "backgrounds" / "battle"
SKY_DIR = REPO_ROOT / "assets" / "backgrounds" / "sky"
BATTLE_UI_DIR = REPO_ROOT / "assets" / "ui" / "battle"

HALL_SPRITE = 3435
SKY_SPRITE = 3454
# The character rig each hall label places six times, deleted so the halls
# render as bare scene art.
FIGHTER_RIG = 2676
# These fill the window behind everything else, so they are rendered well above
# the window's 2x default scale.
ZOOM = 4.0

# The four chrome characters the battle frame places, named for what they are.
# 3317 sits at depth 1 on the Navigation frame too, so the bottom bar is one
# shared asset rather than the two copies the repo keeps.
CHROME: dict[int, str] = {
    3317: "bottom_bar",
    3465: "top_panel",
    3460: "alert_icon",
    3455: "stage_rect",
}

LAYOUT_JSON = HALL_DIR / "battle_layout.json"
FRAME_LABEL = "KRINBATTLESCENE"

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


def sprite_label_frames(xml: str, sprite: int) -> dict[str, int]:
    """-> {frame label: frame number} for one sprite's own timeline."""
    _snaps, labels = snapshot_timeline(xml, sprite, set())
    if not labels:
        raise RuntimeError(f"sprite {sprite} has no frame labels")
    return labels


def render_labels(
    swf: Path, sprite: int, frames: dict[str, int], out_dir: Path, prefix: str
) -> None:
    """Render one sprite at each of its labelled frames, trim each to its own
    opaque content, and write <prefix><LABEL>.png into out_dir."""
    work = Path(tempfile.mkdtemp(prefix="battle_screen_"))
    try:
        wanted = sorted(set(frames.values()))
        run(
            [
                str(FFDEC),
                "-zoom",
                str(ZOOM),
                "-format",
                "sprite:png",
                "-selectid",
                str(sprite),
                "-select",
                ",".join(f"{sprite}:{f}" for f in wanted),
                "-export",
                "sprite",
                str(work),
                str(swf),
            ]
        )
        rendered = work / f"DefineSprite_{sprite}"
        out_dir.mkdir(parents=True, exist_ok=True)
        for label, frame in sorted(frames.items()):
            image = Image.open(rendered / f"{frame}.png").convert("RGBA")
            bbox = image.getchannel("A").getbbox()
            if bbox is None:
                raise RuntimeError(
                    f"sprite {sprite} label {label} (frame {frame}) rendered empty"
                )
            cropped = image.crop(bbox)
            name = f"{prefix}{label.replace(' ', '_')}.png"
            cropped.save(out_dir / name)
            print(
                f"  {label:<16} frame {frame:>3} -> {name} {cropped.size}",
                file=sys.stderr,
            )
    finally:
        shutil.rmtree(work, ignore_errors=True)


def render_chrome(swf: Path) -> None:
    """Render each chrome character's first frame, trimmed to its content."""
    work = Path(tempfile.mkdtemp(prefix="battle_chrome_"))
    try:
        ids = ",".join(str(c) for c in CHROME)
        run(
            [
                str(FFDEC),
                "-zoom",
                str(ZOOM),
                "-format",
                "sprite:png",
                "-selectid",
                ids,
                "-select",
                ",".join(f"{c}:1" for c in CHROME),
                "-export",
                "sprite",
                str(work),
                str(swf),
            ]
        )
        BATTLE_UI_DIR.mkdir(parents=True, exist_ok=True)
        for cid, name in sorted(CHROME.items()):
            image = Image.open(work / f"DefineSprite_{cid}" / "1.png").convert("RGBA")
            bbox = image.getchannel("A").getbbox()
            if bbox is None:
                raise RuntimeError(f"chrome {cid} ({name}) rendered empty")
            cropped = image.crop(bbox)
            cropped.save(BATTLE_UI_DIR / f"{name}.png")
            print(f"  {cid} -> {name}.png {cropped.size}", file=sys.stderr)
    finally:
        shutil.rmtree(work, ignore_errors=True)


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
        -float(matrix.group(1)) / ZOOM,
        -float(matrix.group(2)) / ZOOM,
        float(width.group(1)) / ZOOM,
        float(height.group(1)) / ZOOM,
    )


def content_rect(origin, display_rect, canvas, bbox):
    """The trimmed render's rect on the stage in design px, given where the
    main timeline places the sprite, its displayRect, the canvas ffdec
    produced and the canvas-pixel bbox of what it drew there.

    ffdec grows a canvas by the filter dimension on both sides of the
    displayRect, so the growth is symmetric and the canvas keeps the
    displayRect's centre. That centre plus the canvas size locates every
    rendered pixel without any filter math here.
    """
    centre_x = origin[0] + display_rect[0] + display_rect[2] / 2
    centre_y = origin[1] + display_rect[1] + display_rect[3] / 2
    canvas_x = centre_x - canvas[0] / ZOOM / 2
    canvas_y = centre_y - canvas[1] / ZOOM / 2
    return (
        canvas_x + bbox[0] / ZOOM,
        canvas_y + bbox[1] / ZOOM,
        (bbox[2] - bbox[0]) / ZOOM,
        (bbox[3] - bbox[1]) / ZOOM,
    )


def placement_origin(xml: str, character: int) -> tuple[float, float]:
    """-> where the battle frame places one character, in design px."""
    _frame, placements = root_placements(xml, FRAME_LABEL)
    placed = [e for e in placements.values() if e.get("cid") == character]
    if len(placed) != 1:
        raise RuntimeError(
            f"character {character} placed {len(placed)} times on {FRAME_LABEL}"
        )
    matrix = placed[0]["mat"]
    return (matrix[4] / 20.0, matrix[5] / 20.0)


def rect_entry(rect) -> dict[str, float]:
    """-> one (x, y, w, h) tuple as the JSON file records it."""
    return {
        "x": round(rect[0], 2),
        "y": round(rect[1], 2),
        "w": round(rect[2], 2),
        "h": round(rect[3], 2),
    }


def layout_rects(swf: Path, xml: str, sprite: int, frames: dict[str, int]) -> dict:
    """-> {label: {x, y, w, h}} on the 800x575 stage, in design px."""
    origin = placement_origin(xml, sprite)

    work = Path(tempfile.mkdtemp(prefix="battle_layout_"))
    try:
        wanted = sorted(set(frames.values()))
        select = ",".join(f"{sprite}:{f}" for f in wanted)
        for fmt in ("png", "svg"):
            run(
                [
                    str(FFDEC),
                    "-zoom",
                    str(ZOOM),
                    "-format",
                    f"sprite:{fmt}",
                    "-selectid",
                    str(sprite),
                    "-select",
                    select,
                    "-export",
                    "sprite",
                    str(work / fmt),
                    str(swf),
                ]
            )
        out = {}
        for label, frame in sorted(frames.items()):
            image = Image.open(
                work / "png" / f"DefineSprite_{sprite}" / f"{frame}.png"
            ).convert("RGBA")
            bbox = image.getchannel("A").getbbox()
            if bbox is None:
                raise RuntimeError(f"sprite {sprite} label {label} rendered empty")
            display_rect = read_display_rect(
                work / "svg" / f"DefineSprite_{sprite}" / f"{frame}.svg"
            )
            rect = content_rect(origin, display_rect, image.size, bbox)
            out[label.replace(" ", "_")] = rect_entry(rect)
        return out
    finally:
        shutil.rmtree(work, ignore_errors=True)


def chrome_rects(swf: Path, xml: str) -> dict:
    """-> {name: {x, y, w, h}} on the 800x575 stage, in design px.

    The chrome characters carry no frame labels and hold a single frame each,
    so this renders them at frame 1 instead of walking a label list the way
    layout_rects does.
    """
    origins = {cid: placement_origin(xml, cid) for cid in CHROME}
    work = Path(tempfile.mkdtemp(prefix="battle_chrome_layout_"))
    try:
        for fmt in ("png", "svg"):
            run(
                [
                    str(FFDEC),
                    "-zoom",
                    str(ZOOM),
                    "-format",
                    f"sprite:{fmt}",
                    "-selectid",
                    ",".join(str(c) for c in CHROME),
                    "-select",
                    ",".join(f"{c}:1" for c in CHROME),
                    "-export",
                    "sprite",
                    str(work / fmt),
                    str(swf),
                ]
            )
        out = {}
        for cid, name in sorted(CHROME.items()):
            image = Image.open(work / "png" / f"DefineSprite_{cid}" / "1.png").convert(
                "RGBA"
            )
            bbox = image.getchannel("A").getbbox()
            if bbox is None:
                raise RuntimeError(f"chrome {cid} ({name}) rendered empty")
            display_rect = read_display_rect(
                work / "svg" / f"DefineSprite_{cid}" / "1.svg"
            )
            out[name] = rect_entry(
                content_rect(origins[cid], display_rect, image.size, bbox)
            )
        return out
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    xml = WEB_SWF_XML.read_text()
    halls = sprite_label_frames(xml, HALL_SPRITE)
    skies = sprite_label_frames(xml, SKY_SPRITE)

    work = Path(tempfile.mkdtemp(prefix="battle_screen_swf_"))
    try:
        stripped = work / "battle.swf"
        run(
            [
                str(FFDEC),
                "-removeCharacter",
                str(WEB_SWF),
                str(stripped),
                str(FIGHTER_RIG),
            ]
        )
        print(f"halls ({len(halls)}):", file=sys.stderr)
        render_labels(stripped, HALL_SPRITE, halls, HALL_DIR, "")
        print(f"skies ({len(skies)}):", file=sys.stderr)
        render_labels(stripped, SKY_SPRITE, skies, SKY_DIR, "SKY_")
        # The layout recovery has to run against this same stripped copy,
        # while it still exists: the fighter rig's placeholder figure pokes
        # above the hall's own opaque art on 5 of the 10 hall labels, so
        # measuring against the unstripped SWF would inflate their y and h
        # past what the PNGs above were actually cropped to.
        layout = {
            "halls": layout_rects(stripped, xml, HALL_SPRITE, halls),
            "skies": layout_rects(stripped, xml, SKY_SPRITE, skies),
        }
    finally:
        shutil.rmtree(work, ignore_errors=True)

    # The chrome characters sit outside 2676, so the fighter-rig strip above
    # never touches them and they render straight off the original SWF.
    print(f"chrome ({len(CHROME)}):", file=sys.stderr)
    render_chrome(WEB_SWF)
    layout["chrome"] = chrome_rects(WEB_SWF, xml)

    LAYOUT_JSON.write_text(json.dumps(layout, indent=1, sort_keys=True) + "\n")
    print(f"wrote {LAYOUT_JSON}", file=sys.stderr)


if __name__ == "__main__":
    main()
