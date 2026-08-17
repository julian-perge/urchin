# The original item icon sheet: DefineSprite 2064, one labeled frame per
# item (the game does itemSlot.inner.gotoAndStop(ITEMNAME[id])). Composites
# every labeled frame at 2x into assets/ui/items/<label>.png and repoints
# each resources/items/<id>_*.tres slot_image at the matching icon.
#
# Requires ffdec for the shape exports.
# Run: uv run extract_item_icons
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import (
    make_char_bounds,
    parse_swf_xml,
    snapshot_timeline,
)

OUT_DIR = REPO_ROOT / "assets" / "ui" / "items"
ITEMS_DIR = REPO_ROOT / "resources" / "items"
ZOOM = 2.0
ICON_SPRITE = 2064
# The slot viewport is 31x31 design px; icons are drawn centered on (0,0).
ICON_HALF = 15.5
# Shape 1913 is the green editor-backing square behind every icon frame -
# never visible in game (the slot art sits behind the icon instead).
SKIP_CIDS = {1913}
# Items whose icon-clip frame does not match the live game (verified by
# side-by-side playtest) keep a hand-picked icon instead.
ICON_OVERRIDES = {
    11: "res://assets/item_slot_icons/OTHER/White_T_Shirt.png"  # White T-shirt
}


def sanitize(label: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_")


def main():
    xml = WEB_SWF_XML.read_text()
    shapes, sprites, _exports = parse_swf_xml(WEB_SWF_XML)
    char_bounds = make_char_bounds(shapes, sprites)

    # find total frames by snapshotting a big range; labels come along
    snaps, labels = snapshot_timeline(xml, ICON_SPRITE, set(range(1, 900)))
    print("icon frames:", len(snaps), "labels:", len(labels), file=sys.stderr)

    needed = set()

    def collect(cid):
        if cid in shapes:
            needed.add(cid)
        elif cid in sprites:
            for child, _mat in sprites[cid]:
                collect(child)

    label_frames = {}
    for label, frame in labels.items():
        snap = snaps.get(frame)
        if not snap:
            continue
        label_frames[label] = snap
        for entry in snap.values():
            collect(entry["cid"])
    print("shapes needed:", len(needed), file=sys.stderr)

    shape_dir = Path(tempfile.mkdtemp(prefix="item_icon_shapes_"))
    ids = sorted(needed)
    for i in range(0, len(ids), 400):  # keep the CLI arg length sane
        subprocess.run(
            [
                str(FFDEC),
                "-zoom",
                str(ZOOM),
                "-format",
                "shape:png",
                "-selectid",
                ",".join(str(c) for c in ids[i : i + 400]),
                "-export",
                "shape",
                str(shape_dir),
                str(WEB_SWF),
            ],
            check=True,
            capture_output=True,
        )

    def paste_char(canvas, cid, mat, origin):
        if cid in SKIP_CIDS:
            return
        sx, _r0, _r1, sy, tx, ty = mat
        if cid in sprites:
            for child, child_mat in sprites[cid]:
                csx, _cr0, _cr1, csy, ctx, cty = child_mat
                combined = (sx * csx, 0.0, 0.0, sy * csy, tx + ctx * sx, ty + cty * sy)
                paste_char(canvas, child, combined, origin)
            return
        b = char_bounds(cid)
        path = shape_dir / f"{cid:d}.png"
        if b is None or not path.exists():
            return
        img = Image.open(path).convert("RGBA")
        if abs(sx) != 1.0 or abs(sy) != 1.0:
            img = img.resize(
                (max(1, int(img.width * abs(sx))), max(1, int(img.height * abs(sy))))
            )
        px = (b[0] / 20.0 * sx + tx / 20.0 - origin[0]) * ZOOM
        py = (b[1] / 20.0 * sy + ty / 20.0 - origin[1]) * ZOOM
        canvas.alpha_composite(img, (int(round(px)), int(round(py))))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    size = (int(ICON_HALF * 2 * ZOOM), int(ICON_HALF * 2 * ZOOM))
    written = {}
    for label, snap in label_frames.items():
        canvas = Image.new("RGBA", size, (0, 0, 0, 0))
        for depth in sorted(snap):
            entry = snap[depth]
            paste_char(
                canvas,
                entry["cid"],
                entry.get("mat", (1, 0, 0, 1, 0, 0)),
                (-ICON_HALF, -ICON_HALF),
            )
        file_name = sanitize(label) + ".png"
        canvas.save(OUT_DIR / file_name)
        written[label] = file_name
    print("icons written:", len(written), file=sys.stderr)

    # --- repoint the item .tres slot_image at the new icons -----------------
    # Labels and item names disagree on case/punctuation sometimes ("White
    # T-Shirt" vs "White T-shirt") - match on the sanitized lowercase form.
    # Never touches other Texture2D ext_resources (sprite_image); adds the
    # icon as its own ext_resource with a dedicated id.
    by_key = {
        sanitize(label).lower(): file_name for label, file_name in written.items()
    }
    patched, missing = 0, []
    for tres in ITEMS_DIR.glob("*.tres"):
        item_id = int(tres.name.split("_", 1)[0])
        text = tres.read_text()
        name_match = re.search(r'^name = "(.*)"$', text, re.MULTILINE)
        if name_match is None:
            continue
        if item_id in ICON_OVERRIDES:
            new_path = ICON_OVERRIDES[item_id]
        else:
            icon = by_key.get(sanitize(name_match.group(1)).lower())
            if icon is None:
                missing.append(name_match.group(1))
                continue
            new_path = f"res://assets/ui/items/{icon}"
        if (
            f'path="{new_path}"' in text
            and 'slot_image = ExtResource("icon_slot")' in text
        ):
            patched += 1
            continue
        # Drop any previous icon ext_resource/assignment of ours.
        text = re.sub(
            r'^\[ext_resource type="Texture2D" path="[^"]*" id="(?:2_icon|icon_slot)"\]\n',
            "",
            text,
            flags=re.MULTILINE,
        )
        text = re.sub(
            r'^slot_image = ExtResource\("(?:2_icon|icon_slot)"\)\n',
            "",
            text,
            flags=re.MULTILINE,
        )
        # Insert the icon ext_resource before the Script one (always present).
        text = re.sub(
            r'^(\[ext_resource type="Script")',
            f'[ext_resource type="Texture2D" path="{new_path}" id="icon_slot"]\n\\1',
            text,
            count=1,
            flags=re.MULTILINE,
        )
        # Point slot_image at it (replace an existing assignment, else add
        # right after the script line in the [resource] block).
        if re.search(r"^slot_image = ", text, re.MULTILINE):
            text = re.sub(
                r"^slot_image = .*$",
                'slot_image = ExtResource("icon_slot")',
                text,
                count=1,
                flags=re.MULTILINE,
            )
        else:
            text = re.sub(
                r'^(script = ExtResource\("[^"]*"\))$',
                '\\1\nslot_image = ExtResource("icon_slot")',
                text,
                count=1,
                flags=re.MULTILINE,
            )
        # load_steps count may now be off by one - Godot tolerates and fixes
        # it on the next editor save.
        tres.write_text(text)
        patched += 1
    print("tres repointed:", patched, "no icon for:", missing[:10], file=sys.stderr)


if __name__ == "__main__":
    main()
