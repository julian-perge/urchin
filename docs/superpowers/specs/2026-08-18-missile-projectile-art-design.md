# Missile Projectile Art — Design

## Goal

Replace `Projectile`'s generic tinted circle+line with the original game's real per-clip bolt art, add the `KrinTrail` streak effect, and add `BOOM_*`/`ex_*` impact clips at all three move-impact hook points (melee, shock, missile) — all extracted from the SWF with the same low-modification approach already established for `faces.py`/`item_icons.py`/`buff_icons.py`. Also fixes the cast-glow tint, currently approximated by the move's element color, to use the move's own real color.

## Background

Traced directly against `dev/source_files/action_script/frame_42/DoAction_4.as` (`krinBoltMake`) and `frame217/onClipEvent_enterFrame.txt`, not inferred from `NEXT_PHASES.md`'s (stale) summary:

- `krinBoltMake(shooter, hitter, tColorKrin, projectileModel, boomType)` attaches `projectileModel` (`Ability.animation_label`, JSON `12_animation_model_name`) as the bolt clip, shown **untinted** — its own art is pre-colored per element (Firebolt is inherently orange, Iceball inherently blue). `tColorKrin` (a new `Ability.visual_effect_color`, JSON `11_visual_effect_color`, hex string e.g. `"0xFF3366"`) tints **only** a separate `KrinTrail` clip, attached once via `Color.setRGB`.
- `KrinTrail` (sprite id 3) is a **single static frame**, confirmed against the SWF — not an animated clip. It's attached once at the bolt's position on the first tick and left there; only its `inner._xscale` grows every tick (`8.3 * step_magnitude`), and it's rotated once to the flight angle. A fixed-origin stretching streak, not a trail that follows the bolt.
- The bolt's own `_alpha` fades in over 10 ticks (10% per tick to 100) — already matches `Projectile.gd`'s existing `_alpha += 0.1`.
- Impact resolution, same tick the bolt's x crosses the target's x:
  ```as
  _root.BAMBAMBAM = true;
  if(_root.strikeSuccess) {
     _root.BATTLESCREEN.attachMovie(boomType, "bbb"+counter, ...);
     this._parent["bbb"+counter]._x = this.targetMC._x;
     this._parent["bbb"+counter]._y = this.targetMC._y;
     this.removeMovieClip();               // bolt destroyed instantly on a hit
  } else {
     ...inner._xscale += 8.3 * step_magnitude...   // miss: trail keeps growing
     if(this._x > 500 || this._x < -500) { this.removeMovieClip(); }  // off original's centered AS2 stage
  }
  ```
  `boomType` (`Ability.impact_effect_name`, JSON `13_impact_effect_name`, already an unused field) only attaches on a genuine hit. `BAMBAMBAM` is a one-frame pulse flag consumed by `frame_217`'s own loop for its impact-reaction bookkeeping (`AttackEndCounter = 0`, etc.) — this port already achieves the same "do things exactly at impact" purpose directly via `attack_connected`/bolt-arrival awaits, so `BAMBAMBAM` itself needs no equivalent.
- Neither the trail (`"tt"+counter`) nor the impact clip (`"bbb"+counter`) is ever explicitly removed anywhere in this file, on a hit or a miss. Both `BOOM_*` and `KrinTrail` are plain shape/tween content with no ActionScript of their own, so they almost certainly don't self-destruct on their last frame either — they're most likely left as static leftover debris until the whole battle scene is torn down for the next fight. This port's planned `ImpactEffect` (auto-`queue_free()` on animation end) is a deliberate improvement over this, not an unfaithful port.
- `colortobe = mAry1[11]` (i.e. `visual_effect_color`) tints the caster's own cast-glow clip for **both** Missile and Shock casts (`frame217/onClipEvent_enterFrame.txt:417,450`) — currently approximated in `battle_scene.gd` with the move's *element* color (`_move_color(move)`) instead of the real per-move color. Melee never sets `colortobe` (it calls the separate `krinMelee` function, not `krinBoltMake`) — no change needed there.
- This port's canvas is 800×600, top-left origin (`SLOT_POSITIONS` range x≈161–638) — a different coordinate convention from the source's centered AS2 stage, so its `±500` off-screen bounds don't transfer literally; this port needs its own margin past its own 0–800 canvas.

