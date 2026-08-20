# VFX Registration Scenes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix `Bolt`/`ImpactEffect`'s registration-point mismatch (Godot's default `centered = true`, drawing them centered on their own bounding box instead of at the source clip's real local origin) by giving every VFX clip its own correctly-positioned, generated scene - replacing the current dynamic PNG-folder loading and flat `VFX_SCALE` approximation.

**Architecture:** Two new Python scripts compute a real per-clip registration offset from the SWF's own timeline data (correcting for glow-filter padding `ffdec`'s PNG exporter bakes in but the raw shape data doesn't capture) and bake it, together with each clip's frames, into a dedicated `.tscn` per clip. `Projectile`/`ImpactEffect` instantiate the resolved clip's scene by name instead of scanning a PNG folder or applying a runtime offset lookup.

**Tech Stack:** Python 3.14 (`uv run`), `ffdec`, Pillow, GDScript/Godot 4.7, GUT 9.6.1.

**Spec:** `docs/superpowers/specs/2026-08-19-vfx-registration-scenes-design.md`

## Global Constraints

- `ZOOM = 2.0` - imported from `dev/urchin_dev/swf/extract/vfx.py`, never redefined elsewhere.
- 51 total clips: 15 bolts + 1 trail (`KrinTrail`) + 35 resolvable impacts. 36 `impact_effect_name` values resolve to a real sprite, but `ex_DownBlue` and `ex_DOWNBLUE` name the same clip.
- Position values (in `assets/vfx/vfx_offsets.json` and baked into generated scenes' `AnimatedSprite2D.position`) are **natural, unzoomed units** - the same convention `resources/sprites/doll_offsets.json` already uses. This is NOT the same convention the already-shipped `Trail.offset = Vector2(0, -7)` used (that was `.offset`, pre-scale texture-pixel/zoomed units, on a since-retired shared node) - the same real position, expressed differently because `.position` and `.offset` are consumed differently by Godot.
- `VfxFrames.sanitize()` stays; it is still how a `clip_name` (`Ability.animation_label`/`impact_effect_name`) resolves to a generated scene's filename. `VfxFrames.load_frames()` and `VfxFrames.VFX_SCALE` are retired - fully superseded by the generated scenes.
- No pytest suite exists anywhere in this project (`dev/` has no test files, no pytest config) - Python-side verification for this plan follows the same established convention as `item_icons.py`/`buff_icons.py`/`vfx.py`: a diagnostic run whose printed output is inspected directly, not a persisted test file.
- No visual/screenshot verification is available in this environment. Every claim about correct positioning is verified via property assertions (`position`, `scale`, `rotation`, `centered`) or direct pixel measurement of already-extracted PNGs, never by eyeballing a render.
- `vfx_offsets.py` and `vfx_scenes.py` are one-time-use scripts: run once during this plan's execution, their output reviewed and committed, not re-run as part of the normal build afterward.
- pyproject.toml script entries are kept in alphabetical order, matching this project's existing convention.

---

### Task 1: Full-timeline union bounds in `xml_lib.py`

**Files:**
- Modify: `dev/urchin_dev/swf/xml_lib.py`
- Modify: `dev/urchin_dev/swf/__init__.py`

**Interfaces:**
- Consumes: `sprite_body(xml, sprite_id) -> str`, `snapshot_timeline(xml, sprite_id, wanted_frames) -> (snaps, labels)`, `transform_rect(mat, rect) -> tuple`, `IDENTITY` - all already in `xml_lib.py`.
- Produces: `make_timeline_bounds(shape_bounds: dict, xml: str) -> Callable[[int], tuple | None]` - a resolver function, called as `bounds_fn(sprite_id)`, matching `make_char_bounds`'s existing calling convention exactly (so callers familiar with one recognize the other).

- [ ] **Step 1: Add `make_timeline_bounds` to `xml_lib.py`**

Add this function after `make_char_bounds` (which stays completely unchanged - the doll-art pipeline depends on its current first-frame-only behavior):

```python
def make_timeline_bounds(shape_bounds, xml):
    """Recursive FULL-TIMELINE rendered bounds (twips), memoized per sprite
    id. Unlike make_char_bounds (first frame only), this walks every frame
    of a sprite's own timeline via snapshot_timeline(), and recurses with
    the SAME full-timeline treatment for whatever's placed at each depth -
    not just the first frame of nested children. Needed because some
    clips' placed children are themselves independently-animating
    sub-timelines: KRIN.SHADOWSHOCK's placed child (sprite id 2432) has
    its own 3-frame timeline, and first-frame-only recursion for it missed
    2 of those 3 frames - confirmed by cross-checking against ffdec's own
    SVG-per-frame export (an independent renderer), which agreed with the
    corrected computation to within rounding."""
    memo = {}

    def frame_count(cid):
        return sprite_body(xml, cid).count("ShowFrameTag")

    def timeline_bounds(cid, depth=0):
        if cid in memo:
            return memo[cid]
        if depth > 12:
            return None
        if cid in shape_bounds:
            memo[cid] = shape_bounds[cid]
            return memo[cid]
        fc = frame_count(cid)
        if fc == 0:
            memo[cid] = None
            return None
        snaps, _labels = snapshot_timeline(xml, cid, set(range(1, fc + 1)))
        acc: list | None = None
        for frame_state in snaps.values():
            for entry in frame_state.values():
                child_cid = entry.get("cid")
                if child_cid is None:
                    continue
                cb = timeline_bounds(child_cid, depth + 1)
                if cb is None:
                    continue
                mat = entry.get("mat", IDENTITY)
                tb = transform_rect(mat, cb)
                if acc is None:
                    acc = list(tb)
                else:
                    acc = [
                        min(acc[0], tb[0]),
                        min(acc[1], tb[1]),
                        max(acc[2], tb[2]),
                        max(acc[3], tb[3]),
                    ]
        memo[cid] = tuple(acc) if acc else None
        return memo[cid]

    return timeline_bounds
```

- [ ] **Step 2: Export it from the package**

Edit `dev/urchin_dev/swf/__init__.py` - add `"make_timeline_bounds"` to `__all__` (alphabetically, after `"make_char_bounds"`) and to the import list from `urchin_dev.swf.xml_lib` (same position):

```python
from __future__ import annotations

__all__ = [
    "find_matrix",
    "make_char_bounds",
    "make_timeline_bounds",
    "parse_swf_xml",
    "snapshot_timeline",
    "sprite_body",
    "transform_rect",
]

from urchin_dev.swf.xml_lib import (
    find_matrix,
    make_char_bounds,
    make_timeline_bounds,
    parse_swf_xml,
    snapshot_timeline,
    sprite_body,
    transform_rect,
)
```

- [ ] **Step 3: Verify by direct inspection (no pytest suite exists in this project - see Global Constraints)**

Run this from the repo root and compare the printed numbers against the values below, which were independently confirmed during design (including cross-checking `KRIN.SHADOWSHOCK` against `ffdec`'s own SVG export):

```bash
uv run python -c "
from urchin_dev import WEB_SWF_XML
from urchin_dev.swf import parse_swf_xml, make_timeline_bounds

xml = WEB_SWF_XML.read_text()
shape_bounds, _sprites, _exports = parse_swf_xml(WEB_SWF_XML)
bounds_fn = make_timeline_bounds(shape_bounds, xml)

b = bounds_fn(2)  # KrinTrail's real content, sprite id 2 - static, no filter
w, h = (b[2]-b[0])/20.0, (b[3]-b[1])/20.0
print('Trail natural px:', round(w,2), round(h,2), 'origin', round(b[0]/20.0,2), round(b[1]/20.0,2))
assert abs(w - 10.0) < 0.01 and abs(h - 7.0) < 0.01
assert abs(b[0]/20.0 - 0.0) < 0.01 and abs(b[1]/20.0 - (-3.5)) < 0.01

b2 = bounds_fn(2433)  # KRIN.SHADOWSHOCK - moving placement, nested child has its own 3-frame timeline
w2, h2 = (b2[2]-b2[0])/20.0, (b2[3]-b2[1])/20.0
print('Shadowshock natural px (zoom2):', round(w2*2,2), round(h2*2,2))
assert abs(w2*2 - 219.37) < 0.5 and abs(h2*2 - 218.76) < 0.5
print('OK - matches design-time values')
"
```

Expected output ends with `OK - matches design-time values`. If either assertion fails, stop and re-check the implementation against Step 1 before continuing - this is the foundation every later task's numbers depend on.

- [ ] **Step 4: Commit**

```bash
git add dev/urchin_dev/swf/xml_lib.py dev/urchin_dev/swf/__init__.py
git commit -m "feat: full-timeline union bounds for VFX registration points"
```

---

### Task 2: `vfx_offsets.py` - compute and record real per-clip offsets

**Files:**
- Create: `dev/urchin_dev/swf/extract/vfx_offsets.py`
- Modify: `pyproject.toml`

**Interfaces:**
- Consumes: `make_timeline_bounds` (Task 1); `dev/urchin_dev/swf/extract/vfx.py`'s `ZOOM`, `BOLT_NAMES`, `TRAIL_CLIP_NAME`, `TRAIL_SPRITE_ID`, `sanitize()`, `_impact_names()` (all already module-level in that file - import and reuse, don't duplicate); `parse_swf_xml`.
- Produces: `assets/vfx/vfx_offsets.json` - `{sanitized_name: {"x": float, "y": float, "w": float, "h": float}}`, natural (unzoomed) units. Consumed by Task 3's generator.

- [ ] **Step 1: Write `vfx_offsets.py`**

```python
# Computes real per-clip registration offsets for every VFX clip
# (dev/urchin_dev/swf/extract/vfx.py's own bolt/trail/impact categories),
# correcting for glow-filter padding that raw shapeBounds XML data can't
# see: ffdec's PNG exporter bakes a glow filter's rendered footprint into
# its canvas, but neither shapeBounds tags nor ffdec's own SVG exporter
# account for it. Confirmed the padding is symmetric around the computed
# shape's own center by measuring real pixel data directly: Krin.Firebolt's
# solid core (opaque pixels, excluding the soft glow halo) has its
# centroid at (97.9, 98.0) in a 196x196 canvas centered on (98.0, 98.0) -
# a match to within 0.1 px. Correcting for this only needs the real
# canvas size (trivially measurable from the already-extracted PNG) - no
# attempt to replicate Flash's exact blur-filter rendering math.
#
# Writes assets/vfx/vfx_offsets.json: one {"x", "y", "w", "h"} entry per
# clip (natural, unzoomed px - matching resources/sprites/doll_offsets.json's
# own convention), keyed by the same sanitize()d name vfx.py already uses
# for its PNG folder names.
#
# See docs/superpowers/specs/2026-08-19-vfx-registration-scenes-design.md.
# Run: uv run extract_vfx_offsets
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

from urchin_dev import REPO_ROOT, WEB_SWF_XML
from urchin_dev.swf import make_timeline_bounds, parse_swf_xml
from urchin_dev.swf.extract.vfx import (
    BOLT_NAMES,
    TRAIL_CLIP_NAME,
    TRAIL_SPRITE_ID,
    ZOOM,
    _impact_names,
    sanitize,
)

VFX_DIR = REPO_ROOT / "assets" / "vfx"
OUT = VFX_DIR / "vfx_offsets.json"


def _clip_offset(bounds_fn, name: str, cid: int, category: str) -> dict | None:
    bounds = bounds_fn(cid)
    if bounds is None:
        return None
    frame1 = VFX_DIR / category / sanitize(name) / "1.png"
    if not frame1.exists():
        return None
    real_w_px, real_h_px = Image.open(frame1).size
    real_w = real_w_px / ZOOM
    real_h = real_h_px / ZOOM
    computed_cx = (bounds[0] + bounds[2]) / 2.0 / 20.0
    computed_cy = (bounds[1] + bounds[3]) / 2.0 / 20.0
    return {
        "x": round(computed_cx - real_w / 2.0, 2),
        "y": round(computed_cy - real_h / 2.0, 2),
        "w": round(real_w, 2),
        "h": round(real_h, 2),
    }


def main():
    xml = WEB_SWF_XML.read_text()
    shape_bounds, _sprites, exports = parse_swf_xml(WEB_SWF_XML)
    bounds_fn = make_timeline_bounds(shape_bounds, xml)
    ci_exports = {k.lower(): v for k, v in exports.items()}

    def resolve(name: str):
        return ci_exports.get(name.lower())

    result = {}
    unresolved = []
    seen_ids: dict[int, str] = {}

    for name in BOLT_NAMES:
        cid = resolve(name)
        if cid is None:
            unresolved.append(name)
            continue
        if cid in seen_ids:
            continue  # KRIN.MAGICBOLT/Krin.Magicbolt etc. - same clip, already recorded
        seen_ids[cid] = name
        offset = _clip_offset(bounds_fn, name, cid, "bolts")
        if offset is None:
            unresolved.append(name)
            continue
        result[sanitize(name)] = offset

    trail_offset = _clip_offset(bounds_fn, TRAIL_CLIP_NAME, TRAIL_SPRITE_ID, "trail")
    if trail_offset is not None:
        result[sanitize(TRAIL_CLIP_NAME)] = trail_offset
    else:
        unresolved.append(TRAIL_CLIP_NAME)

    for name in _impact_names():
        cid = resolve(name)
        if cid is None:
            unresolved.append(name)
            continue
        if cid in seen_ids:
            continue
        seen_ids[cid] = name
        offset = _clip_offset(bounds_fn, name, cid, "impacts")
        if offset is None:
            unresolved.append(name)
            continue
        result[sanitize(name)] = offset

    OUT.write_text(json.dumps(result, indent=1, sort_keys=True))
    print(f"clips resolved: {len(result)}", file=sys.stderr)
    if unresolved:
        print(f"unresolved: {unresolved}", file=sys.stderr)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Register in `pyproject.toml`**

Add after the existing `extract_vfx = "urchin_dev.swf.extract.vfx:main"` line (alphabetically next):

```toml
extract_vfx_offsets = "urchin_dev.swf.extract.vfx_offsets:main"
```

- [ ] **Step 3: Run it and inspect the output**

```bash
uv run extract_vfx_offsets
```

Expected stderr: `clips resolved: 51` and `unresolved: [...]` naming exactly the 5 known content gaps (`BOOM_DARK2`, `BOOM_DOWN_BLUE`, `BOOM_DOWN_PURPLE`, `BOOM_PURPLE`, `BOOM_SUN`) - if any other name appears unresolved, or the resolved count isn't 51, stop and investigate before continuing (a silent extra gap here means Task 3 will generate one less scene than expected).

Spot check the output:

```bash
uv run python -c "
import json
data = json.loads(open('assets/vfx/vfx_offsets.json').read())
print('krin_trail:', data.get('krintrail') or data.get('krin_trail'))
print('krin_firebolt:', data['krin_firebolt'])
print('krin_shadowshock:', data['krin_shadowshock'])
"
```

`krintrail` (or however `sanitize('KrinTrail')` renders it - confirm the exact key) should show `x=0.0, y=-3.5, w=10.0, h=7.0`. `krin_firebolt`'s `w`/`h` should be close to `98.0`/`98.0` (196px canvas / ZOOM). `krin_shadowshock`'s `w`/`h` should be close to `162.0`/`161.5` (324x323px canvas / ZOOM).

- [ ] **Step 4: Commit**

```bash
git add dev/urchin_dev/swf/extract/vfx_offsets.py pyproject.toml assets/vfx/vfx_offsets.json
git commit -m "feat: compute real per-clip VFX registration offsets"
```

---

### Task 3: `vfx_scenes.py` - generate one scene per clip

**Files:**
- Create: `dev/urchin_dev/swf/extract/vfx_scenes.py`
- Modify: `pyproject.toml`
- Create: `scenes/battle/vfx/bolts/*.tscn` (15, generated)
- Create: `scenes/battle/vfx/trail/krintrail.tscn` (generated)
- Create: `scenes/battle/vfx/impacts/*.tscn` (35, generated)
- Delete: `scenes/battle/krin_electrobolt.tscn` (the hand-made prototype, superseded by `scenes/battle/vfx/bolts/krin_electrobolt.tscn`)

**Interfaces:**
- Consumes: `assets/vfx/vfx_offsets.json` (Task 2); the PNG folders `vfx.py` already produced under `assets/vfx/{bolts,trail,impacts}/`.
- Produces: one `.tscn` per clip, each a `Node2D` wrapper with a single `AnimatedSprite2D` child named exactly `"AnimatedSprite2D"` (`centered = false`, `position` and `scale` baked in, one animation whose name matches what `Projectile`/`ImpactEffect` will `.play()` in Tasks 4/5: `"fly"` for bolts, `"pulse"` for trail, `"default"` for impacts). Only the trail wrapper sets `top_level = true`.

- [ ] **Step 1: Write `vfx_scenes.py`**

```python
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


def _build_scene(frame_paths, res_prefix, offset, texture_size, anim_name, loop, node_name, top_level):
    real_w_px, real_h_px = texture_size
    scale_x = round(offset["w"] / real_w_px, 6)
    scale_y = round(offset["h"] / real_h_px, 6)

    ext_lines = []
    frame_entries = []
    for i, path in enumerate(frame_paths, start=1):
        eid = f"frame_{i}"
        ext_lines.append(f'[ext_resource type="Texture2D" path="{res_prefix}{path.name}" id="{eid}"]')
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
    lines.append(f'position = Vector2({offset["x"]}, {offset["y"]})')
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
                frame_paths, res_prefix, offset, texture_size,
                anim_name, loop, node_name, category == "trail",
            )
            (out_dir / f"{name}.tscn").write_text(text)
            written += 1

    print(f"scenes written: {written}", file=sys.stderr)
    if skipped:
        print(f"skipped (no offset data): {skipped}", file=sys.stderr)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Register in `pyproject.toml`**

Add after `extract_vfx_offsets` (alphabetically next):

```toml
extract_vfx_scenes = "urchin_dev.swf.extract.vfx_scenes:main"
```

- [ ] **Step 3: Run it**

```bash
uv run extract_vfx_scenes
```

Expected stderr: `scenes written: 51` (matching Task 2's `clips resolved` count) and no `skipped` line (if one appears, cross-check the named clip against Task 2's `unresolved` list - it should be empty, since every skip here would mean a clip resolved in Task 2 but is missing frames on disk, a real bug worth stopping for).

- [ ] **Step 4: Verify one generated scene actually loads in Godot before trusting the rest**

Generated `.tscn` files here omit `uid=` attributes on `ext_resource`/`gd_scene` lines (every other manually-authored scene in this project has them, added by the editor) - Godot 4 treats `uid=` as optional resource-cache acceleration, not a hard requirement, but this needs a real check, not an assumption, before relying on it across 51 files. Add a throwaway check (delete after confirming, it's not meant to be permanent - Tasks 4 and 5's own tests provide the lasting regression coverage for this):

```bash
cat > /tmp/vfx_scene_smoke_test.gd << 'EOF'
extends GutTest
func test_a_generated_scene_loads():
	var scene: PackedScene = load("res://scenes/battle/vfx/trail/krintrail.tscn")
	assert_not_null(scene, "generated scene loads despite no uid= attributes")
	var root: Node2D = scene.instantiate()
	assert_not_null(root.get_node("AnimatedSprite2D"))
	root.free()
EOF
cp /tmp/vfx_scene_smoke_test.gd test/unit/test_vfx_scene_smoke.gd
# run the project's normal GUT invocation, scoped to this one file
# (match whatever command test/README or CI config already uses for a
# single-file GUT run - e.g. via the `-gtest=` flag or an equivalent
# already established in this repo)
rm test/unit/test_vfx_scene_smoke.gd
```

Report the actual pass/fail result. If it fails, stop - every later task depends on this assumption holding.

- [ ] **Step 5: Remove the superseded hand-made prototype**

```bash
rm scenes/battle/krin_electrobolt.tscn
```

(The real, correctly-positioned version now lives at `scenes/battle/vfx/bolts/krin_electrobolt.tscn`; the prototype was created during design to check what the scene structure looked like, before the offset math existed.)

- [ ] **Step 6: Commit**

```bash
git add dev/urchin_dev/swf/extract/vfx_scenes.py pyproject.toml scenes/battle/vfx
git rm scenes/battle/krin_electrobolt.tscn
git commit -m "feat: generate one registration-correct scene per VFX clip"
```

---

### Task 4: `Projectile` - instantiate the clip's own scene

**Files:**
- Modify: `scenes/battle/projectile.tscn`
- Modify: `scripts/battle/projectile.gd`
- Modify: `test/unit/test_projectile.gd`

**Interfaces:**
- Consumes: `scenes/battle/vfx/bolts/<name>.tscn`, `scenes/battle/vfx/trail/krintrail.tscn` (Task 3); `VfxFrames.sanitize()`.
- Produces: `Projectile.reached_target`, `Projectile.start(origin, target)`, `Projectile.clip_name`/`trail_color`/`did_hit` - all UNCHANGED public interface; `battle_scene.gd` needs no changes.

- [ ] **Step 1: Shrink `projectile.tscn`**

Replace its contents entirely - no more static `Bolt`/`Trail` children, both are instantiated per `clip_name` in `start()`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/battle/projectile.gd" id="1_projectile"]

[node name="Projectile" type="Node2D"]
script = ExtResource("1_projectile")
```

- [ ] **Step 2: Rewrite `projectile.gd`**

Replace its contents entirely:

```gdscript
# projectile.gd
# krinBoltMake port (frame_42/DoAction_4.as) for Missile-type moves: a bolt
# that starts slow and ACCELERATES (SpeedConst compounds by BOLT_INCREASE
# every original frame) rather than moving at constant speed. The per-frame
# step is a fixed fraction of the distance measured at spawn (distance / 60,
# never recomputed against the bolt's current position), and arrival is a
# coordinate-crossing test (has the bolt's x passed the target's x) rather
# than a distance threshold or a fixed duration - see DECODED_ALGORITHMS.md.
#
# Bolt/Trail art come from per-clip generated scenes
# (dev/urchin_dev/swf/extract/vfx_scenes.py's own output, under
# scenes/battle/vfx/) instantiated per clip_name in start() - each one
# already carries its own frames and its real registration offset
# (dev/urchin_dev/swf/extract/vfx_offsets.py), so nothing here computes a
# position/scale correction at runtime. The bolt clip is shown UNTINTED -
# the source's own krinBoltMake never colors the bolt clip itself, only
# the separate KrinTrail streak (Trail, its own generated scene - KrinTrail's
# real content is a genuine 33-frame fade-in/fade-out pulse baked into its
# own timeline, not a static frame this script fades manually). Both
# clips are rotated to the flight angle, which never changes after spawn.
# Trail is spawned once at the bolt's position on the first tick, handed
# over to the bolt's own parent so it can outlive it, played once
# (non-looping - its own frames already carry the fade), tinted by
# trail_color (RGB only - alpha comes from the frames), and grows scale.x
# every tick, independent of its own internal animation - see
# docs/superpowers/specs/2026-08-19-vfx-registration-scenes-design.md.
class_name Projectile
extends Node2D

signal reached_target

const BOLT_TIME := 60.0       # krinBoltTime: step = distance / 60, fixed at spawn
const BOLT_INCREASE := 1.15   # krinBoltIncrease: SpeedConst *= 1.15 every original frame
const BOLT_FPS := 30.0        # the original ticks this once per SWF frame - drives this
                                # script's own movement pacing; each clip's own animation
                                # playback speed is baked into its generated scene instead
const BOLT_SCENE_DIR := "res://scenes/battle/vfx/bolts/"
const TRAIL_SCENE: PackedScene = preload("res://scenes/battle/vfx/trail/krintrail.tscn")
# This port's own canvas is 800x600, top-left origin (SLOT_POSITIONS range
# x=161..638) - a different coordinate convention from the source's
# centered AS2 stage, so its own off-screen bounds don't transfer
# literally. A small margin past the 800-wide canvas is this port's
# equivalent, used only by the miss-fly-past logic below.
const OFF_SCREEN_MIN_X := -20.0
const OFF_SCREEN_MAX_X := 820.0
# Safety net for the miss fly-past below. A move whose caster and target
# share an x coordinate would give the bolt a zero x-step, so its x would
# never change and the off-screen test could never become true - the
# while loop would spin forever with _speed_const compounding. No slot
# pairing in SLOT_POSITIONS produces that today; the cap costs one
# comparison and closes it for good. Set far above the roughly 20 ticks a
# real caster-to-target miss takes to leave the canvas, so it can only
# ever fire on a flight that would otherwise never end.
const MAX_FLIGHT_TICKS: int = 300

var clip_name: String = ""
var trail_color: Color = Color.WHITE
# Set by battle_scene.gd before start(), from result.type != MISS. A hit
# frees the bolt the instant it reaches the target (matching source: the
# bolt is destroyed the same tick its impact clip appears). A miss keeps
# the bolt (and its growing trail) moving past the target until it exits
# this port's own screen bounds - reached_target still fires at the same
# coordinate-cross tick either way, so turn pacing/audio/the floatie land
# exactly where they do on a hit.
var did_hit: bool = true
var color: Color = Color.WHITE  # fallback tinted-circle color when clip_name has no real asset

var _bolt_root: Node2D
var _bolt_sprite: AnimatedSprite2D
var _trail_root: Node2D
var _trail_sprite: AnimatedSprite2D
# The trail scene's own baked scale, captured once so growth multiplies
# the real per-clip ratio instead of assuming every clip shares one flat
# constant.
var _trail_base_scale: Vector2 = Vector2.ONE

var _step: Vector2
var _checker: float = 1.0
var _target_x: float = 0.0
var _speed_const: float = 1.0
var _alpha: float = 0.0
var _frame_accum: float = 0.0
var _trail_start: Vector2
var _trail_spawned: bool = false
# How far the trail has stretched, as a multiple of its own natural
# length. Tracked apart from _trail_sprite.scale so the rendered scale can
# stay _trail_base_scale times this, instead of the growth increments
# quietly cancelling out the baked-in registration scale.
var _trail_growth: float = 1.0
var _reached: bool = false  # reached_target already fired - only matters for the miss fly-past
var _ticks: int = 0


func start(origin: Vector2, target: Vector2) -> void:
	position = origin
	_trail_start = origin
	_target_x = target.x
	_step = (target - origin) / BOLT_TIME
	_checker = 1.0 if origin.x < target.x else -1.0
	_load_bolt_sprite()
	_load_trail_sprite()


func _load_bolt_sprite() -> void:
	if clip_name.is_empty():
		return  # no real asset - _draw()'s tinted-circle fallback below covers this
	var scene: PackedScene = load("%s%s.tscn" % [BOLT_SCENE_DIR, VfxFrames.sanitize(clip_name)])
	if scene == null:
		return  # no real asset - _draw()'s tinted-circle fallback below covers this
	_bolt_root = scene.instantiate()
	_bolt_sprite = _bolt_root.get_node("AnimatedSprite2D")
	add_child(_bolt_root)
	# The flight direction is fixed at spawn and never recomputed, so the
	# bolt's own rotation can be set here once. Rotating the wrapper
	# rotates the sprite's own baked registration offset around the
	# wrapper's origin - the clip's true pivot, not its texture's center.
	# The source rotates both (frame_42/DoAction_4.as's krinBoltMake sets
	# the bolt's _rotation, then copies it onto the trail).
	_bolt_root.rotation = _step.angle()
	_bolt_sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)  # alpha-only - never color-tinted
	_bolt_sprite.play("fly")


# KrinTrail's real content (dev/urchin_dev/swf/extract/vfx.py's
# TRAIL_SPRITE_ID) is a genuine 33-frame fade-in/fade-out pulse, not a
# static frame - the animation itself carries the alpha; this script only
# ever sets the RGB tint, never touches trail alpha manually.
func _load_trail_sprite() -> void:
	_trail_root = TRAIL_SCENE.instantiate()
	_trail_sprite = _trail_root.get_node("AnimatedSprite2D")
	_trail_base_scale = _trail_sprite.scale
	_trail_sprite.modulate = trail_color  # RGB tint only - alpha comes from the frames themselves
	_trail_root.visible = false


func _process(delta: float) -> void:
	_frame_accum += delta * BOLT_FPS
	while _frame_accum >= 1.0:
		_frame_accum -= 1.0
		_ticks += 1
		_alpha = minf(_alpha + 0.1, 1.0)
		position += _step * _speed_const
		if not _trail_spawned:
			_spawn_trail()
		if _bolt_sprite != null:
			_bolt_sprite.modulate.a = _alpha
		# The trail runs its own fade to the end and frees itself, which on
		# a long miss happens while the bolt is still flying - so this has
		# to check the node is still there before touching it.
		if is_instance_valid(_trail_root) and _trail_root.visible:
			_trail_growth += 0.083 * _step.length() * _speed_const
			_trail_sprite.scale = Vector2(_trail_base_scale.x * _trail_growth, _trail_base_scale.y)
		_speed_const *= BOLT_INCREASE
		if not _reached and (_target_x - position.x) * _checker <= 0.0:
			_reached = true
			reached_target.emit()
			if did_hit:
				queue_free()
				return
		if _reached and (
			position.x < OFF_SCREEN_MIN_X
			or position.x > OFF_SCREEN_MAX_X
			or _ticks >= MAX_FLIGHT_TICKS
		):
			queue_free()
			return
	queue_redraw()


# Places the trail at the point the bolt is passing through right now,
# then hands it over to the bolt's own parent so it stops being the
# bolt's child. On a hit the bolt frees itself the instant it reaches the
# target, and KrinTrail's 33-frame fade is nowhere near finished by then -
# as the bolt's child the trail would be torn down mid-fade. The source
# has the same separation: the trail is attached to BATTLESCREEN, a
# sibling of the bolt clip, not to the bolt itself. Trail's own generated
# scene already sets top_level = true, so where it draws is unchanged by
# the move.
func _spawn_trail() -> void:
	_trail_spawned = true
	_trail_root.global_position = global_position
	_trail_root.rotation = _step.angle()
	_trail_root.visible = true
	var parent: Node = get_parent()
	if parent != null:
		remove_child(_trail_root)
		parent.add_child(_trail_root)
	_trail_sprite.animation_finished.connect(_trail_root.queue_free)
	_trail_sprite.play("pulse")


func _draw() -> void:
	if _bolt_sprite != null:
		return  # real art loaded - the fallback circle stays hidden
	draw_line(_trail_start - position, Vector2.ZERO, Color(color, _alpha * 0.5), 2.0)
	draw_circle(Vector2.ZERO, 4.0, Color(color, _alpha))
```

- [ ] **Step 3: Rewrite `test_projectile.gd`**

Replace its contents entirely - same coverage as before, updated for the instantiate-per-clip-scene structure (`_bolt_root`/`_bolt_sprite`/`_trail_root`/`_trail_sprite` accessed as private fields directly, matching this test suite's established convention of calling private members, rather than `get_node("Bolt")`/`get_node("Trail")` on children that no longer exist):

```gdscript
# Projectile's bolt/trail rendering - each clip's own generated scene
# (dev/urchin_dev/swf/extract/vfx_scenes.py) instead of a tinted circle+
# line or a dynamically-scanned PNG folder.
# docs/superpowers/specs/2026-08-19-vfx-registration-scenes-design.md.
extends GutTest

const ProjectileScene = preload("res://scenes/battle/projectile.tscn")


func test_start_loads_the_named_bolt_clip_untinted():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color(1.0, 0.2, 0.4)
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	assert_not_null(bolt._bolt_sprite, "loaded the real generated scene for this clip")
	assert_eq(bolt._bolt_sprite.modulate.r, 1.0, "bolt art itself is never color-tinted")
	assert_eq(bolt._bolt_sprite.modulate.g, 1.0)
	assert_eq(bolt._bolt_sprite.modulate.b, 1.0)


func test_bolt_art_is_halved_to_undo_the_extractors_2x_zoom():
	# Every generated scene's baked scale collapses to exactly 1/ZOOM -
	# see extract_vfx_scenes.py's own note on why - so this stays a flat
	# assertion even though the value now comes from the clip's own scene,
	# not a shared VFX_SCALE constant.
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	assert_eq(bolt._bolt_sprite.scale, Vector2(0.5, 0.5), "bolt renders at its design size")


func test_trail_art_is_halved_and_grows_from_that_baseline():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	bolt._process(1.0 / 30.0)  # first tick - spawns the trail and grows it once
	assert_eq(bolt._trail_sprite.scale.y, 0.5, "the trail's thickness stays at its design size")
	# One tick of growth is 0.083 * step length * speed_const on top of a
	# 1.0 baseline, then the whole thing is halved (the trail scene's own
	# baked scale).
	var step_length: float = (Vector2(300, 100) - Vector2(100, 100)).length() / Projectile.BOLT_TIME
	assert_almost_eq(bolt._trail_sprite.scale.x, 0.5 * (1.0 + 0.083 * step_length), 0.001,
		"growth is a multiple of the halved baseline, not an unscaled increment")


func test_bolt_is_rotated_to_the_flight_direction():
	# krinBoltMake rotates the bolt clip itself and copies that rotation
	# onto the trail. The direction is fixed at spawn, so start() can set
	# it - on the wrapper node, so the sprite's own baked registration
	# offset rotates around the wrapper's origin (the clip's true pivot),
	# not the texture's own center.
	var rightward: Projectile = add_child_autofree(ProjectileScene.instantiate())
	rightward.clip_name = "Krin.Firebolt"
	rightward.start(Vector2(100, 100), Vector2(300, 100))
	assert_almost_eq(rightward._bolt_root.rotation, 0.0, 0.001, "flying right - no rotation")

	var leftward: Projectile = add_child_autofree(ProjectileScene.instantiate())
	leftward.clip_name = "Krin.Firebolt"
	leftward.start(Vector2(300, 100), Vector2(100, 100))
	assert_almost_eq(absf(leftward._bolt_root.rotation), PI, 0.001, "flying left - turned around")

	var diagonal: Projectile = add_child_autofree(ProjectileScene.instantiate())
	diagonal.clip_name = "Krin.Firebolt"
	diagonal.start(Vector2(100, 100), Vector2(200, 200))
	assert_almost_eq(diagonal._bolt_root.rotation, PI / 4.0, 0.001, "flying down-right")


func test_trail_is_not_centered_on_its_own_bounding_box():
	# KrinTrail's real inner sprite (id 2) places its shape at x 0..10,
	# y -3.5..3.5 design units - the clip's origin sits at the streak's
	# LEFT edge, vertically centered, not its texture's own center. The
	# generated scene bakes this as a plain .position on its
	# AnimatedSprite2D (natural, unzoomed units - the same convention
	# resources/sprites/doll_offsets.json uses).
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	assert_false(bolt._trail_sprite.centered, "grows forward from its anchor, not out of its own middle")
	assert_eq(bolt._trail_sprite.position, Vector2(0, -3.5), "left edge on the anchor, vertically centered on it")
	var frame: Texture2D = bolt._trail_sprite.sprite_frames.get_frame_texture("pulse", 0)
	assert_eq(frame.get_size(), Vector2(20, 14), "the position above is in natural units - half this texture's height, unzoomed")


func test_start_with_unknown_clip_falls_back_to_the_tinted_circle():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "NOT_A_REAL_BOLT_CLIP"
	bolt.trail_color = Color.WHITE
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	assert_null(bolt._bolt_sprite, "no matching generated scene - falls back to the _draw() circle guard")


func test_start_loads_the_trail_as_a_non_looping_tinted_pulse():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color(1.0, 0.2, 0.4)
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	assert_not_null(bolt._trail_sprite.sprite_frames, "loaded the real 33-frame KrinTrail generated scene")
	assert_eq(bolt._trail_sprite.sprite_frames.get_frame_count("pulse"), 33, "the real animated content, not sprite 3's 1-frame wrapper")
	assert_false(bolt._trail_sprite.sprite_frames.get_animation_loop("pulse"), "plays once - its own frames already carry the fade in/out")
	assert_almost_eq(bolt._trail_sprite.modulate.r, 1.0, 0.01, "RGB tint only")
	assert_almost_eq(bolt._trail_sprite.modulate.g, 0.2, 0.01)
	assert_almost_eq(bolt._trail_sprite.modulate.b, 0.4, 0.01)


func test_trail_stays_anchored_at_its_spawn_point_as_the_bolt_flies_on():
	# Confirmed empirically (a real running scene): a normal Node2D child
	# keeps inheriting its parent's transform every frame - without
	# top_level=true (baked into the trail's generated scene), the trail
	# would be dragged along as Projectile's own position keeps advancing,
	# instead of staying anchored at the point it was given on the first
	# tick, defeating the whole point of a streak that bridges a growing
	# gap as the bolt flies away.
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	bolt._process(1.0 / 30.0)  # first tick - spawns the trail at the bolt's current position
	var spawn_pos: Vector2 = bolt._trail_sprite.global_position
	for i in 10:
		bolt._process(1.0 / 30.0)  # the bolt keeps advancing
	assert_eq(bolt._trail_sprite.global_position, spawn_pos, "trail stays put while the bolt flies on")
	assert_gt(bolt.global_position.x, spawn_pos.x, "the bolt itself really did move away from that point")


func test_hit_frees_immediately_on_reaching_target():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.did_hit = true
	bolt.start(Vector2(100, 100), Vector2(103, 100))  # short hop - reaches fast
	# A Dictionary is used (not a bare local) because GDScript lambdas
	# capture plain locals by value, not by reference - see
	# test_cutscene_player.gd's identical note.
	var result := {"reached": false}
	bolt.reached_target.connect(func(): result.reached = true)

	for i in 200:
		bolt._process(1.0 / 30.0)
		if bolt.is_queued_for_deletion():
			break

	assert_true(result.reached, "reached_target fired")
	assert_true(bolt.is_queued_for_deletion(), "hit - frees right at the coordinate-cross tick")


func test_trail_outlives_the_bolt_so_its_own_fade_can_finish():
	# The flight to a real target takes ~17 ticks; KrinTrail's own fade
	# runs 33 frames. As the bolt's child the trail would be torn down
	# mid-fade the moment a hit freed the bolt, so its wrapper moves up to
	# be the bolt's sibling as soon as it is placed.
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.did_hit = true
	bolt.start(Vector2(100, 100), Vector2(103, 100))

	var trail_root: Node2D = bolt._trail_root
	var trail_sprite: AnimatedSprite2D = bolt._trail_sprite
	for i in 200:
		bolt._process(1.0 / 30.0)
		if bolt.is_queued_for_deletion():
			break
	assert_true(bolt.is_queued_for_deletion(), "the hit really did free the bolt")
	assert_eq(trail_root.get_parent(), self, "trail's wrapper moved up to the bolt's own parent")

	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(bolt), "the bolt's deferred free has actually run by now")
	assert_true(is_instance_valid(trail_root), "the trail was not taken down with it")
	assert_true(trail_sprite.is_playing(), "it is still running its own fade")
	trail_root.queue_free()


func test_miss_keeps_flying_past_the_target_until_off_screen():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.did_hit = false
	bolt.start(Vector2(100, 100), Vector2(103, 100))
	# A Dictionary is used (not a bare local) because GDScript lambdas
	# capture plain locals by value, not by reference - see
	# test_cutscene_player.gd's identical note.
	var result := {"reached": false}
	bolt.reached_target.connect(func(): result.reached = true)

	# Advance a handful of ticks - reached_target should have already fired
	# (same coordinate-cross tick a hit would use), but the bolt must still
	# be alive, still past the target, not yet off-screen.
	for i in 30:
		bolt._process(1.0 / 30.0)
	assert_true(result.reached, "reached_target fires on a miss too, at the same tick a hit would")
	assert_false(bolt.is_queued_for_deletion(), "miss - doesn't free at the coordinate-cross tick")
	assert_true(bolt.position.x > 103.0, "kept moving past the target")

	# Let it keep flying until it exits this port's own screen bounds.
	for i in 2000:
		bolt._process(1.0 / 30.0)
		if bolt.is_queued_for_deletion():
			break
	assert_true(bolt.is_queued_for_deletion(), "eventually frees once off-screen")


func test_a_miss_with_no_horizontal_travel_still_ends():
	# A caster and target sharing an x coordinate would give the bolt a
	# zero x-step, so it could never cross the off-screen bound and the
	# fly-past would run forever. No battle slot pairing does that today -
	# this is the guard against future data that would.
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.did_hit = false
	bolt.start(Vector2(400, 100), Vector2(400, 300))

	for i in Projectile.MAX_FLIGHT_TICKS + 10:
		bolt._process(1.0 / 30.0)
		if bolt.is_queued_for_deletion():
			break
	assert_true(bolt.is_queued_for_deletion(), "the tick cap ends a flight that can never exit sideways")
```

- [ ] **Step 4: Run the tests**

Run this project's GUT suite scoped to `test/unit/test_projectile.gd`. All tests should pass. If `test_trail_is_not_centered_on_its_own_bounding_box` fails on the exact `Vector2(0, -3.5)` value, re-check Task 2's `vfx_offsets.json` entry for `krintrail` (or whatever `VfxFrames.sanitize("KrinTrail")` actually produces - confirm the key matches) before assuming the test itself is wrong.

- [ ] **Step 5: Commit**

```bash
git add scenes/battle/projectile.tscn scripts/battle/projectile.gd test/unit/test_projectile.gd
git commit -m "feat: Projectile instantiates each clip's own registration-correct scene"
```

---

### Task 5: `ImpactEffect` - instantiate the clip's own scene

**Files:**
- Modify: `scenes/battle/impact_effect.tscn`
- Modify: `scripts/battle/impact_effect.gd`
- Modify: `test/unit/test_impact_effect.gd`

**Interfaces:**
- Consumes: `scenes/battle/vfx/impacts/<name>.tscn` (Task 3); `VfxFrames.sanitize()`.
- Produces: `ImpactEffect.play(clip_name)` - UNCHANGED public interface; `battle_scene.gd`'s `_spawn_impact()` needs no changes.

- [ ] **Step 1: Shrink `impact_effect.tscn`**

Replace its contents entirely - no more static `Anim` child:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/battle/impact_effect.gd" id="1_impact"]

[node name="ImpactEffect" type="Node2D"]
script = ExtResource("1_impact")
```

- [ ] **Step 2: Rewrite `impact_effect.gd`**

Replace its contents entirely:

```gdscript
# impact_effect.gd
# A one-shot BOOM_*/ex_* impact clip - plays once at wherever it's
# positioned, then frees itself. Art comes from a per-clip generated
# scene (dev/urchin_dev/swf/extract/vfx_scenes.py's own output, under
# scenes/battle/vfx/impacts/), already carrying its own frames and its
# real registration offset (dev/urchin_dev/swf/extract/vfx_offsets.py) -
# this script only instantiates it and wires cleanup. The source never
# explicitly removes its own equivalent clips ("bbb"+counter in
# frame_42/DoAction_4.as's krinBoltMake) - a deliberate improvement, not
# an unfaithful port. See docs/superpowers/specs/2026-08-19-vfx-registration-scenes-design.md.
class_name ImpactEffect
extends Node2D

const VFX_SCENE_DIR: String = "res://scenes/battle/vfx/impacts/"

var _root: Node2D
var _anim_sprite: AnimatedSprite2D


func play(clip_name: String) -> void:
	if clip_name.is_empty():
		queue_free()
		return
	var scene: PackedScene = load("%s%s.tscn" % [VFX_SCENE_DIR, VfxFrames.sanitize(clip_name)])
	if scene == null:
		queue_free()
		return
	_root = scene.instantiate()
	add_child(_root)
	_anim_sprite = _root.get_node("AnimatedSprite2D")
	_anim_sprite.animation_finished.connect(queue_free)  # frees the whole ImpactEffect, as before
	_anim_sprite.play("default")
```

- [ ] **Step 3: Rewrite `test_impact_effect.gd`**

Replace its contents entirely:

```gdscript
# ImpactEffect - a one-shot animation that frees itself when done. Art
# comes from a per-clip generated scene under scenes/battle/vfx/impacts/.
# docs/superpowers/specs/2026-08-19-vfx-registration-scenes-design.md.
extends GutTest

const ImpactEffectScene = preload("res://scenes/battle/impact_effect.tscn")


func test_play_empty_name_is_a_noop_that_frees_the_node():
	var effect: ImpactEffect = add_child_autofree(ImpactEffectScene.instantiate())
	effect.play("")
	assert_true(effect.is_queued_for_deletion(), "no clip name - nothing to play, frees immediately")


func test_play_unknown_clip_is_a_noop_that_frees_the_node():
	var effect: ImpactEffect = add_child_autofree(ImpactEffectScene.instantiate())
	effect.play("NOT_A_REAL_IMPACT_CLIP")
	assert_true(effect.is_queued_for_deletion(), "no matching generated scene - frees immediately")


func test_play_real_clip_plays_and_frees_on_finish():
	var effect: ImpactEffect = add_child_autofree(ImpactEffectScene.instantiate())
	effect.play("BOOM_SPARK")
	assert_false(effect.is_queued_for_deletion(), "a real clip starts playing, not immediately freed")
	assert_true(effect._anim_sprite.is_playing(), "the one-shot animation is running")
	effect._anim_sprite.animation_finished.emit()
	assert_true(effect.is_queued_for_deletion(), "frees once the one-shot animation finishes")


func test_impact_art_is_halved_to_undo_the_extractors_2x_zoom():
	# Every generated scene's baked scale collapses to exactly 1/ZOOM -
	# see extract_vfx_scenes.py's own note on why.
	var effect: ImpactEffect = add_child_autofree(ImpactEffectScene.instantiate())
	effect.play("BOOM_SPARK")
	assert_eq(effect._anim_sprite.scale, Vector2(0.5, 0.5), "impact renders at its design size")


func test_impact_is_not_centered_on_its_own_bounding_box():
	# Real registration point from the generated scene, not Godot's
	# centered=true default - the whole reason this rework exists.
	var effect: ImpactEffect = add_child_autofree(ImpactEffectScene.instantiate())
	effect.play("BOOM_SPARK")
	assert_false(effect._anim_sprite.centered, "positioned at its real registration point, not centered on its texture")
```

- [ ] **Step 4: Run the tests**

Run this project's GUT suite scoped to `test/unit/test_impact_effect.gd`. All tests should pass.

- [ ] **Step 5: Commit**

```bash
git add scenes/battle/impact_effect.tscn scripts/battle/impact_effect.gd test/unit/test_impact_effect.gd
git commit -m "feat: ImpactEffect instantiates each clip's own registration-correct scene"
```

---

### Task 6: Retire `VfxFrames.load_frames()`/`VFX_SCALE`

**Files:**
- Modify: `scripts/entities/vfx_frames.gd`
- Modify: `test/unit/test_vfx_frames.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `VfxFrames.sanitize()` - the only surviving member, UNCHANGED signature/behavior. Both `Projectile` and `ImpactEffect` (Tasks 4/5) already only call this one.

- [ ] **Step 1: Confirm nothing else still calls the retired members**

```bash
rg -n "VfxFrames\.load_frames|VfxFrames\.VFX_SCALE" scripts/ test/
```

Expected: no matches (Tasks 4 and 5 already removed every call site). If anything shows up, stop - a caller was missed in an earlier task.

- [ ] **Step 2: Rewrite `vfx_frames.gd`**

Replace its contents entirely:

```gdscript
# vfx_frames.gd
# Shared VFX naming helper. Frame loading and the flat zoom-compensation
# scale this class used to provide are retired - every VFX clip now gets
# its own generated scene (dev/urchin_dev/swf/extract/vfx_scenes.py) with
# real frames and a real per-clip registration offset already baked in,
# rather than being built from a dynamically-scanned PNG folder at
# runtime. sanitize() is the one piece Projectile and ImpactEffect still
# need: it turns a clip_name (Ability.animation_label/impact_effect_name)
# into the generated scene's filename.
class_name VfxFrames
extends RefCounted


# Mirrors dev/urchin_dev/swf/extract/vfx.py's own sanitize() exactly
# (re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_").lower()), so a clip
# name carrying a character the filename can't hold resolves to the
# scene the extractor actually wrote. BuffIcons keeps its own copy of
# this transform for its own unrelated icon-name convention.
static func sanitize(name: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^A-Za-z0-9]+")
	return regex.sub(name, "_", true).lstrip("_").rstrip("_").to_lower()
```

- [ ] **Step 3: Rewrite `test_vfx_frames.gd`**

Replace its contents entirely:

```gdscript
# VfxFrames.sanitize() - turns a clip name into the filename
# dev/urchin_dev/swf/extract/vfx_scenes.py wrote for it. Frame-loading
# tests retired along with load_frames() itself - every clip now loads
# from a generated scene instead of a dynamically-scanned folder.
# docs/superpowers/specs/2026-08-19-vfx-registration-scenes-design.md.
extends GutTest


func test_sanitize_lowercases_and_collapses_non_alnum_runs():
	assert_eq(VfxFrames.sanitize("Krin.Firebolt"), "krin_firebolt")


func test_sanitize_matches_across_casing_variants():
	# KRIN.MAGICBOLT and Krin.Magicbolt are the same clip under Flash's
	# case-insensitive attachMovie lookup - both must resolve to the
	# scene extract_vfx_scenes.py actually wrote.
	assert_eq(VfxFrames.sanitize("KRIN.MAGICBOLT"), VfxFrames.sanitize("Krin.Magicbolt"))
```

- [ ] **Step 4: Run the full GUT suite**

Every test in the project should pass, not just this file's - this task removes code other files might still reference.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/vfx_frames.gd test/unit/test_vfx_frames.gd
git commit -m "refactor: retire VfxFrames.load_frames()/VFX_SCALE, superseded by generated scenes"
```
