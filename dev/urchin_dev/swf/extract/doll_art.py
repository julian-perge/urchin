# Re-renders every doll art sprite in resources/sprites/ at exactly 2x the
# design size (the window's default scale), and writes the render bounds each
# one needs to be placed with to resources/sprites/doll_offsets.json. The
# Steam SWF fills names the web SWF lacks (DOG/WOLF/... art).
#
# Each sprite is exported through ffdec's own sprite renderer, not reassembled
# shape-by-shape. A hand-rolled compositor reads only characterId and matrix
# off each PlaceObject tag, so anything else living on that tag is silently
# dropped: 159 of these 789 sprites carry a surface filter and 56 carry a
# colorTransform. Same root cause and fix as item_icons.py and faces.py.
#
# Positioning these needs care, because a filter makes ffdec's canvas bigger
# than the art's own bounds - F_SHEAD_FIR's shape bounds are 12.05x19.45
# design px but its exported canvas is 32.5x39.5, since the glow is drawn
# outside the shape. So the recorded rect has to describe what was rendered,
# not what the shape geometry says, or every filtered part would be scaled
# down and shifted by the width of its own glow.
#
# ffdec's canvas is Timeline.getDisplayRectWithFilters(): the timeline's
# displayRect grown by filterDimension, subtracted from the minimums and added
# to the maximums, so the growth is symmetric on both axes (verified in
# ffdec's own Timeline.java). Symmetric growth means the canvas keeps the
# displayRect's centre, which is what recover_rect() below relies on - it
# needs no filter math of its own, only that centre and the canvas size ffdec
# actually produced.
#
# The displayRect comes from a second ffdec pass in SVG, whose root element
# carries it directly:
#
#     <svg height="38.9px" width="24.1px" ...>
#       <g transform="matrix(2.0, 0.0, 0.0, 2.0, 12.2, 29.2)">
#
# so Xmin is -tx/ZOOM and width/height give the size. xml_lib's
# make_timeline_bounds() computes the same rect in Python and was used here
# first; the two agree on all 780 sprites to within 0.06 design px, but the
# SVG pass takes 4.1s against 28.2s and is what ffdec itself will use when it
# sizes the PNG canvas, so it cannot drift from the render the way a
# reimplementation can.
#
# Run: uv run extract_doll_art
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import FFDEC, REPO_ROOT, STEAM_SWF, STEAM_SWF_XML, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import parse_swf_xml

SPRITES = REPO_ROOT / "resources" / "sprites"
OFFSETS = SPRITES / "doll_offsets.json"
ZOOM = 2.0
# ffdec rounds each canvas dimension up to a whole pixel, so a canvas can read
# as very slightly larger than its own displayRect with no filter involved.
# Anything past this much growth is a real filter.
ROUNDING_SLACK_PX = 0.75
# Keep each ffdec command line a sane length; there are 789 names in total.
BATCH = 400

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


def export_first_frames(
    swf_path: Path, cids: list[int], out_root: Path, fmt: str, suffix: str
) -> dict[int, Path]:
    """-> {characterId: that sprite's exported first frame, in `fmt`}."""
    found: dict[int, Path] = {}
    for start in range(0, len(cids), BATCH):
        chunk = cids[start : start + BATCH]
        out_dir = out_root / f"{suffix}_{start}"
        # "<characterId>:1" per sprite renders only the first frame of each.
        # The prefix is required: a bare "1" selects main-timeline frames and
        # every sprite then renders in full. Do not use the documented "all:"
        # prefix, which throws a NullPointerException in ffdec 26.2.1 because
        # Selection.contains unboxes a null prefix ahead of its own null check.
        run(
            [
                str(FFDEC),
                "-zoom",
                str(ZOOM),
                "-format",
                f"sprite:{fmt}",
                "-selectid",
                ",".join(str(c) for c in chunk),
                "-select",
                ",".join(f"{c}:1" for c in chunk),
                "-export",
                "sprite",
                str(out_dir),
                str(swf_path),
            ]
        )
        # ffdec names each directory DefineSprite_<cid> and appends the export
        # name when the sprite has one, so match on the id rather than the name.
        for child in out_dir.iterdir():
            parts = child.name.split("_")
            if len(parts) < 2 or not parts[1].isdigit():
                continue
            frame = child / f"1.{suffix}"
            if frame.exists():
                found[int(parts[1])] = frame
    return found


def read_display_rect(svg_path: Path):
    """-> (x, y, w, h) of the sprite's displayRect in design px, or None."""
    head = svg_path.read_text()[:2000]
    matrix = _ROOT_MATRIX.search(head)
    width = _SVG_WIDTH.search(head)
    height = _SVG_HEIGHT.search(head)
    if matrix is None or width is None or height is None:
        return None
    return (
        -float(matrix.group(1)) / ZOOM,
        -float(matrix.group(2)) / ZOOM,
        float(width.group(1)) / ZOOM,
        float(height.group(1)) / ZOOM,
    )


