# One-time generator: bakes each VFX clip's frames + real registration
# offset (assets/vfx/vfx_offsets.json, from extract_vfx_offsets) into a
# dedicated Godot scene under scenes/battle/vfx/<category>/<name>.tscn.
# Not meant to be re-run as part of the normal build once its output is
# committed - the source SWF is fixed, so there is no new content to
# regenerate later.
#
# The generated AnimatedSprite2D's scale always works out to exactly
# 1/ZOOM: "w"/"h" in vfx_offsets.json are themselves derived from the
# same PNG this script measures again for the scale ratio's denominator,
# so the ZOOM factor cancels regardless of a clip's own filter padding.
#
# See docs/superpowers/specs/2026-08-19-vfx-registration-scenes-design.md.
# Run: uv run extract_vfx_scenes
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

from urchin_dev import REPO_ROOT

VFX_DIR = REPO_ROOT / "assets" / "vfx"
OFFSETS_FILE = VFX_DIR / "vfx_offsets.json"
SCENES_DIR = REPO_ROOT / "scenes" / "battle" / "vfx"

# (category folder under assets/vfx, animation name, loop, wrapper node name)
CATEGORIES = [
    ("bolts", "fly", True, "Bolt"),
    ("trail", "pulse", False, "Trail"),
    ("impacts", "default", False, "Impact"),
]


def _frame_paths(clip_dir: Path) -> list[Path]:
    return sorted(clip_dir.glob("*.png"), key=lambda p: int(p.stem))


def _build_scene(
    frame_paths, res_prefix, offset, texture_size, anim_name, loop, node_name, top_level
):
    real_w_px, real_h_px = texture_size
    scale_x = round(offset["w"] / real_w_px, 6)
    scale_y = round(offset["h"] / real_h_px, 6)

    ext_lines = []
    frame_entries = []
    for i, path in enumerate(frame_paths, start=1):
        eid = f"frame_{i}"
        ext_lines.append(
            f'[ext_resource type="Texture2D" path="{res_prefix}{path.name}" id="{eid}"]'
        )
        frame_entries.append(f'{{"duration": 1.0, "texture": ExtResource("{eid}")}}')

    load_steps = len(frame_paths) + 2  # N textures + 1 SpriteFrames + the scene itself
    lines = [f"[gd_scene load_steps={load_steps} format=3]", ""]
    lines.extend(ext_lines)
    lines.append("")
    lines.append('[sub_resource type="SpriteFrames" id="SpriteFrames_1"]')
    lines.append("animations = [{")
    lines.append(f'"frames": [{", ".join(frame_entries)}],')
    lines.append(f'"loop": {"true" if loop else "false"},')
    lines.append(f'"name": &"{anim_name}",')
    lines.append('"speed": 30.0')
    lines.append("}]")
    lines.append("")
    lines.append(f'[node name="{node_name}" type="Node2D"]')
    if top_level:
        lines.append("top_level = true")
    lines.append("")
    lines.append('[node name="AnimatedSprite2D" type="AnimatedSprite2D" parent="."]')
    lines.append(f"position = Vector2({offset['x']}, {offset['y']})")
    lines.append(f"scale = Vector2({scale_x}, {scale_y})")
    lines.append("centered = false")
    lines.append('sprite_frames = SubResource("SpriteFrames_1")')
    lines.append(f'animation = &"{anim_name}"')
    return "\n".join(lines) + "\n"


def main():
    offsets = json.loads(OFFSETS_FILE.read_text())
    written = 0
    skipped = []

    for category, anim_name, loop, node_name in CATEGORIES:
        category_dir = VFX_DIR / category
        out_dir = SCENES_DIR / category
        out_dir.mkdir(parents=True, exist_ok=True)
        for clip_dir in sorted(p for p in category_dir.iterdir() if p.is_dir()):
            name = clip_dir.name
            offset = offsets.get(name)
            if offset is None:
                skipped.append(f"{category}/{name}")
                continue
            frame_paths = _frame_paths(clip_dir)
            if not frame_paths:
                skipped.append(f"{category}/{name}")
                continue
            texture_size = Image.open(frame_paths[0]).size
            res_prefix = f"res://assets/vfx/{category}/{name}/"
            text = _build_scene(
                frame_paths,
                res_prefix,
                offset,
                texture_size,
                anim_name,
                loop,
                node_name,
                category == "trail",
            )
            (out_dir / f"{name}.tscn").write_text(text)
            written += 1

    print(f"scenes written: {written}", file=sys.stderr)
    if skipped:
        print(f"skipped (no offset data): {skipped}", file=sys.stderr)


if __name__ == "__main__":
    main()