**Clip lists** — re-derived directly from `dev/converted_json/moves_abilities.json` rather than trusting `NEXT_PHASES.md`'s list (found to be stale and incomplete):

- **15 unique bolt clips** across 17 name strings — `KRIN.MAGICBOLT`/`KRIN.POISONBOLT` are just differently-cased references to `Krin.Magicbolt`/`Krin.Poisonbolt`; Flash's `attachMovie` linkage lookup is case-insensitive, confirmed by both variants resolving to the same sprite id (2446, 2443) in the export table.
- **41 `impact_effect_name` values**, not 15 — `ex_DownBlue` case-folds onto `ex_DOWNBLUE` (1182), leaving **36 that resolve** to a real sprite and **5 that don't exist in this SWF's export table at all**: `BOOM_DARK2`, `BOOM_DOWN_BLUE`, `BOOM_DOWN_PURPLE`, `BOOM_PURPLE`, `BOOM_SUN`. A real content gap in the source, not an extraction bug — these 5 have no clip to extract.
- 51 total unique clips (15 bolts + `KrinTrail` + 36 impacts), 875 total frames across all of them (verified via `snapshot_timeline`) — every clip's frames share one consistent canvas size (confirmed against the user's own manual `BOOM_SPARKBLUE` extraction: all 25 frames are 382×317), so packing is pure relocation, no per-frame measurement needed.

## Requirements

- Extract all 51 clips into packed spritesheets with zero per-pixel modification (no cropping, no resizing, no recoloring — frames are relocated whole into one wider canvas).
- `Ability.visual_effect_color: Color`, parsed from `11_visual_effect_color`.
- `Projectile` renders the real bolt clip via `AnimatedSprite2D` (untinted, alpha-only fade) and the `KrinTrail` single frame via a plain `Sprite2D` (tinted by `visual_effect_color`, growing `scale.x`, rotated once to the flight angle) — all existing `krinBoltMake` movement math (`BOLT_TIME`/`BOLT_INCREASE`/`BOLT_FPS`) untouched.
- A hit stops the bolt at the target and shows its impact clip, exactly as today. **A miss (in scope per project owner)**: the bolt and trail keep moving/growing past the target until they exit this port's own screen bounds, instead of stopping — turn pacing (audio, the damage/MISS floatie) still lands at the same coordinate-cross moment as today, decoupled from the bolt's own cleanup.
- A reusable `ImpactEffect` one-shot scene, spawned at melee `attack_connected`, shock cast-tick, and missile hit (not miss) — matching `strikeSuccess`'s gating exactly.
- Cast glow tint switches from the element-color approximation to `move.visual_effect_color`, for both Missile and Shock (Melee is untouched — it never sets `colortobe`).
- No new third-party dependencies; Python extraction uses the existing `urchin_dev.swf` (`snapshot_timeline`, `parse_swf_xml`) + `ffdec` pipeline, same conventions as `item_icons.py`/`buff_icons.py`.

## Architecture

### Extraction — `dev/urchin_dev/swf/extract/vfx.py`

One script covering all three categories (bolts, `KrinTrail`, impacts), registered as `extract_vfx` in `pyproject.toml`.

