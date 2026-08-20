# VFX Registration Scenes: Design

## Goal

Fix the registration-point mismatch parked at the end of the missile
projectile art work: `Bolt` and `ImpactEffect`'s sprites use Godot's default
`centered = true`, which draws them centered on their own bounding box
instead of at the source clip's real local origin. Replace the current
dynamic PNG-folder loading and flat `VFX_SCALE` approximation with one
correctly-positioned scene per clip, generated once directly from the SWF's
own timeline data.

## Background

- The parked finding, from the missile projectile art final review: `Bolt`
  (and `ImpactEffect`'s `Anim`) likely have the same registration-point
  mismatch `Trail` had before its own fix (`top_level = true`,
  `centered = false`, `offset = Vector2(0, -7)`). Rotating bolts (added in
  that same fix wave) makes a wrong pivot far more visible than a static
  sprite sitting a few pixels off: the whole clip visibly swings around the
  wrong point instead.
- Investigated directly against the SWF's own timeline data
  (`dev/source_files/swf_xml/sonny-2-2900.xml`), not assumption:
  - `parse_swf_xml()`/`make_char_bounds()` (`dev/urchin_dev/swf/xml_lib.py`)
    already compute a character's rendered bounds, but only from its
    **first frame**. That's correct for a clip whose own top-level
    placement never moves across its timeline (only color/glow tweening),
    and wrong for a clip whose placement does move.
  - Checked all 15 bolt clips directly, counting distinct top-level
    placement matrices across each clip's own frames: 12 are static
    (frame-1-only bounds already correct); 3 move:
    `KRIN.SHADOWSHOCK` (21 distinct matrices across 22 frames),
    `Krin.Electrobolt` (21/22), `Krin.Iceball` (3/5).
  - Same check across the 41 distinct `impact_effect_name` values (36
    resolvable to a real sprite): 5 move, including `BOOM1`/`BOOM2`, the
    same two clips that caused the earlier packed-spritesheet width-cap
    bug.
  - Proved this matters concretely, not just in theory: `KRIN.SHADOWSHOCK`'s
    real exported PNG is 324x323 px. Frame-1-only bounds compute
    149x153 px, less than half. Using frame-1-only data for this clip
    would place its registration point at a badly wrong spot.
  - 30 of the 51 underlying VFX clips use `RemoveObjectTag`/
    `RemoveObject2Tag` somewhere in their own timeline (typically once,
    near the end), so a correct fix has to handle a depth being cleared
    partway through, not just moved.
  - Validated the bounds-to-pixel formula against the already-shipped,
    tested `Trail` fix before building anything further on it:
    `KrinTrail`'s real content (sprite id 2) computes to a natural-units
    bounds origin of `(0.0, -3.5)` px. At `ZOOM = 2.0` (the zoom every
    extractor in this project renders at), `-3.5 * 2 = -7`, an exact
    match to the already-shipped `offset = Vector2(0, -7)` (that fix used
    a shared node's `.offset`, in pre-scale texture-pixel units; the
    dedicated-scene design below uses a child node's `.position` instead,
    in the same natural, unzoomed units as `doll_offsets.json` - the same
    real position, expressed in the convention each property expects).
  - A second, larger gap turned up while building the full-timeline
    extension: `KRIN.SHADOWSHOCK`'s placed child (sprite id 2432, not
    itself export-named) has its own independent 3-frame timeline -
    confirmed directly, not assumed. `make_char_bounds`'s existing
    first-frame-only recursion for nested children (the scope cut this
    design first assumed) misses frames 2 and 3 of that child entirely.
    Fixed by making the new function recurse with full-timeline treatment
    at every nesting level, not just the top sprite - validated against
    `ffdec`'s own SVG-per-frame export (a second, independent renderer)
    for `KRIN.SHADOWSHOCK`, which agreed with the corrected Python
    computation to within rounding (219.37x218.76 px computed vs.
    219.2x218.7 px from the SVG's own `width`/`height`).
  - A third, separate gap: most bolt and impact clips carry a glow
    filter (`Krin.Firebolt`: 10 glow-filter placements, `KRIN.SHADOWSHOCK`:
    44; `KrinTrail`, the one already-validated clip, has none). `ffdec`'s
    PNG exporter bakes the glow's rendered footprint into its canvas;
    neither the raw `shapeBounds` XML data nor `ffdec`'s own SVG exporter
    account for it. Confirmed concretely: even with the nested-timeline
    fix above, `KRIN.SHADOWSHOCK`'s computed size (219x219 px) still
    undershoots its real exported canvas (324x323 px) by 1.5x;
    `Krin.Firebolt`'s undershoots by 3.3x (60x60 px computed vs.
    196x196 px real).
  - Resolved by measuring the real canvas size directly from the
    already-extracted PNG (trivial - it's just the file's own pixel
    dimensions) and assuming the filter padding is added symmetrically
    around the computed shape's own center, rather than trying to
    replicate Flash's exact blur-filter rendering math. Confirmed against
    real pixel data, not assumed: `Krin.Firebolt`'s solid core (opaque
    pixels, excluding the soft glow halo) has its centroid at
    `(97.9, 98.0)` in a 196x196 canvas centered on `(98.0, 98.0)` - a
    match to within 0.1 px. For the 8 of 51 clips whose own placement
    moves across frames (`KRIN.SHADOWSHOCK`, `Krin.Electrobolt`,
    `Krin.Iceball`, and 5 impact clips including `BOOM1`/`BOOM2`), the
    same direct-pixel check on one representative frame showed a small
    residual gap (about 2% of canvas width) between the corrected
    formula's prediction and that frame's own core centroid - project
    owner confirmed applying the same corrected formula to these 8
    clips anyway, since it is still a meaningful improvement over
    today's `centered = true` regardless of the small residual
    imprecision, and there is no way to verify further without
    rendering the game (no screenshot/visual capability in this
    environment).
