"""Shape styles and all filters for every piece that carries an inner DropShadow outside the 16 KRINMENU panels."""

import importlib.util, json, struct, sys
from pathlib import Path
from urchin_dev.swf import timeline
from urchin_dev.swf.swf_index import _skip_rect, character_kind, read_swf, shape_bounds

spec = importlib.util.spec_from_file_location(
    "win_layout",
    Path.home()
    / "tmp/2026-11-09-inner-shadow/proto/dev/prototypes/victory_containers/win_layout.py",
)
wl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wl)
source = (
    (Path.home() / "tmp/2026-11-09-inner-shadow/inventory.py")
    .read_text()
    .replace("\nmain()\n", "\n")
)
inv = {}
exec(compile(source, "inventory", "exec"), inv)

index = read_swf(Path(sys.argv[1]))
data = index.data
found = []
inv["walk"](data, _skip_rect(data, 8) + 4, len(data), 0, found)


def describe(cid, indent="    "):
    kind = character_kind(index, cid)
    if kind == "shape":
        fills, lines = wl.shape_styles(index, cid)
        b = shape_bounds(index, cid)
        print(
            f"{indent}shape {cid}: bounds {[v / 20 for v in b]} size {(b[2] - b[0]) / 20}x{(b[3] - b[1]) / 20}"
        )
        print(f"{indent}  fills {json.dumps(fills)[:300]}")
        print(f"{indent}  lines {json.dumps(lines)[:200]}")
    elif kind == "sprite":
        ls = timeline.frames(index, cid)[0]
        print(
            f"{indent}sprite {cid}: {index.sprite_frames[cid]} frames, {len(ls)} layers on frame 1"
        )
        for depth, layer in sorted(ls.items()):
            print(
                f"{indent}  depth {depth} matrix {[round(v, 3) for v in layer.matrix[:4]]} name {layer.name} clip {layer.clip_depth}"
            )
            describe(layer.character_id, indent + "    ")
    else:
        print(f"{indent}{kind} {cid}")


targets = [
    (3142, 25, 9),
    (2846, 1, 2),
    (3325, 1, 2),
    (3365, 1, 2),
    (2984, 1, 1),
    (3312, 1, 1),
    (2427, 7, 4),
]
for owner, frame, depth in targets:
    rec = [
        f
        for f in found
        if f["owner"] == owner and f["depth"] == depth and f["frame"] <= frame
    ][-1]
    layer = timeline.frames(index, owner)[frame - 1][depth]
    print(
        f"owner {owner} frame {frame} depth {depth} cid {layer.character_id} matrix {[round(v, 3) for v in layer.matrix[:4]]}"
    )
    for x in rec["filters"]:
        print("   filter", json.dumps(x))
    describe(layer.character_id)
