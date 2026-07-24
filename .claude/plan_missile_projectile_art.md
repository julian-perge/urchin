# Implementation Plan — Missile Projectile Art

## Problem Statement
`Projectile` currently draws a generic tinted circle+line for every bolt and shows no impact effect at all (for missile, melee, or shock). The goal is to replace the circle+line with real per-clip bolt art extracted from the SWF (`AnimatedSprite2D`, one sprite sheet per bolt clip), add a `KrinTrail` streak effect using the same tint mechanism, play `BOOM_*` impact clips as one-shot animations at the target on every move type (melee impact, shock cast, missile arrival), and import the `colortobe` hex from `moves_abilities.json` so the glow tint uses the original per-move color rather than the element color approximation.

## Requirements
- Extract all 15 bolt clips + `KrinTrail` from the web SWF as per-clip sprite sheets into `assets/vfx/bolts/`; strip down to every-other frame if a clip exceeds 15 frames
- Extract all referenced `BOOM_*` / `ex_*` impact clips as per-clip sprite sheets into `assets/vfx/impacts/`
- Add `visual_effect_color: Color` to `Ability` (imported from `11_visual_effect_color`); use it for the cast glow tint in `battle_scene.gd` instead of the current element-color approximation
- `Projectile` becomes an `AnimatedSprite2D`-bearing scene (`projectile.tscn`): the bolt is a real per-clip sprite sheet animation, the trail is a separate `KrinTrail` node (tinted `Node2D` with custom `_draw()`), all existing `krinBoltMake` movement math untouched
- A new `ImpactEffect` scene (`impact_effect.tscn`) plays any `BOOM_*` clip as a one-shot `AnimatedSprite2D` then `queue_free`s
- `battle_scene.gd` spawns `ImpactEffect` on missile arrival, melee `attack_connected`, and shock cast tick (all three hook points already exist)
- GUT tests cover `ImpactEffect` auto-free after one loop and `Ability.visual_effect_color` parsing
- No new third-party dependencies; Python extraction uses the existing `swf_xml_lib` + `ffdec` pipeline

## Background
- The 15 bolt clips are `ExportAssetsTag`-named `DefineSprite`s — pure shape/tween content, no ActionScript. `snapshot_timeline` in `swf_xml_lib.py` iterates every frame of a sprite timeline; `extract_doll_art.py`'s `paste_char` + bulk shape export is the exact composite pattern needed.
- `KrinTrail` (web sprite 3, Steam sprite 205) is structurally identical — short tween, same extraction path.
- `BOOM_*` clips are also named `DefineSprite`s, shape/tween, no AS. Same extraction script handles them.
- `11_visual_effect_color` is already in the JSON as a hex string (`"0xFF3366"`) for every non-None move. It is the `colortobe` value that tints both the cast glow subclips AND the `KrinTrail` trail.
- The 15 bolt clip names (from `NEXT_PHASES.md`): `Krin.Magicbolt`, `Krin.Electrobolt`, `Krin.Electrobolt2`, `Krin.Poisonbolt`, `KRIN.POISONBOLT2`, `Krin.Iceball`, `Krin.Iceblade`, `Krin.Icebolt`, `KRIN.SHADOWSHOCK`, `KRIN.YELLOWBLADE`, `KRIN.SHADOWBLADE`, `Krin.Firebolt`, `KRIN.BLADEWHITE`, `KRIN.REDBLADE`, `KRIN.REDBOLT`.
- BOOM clip names: collect programmatically from all unique `13_impact_effect_name` values in `moves_abilities.json` (guaranteed complete). Known set: `BOOM1`, `BOOM2`, `BOOM3`, `BOOM_ANAS`, `BOOM_DARK`, `BOOM_RED`, `BOOM_SPARK`, `BOOM_STAR_PURPLE`, `BOOM_SLASH2`, `BOOM_SLASHORANGE`, `BOOM_SLASHBLUE`, `BOOM_SLASHGREEN`, `BOOM_SLASHPURPLE`, `ex_SPRBLUE`, `ex_AnasOut2`.
- `ExportAssetsTag` name → sprite ID resolved via `parse_swf_xml`'s `export_name_to_id` dict against the web SWF.