- Resolve each clip name to a sprite id via `parse_swf_xml`'s export table, **case-insensitively** (build a lowercase-keyed lookup once; this is the only clip category with real casing variance in the source data — impacts happen to already match case-exactly except the one `ex_DownBlue`/`ex_DOWNBLUE` fold, handled the same way).
- Per clip: `ffdec -zoom 2.0 -format sprite:png -selectid <id> -export sprite <dir> <swf>` (same invocation shape as `item_icons.py`/`buff_icons.py`), collect the resulting `1.png, 2.png, ...` frames in order.
- Pack frames left-to-right into one spritesheet canvas (`frame_width * frame_count` wide, `frame_height` tall — both taken directly from the first frame's own dimensions, since every frame in a clip shares one canvas size). No `getchannel("A").getbbox()` trim step here (unlike `item_icons.py`/`buff_icons.py`) — trimming would misalign frames of an animation against each other; the whole point of the sprite:png export's consistent per-clip canvas is that every frame already lines up.
- Write a JSON sidecar per clip: `{"frame_count": N, "frame_width": W, "frame_height": H, "fps": 30.0}` (30fps matches every other timeline-derived asset in this project — `model1_animations.json`, the buff/ability sheets' own frame-rate assumption).
- Output paths: `assets/vfx/bolts/<name>.png`/`.json` (15), `assets/vfx/trail/krin_trail.png`/`.json` (1 — packing code handles a 1-frame clip the same way as any other, no special case), `assets/vfx/impacts/<name>.png`/`.json` (36). Filenames use the same `sanitize()` convention as `item_icons.py`/`buff_icons.py` (`re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_")`), **lowercased** (matching `faces.py`'s own lowercase convention) — this is what makes the two differently-cased bolt names collapse onto one output file instead of writing duplicates, and what lets the GDScript consumer resolve a clip name to a file without needing a case-insensitive dictionary at runtime (lowercase both sides, symmetrically — the same lesson just applied to `buff_icons.py`/`BuffIcons._sanitize()`'s cross-language contract).
- The 5 unresolvable impact names print a warning (`unresolved: [...]`) and are skipped, matching `item_icons.py`'s/`buff_icons.py`'s existing tolerance for names with no real content.

### Data model — `scripts/battle/ability.gd`

```gdscript
@export var visual_effect_color: Color = Color.WHITE
```
Parsed in `Ability.from_json`, from `data.get("11_visual_effect_color")` (a `"0xRRGGBB"` string) via `Color.html(raw.substr(2))` (stripping the `0x` prefix) if it's a String, else `Color.WHITE` (the `Undefined` fallback, matching move id 0's "None" sentinel).

### `Projectile` upgrade — `scenes/battle/projectile.tscn` + `scripts/battle/projectile.gd`

`Projectile` becomes a real scene (was `Projectile.new()` from pure script — no children possible before now):

```
projectile.tscn
  Node2D (root, Projectile script — all existing krinBoltMake movement math unchanged)
    AnimatedSprite2D "Bolt"    <- spritesheet-loaded per clip_name, looping, modulate = Color(1,1,1,_alpha) (never tinted)
    Sprite2D "Trail"           <- KrinTrail's single frame, spawned once, modulate = Color(trail_color, _alpha), scale.x grows
```

New/changed fields on `Projectile`:
- `var clip_name: String = ""` and `var trail_color: Color = Color.WHITE` — set by `battle_scene.gd` before `start()`.
- `var did_hit: bool = true` — set by `battle_scene.gd` before `start()`, from `result.get("type") != BattleManager.ResultType.MISS`.
- `signal reached_target` — replaces `arrived`; fires once, at the coordinate-cross tick, **regardless of hit or miss**. `_fire_projectile()` awaits this (not the bolt's full lifecycle), so turn pacing, `sound_effect_name`, and `_show_move_result()`'s floatie land at the same moment they do today, whether it's a hit or a miss.
- On the `reached_target` tick: if `did_hit`, `queue_free()` immediately (same as today's behavior). If not `did_hit`, keep ticking — the existing per-tick movement/trail-growth code already runs identically whether or not the bolt has passed the target (confirmed from source: `inner._xscale` grows on literally every tick, arrival or not) — until `position.x` exits `[-20.0, 820.0]` (this port's own small margin past its 800-wide canvas; not the source's unrelated `±500`), then `queue_free()` itself, unawaited by the caller.
- `_bolt_sprite.sprite_frames` built at `start()` time from the clip's spritesheet + JSON sidecar (same `AtlasTexture` slicing shape as `ImpactEffect`, below) — a looping `"fly"` animation. Fallback: if the sheet doesn't exist (`clip_name` empty or unresolvable), skip sprite setup and keep the existing tinted-circle `_draw()` as a visible fallback rather than showing nothing — same tolerance this project already extends to unresolved buff icons.
- `Trail`'s rotation is set once (matching source: computed from `atan(yLength/xLength)`, adjusted +180° if flying leftward) and its `scale.x` grows every tick (`clampf` isn't in source — the original never bounds `_xscale`'s growth, so this port doesn't invent a cap either, matching the "reference the source, don't invent design" principle this session has repeatedly enforced).

### `ImpactEffect` — new `scenes/battle/impact_effect.tscn` + `scripts/battle/impact_effect.gd`

```gdscript
class_name ImpactEffect
extends Node2D

const VFX_DIR := "res://assets/vfx/impacts/"

func play(clip_name: String) -> void:
	if clip_name.is_empty():
		queue_free()
		return
	var key := _sanitize(clip_name)
	var sheet_path := "%s%s.png" % [VFX_DIR, key]
	var json_path := "%s%s.json" % [VFX_DIR, key]
	if not ResourceLoader.exists(sheet_path):
		queue_free()
		return
	var meta: Dictionary = JSON.parse_string(FileAccess.open(json_path, FileAccess.READ).get_as_text())
	var texture: Texture2D = load(sheet_path)
	var frame_count: int = int(meta["frame_count"])
	var frame_width: int = int(meta["frame_width"])
	var frame_height: int = int(meta["frame_height"])
	var fps: float = float(meta.get("fps", 30.0))
	var sprite_frames := SpriteFrames.new()
	sprite_frames.add_animation("default")
	sprite_frames.set_animation_speed("default", fps)
	sprite_frames.set_animation_loop("default", false)
	for i in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * frame_width, 0, frame_width, frame_height)
		sprite_frames.add_frame("default", atlas)
	var anim_sprite: AnimatedSprite2D = $Anim
	anim_sprite.sprite_frames = sprite_frames
	anim_sprite.animation_finished.connect(queue_free)
	anim_sprite.play("default")


static func _sanitize(name: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^A-Za-z0-9]+")
	return regex.sub(name, "_", true).lstrip("_").rstrip("_").to_lower()
```
(`_sanitize` mirrors `BuffIcons._sanitize()`/`vfx.py`'s own `sanitize()` exactly — the same cross-language contract already established for buffs.)

`impact_effect.tscn`: `Node2D` root, one `AnimatedSprite2D` child named `Anim` (`autoplay = ""`, `centered = true`).

### Wiring — `scripts/battle/battle_scene.gd`

```gdscript
const ImpactEffectScene: PackedScene = preload("res://scenes/battle/impact_effect.tscn")

func _spawn_impact(target_slot: int, move: Ability, result: Dictionary) -> void:
	if move == null or move.impact_effect_name.is_empty():
		return
	if result.get("type") == BattleManager.ResultType.MISS:
		return
	var effect: ImpactEffect = ImpactEffectScene.instantiate()
	effect.position = SLOT_POSITIONS.get(target_slot, Vector2(400, 300))
	battlefield.add_child(effect)
	effect.play(move.impact_effect_name)
```

Three call sites in `_play_move_event`:
1. **Melee** — inside the existing `on_impact` lambda, after `AudioManagerAuto.play_effect(move.sound_effect_name)`: `_spawn_impact(target_slot, move, event.get("result", {}))`.
2. **Shock** — after `_show_move_result(event, target_slot)` in the Shock branch (same `result` dict already in scope via `event`).
3. **Missile** — in `_fire_projectile`, after `await bolt.reached_target` (only reached on the hit path's timing — see `Projectile` section above; a miss still emits `reached_target` at the same tick, so `_spawn_impact`'s own `MISS` gate is what actually suppresses it, keeping the gating logic in one place rather than duplicated across both `Projectile` and `battle_scene.gd`).

`_fire_projectile`'s signature gains `move.visual_effect_color`/`did_hit` threading:
```gdscript
func _fire_projectile(caster_slot: int, target_slot: int, move: Ability, result: Dictionary) -> void:
	if animation_speed <= 0.0:
		return
	var from: Vector2 = SLOT_POSITIONS.get(caster_slot, Vector2(400, 300))
	var to: Vector2 = SLOT_POSITIONS.get(target_slot, Vector2(400, 300))
	var bolt: Projectile = ProjectileScene.instantiate()
	bolt.clip_name = move.animation_label
	bolt.trail_color = move.visual_effect_color
	bolt.did_hit = result.get("type") != BattleManager.ResultType.MISS
	battlefield.add_child(bolt)
	bolt.start(from, to)
	await bolt.reached_target
```

The existing Missile-branch call site in `_play_move_event` (`await _fire_projectile(caster_slot, target_slot, move)`) needs its argument list updated to match the new signature: `await _fire_projectile(caster_slot, target_slot, move, event.get("result", {}))`. Nothing else in that branch changes — `_show_move_result(event, target_slot)` still runs after `_fire_projectile` returns, showing the damage number or "MISS" text at the same point it does today.

Cast-glow tint (`caster_visual.modulate = ...`) switches from `_move_color(move).lerp(Color.WHITE, 0.4)` to `move.visual_effect_color.lerp(Color.WHITE, 0.4)`. This is a separate mechanism from `_show_move_result`'s damage-number coloring (`move.damage_element_type`-based `MenuTheme.ELEMENT_COLORS`, matching the source's own `KrinNumberShow`) — untouched by this design.

## Testing

- `test/unit/test_ability_visual_effect.gd` (new): `visual_effect_color` parses a real hex move (e.g. move id 5, "Nuke", `"0xFF3366"`) to the matching `Color`; move id 0 ("None") yields `Color.WHITE`.
- `test/unit/test_impact_effect.gd` (new): `play("")` is a no-op that queues the node for deletion; a real clip name plays and `animation_finished` frees the node (inject a short fake `SpriteFrames` rather than waiting on a real one).
- `test/unit/test_projectile.gd` (new): hit case — `reached_target` fires and the node frees itself immediately after. Miss case — `reached_target` still fires at the same coordinate-cross tick, but the node survives past that point and only frees once `position.x` exits the off-screen bounds (drive `_process()` with `animation_speed`-independent deltas the same way `test_battle_scene.gd`'s existing tween tests do).
- `test/integration/test_battle_scene.gd` (extend): a Missile move's miss doesn't block the turn loop past the coordinate-cross moment (turn pacing observable via `_play_events` completing without an unbounded wait); `_spawn_impact` is not called for a MISS result at any of the three hook points; no `ImpactEffect`/`Projectile` node remains in the scene tree once a full headless battle completes.
- No tests for the Python extraction script (matches this project's established convention for `item_icons.py`/`buff_icons.py`/`faces.py` — verified by direct file-output inspection instead: labels-found/written counts, and a visual spot-check of 2-3 clips, including the 5-name unresolved list matching the design's stated gap exactly).

## Out of Scope

- Steam-build cross-check for the 5 unresolvable impact clip names (`SWF_DIFFERENCES.md`-style web-vs-Steam investigation) — not pursued this pass; these 5 moves simply show no impact effect, same tolerance `BuffIcons.icon_for()` already extends to unresolvable buffs.
- `BAMBAMBAM`'s other consumers in `frame_217` (screen shake / stun-check bookkeeping beyond the impact visual itself) — this port already threads impact timing through explicit signals/awaits; no equivalent flag needed.
- Any change to melee's own animation/impact timing — untouched by this design; melee never calls `krinBoltMake`/sets `colortobe`.