def recover_rect(centre: tuple[float, float], canvas: tuple[int, int], bbox):
    """The opaque content's rect in design px, given the displayRect's centre,
    the canvas ffdec produced, and the canvas-pixel bbox of what it drew."""
    canvas_w, canvas_h = canvas[0] / ZOOM, canvas[1] / ZOOM
    origin_x = centre[0] - canvas_w / 2
    origin_y = centre[1] - canvas_h / 2
    return (
        origin_x + bbox[0] / ZOOM,
        origin_y + bbox[1] / ZOOM,
        (bbox[2] - bbox[0]) / ZOOM,
        (bbox[3] - bbox[1]) / ZOOM,
    )


def render_swf(xml_path: Path, swf_path: Path, names: list[str]):
    """-> (rects, unresolved, grown). rects maps name to its design-px rect."""
    _shapes, sprites, exports = parse_swf_xml(xml_path)

    wanted: dict[int, str] = {}
    unresolved: list[str] = []
    for name in names:
        cid = exports.get(name)
        if cid is None or cid not in sprites:
            unresolved.append(name)
            continue
        wanted[cid] = name

    if not wanted:
        return {}, unresolved, []

    rects: dict[str, tuple[float, float, float, float]] = {}
    grown: list[str] = []
    work = Path(tempfile.mkdtemp(prefix="doll_art_"))
    try:
        cids = sorted(wanted)
        svgs = export_first_frames(swf_path, cids, work, "svg", "svg")
        spans: dict[int, tuple[float, float, float, float]] = {}
        for cid in cids:
            svg = svgs.get(cid)
            span = read_display_rect(svg) if svg is not None else None
            if span is None:
                unresolved.append(wanted[cid])
                continue
            spans[cid] = span

        pngs = export_first_frames(swf_path, sorted(spans), work, "png", "png")
        for cid, span in spans.items():
            name = wanted[cid]
            png = pngs.get(cid)
            if png is None:
                unresolved.append(name)
                continue
            img = Image.open(png).convert("RGBA")
            bbox = img.getchannel("A").getbbox()
            if bbox is None or bbox[2] - bbox[0] <= 1 or bbox[3] - bbox[1] <= 1:
                # A deliberately empty part. Leave whatever placeholder PNG is
                # already on disk alone and record no rect, which is how
                # character_visual.gd's _add_layer() detects and skips one.
                unresolved.append(name)
                continue
            x0, y0, w, h = span
            if (
                img.width / ZOOM - w > ROUNDING_SLACK_PX
                or img.height / ZOOM - h > ROUNDING_SLACK_PX
            ):
                grown.append(name)
            elif (
                img.width / ZOOM - w < -ROUNDING_SLACK_PX
                or img.height / ZOOM - h < -ROUNDING_SLACK_PX
            ):
                # Filters only ever grow the canvas, so a canvas smaller than
                # its own displayRect means the SVG and the PNG disagree about
                # this sprite and the recovered centre cannot be trusted.
                raise RuntimeError(
                    f"{name} (cid {cid}): canvas "
                    f"{img.width / ZOOM:.2f}x{img.height / ZOOM:.2f} is smaller "
                    f"than its displayRect {w:.2f}x{h:.2f} design px"
                )
            rects[name] = recover_rect((x0 + w / 2, y0 + h / 2), img.size, bbox)
            img.crop(bbox).save(SPRITES / (name + ".png"))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return rects, unresolved, grown


def main():
    names = sorted(p.stem for p in SPRITES.glob("*.png"))
    print(f"doll sprites on disk: {len(names)}", file=sys.stderr)

    rects, unresolved, grown = render_swf(WEB_SWF_XML, WEB_SWF, names)
    print(
        f"web SWF: {len(rects)} rendered, {len(grown)} grown by a filter",
        file=sys.stderr,
    )

    if unresolved:
        steam_rects, unresolved, steam_grown = render_swf(
            STEAM_SWF_XML, STEAM_SWF, sorted(unresolved)
        )
        rects.update(steam_rects)
        grown.extend(steam_grown)
        print(
            f"steam SWF: {len(steam_rects)} rendered, "
            f"{len(steam_grown)} grown by a filter",
            file=sys.stderr,
        )

    OFFSETS.write_text(
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
        )
    )
    print(f"wrote {OFFSETS} ({len(rects)} entries)", file=sys.stderr)
    print(
        f"skipped (placeholders / not in either SWF): {len(unresolved)}",
        file=sys.stderr,
    )
    if unresolved:
        print(f"skipped: {sorted(unresolved)}", file=sys.stderr)


if __name__ == "__main__":
    main()