```
Extraction pipeline:
  swf_xml_lib.snapshot_timeline(sprite_id, all_frames)
     └─> per-frame paste_char composite
         └─> horizontal sprite sheet PNG  (assets/vfx/bolts/<ClipName>.png)
             + JSON sidecar               (assets/vfx/bolts/<ClipName>.json)
                {"frame_count": N, "frame_width": W, "frame_height": H, "fps": 30}

Godot runtime:
  projectile.tscn
    Node2D (root, krinBoltMake movement)
      AnimatedSprite2D "Bolt"   <- sprite sheet loaded by clip name, looping during flight
      Node2D "Trail"            <- custom _draw() stretched line, tinted by visual_effect_color

  impact_effect.tscn
    Node2D (root)
      AnimatedSprite2D "Anim"   <- plays once, animation_finished -> queue_free
```

## Task Breakdown

### Task 1: Extract bolt clips, `KrinTrail`, and `BOOM_*` impact clips from the SWF
- Objective: produce sprite sheet PNGs + JSON sidecars for all 15 bolt clips, `KrinTrail`, and all referenced impact clips into `assets/vfx/bolts/` and `assets/vfx/impacts/`.
- Create `conversion_scripts/swf_extraction/extract_vfx_sprites.py`.
- **Sprite ID resolution**: call `parse_swf_xml(WEB_SWF_XML)` to get `export_name_to_id`. Build the bolt target list from the 15 clip names above plus `"KrinTrail"`. Build the BOOM target list programmatically: read `moves_abilities.json`, collect every unique non-empty `13_impact_effect_name` string. This guarantees no impact name is missed.
- **Per-clip extraction loop**:
  - `snapshot_timeline(xml, sprite_id, set(range(1, MAX_FRAMES + 1)))` — use `MAX_FRAMES = 60` as a safe upper bound.
  - If resulting frame count > 15, downsample to every-other frame (`frames[::2]`).
  - Collect all shape IDs across all frames of the clip, one bulk `ffdec -selectid` export per clip (cap at 400 IDs per call, same pattern as `extract_item_icons.py`).
  - `paste_char` composite per frame using `make_char_bounds` for the canvas origin. Canvas size = the clip's own rendered bounds.
  - Pack frames into a horizontal sprite sheet PNG. Write a JSON sidecar: `{"frame_count": N, "frame_width": W, "frame_height": H, "fps": 30}`.
- Print per-clip summary to stderr: `clip_name: N frames, WxH px`. Print a final `UNRESOLVED: [names]` list for any clip whose `ExportAssetsTag` name wasn't found in the web SWF export table.
- Idempotent: skip if `.png` already exists unless `--force` is passed.
- Demo: `assets/vfx/bolts/` contains ~16 PNGs + JSON sidecars (15 bolts + KrinTrail). `assets/vfx/impacts/` contains ~15 PNGs + JSON sidecars. Script exits cleanly with a per-clip summary on stderr.

### Task 2: Import `visual_effect_color` into `Ability` and wire the cast glow
- Objective: the `colortobe` hex from `moves_abilities.json` reaches `battle_scene.gd` so cast glow tint uses the original per-move color, not the element approximation.
- Add to `ability.gd`:
  ```gdscript
  @export var visual_effect_color: Color
  ```
- In `Ability.from_json`:
  ```gdscript
  var raw_color = data.get("11_visual_effect_color")
  ability.visual_effect_color = Color(raw_color) if raw_color is String else Color.WHITE
  ```
  If `Color("0xFF3366")` doesn't parse in Godot 4, use `Color.html(raw_color.substr(2))` instead (strips the `0x` prefix).
- In `battle_scene.gd`'s `_play_move_event`, replace:
  ```gdscript
  caster_visual.modulate = _move_color(move).lerp(Color.WHITE, 0.4)
  ```
  with:
  ```gdscript
  caster_visual.modulate = move.visual_effect_color.lerp(Color.WHITE, 0.4)
  ```