- Considered three ways to deliver the corrected numbers to Godot, in the
  order they came up:
  1. A runtime JSON lookup (`vfx_offsets.json`), applied via `.offset =`/
     `.scale =` on `Projectile`/`ImpactEffect`'s existing shared nodes at
     play time. Works, but needs `AnimatedSprite2D.offset`'s pre-scale,
     texture-pixel-space convention (real, verified, but non-obvious), and
     keeps a second runtime mechanism (an offset lookup) alongside frame
     loading.
  2. One shared `SpriteFrames` per role (`Bolt`/`Anim`), holding every clip
     as a separately-named animation, selected via `.play(clip_name)`.
     Solves frame loading, but not the registration point: a `SpriteFrames`
     animation carries no transform of its own. Confirmed empirically
     (not just in theory) while prototyping this: adjusting `offset`/
     `position` on the shared node moves whichever animation is currently
     playing, not the one it was tuned for. Still needs (1)'s runtime
     lookup layered on top to work at all.
  3. **Adopted:** one dedicated scene per clip, generated once, with its
     frames and its correct baked transform (`centered = false`,
     `position`, `scale`) together in the same file. No runtime lookup of
     any kind: every value that used to need a JSON read at play time is
     now a plain node property, exactly like every other hand-authored
     scene in this project. The generator itself is a one-time step: run
     once, review and commit the output, never rerun as part of the normal
     build (the source SWF is fixed; there's no new content to extract
     later).

## Requirements

- Extend `dev/urchin_dev/swf/xml_lib.py` with a full-timeline union-bounds
  function, correct for every VFX clip, not just the 46 of 51 that happen
  to have a static top-level placement. `parse_swf_xml`/`make_char_bounds`
  stay exactly as they are (the doll-art pipeline depends on their current
  first-frame-only behavior); this is a new, additive function.
- Generate one `.tscn` per clip (15 bolts + 1 trail + 36 impacts, 52 total)
  with the correct frames and baked transform, via a one-time script.
  Not part of the normal build once committed.
- Keep a checked-in `assets/vfx/vfx_offsets.json` as the durable,
  human-readable record of the real per-clip numbers, matching this
  project's existing convention for persisting extracted SWF data (e.g.
  `resources/sprites/doll_offsets.json`). This is an audit trail for the
  baked scenes, not something read at Godot runtime.
- `Projectile`/`ImpactEffect` load the clip-specific scene by name instead
  of dynamically scanning a PNG folder or applying a runtime offset
  lookup. `battle_scene.gd`'s own calls into both, `_spawn_impact()` and
  `_fire_projectile()`, do not change; only what happens inside
  `Projectile`/`ImpactEffect` changes.
- Retire `VfxFrames.load_frames()` (dynamic PNG-folder probing) and
  `VfxFrames.VFX_SCALE` (the flat `0.5` approximation), both superseded
  by the baked scenes. `VfxFrames.sanitize()` stays: it is still how a
  `clip_name` (from `Ability.animation_label`/`impact_effect_name`)
  resolves to a scene filename.
