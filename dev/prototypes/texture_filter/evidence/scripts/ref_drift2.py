#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["numpy", "pillow", "scipy"]
# ///
"""Where today's win_full and win_chrome renders differ from the committed ones, against the rects compare.py leaves out."""
from pathlib import Path
import json
import numpy as np
from PIL import Image
from scipy import ndimage

T = Path.home() / "tmp/2026-11-09-urchin-filter"
P = T / "proto/dev/prototypes/victory_containers"
layout = json.loads((P / "win_layout.json").read_text())
art = json.loads((P / "art.json").read_text())
face = layout["row_pieces"]["face"]
a = art["face_Veradux"]["rect"]
rects = []
for role, row in layout["rows"].items():
    x = row["rect"][0] + face["offset"][0] + a[0] * face["scale"]
    y = row["rect"][1] + face["offset"][1] + a[1] * face["scale"]
    rects.append((role, x, y, a[2] * face["scale"], a[3] * face["scale"]))
print("face rects (design px):", [(r, round(x, 1), round(y, 1), round(w, 1), round(h, 1)) for r, x, y, w, h in rects])
for name in ("win_full_2x", "win_chrome_2x"):
    old = np.asarray(Image.open(P / f"images/ref/{name}.png").convert("RGBA"), dtype=np.int16)
    new = np.asarray(Image.open(T / f"ref_today/images/ref/{name}.png").convert("RGBA"), dtype=np.int16)
    d = np.abs(old - new).max(axis=2) > 0
    mask = np.zeros(d.shape, dtype=bool)
    for _, x, y, w, h in rects:
        mask[int(y * 2) : int(np.ceil((y + h) * 2)), int(x * 2) : int(np.ceil((x + w) * 2))] = True
    inside = int((d & mask).sum())
    print(f"{name}: changed {int(d.sum())}, inside the left-out face rects {inside}, outside {int(d.sum()) - inside}")
    labeled, count = ndimage.label(ndimage.binary_dilation(d, iterations=2))
    for slc in ndimage.find_objects(labeled):
        y, x = slc
        print(f"  box design x {x.start/2:.1f}..{x.stop/2:.1f} y {y.start/2:.1f}..{y.stop/2:.1f}")
    if name == "win_chrome_2x":
        # A side by side crop of the first changed box.
        y, x = ndimage.find_objects(labeled)[0]
        pad = 20
        y0, y1, x0, x1 = max(y.start - pad, 0), y.stop + pad, max(x.start - pad, 0), x.stop + pad
        o = Image.fromarray(old[y0:y1, x0:x1].astype(np.uint8))
        n = Image.fromarray(new[y0:y1, x0:x1].astype(np.uint8))
        sheet = Image.new("RGBA", (o.width * 2 + 8, o.height), (255, 0, 255, 255))
        sheet.alpha_composite(o, (0, 0))
        sheet.alpha_composite(n, (o.width + 8, 0))
        sheet.resize((sheet.width * 3, sheet.height * 3), Image.Resampling.NEAREST).save(T / "ref_today/face_old_new.png")