- GUT test: assert `MoveManagerAuto.get_move(5).visual_effect_color` approximately equals `Color(1.0, 0.2, 0.4)` (the `0xFF3366` Magicbolt/Nuke value). Assert move id 0 ("None") yields `Color.WHITE` (Undefined fallback).
- No other file changes in this task.
- Demo: GUT passes. In a live battle, the cast glow on a Firebolt move shows the original pink-red tint instead of the generic Magic element color.

### Task 3: Build `impact_effect.tscn` and `ImpactEffect`
- Objective: a reusable one-shot scene that plays any `BOOM_*` clip at a world position then removes itself — used by melee, shock, and missile.
- Create `scenes/battle/impact_effect.tscn`: a `Node2D` root with a single `AnimatedSprite2D` child named `Anim` (`autoplay = ""`, `centered = true`).
- Create `scripts/battle/impact_effect.gd`:
  ```gdscript
  class_name ImpactEffect
  extends Node2D

  const VFX_DIR := "res://assets/vfx/impacts/"

  func play(clip_name: String) -> void:
      if clip_name.is_empty():
          queue_free()
          return
      var sheet_path := VFX_DIR + _sanitize(clip_name) + ".png"
      var json_path  := VFX_DIR + _sanitize(clip_name) + ".json"
      if not ResourceLoader.exists(sheet_path):
          queue_free()
          return
      var meta := JSON.parse_string(FileAccess.open(json_path, FileAccess.READ).get_as_text())
      var texture: Texture2D = load(sheet_path)
      var frames: int = int(meta["frame_count"])
      var fw: int    = int(meta["frame_width"])
      var fh: int    = int(meta["frame_height"])
      var fps: float = float(meta.get("fps", 30.0))
      var anim_sprite: AnimatedSprite2D = $Anim
      var frames_res := SpriteFrames.new()
      frames_res.add_animation("default")
      frames_res.set_animation_speed("default", fps)
      frames_res.set_animation_loop("default", false)
      for i in frames:
          var atlas := AtlasTexture.new()
          atlas.atlas = texture
          atlas.region = Rect2(i * fw, 0, fw, fh)
          frames_res.add_frame("default", atlas)
      anim_sprite.sprite_frames = frames_res
      anim_sprite.animation_finished.connect(queue_free)
      anim_sprite.play("default")

  static func _sanitize(name: String) -> String:
      return name.replace(".", "_").replace(" ", "_")
  ```
- GUT test (headless-safe): instantiate `ImpactEffect`, call `play("")` → no crash, node marked for deletion. Separately: inject a mock `SpriteFrames`, emit `animation_finished` manually, assert `is_queued_for_deletion()`.
- Demo: `ImpactEffect.play("BOOM_SPARK")` shows the clip and auto-removes. Missing clip names are silent no-ops. No `ImpactEffect` nodes leak after a battle.

### Task 4: Upgrade `Projectile` to sprite-sheet bolt + `KrinTrail`
- Objective: `Projectile` renders real per-clip bolt art via `AnimatedSprite2D` and a `KrinTrail` streak — all existing `krinBoltMake` movement math stays exactly as-is.
- Create `scenes/battle/projectile.tscn`: `Node2D` root (existing `Projectile` script attached) with two children:
  - `AnimatedSprite2D` named `Bolt` (`centered = true`, `autoplay = ""`)
  - `Node2D` named `Trail` (custom `_draw()` for the streak)
