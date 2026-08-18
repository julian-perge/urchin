# The original item icon sheet: DefineSprite 2064, one labeled frame per
# item (the game does itemSlot.inner.gotoAndStop(ITEMNAME[id])). Writes
# assets/ui/items/<label>.png and repoints each resources/items/<id>_*.tres
# slot_image at the matching icon.
#
# Each frame is exported directly via ffdec's own sprite renderer
# (`-format sprite:png -selectid 2064`), not reassembled shape-by-shape. An
# earlier version of this script pasted each frame's shapes onto a canvas by
# hand, reading only characterId/matrix off every PlaceObject tag - so any
# effect that lives on the PlaceObject instead of the raw shape (a
# colorTransform, a glow filter) silently vanished. Confirmed on item 592
# "Ancient Cage": the old output (assets/ui/items/Ancient_Cage.png before
# this rewrite) is missing the glowing yellow ward markings the live game
# shows, and ffdec's own render of that frame has them. Same root cause and
# fix as faces.py's portrait glow bug.
#
# Every frame in 2064 places DefineShape 1913 at depth 2 with
# clipDepth="15" - a real SWF clip mask, not editor scaffolding (an earlier
# version of this file assumed the latter and stripped it via
# -removeCharacter before export; that let ffdec render depths 2-15 fully
# unclipped, ballooning e.g. item 69 "A Broken Pipe" from a correctly-masked
# 63x63px to 101x140 - restoring the mask brought it straight back). Same
# clipping mechanic cutscenes.py's wrapper sprites use, just with the mask
# shape and the masked content siblings in one timeline instead of split
# across a wrapper/inner pair. Left untouched here so ffdec's own renderer
# applies it like every other placement.
#
# ffdec still sizes every frame's exported PNG to the whole sprite
# timeline's union bounding box (856 frames), so each frame comes back as
# an ~identical, mostly-transparent canvas with the masked icon - always
# ~62x62px at ZOOM=2, since the mask constrains every frame to the same
# size - in one small corner. Trimmed here to that frame's own opaque
# bounds before saving, same as faces.py does for its own (much smaller)
# per-frame canvas.
#
# Requires ffdec (~/.local/bin/ffdec) for the sprite PNG export.
# Run: uv run extract_item_icons
from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

from urchin_dev import FFDEC, REPO_ROOT, WEB_SWF, WEB_SWF_XML
from urchin_dev.swf import snapshot_timeline

OUT_DIR = REPO_ROOT / "assets" / "ui" / "items"
ITEMS_DIR = REPO_ROOT / "resources" / "items"
ZOOM = 2.0
ICON_SPRITE = 2064


def sanitize(label: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_")


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed (exit {proc.returncode}): {' '.join(cmd)}\n"
            f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
        )
    return proc


def main():
    xml = WEB_SWF_XML.read_text()
    _snaps, labels = snapshot_timeline(xml, ICON_SPRITE, set())
    print(f"icon labels: {len(labels)}", file=sys.stderr)

    work_dir = Path(tempfile.mkdtemp(prefix="item_icons_"))
    try:
        frames_dir = work_dir / "frames"
        run(
            [
                str(FFDEC),
                "-zoom",
                str(ZOOM),
                "-format",
                "sprite:png",
                "-selectid",
                str(ICON_SPRITE),
                "-export",
                "sprite",
                str(frames_dir),
                str(WEB_SWF),
            ]
        )
        sprite_frames_dir = frames_dir / f"DefineSprite_{ICON_SPRITE}"

        OUT_DIR.mkdir(parents=True, exist_ok=True)
        written: dict[str, str] = {}
        missing = []
        for label, frame in labels.items():
            src = sprite_frames_dir / f"{frame}.png"
            if not src.exists():
                missing.append((label, frame))
                continue
            file_name = sanitize(label) + ".png"
            img = Image.open(src)
            bbox = img.getchannel("A").getbbox()
            # Trim the mostly-transparent export canvas down to this frame's
            # own content (see file header) - a couple of labels ("Nichts"/
            # "None") are the deliberately blank empty-slot icon and have no
            # content at all, so keep those as a minimal 1x1 transparent
            # pixel instead of the full untrimmed canvas.
            img = (
                img.crop(bbox)
                if bbox is not None
                else Image.new("RGBA", (1, 1), (0, 0, 0, 0))
            )
            img.save(OUT_DIR / file_name)
            written[label] = file_name
        print(f"icons written: {len(written)}", file=sys.stderr)
        if missing:
            print(f"missing source frames: {missing}", file=sys.stderr)
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)

    # --- repoint the item .tres slot_image at the new icons -----------------
    # Labels and item names disagree on case/punctuation sometimes ("White
    # T-Shirt" vs "White T-shirt") - match on the sanitized lowercase form.
    # Never touches other Texture2D ext_resources (sprite_image); adds the
    # icon as its own ext_resource with a dedicated id.
    by_key = {
        sanitize(label).lower(): file_name for label, file_name in written.items()
    }
    patched, no_icon = 0, []
    for tres in ITEMS_DIR.glob("*.tres"):
        text = tres.read_text()
        name_match = re.search(r'^name = "(.*)"$', text, re.MULTILINE)
        if name_match is None:
            continue
        else:
            icon = by_key.get(sanitize(name_match.group(1)).lower())
            if icon is None:
                no_icon.append(name_match.group(1))
                continue
            new_path = f"res://assets/ui/items/{icon}"
        if (
            f'path="{new_path}" id="icon_slot"]' in text
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
    print(f"tres repointed: {patched}, no icon for: {no_icon[:10]}", file=sys.stderr)


if __name__ == "__main__":
    main()