- Fold `Trail`'s already-shipped, already-correct fix into the same
  generated-scene mechanism as every other clip, so there is one
  consistent pipeline instead of one clip living differently from the
  other 51.

## Architecture

### `xml_lib.py`: full-timeline union bounds (new, additive function)

A new function, alongside the existing `make_char_bounds`:

```python
def make_timeline_bounds(shape_bounds, xml):
    """-> (sprite_id) -> (xmin, ymin, xmax, ymax) twips, or None.

    Unlike make_char_bounds (first frame only), recurses with FULL-TIMELINE
    treatment at every nesting level, not just the top sprite - confirmed
    necessary: KRIN.SHADOWSHOCK's placed child (sprite id 2432) has its own
    independent 3-frame timeline, and first-frame-only recursion for it
    (this design's original assumption) missed 2 of its 3 frames. Reuses
    the existing snapshot_timeline() (already used by item_icons.py,
    ability_icons.py, buff_icons.py, faces.py, model1_animations.py) rather
    than duplicating its PlaceObject/RemoveObject tag-walking: for a given
    sprite_id, counts its own frames (sprite_body(xml, sprite_id).count(
    "ShowFrameTag")), calls snapshot_timeline(xml, sprite_id, set(range(1,
    frame_count + 1))) for a full-timeline depth-state snapshot per frame,
    and for every {cid, mat} entry in every frame's snapshot, recurses into
    this same function for cid (memoized), transforms the result by mat
    (transform_rect(), already in xml_lib.py), and unions across every
    entry in every frame - the same min/max accumulation make_char_bounds
    already uses for its own (first-frame-only) recursive union. Validated
    against ffdec's own SVG-per-frame export for KRIN.SHADOWSHOCK (an
    independent renderer): 219.37x218.76 px computed vs. 219.2x218.7 px
    from the SVG's own width/height, agreeing to within rounding.
    """
```

### `dev/urchin_dev/swf/extract/vfx_offsets.py` (new, registered `extract_vfx_offsets`)

Computes and writes `assets/vfx/vfx_offsets.json`:

- Resolves every VFX clip name (the 15 bolt names, `KrinTrail` (sprite id
  2, same hardcoded override `vfx.py` already uses), and the 36 resolvable
  `impact_effect_name` values from `moves_abilities.json`), using the same
  resolution logic `vfx.py` already has (import and reuse it rather than
  duplicating the export-table lookup a second time).
