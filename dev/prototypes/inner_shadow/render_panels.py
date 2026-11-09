"""Renders the three panel shapes with their inner shadow through ffdec at zoom 1 and 4
and writes 1x nine-patch sources. KRINMENU frame 1 places each shape at scale 1.

Run from the repo root (one ffdec at a time):
  uv run python ~/tmp/2026-11-09-inner-shadow/render_panels.py <web.swf>
"""

import json
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev.swf import ffdec_lib, render, timeline
from urchin_dev.swf.swf_index import read_swf, shape_bounds

OUT = Path.home() / "tmp/2026-11-09-inner-shadow/art"
KRINMENU = 3142
PANELS = {"grey": 7, "dark": 21, "bar": 5}  # depth on frame 1, shapes 2989, 2987, 2991
ZOOMS = (1.0, 2.0)

swf = Path(sys.argv[1])
index = read_swf(swf)
layers = timeline.frames(index, KRINMENU)[0]
shape_rects = {}
for name, depth in PANELS.items():
    layer = layers[depth]
    child = next(iter(timeline.frames(index, layer.character_id)[0].values()))
    b = shape_bounds(index, child.character_id)
    x = (layer.matrix[4] + child.matrix[4] + b[0]) / 20
    y = (layer.matrix[5] + child.matrix[5] + b[1]) / 20
    shape_rects[name] = [x, y, (b[2] - b[0]) / 20, (b[3] - b[1]) / 20]
    print(
        name,
        "matrix",
        layer.matrix,
        "child",
        child.matrix,
        "shape",
        child.character_id,
        shape_rects[name],
    )

jobs, names = [], []
with tempfile.TemporaryDirectory(prefix="shadow_") as tmp:
    for name, depth in PANELS.items():
        for zoom in ZOOMS:
            jobs.append(
                {
                    "timeline": KRINMENU,
                    "frame": 1,
                    "zoom": zoom,
                    "only_depths": [depth],
                    "background": "none",
                    "out": str(Path(tmp) / f"{name}_{int(zoom)}.png"),
                }
            )
            names.append((name, zoom))
    results = ffdec_lib.render(swf, jobs)
    info = {}
    for (name, zoom), result, job in zip(names, results, jobs, strict=True):
        frame = render.Frame(
            job=render.Job(KRINMENU, 1, zoom, (0.0, 0.0)),
            path=Path(result["out"]),
            size=(result["width"], result["height"]),
            canvas_rect=(
                result["xmin"],
                result["ymin"],
                result["xmax"],
                result["ymax"],
            ),
            display_rect=tuple(result["display"]),
        )
        render.check_canvas(frame)
        cut = render.trim(frame)
        cut.image.save(OUT / f"{name}_z{int(zoom)}.png")
        info[f"{name}_z{int(zoom)}"] = {
            "rect": list(cut.rect),
            "zoom": zoom,
            "shape_rect": shape_rects[name],
        }
        print(
            name,
            zoom,
            frame.size,
            "bbox",
            cut.bbox,
            "rect",
            [round(v, 3) for v in cut.rect],
            "shape",
            shape_rects[name],
        )

    # 1x nine-patch sources, box-resampled from the 4x render so the shape's outer edge lies on a texel edge.
    for name in PANELS:
        a = info[f"{name}_z2"]
        img = Image.open(OUT / f"{name}_z2.png").convert("RGBA")
        s = a["shape_rect"]
        ox, oy = (s[0] - a["rect"][0]) * 2, (s[1] - a["rect"][1]) * 2
        w, h = round(s[2]), round(s[3])
        box = (ox, oy, min(ox + w * 2, img.width), min(oy + h * 2, img.height))
        aligned = img.resize((w, h), Image.BOX, box=box)
        aligned.save(OUT / f"{name}_aligned_1x.png")
        info[f"{name}_aligned_1x"] = {"size": [w, h], "from_box": list(box)}
        print(
            name,
            "aligned",
            aligned.size,
            "alpha min/max",
            aligned.getchannel("A").getextrema(),
        )

(OUT / "info.json").write_text(json.dumps(info, indent=1) + "\n")