- Modify `scripts/battle/projectile.gd`:
  - Add `var clip_name: String = ""` and `var trail_color: Color = Color.WHITE` (set by `battle_scene.gd` before `start()`).
  - Add `@onready var _bolt_sprite: AnimatedSprite2D = $Bolt` and `@onready var _trail_node: Node2D = $Trail`.
  - In `start()`: load `res://assets/vfx/bolts/<sanitize(clip_name)>.png` + its JSON sidecar. Build a `SpriteFrames` with a looping `"fly"` animation (same `AtlasTexture` loop as `ImpactEffect`, but `loop = true`). Assign to `_bolt_sprite.sprite_frames`, call `_bolt_sprite.play("fly")`. Set `_bolt_sprite.modulate = Color(trail_color, 0.0)` (starts transparent, matching the original's `_alpha = 0`). Fallback: if the sheet doesn't exist, skip sprite setup — the existing `_draw()` circle guard (`if _bolt_sprite.sprite_frames == null`) keeps headless tests passing.
  - Each tick: set `_bolt_sprite.modulate = Color(trail_color, _alpha)` alongside the existing `_alpha += 0.1` fade-in logic. Call `_trail_node.queue_redraw()`.
  - Remove the circle from `_draw()` once confirmed loading; keep it behind a `if _bolt_sprite.sprite_frames == null:` guard for the fallback.
  - `Trail` node `_draw()`: draw a line from `_trail_start - position` to `Vector2.ZERO`, color `Color(trail_color, _alpha * 0.6)`, width `clampf(2.0 + (_speed_const - 1.0) * 4.0, 2.0, 10.0)` (approximates the original's `_xscale += 8.3 * step_magnitude` stretch as `SpeedConst` compounds). This replaces the line currently in `Projectile._draw()`.
- In `battle_scene.gd`'s `_fire_projectile`: set `bolt.clip_name = move.animation_label` and `bolt.trail_color = move.visual_effect_color` before `bolt.start(from, to)`. Remove the old `bolt.color = _move_color(move)` line.
- Re-run existing `Projectile` movement GUT tests to confirm nothing broke. No new movement tests needed.
- Demo: a Firebolt move shows a looping animated bolt flying to target with a tinted growing trail. Missing sprite sheet falls back to the old tinted circle — headless tests pass unchanged.

### Task 5: Wire `ImpactEffect` to all three impact hook points
- Objective: `BOOM_*` clips spawn at the target on melee impact, shock cast, and missile arrival — completing the impact effect gap for all three move types at once.
- Add to `battle_scene.gd`:
  ```gdscript
  const ImpactEffectScene: PackedScene = preload("res://scenes/battle/impact_effect.tscn")

  func _spawn_impact(target_slot: int, move: Ability) -> void:
      if move == null or move.impact_effect_name.is_empty():
          return
      var effect: ImpactEffect = ImpactEffectScene.instantiate()
      effect.position = SLOT_POSITIONS.get(target_slot, Vector2(400, 300))
      battlefield.add_child(effect)
      effect.play(move.impact_effect_name)
  ```
- Wire the three call sites in `_play_move_event`:
  1. **Melee** — inside the `on_impact` lambda, after `AudioManagerAuto.play_effect(move.sound_effect_name)`:
     ```gdscript
     _spawn_impact(target_slot, move)
     ```
  2. **Shock** — after `_show_move_result(event, target_slot)` in the Shock branch:
     ```gdscript
     _spawn_impact(target_slot, move)
     ```
  3. **Missile** — in `_fire_projectile`, after `await bolt.arrived`. Thread `target_slot` and `move` into `_fire_projectile`'s signature (already present — the call site in `_play_move_event` has both), then call:
     ```gdscript
     _spawn_impact(target_slot, move)
     ```
     Update `_fire_projectile`'s signature from `(caster_slot, target_slot, move)` to also accept them explicitly if not already — check the current signature and adjust if needed.
- GUT test: in a headless battle (`animation_speed = 0`), `_fire_projectile` returns instantly (no projectile spawned). `_spawn_impact` is called regardless of `animation_speed` — verify the existing integration tests produce a `"move"` event for a Missile move without error. Assert no `ImpactEffect` nodes remain in the scene tree after the battle loop finishes (they should have `queue_free`d themselves; check via `get_tree().get_nodes_in_group` or a node count on `battlefield`).
- Demo: fire a Firebolt in a live battle — the bolt flies, `BOOM_SLASHORANGE` plays at the target on arrival. A melee strike shows its `BOOM_SPARK` at impact. A shock cast shows its clip instantly. All three auto-remove. GUT suite passes.