- For each, calls the new `make_timeline_bounds` to get `bounds` (twips),
  then corrects for glow-filter padding by measuring the real exported
  canvas directly from frame 1 of the clip's already-extracted PNG folder
  (`PIL.Image.open(...).size`) and assuming the padding is symmetric
  around the computed shape's own center (confirmed against real pixel
  data - see Background):
  ```python
  computed_w = (bounds[2] - bounds[0]) / 20.0   # natural (unzoomed) px
  computed_h = (bounds[3] - bounds[1]) / 20.0
  computed_cx = (bounds[0] + bounds[2]) / 2.0 / 20.0
  computed_cy = (bounds[1] + bounds[3]) / 2.0 / 20.0

  real_w_px, real_h_px = <frame 1's actual PNG size>  # ZOOM = 2.0, same
                                                        # zoom vfx.py used
  real_w = real_w_px / ZOOM   # natural units, matching computed_w/h
  real_h = real_h_px / ZOOM

  x = round(computed_cx - real_w / 2.0, 2)   # natural units, matching
  y = round(computed_cy - real_h / 2.0, 2)   # doll_offsets.json's own
                                               # convention - NOT zoomed;
                                               # the dedicated scene's
                                               # child node consumes this
                                               # as plain .position
  w = round(real_w, 2)   # the real, glow-inclusive size, not the
  h = round(real_h, 2)   # filter-blind computed size
  ```
  For `KrinTrail` (no filter, zero padding) this reduces to the plain
  bounds-to-px conversion and reproduces the already-shipped fix exactly:
  `x = 0`, `y = -3.5` (natural units - the same real position as the old
  `offset = Vector2(0, -7)`, expressed in `.position`'s unzoomed
  convention instead of `.offset`'s zoomed one).
- Writes `assets/vfx/vfx_offsets.json`: one `{"x": ..., "y": ..., "w": ...,
  "h": ...}` entry per clip, keyed by the same `sanitize()`d name `vfx.py`
  already uses for its PNG folder names.
- Unresolved clip names (the same 5 impact names `vfx.py` already can't
  resolve) are skipped with the same warning-and-continue tolerance
  `vfx.py` uses.

### `dev/urchin_dev/swf/extract/vfx_scenes.py` (new, registered `extract_vfx_scenes`, one-time use)

Reads `vfx_offsets.json` plus the PNG folders `vfx.py` already produced
under `assets/vfx/`, and writes one `.tscn` per clip:

- `scenes/battle/vfx/bolts/<sanitized_name>.tscn` (15)
- `scenes/battle/vfx/trail/krintrail.tscn` (1)
- `scenes/battle/vfx/impacts/<sanitized_name>.tscn` (36)

Each generated scene:

```
[gd_scene format=3]

[ext_resource type="Texture2D" path="res://assets/vfx/bolts/<name>/1.png" id="1"]
... one ext_resource per frame, no uid= attribute (Godot assigns/tolerates
    its absence on a plain path-based ext_resource - verify with one
    hand-generated file loaded in the editor before generating the other 51)

[sub_resource type="SpriteFrames" id="SpriteFrames_1"]
animations = [{
"frames": [{"duration": 1.0, "texture": ExtResource("1")}, ...],
"loop": <true for bolts, false for trail/impacts - matches today's values>,
"name": &"<fly | pulse | default - matches today's Projectile/ImpactEffect .play() calls>",
"speed": 30.0
}]

[node name="<Bolt | Trail | Impact>" type="Node2D"]
<top_level = true, ONLY on the trail scene - Trail is the one clip that must
 stay anchored at its spawn point independent of the flying bolt; every
 other category leaves this unset>

[node name="AnimatedSprite2D" type="AnimatedSprite2D" parent="."]
position = Vector2(<x>, <y>)      # from vfx_offsets.json, natural units
scale = Vector2(<w/tex_w>, <h/tex_h>)  # from vfx_offsets.json vs. the
                                        # actual loaded texture size -
                                        # collapses to ~0.5 for the common
                                        # case, but computed per clip
centered = false
sprite_frames = SubResource("SpriteFrames_1")
animation = &"<fly | pulse | default>"
```

The child node is always literally named `AnimatedSprite2D` across all 52
files, so `Projectile`/`ImpactEffect` can reach it the same way regardless
of category (`.get_node("AnimatedSprite2D")`).

No JSON sidecar per scene beyond the shared `vfx_offsets.json`. This
script is not meant to run again after its one commit, so there's nothing
to keep in sync.

### `Projectile`: `scenes/battle/projectile.tscn` + `scripts/battle/projectile.gd`

`projectile.tscn` shrinks to just the script-bearing root, no more static
`Bolt`/`Trail` children; both are instantiated per `clip_name` in `start()`:

```
[node name="Projectile" type="Node2D"]
script = ExtResource("1_projectile")
```

```gdscript
const BOLT_SCENE_DIR := "res://scenes/battle/vfx/bolts/"
const TRAIL_SCENE: PackedScene = preload("res://scenes/battle/vfx/trail/krintrail.tscn")

var _bolt_root: Node2D
var _bolt_sprite: AnimatedSprite2D
var _trail_root: Node2D
var _trail_sprite: AnimatedSprite2D
var _trail_base_scale: Vector2 = Vector2.ONE  # the scene's own baked scale,
                                                # captured once so growth
                                                # multiplies the real
                                                # per-clip ratio instead of
                                                # a flat constant

func _load_bolt_sprite() -> void:
	if clip_name.is_empty():
		return  # tinted-circle _draw() fallback stays, as today
	var scene: PackedScene = load("%s%s.tscn" % [BOLT_SCENE_DIR, VfxFrames.sanitize(clip_name)])
	if scene == null:
		return  # unresolved clip - same fallback
	_bolt_root = scene.instantiate()
	_bolt_sprite = _bolt_root.get_node("AnimatedSprite2D")
	add_child(_bolt_root)
	_bolt_root.rotation = _step.angle()  # rotating the wrapper rotates the
	                                       # baked-offset sprite around the
	                                       # clip's true registration point
	_bolt_sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_bolt_sprite.play("fly")

func _load_trail_sprite() -> void:
	_trail_root = TRAIL_SCENE.instantiate()
	_trail_sprite = _trail_root.get_node("AnimatedSprite2D")
	_trail_base_scale = _trail_sprite.scale
	_trail_sprite.modulate = trail_color
	_trail_root.visible = false
```

`_spawn_trail()` and the `_process()` growth line operate on `_trail_root`
(added/reparented/rotated) and `_trail_sprite` (played/tinted/grown)
instead of a single shared node:

```gdscript
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

# in _process(), replacing the current VFX_SCALE-based growth line:
if is_instance_valid(_trail_root) and _trail_root.visible:
	_trail_growth += 0.083 * _step.length() * _speed_const
	_trail_sprite.scale = Vector2(_trail_base_scale.x * _trail_growth, _trail_base_scale.y)
```

`top_level = true` is no longer set at runtime. It's baked into
`krintrail.tscn`'s own root node, since it's now a permanent property of
that one scene rather than something every trail instance needs set on it.

`BOLT_DIR`/`TRAIL_DIR` (the old PNG-folder path constants) are removed,
dead once frames are embedded in the generated scenes rather than read by
folder path at runtime.

### `ImpactEffect`: `scenes/battle/impact_effect.tscn` + `scripts/battle/impact_effect.gd`

Same restructuring: `impact_effect.tscn` shrinks to just its script-bearing
root (no more static `Anim` child); `play()` instantiates the resolved
clip scene as its child.

```gdscript
const VFX_DIR := "res://scenes/battle/vfx/impacts/"

func play(clip_name: String) -> void:
	if clip_name.is_empty():
		queue_free()
		return
	var scene: PackedScene = load("%s%s.tscn" % [VFX_DIR, VfxFrames.sanitize(clip_name)])
	if scene == null:
		queue_free()
		return
	var root: Node2D = scene.instantiate()
	add_child(root)
	var anim_sprite: AnimatedSprite2D = root.get_node("AnimatedSprite2D")
	anim_sprite.animation_finished.connect(queue_free)  # frees the whole
	                                                      # ImpactEffect, as
	                                                      # today
	anim_sprite.play("default")
```

Impact clips are never rotated (matching source and the current, unchanged
behavior), so no `.rotation` line is needed on the instantiated root here.

### `VfxFrames`: `scripts/entities/vfx_frames.gd`

Shrinks to just `sanitize()`. `load_frames()` and `VFX_SCALE` are removed,
both fully superseded by the generated scenes.

### `battle_scene.gd`

No changes. `_spawn_impact()` and `_fire_projectile()` call the same
public `ImpactEffect.play(clip_name)` / `Projectile.start(from, to)`
interfaces as today; everything that changes is internal to
`Projectile`/`ImpactEffect`.

## Testing

- No pytest suite exists anywhere in this project's Python side (`dev/`
  has no test files, no pytest config) - matching that established
  convention rather than introducing one for a single function,
  `make_timeline_bounds` is verified the same way every extraction script
  already is: a diagnostic run printing its result for known clips,
  inspected directly. `KrinTrail`'s static case should reproduce the
  bounds behind the already-shipped `(0, -7)`; `KRIN.SHADOWSHOCK`'s moving
  case should reproduce the 219x219 px (natural-corrected) result recorded
  in the Background section, cross-checked against `ffdec`'s own SVG
  export as that section describes.
