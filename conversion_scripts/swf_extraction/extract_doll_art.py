# extract_doll_art.py
# Re-renders every doll art sprite in resources/sprites/ at exactly 2x the
# design size (the window's default scale), replacing the mixed-zoom
# exports whose heavy downscale blurred the dolls. Composites each export
# name's first frame from shape renders; the Steam SWF fills names the web
# SWF lacks (DOG/WOLF/... art). doll_offsets.json keeps working because it
# derives scale from bounds/png-size - regenerate it after this
# (extract_doll_offsets.py).
#
# Run: uv run extract_doll_art
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image
from swf_xml_lib import WEB_SWF_XML, make_char_bounds, parse_swf_xml

from .. import STEAM_SWF_XML

REPO = Path(__file__).resolve().parent.parent.parent
SPRITES = REPO / "resources" / "sprites"
FFDEC = Path.home() / ".local" / "bin" / "ffdec"
WEB_SWF = REPO / "sonny-2-2900.swf"
STEAM_SWF = REPO / "SONNY2.swf"
ZOOM = 2.0


def build_renderer(xml_path: Path, swf_path: Path):
    shapes, sprites, exports = parse_swf_xml(xml_path)
    char_bounds = make_char_bounds(shapes, sprites)
    shape_dir = Path(tempfile.mkdtemp(prefix="doll_shapes_"))
    exported: set[int] = set()

    def export_shapes(needed):
        missing = sorted(set(needed) - exported)
        for i in range(0, len(missing), 400):
            subprocess.run(
                [
                    str(FFDEC),
                    "-zoom",
                    str(ZOOM),
                    "-format",
                    "shape:png",
                    "-selectid",
                    ",".join(str(c) for c in missing[i : i + 400]),
                    "-export",
                    "shape",
                    str(shape_dir),
                    str(swf_path),
                ],
                check=True,
                capture_output=True,
            )
        exported.update(missing)

    def collect(cid, acc):
        if cid in shapes:
            acc.add(cid)
        elif cid in sprites:
            for child, _mat in sprites[cid]:
                collect(child, acc)

    def paste_char(canvas, cid, mat, origin):
        sx, _r0, _r1, sy, tx, ty = mat
        if cid in sprites:
            for child, child_mat in sprites[cid]:
                csx, _c0, _c1, csy, ctx, cty = child_mat
                combined = (sx * csx, 0.0, 0.0, sy * csy, tx + ctx * sx, ty + cty * sy)
                paste_char(canvas, child, combined, origin)
            return
        b = char_bounds(cid)
        path = shape_dir / ("%d.png" % cid)
        if b is None or not path.exists():
            return
        img = Image.open(path).convert("RGBA")
        target_w = max(1, int(round((b[2] - b[0]) / 20.0 * abs(sx) * ZOOM)))
        target_h = max(1, int(round((b[3] - b[1]) / 20.0 * abs(sy) * ZOOM)))
        if (img.width, img.height) != (target_w, target_h):
            img = img.resize((target_w, target_h))
        px = (b[0] / 20.0 * sx + tx / 20.0 - origin[0]) * ZOOM
        py = (b[1] / 20.0 * sy + ty / 20.0 - origin[1]) * ZOOM
        canvas.alpha_composite(img, (int(round(px)), int(round(py))))

    def render_batch(names: list[str]) -> tuple[list[str], list[str]]:
        """Renders every name this SWF can resolve; ONE bulk shape export.
        Returns (rendered, unresolved)."""
        plans = []
        needed = set()
        unresolved = []
        for name in names:
            cid = exports.get(name)
            b = char_bounds(cid) if cid is not None else None
            if b is None:
                unresolved.append(name)
                continue
            w = int(round((b[2] - b[0]) / 20.0 * ZOOM))
            h = int(round((b[3] - b[1]) / 20.0 * ZOOM))
            if w <= 1 or h <= 1:
                unresolved.append(name)
                continue
            plans.append((name, cid, b, w, h))
            collect(cid, needed)
        export_shapes(needed)
        rendered = []
        for name, cid, b, w, h in plans:
            canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            origin = (b[0] / 20.0, b[1] / 20.0)
            paste_char(canvas, cid, (1.0, 0.0, 0.0, 1.0, 0.0, 0.0), origin)
            canvas.save(SPRITES / (name + ".png"))
            rendered.append(name)
        return rendered, unresolved

    return render_batch


def main():
    names = sorted(p.stem for p in SPRITES.glob("*.png"))
    web_batch = build_renderer(WEB_SWF_XML, WEB_SWF)
    rendered, unresolved = web_batch(names)
    done = len(rendered)
    skipped = []
    if unresolved:
        steam_batch = build_renderer(STEAM_SWF_XML, STEAM_SWF)
        steam_rendered, skipped = steam_batch(unresolved)
        done += len(steam_rendered)
    print(
        f"re-rendered: {done}, skipped (placeholders): {len(skipped)}", file=sys.stderr
    )
    if skipped:
        print("skipped:", skipped, file=sys.stderr)


if __name__ == "__main__":
    main()
