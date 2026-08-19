# Missile Projectile Art — Design

## Goal

Replace `Projectile`'s generic tinted circle+line with the original game's real per-clip bolt art, add the `KrinTrail` streak effect, and add `BOOM_*`/`ex_*` impact clips at all three move-impact hook points (melee, shock, missile) — all extracted from the SWF with the same low-modification approach already established for `faces.py`/`item_icons.py`/`buff_icons.py`. Also fixes the cast-glow tint, currently approximated by the move's element color, to use the move's own real color.

## Background

Traced directly against `dev/source_files/action_script/frame_42/DoAction_4.as` (`krinBoltMake`) and `frame217/onClipEvent_enterFrame.txt`, not inferred from `NEXT_PHASES.md`'s (stale) summary:

- `krinBoltMake(shooter, hitter, tColorKrin, projectileModel, boomType)` attaches `projectileModel` (`Ability.animation_label`, JSON `12_animation_model_name`) as the bolt clip, shown **untinted** — its own art is pre-colored per element (Firebolt is inherently orange, Iceball inherently blue). `tColorKrin` (a new `Ability.visual_effect_color`, JSON `11_visual_effect_color`, hex string e.g. `"0xFF3366"`) tints **only** a separate `KrinTrail` clip, attached once via `Color.setRGB`.
- `KrinTrail` (sprite id 3) is a **1-frame wrapper around a 33-frame child** (sprite id 2 - the "inner" clip the source's `inner._xscale` line refers to), confirmed against the SWF's raw tags: sprite 2's own frame 1 has an explicit `alphaMultTerm="0"` (starts invisible), ramps up to `alphaMultTerm=96` by frame 9, holds through frame 23, then ramps back to 0 by frame 33 - a real, self-contained fade-in/fade-out pulse baked into the clip's own timeline, not something the outer AS3 tracks manually (which is why `krinBoltMake` never touches the trail's alpha - it doesn't need to). Corrected after Task 1's extraction produced a fully-blank `krintrail.png`: exporting sprite 3 (the 1-frame wrapper) only ever captures the child's alpha=0 starting keyframe; the real content lives one level down, at sprite 2, exported the same way as every other clip (`ffdec -format sprite:png -selectid 2`, 33 real frames, confirmed non-blank). It's attached once at the bolt's position on the first tick and left there; only its `inner._xscale` grows every tick (`8.3 * step_magnitude`) on top of its own internal fade, and it's rotated once to the flight angle. A fixed-origin stretching streak, not a trail that follows the bolt.
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
- Neither the trail (`"tt"+counter`) nor the impact clip (`"bbb"+counter`) is ever explicitly removed anywhere in `krinBoltMake` itself, on a hit or a miss. `BOOM_*` clips are plain shape/tween content with no ActionScript of their own, so they almost certainly don't self-destruct on their last frame either — most likely left as static leftover debris until the whole battle scene is torn down for the next fight. `KrinTrail`'s inner clip (sprite 2) is the one exception: its own 33-frame timeline ends with a `_parent`-referencing `DoActionTag` (a self-detach, matching the fact that nothing in the outer AS3 ever removes it explicitly) — its fade-out and cleanup are both self-contained, not something `krinBoltMake` manages. This port's planned `ImpactEffect` (auto-`queue_free()` on animation end) mirrors that same self-contained-cleanup idea for the impact clips, which the source doesn't actually do for them - a deliberate improvement, not an unfaithful port.
- `colortobe = mAry1[11]` (i.e. `visual_effect_color`) tints the caster's own cast-glow clip for **both** Missile and Shock casts (`frame217/onClipEvent_enterFrame.txt:417,450`) — currently approximated in `battle_scene.gd` with the move's *element* color (`_move_color(move)`) instead of the real per-move color. Melee never sets `colortobe` (it calls the separate `krinMelee` function, not `krinBoltMake`) — no change needed there.
- This port's canvas is 800×600, top-left origin (`SLOT_POSITIONS` range x≈161–638) — a different coordinate convention from the source's centered AS2 stage, so its `±500` off-screen bounds don't transfer literally; this port needs its own margin past its own 0–800 canvas.

**Clip lists** — re-derived directly from `dev/converted_json/moves_abilities.json` rather than trusting `NEXT_PHASES.md`'s list (found to be stale and incomplete):

- **15 unique bolt clips** across 17 name strings — `KRIN.MAGICBOLT`/`KRIN.POISONBOLT` are just differently-cased references to `Krin.Magicbolt`/`Krin.Poisonbolt`; Flash's `attachMovie` linkage lookup is case-insensitive, confirmed by both variants resolving to the same sprite id (2446, 2443) in the export table.
- **41 `impact_effect_name` values**, not 15 — `ex_DownBlue` case-folds onto `ex_DOWNBLUE` (1182), leaving **36 that resolve** to a real sprite and **5 that don't exist in this SWF's export table at all**: `BOOM_DARK2`, `BOOM_DOWN_BLUE`, `BOOM_DOWN_PURPLE`, `BOOM_PURPLE`, `BOOM_SUN`. A real content gap in the source, not an extraction bug — these 5 have no clip to extract.
- 51 total unique clips (15 bolts + `KrinTrail`'s real content + 36 impacts, though `KrinTrail` is fetched by sprite id 2 directly rather than resolved through the export-name table - see Requirements below), 875+ total frames across all of them (verified via `snapshot_timeline`; the trail's real 33 frames replace the 1 originally counted against sprite 3's wrapper) — every clip's frames share one consistent canvas size (confirmed against the user's own manual `BOOM_SPARKBLUE` extraction: all 25 frames are 382×317), so packing is pure relocation, no per-frame measurement needed.

## Requirements

- Extract all 51 clips as **per-frame PNG files** (one file per animation frame, in a per-clip subfolder — `1.png, 2.png, ..., N.png`, exactly as ffdec itself names them) with zero pixel modification (no cropping, no resizing, no recoloring, no packing into a shared canvas). Adopted after discovering, mid-implementation, that two real impact clips (`BOOM1`: 36 frames at 1225px wide, `BOOM2`: 36 frames at 956px wide) pack into spritesheets 44100px/34416px wide — Godot's texture importer silently caps texture width at 32768px and rescales the whole image on import, which would desync every packed clip's frame regions from its own recorded dimensions once that cap is hit. Per-clip folders of individually-sized frames have no shared-canvas width to overflow, so this failure mode can't recur for any clip, not just these two.
- `Ability.visual_effect_color: Color`, parsed from `11_visual_effect_color`.
- `Projectile` renders the real bolt clip via `AnimatedSprite2D` (untinted, alpha-only fade) and `KrinTrail`'s real 33-frame content via a second `AnimatedSprite2D` (tinted by `visual_effect_color`, played once non-looping - its own frames already carry the fade-in/fade-out, no external alpha tracking needed - plus a separately-growing `scale.x`, rotated once to the flight angle) — all existing `krinBoltMake` movement math (`BOLT_TIME`/`BOLT_INCREASE`/`BOLT_FPS`) untouched.
- A hit stops the bolt at the target and shows its impact clip, exactly as today. **A miss (in scope per project owner)**: the bolt and trail keep moving/growing past the target until they exit this port's own screen bounds, instead of stopping — turn pacing (audio, the damage/MISS floatie) still lands at the same coordinate-cross moment as today, decoupled from the bolt's own cleanup.
- A reusable `ImpactEffect` one-shot scene, spawned at melee `attack_connected`, shock cast-tick, and missile hit (not miss) — matching `strikeSuccess`'s gating exactly.
- Cast glow tint switches from the element-color approximation to `move.visual_effect_color`, for both Missile and Shock (Melee is untouched — it never sets `colortobe`).
- No new third-party dependencies; Python extraction uses the existing `urchin_dev.swf` (`snapshot_timeline`, `parse_swf_xml`) + `ffdec` pipeline, same conventions as `item_icons.py`/`buff_icons.py`.

## Architecture

### Extraction — `dev/urchin_dev/swf/extract/vfx.py`

One script covering all three categories (bolts, `KrinTrail`, impacts), registered as `extract_vfx` in `pyproject.toml`.

- Resolve each clip name to a sprite id via `parse_swf_xml`'s export table, **case-insensitively** (build a lowercase-keyed lookup once; this is the only clip category with real casing variance in the source data — impacts happen to already match case-exactly except the one `ex_DownBlue`/`ex_DOWNBLUE` fold, handled the same way).
- `KrinTrail` is the one exception to name-based resolution: its export name ("KrinTrail") only resolves to sprite id 3, a 1-frame wrapper whose single frame captures its un-named child's (sprite id 2) own alpha=0 starting keyframe — extracting id 3 produces a fully blank asset. The real 33-frame fade-pulse content is sprite id 2 itself, which has no export name of its own (only reachable by number, not by the export table) — the script fetches it via a hardcoded id override for this one clip, not a general recursion rule (it's the only entry in the trail category).
- Per clip: `ffdec -zoom 2.0 -format sprite:png -selectid <id> -export sprite <dir> <swf>` (same invocation shape as `item_icons.py`/`buff_icons.py`), then **copy** the resulting `1.png, 2.png, ..., N.png` frames as-is into `assets/vfx/<category>/<sanitized_name>/` — no packing, no per-frame modification (matching `faces.py`'s own "just copy the exported frame" precedent, extended here to every frame of a clip instead of one representative frame per label). ffdec names the export directory `DefineSprite_<id>_<export-name>` when the sprite has one (unlike `item_icons.py`/`buff_icons.py`/`faces.py`'s unnamed sprite ids, which get no suffix) — every bolt/impact clip here has an export name, so directory resolution must glob rather than assume the bare `DefineSprite_<id>` form.
- No JSON sidecar: every clip in this project runs at 30fps (matching `model1_animations.json`, the buff/ability sheets' own frame-rate assumption), so the GDScript consumer hardcodes that constant rather than reading it back out of a per-clip file; frame count is discovered at load time by probing for `1.png`, `2.png`, ... until one is missing, so it can never drift out of sync with the files actually present.
- Output paths: `assets/vfx/bolts/<name>/*.png` (15 folders), `assets/vfx/trail/krintrail/*.png` (1 folder, 33 real frames), `assets/vfx/impacts/<name>/*.png` (35 folders, after the `ex_DOWNBLUE`/`ex_DownBlue` case-fold dedup - 36 resolve, one collides). Folder names use the same `sanitize()` convention as `item_icons.py`/`buff_icons.py` (`re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_")`), **lowercased** (matching `faces.py`'s own lowercase convention) — this is what makes the two differently-cased bolt names collapse onto one output folder instead of writing duplicates, and what lets the GDScript consumer resolve a clip name to a folder without needing a case-insensitive dictionary at runtime (lowercase both sides, symmetrically — the same lesson just applied to `buff_icons.py`/`BuffIcons._sanitize()`'s cross-language contract).
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
    AnimatedSprite2D "Trail"   <- KrinTrail's real 33-frame content, spawned once, played once (non-looping - its
                                  own frames already carry the fade-in/fade-out), modulate = trail_color (RGB tint
                                  only, alpha comes from the frames themselves), scale.x grows separately
```

New/changed fields on `Projectile`:
- `var clip_name: String = ""` and `var trail_color: Color = Color.WHITE` — set by `battle_scene.gd` before `start()`.
- `var did_hit: bool = true` — set by `battle_scene.gd` before `start()`, from `result.get("type") != BattleManager.ResultType.MISS`.
- `signal reached_target` — replaces `arrived`; fires once, at the coordinate-cross tick, **regardless of hit or miss**. `_fire_projectile()` awaits this (not the bolt's full lifecycle), so turn pacing, `sound_effect_name`, and `_show_move_result()`'s floatie land at the same moment they do today, whether it's a hit or a miss.
- On the `reached_target` tick: if `did_hit`, `queue_free()` immediately (same as today's behavior). If not `did_hit`, keep ticking — the existing per-tick movement/trail-growth code already runs identically whether or not the bolt has passed the target (confirmed from source: `inner._xscale` grows on literally every tick, arrival or not) — until `position.x` exits `[-20.0, 820.0]` (this port's own small margin past its 800-wide canvas; not the source's unrelated `±500`), then `queue_free()` itself, unawaited by the caller.
- `_bolt_sprite.sprite_frames` built at `start()` time by loading each numbered frame file directly from `assets/vfx/bolts/<sanitized_clip_name>/` (same per-frame-folder shape as `ImpactEffect`, below) — a looping `"fly"` animation. Fallback: if the folder doesn't exist (`clip_name` empty or unresolvable), skip sprite setup and keep the existing tinted-circle `_draw()` as a visible fallback rather than showing nothing — same tolerance this project already extends to unresolved buff icons.
- `_trail_sprite.sprite_frames` built the same way from `assets/vfx/trail/krintrail/` (33 frames) — a **non-looping** `"pulse"` animation, played once when the trail is first spawned. No manual alpha tracking: the source's own fade-in/fade-out is already baked into the 33 frames, so `modulate` only ever carries the RGB tint (alpha stays 1.0).
- `Trail`'s rotation is set once (matching source: computed from `atan(yLength/xLength)`, adjusted +180° if flying leftward - `Vector2.angle()` is the direct Godot equivalent, already quadrant-correct without the manual +180 fixup) and its `scale.x` grows every tick (`clampf` isn't in source — the original never bounds `_xscale`'s growth, so this port doesn't invent a cap either, matching the "reference the source, don't invent design" principle this session has repeatedly enforced) - independent of, and layered on top of, its own internal alpha animation.
- `Trail` needs `top_level = true` (set in the `.tscn`, not at runtime) — confirmed empirically: a normal (non-top-level) `Node2D` child keeps inheriting its parent's transform every frame, so without this, `Trail` would be dragged along as `Projectile.position` keeps advancing every tick, rather than staying anchored at the world position it was given on the first tick. `top_level` makes `Trail`'s `global_position`/`rotation`/`scale` its own, set-once values, independent of whatever `Projectile` (the bolt) does afterward — which is the whole point of a streak that bridges a *growing* gap as the bolt flies away from where the trail was spawned.

### `ImpactEffect` — new `scenes/battle/impact_effect.tscn` + `scripts/battle/impact_effect.gd`

```gdscript
class_name ImpactEffect
extends Node2D

const VFX_DIR := "res://assets/vfx/impacts/"
const FPS := 30.0

func play(clip_name: String) -> void:
	if clip_name.is_empty():
		queue_free()
		return
	var dir: String = "%s%s/" % [VFX_DIR, _sanitize(clip_name)]
	var sprite_frames: SpriteFrames = VfxFrames.load_frames(dir, "default", false, FPS)
	if sprite_frames == null:
		queue_free()
		return
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

### `VfxFrames` — new `scripts/entities/vfx_frames.gd`, shared by `ImpactEffect` and `Projectile`

Both consumers need the identical "load a per-clip folder of numbered frame files into a `SpriteFrames` animation" logic, so it's a small shared static helper rather than duplicated in both scripts:

```gdscript
class_name VfxFrames
extends RefCounted

# Loads a per-clip folder of individually-sized frame files
# (dev/urchin_dev/swf/extract/vfx.py's own output - 1.png, 2.png, ...,
# copied as-is with no packing) into a SpriteFrames animation. Frame
# count is discovered by probing for consecutively-numbered files
# rather than reading it from a sidecar, so it can never drift out of
# sync with what's actually on disk. Returns null if the folder doesn't
# exist or holds no frames - callers fall back accordingly.
static func load_frames(dir: String, anim_name: String, loop: bool, fps: float) -> SpriteFrames:
	if not DirAccess.dir_exists_absolute(dir):
		return null
	var sprite_frames := SpriteFrames.new()
	if not sprite_frames.has_animation(anim_name):
		sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_speed(anim_name, fps)
	sprite_frames.set_animation_loop(anim_name, loop)
	var i := 1
	while true:
		var path: String = "%s%d.png" % [dir, i]
		if not ResourceLoader.exists(path):
			break
		sprite_frames.add_frame(anim_name, load(path))
		i += 1
	if sprite_frames.get_frame_count(anim_name) == 0:
		return null
	return sprite_frames
```
`SpriteFrames.new()` ships with a pre-existing `"default"` animation already registered (confirmed empirically - `add_animation("default")` throws `"SpriteFrames already has animation 'default'."`), which is why this checks `has_animation()` first rather than calling `add_animation()` unconditionally - `ImpactEffect` uses the name `"default"` (colliding with the built-in slot) while `Projectile`'s `"fly"`/`"pulse"` animations don't collide, but one shared helper needs to handle both cases correctly.

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