- No automated test for `vfx_offsets.py`/`vfx_scenes.py` either, same
  convention as `item_icons.py`/`buff_icons.py`/`vfx.py`: verified by
  direct inspection - spot check a handful of generated scenes' baked
  `position`/`scale` against `vfx_offsets.json`, and confirm one generated
  file loads correctly (via a GUT test that `load()`s it and checks the
  result) before generating the rest, settling the `uid=`-omission
  question with a real, checked result instead of an assumption.
- `test_vfx_frames.gd`: remove the `load_frames()` tests (function
  retired); keep or add a minimal `sanitize()` test if one doesn't already
  exist elsewhere.
- `test_projectile.gd` / `test_impact_effect.gd`: rewrite the tests that
  currently assume a static `$Bolt`/`$Trail`/`$Anim` child loaded via
  `VfxFrames.load_frames()` to reflect the new instantiate-per-clip-scene
  flow: property assertions on the instantiated root's `position`/
  `scale`/`rotation` and the located `AnimatedSprite2D` child, same style
  as the existing tests, no visual verification available in this
  environment (unchanged limitation from the prior review).

## Out of Scope

- Re-deriving the already-shipped `Trail` fix's numbers from scratch. Its
  existing values are kept as the validation reference for the new
  formula, not recomputed independently.
- Any change to `battle_scene.gd`'s wiring, hit/miss logic, or the
  cast-glow tint. Untouched by this design.
- Handling a hypothetical independently-animating nested sub-timeline
  inside a bolt/impact clip's own children. No clip sampled during
  design showed evidence of this; if a future clip needs it, that's a
  follow-up to the `make_timeline_bounds` recursion, not solved here.
