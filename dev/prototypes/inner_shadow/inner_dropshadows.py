"""Lists every inner DropShadow placement in the web SWF, per owner, with strength.

Run from the repo root: uv run python ~/tmp/2026-11-09-inner-shadow/inner_dropshadows.py <web.swf>
"""

import importlib.util
import json
import sys
from pathlib import Path

from urchin_dev.swf import timeline
from urchin_dev.swf.swf_index import _skip_rect, character_kind, read_swf, shape_bounds

spec = importlib.util.spec_from_file_location(
    "inv", Path(__file__).with_name("inventory.py")
)
source = (
    Path(__file__).with_name("inventory.py").read_text().replace("\nmain()\n", "\n")
)
inv = {}
exec(compile(source, "inventory", "exec"), inv)

KRINMENU = 3142
index = read_swf(Path(sys.argv[1]))
data = index.data
found = []
inv["walk"](data, _skip_rect(data, 8) + 4, len(data), 0, found)

parents = {}
for p in index.placements:
    if p.character_id is not None:
        parents.setdefault(p.character_id, set()).add(p.owner)


def chain(owner, depth=0):
    if owner == 0:
        return "root"
    if depth > 6:
        return f"{owner}..."
    up = sorted(parents.get(owner, []))[:3]
    exports = [n for n, c in index.exports.items() if c == owner]
    tag = f"{owner}" + (f"[{exports[0]}]" if exports else "")
    if not up:
        return tag
    return tag + " <- " + " | ".join(chain(u, depth + 1) for u in up)


rows = []
for f in found:
    for x in f["filters"]:
        if x["type"] == "DropShadow" and x["inner"]:
            owner_layers = timeline.frames(index, f["owner"])
            layer = owner_layers[f["frame"] - 1].get(f["depth"])
            cid = layer.character_id if layer else f["cid"]
            kind = character_kind(index, cid) if cid else "?"
            size = None
            inner_shape = None
            if cid and kind == "shape":
                inner_shape = cid
            elif cid and kind == "sprite":
                ls = timeline.frames(index, cid)[0]
                if len(ls) == 1:
                    only = next(iter(ls.values()))
                    if character_kind(index, only.character_id) == "shape":
                        inner_shape = only.character_id
            if inner_shape:
                b = shape_bounds(index, inner_shape)
                sx, sy = layer.matrix[0], layer.matrix[3]
                size = (
                    round((b[2] - b[0]) * sx / 20, 2),
                    round((b[3] - b[1]) * sy / 20, 2),
                )
            rows.append(
                {
                    "owner": f["owner"],
                    "frame": f["frame"],
                    "depth": f["depth"],
                    "cid": cid,
                    "kind": kind,
                    "name": f["name"],
                    "strength": x["strength"],
                    "blur": x["blur"][0],
                    "distance": x["distance"],
                    "angle": x["angle"],
                    "color": x["color"],
                    "passes": x["passes"],
                    "size": size,
                }
            )

rows.sort(key=lambda r: (r["owner"] != KRINMENU, r["owner"], r["frame"], r["depth"]))
for r in rows:
    print(json.dumps(r))
print()
for owner in sorted({r["owner"] for r in rows}):
    print(chain(owner))
