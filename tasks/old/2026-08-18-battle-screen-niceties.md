# Battle Screen Niceties Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship 5 independent battle-screen polish items: wire in the extracted bottom-bar art, a visual (non-forcing) decision countdown, a source-corrected hover ring + radial-menu dismissal, real per-buff icons over units, and a toggleable live combat log.

**Architecture:** Each item is a self-contained change to `battle_scene.gd`/`battle_scene.tscn` (plus, for buff icons, `unit_overlay.tscn`/`unit_overlay.gd` and a new Python extraction script). No item depends on another; they're sequenced smallest/safest to largest. Everything follows this project's established Godot 4 GDScript conventions: `class_name`-registered scripts, GUT tests calling "private" (`_`-prefixed) methods directly rather than simulating real OS input, and small helper functions split out specifically so tests can call the pure logic without hitting an engine precondition (already done twice this project for `ItemSlot._get_drag_data`/`_drag_payload`).

**Tech Stack:** Godot 4.7 GDScript, GUT 9.6.1 test framework (`test/unit/`, `test/integration/`), Python 3 + `uv` + `ffdec` for the buff-icon extraction script (mirrors `dev/urchin_dev/swf/extract/item_icons.py`).

**Spec:** `.claude/plan_battle_screen_niceties.md` — the spec this plan implements. Read it first for the *why* behind each item (source-code citations for the countdown's original force-pass semantic, the hover ring's real fade mechanic, and the buff-icon sheet's real extraction technique); this plan covers the *how*.

## Global Constraints

- Run the full GUT suite headless after every task and confirm it's green before committing: `godot --headless -s addons/gut/gut_cmdln.gd --path .` (config already in `.gutconfig.json`).
- Compile-check with `godot --headless --editor --quit --path .` once per session if a new `class_name` script was added (stale class cache otherwise reports false "not declared" errors - see `NEXT_PHASES.md`'s Testing section).
- Never call `set_drag_preview()`-style engine calls with real-drag preconditions directly in a test; split pure logic into its own method first (established pattern, see `item_slot.gd`'s `_drag_payload()`).
- Match existing project conventions exactly: tabs for indentation, `# comment` style (not `##` doc comments) matching the surrounding file, GDScript static typing on every new variable/parameter/return type.
- No non-ASCII characters in code/comments except the already-established `€` currency symbol precedent (`inventory_panel.gd`).
- Do not commit or push without explicit instruction beyond "implement this plan" - commit at the end of each task as this plan's steps direct (that instruction already covers task-level commits); do not push to any remote unless told to separately.

---

## Task 1: Wire in the extracted bottom-bar backdrop art

**Files:**
- Modify: `scenes/battle_scene.tscn` (add `ext_resource` for the new texture, retarget `BottomBar/Backdrop` from `ColorRect` to `TextureRect`)
- Test: `test/integration/test_battle_scene.gd`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: nothing later tasks depend on - purely visual, but Task 2/5 both add new children under `BottomBar` (specifically inside `BottomBar/Panel3`), so this task's `Panel3` node must still exist afterward with the same name/path.

Confirmed by direct pixel inspection this session: `assets/ui/battle/hotbar_background.png` is 771x109px, matching `BottomBar`'s existing `Panel1`+`Panel2`+`Panel3` combined region (`(12,10)` to `(788,120)` = 776x110) almost exactly, and visually shows the real 3-panel-divided backdrop as one texture. `battle_pbar_full.png`/`battle_progress_bar_inner.png` (a 1273x1273 ring and a 126x126 near-blank square) belong to Task 2's countdown instead - "pbar" reads as "progress bar," not a health/focus fill, and there's no HealthBar/FocusBar-shaped asset among the 4 files at all (those stay stock `ProgressBar`s, unchanged). `hotbar_team_select.png` (5701x627, wildly oversized relative to its content - the same "ffdec exports the whole timeline's union bounds" issue this project has hit repeatedly) is NOT wired in this task or anywhere in this plan - its real intended placement isn't confirmable from inspection alone and forcing a guess into committed code isn't worth the risk for a purely-cosmetic asset. Leave it exactly where it is, unreferenced.

- [ ] **Step 1: Write the failing test**

Add to `test/integration/test_battle_scene.gd` (end of file):

```gdscript
func test_bottom_bar_uses_extracted_backdrop_art():
	var save = PlayerSave.new_game("BackdropTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	var backdrop: TextureRect = scene.get_node("BottomBar/Backdrop")
	assert_not_null(backdrop, "Backdrop is a TextureRect now")
	assert_eq(
		backdrop.texture.resource_path, "res://assets/ui/battle/hotbar_background.png",
		"backdrop uses the extracted art"
	)

	GameData.current_save = null
	ZoneManager.auto_start_battles = true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path . -gselect=test_battle_scene -gunit_test_name=test_bottom_bar_uses_extracted_backdrop_art -glog=1`
Expected: FAIL - `get_node("BottomBar/Backdrop")` currently returns a `ColorRect`, which has no `.texture` property, so this errors rather than just failing an assert (that's fine, it still proves the current state doesn't satisfy the test).

- [ ] **Step 3: Implement**

In `scenes/battle_scene.tscn`:
1. Add a new `ext_resource` line near the top, after the existing `id="2_hotbarbg"` line:
   ```
   [ext_resource type="Texture2D" path="res://assets/ui/battle/hotbar_background.png" id="3_battlebar"]
   ```
2. Change the `Backdrop` node's declaration from:
   ```
   [node name="Backdrop" type="ColorRect" parent="BottomBar"]
   layout_mode = 0
   offset_left = 0.0
   offset_top = 0.0
   offset_right = 800.0
   offset_bottom = 130.0
   mouse_filter = 0
   color = Color(0.04, 0.05, 0.06, 1)
   ```
   to:
   ```
   [node name="Backdrop" type="TextureRect" parent="BottomBar"]
   layout_mode = 0
   offset_left = 0.0
   offset_top = 0.0
   offset_right = 800.0
   offset_bottom = 130.0
   mouse_filter = 0
   texture = ExtResource("3_battlebar")
   expand_mode = 1
   stretch_mode = 6
   ```
   (`expand_mode = 1` / `stretch_mode = 6` matches the `expand_mode`/`stretch_mode` values `Background`/`Sky` already use elsewhere in this same scene for a full-rect stretched texture.)

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path . -gselect=test_battle_scene -gunit_test_name=test_bottom_bar_uses_extracted_backdrop_art -glog=1`
Expected: PASS

- [ ] **Step 5: Run the full GUT suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path .`
Expected: all tests pass (this only touches one node's type/texture - nothing else should be affected).

- [ ] **Step 6: Commit**

```bash
git add scenes/battle_scene.tscn test/integration/test_battle_scene.gd
git commit -m "feat: wire in the extracted battle bottom-bar backdrop art

BottomBar/Backdrop was a plain ColorRect; assets/ui/battle/hotbar_background.png
(771x109, matching the Panel1-3 region's 776x110 almost exactly) has been
extracted and unused since day one. Confirmed by direct pixel inspection
this is the real 3-panel backdrop, not related to health/focus bars -
those stay stock ProgressBars. battle_pbar_full.png/battle_progress_bar_inner.png
(a ring + a near-blank square) read as belonging to the decision-countdown
task instead (next), not this one. hotbar_team_select.png (5701x627,
absurdly oversized for its content - the same ffdec-exports-the-whole-
timeline-union-bounds issue this project has hit before) isn't wired
anywhere in this plan; its real placement isn't confirmable from
inspection alone."
```

---

## Task 2: Decision countdown display

**Files:**
- Modify: `scripts/battle/battle_scene.gd`
- Modify: `scenes/battle_scene.tscn` (add countdown UI under `BottomBar/Panel3`)
- Modify: `NEXT_PHASES.md` (document the no-force-pass divergence)
- Test: `test/integration/test_battle_scene.gd`

**Interfaces:**
- Consumes: `BattleRunner.BATTLE_TIME_LIMIT` (already exists, `const BATTLE_TIME_LIMIT: float = 120.0`), `battle_scene.gd`'s existing `_player_action_pending: bool` field.
- Produces: `battle_scene.gd`'s new `_decision_timer: float` field and `_reset_decision_timer()` method - not consumed by any other task in this plan, but keep the name stable in case Task 3's turn-gating logic ever wants to reference it later.

Visual-only: does NOT force-pass the turn at 0, unlike the original (see spec's Background for the sourced reasoning - this port removed real-time pressure everywhere else, and reintroducing it here wasn't asked for). `BattleRunner` is a `RefCounted` with no `_process()`; the timer lives on `battle_scene.gd`, which already runs one every frame via its existing scene tree membership.

- [ ] **Step 1: Write the failing test**

Add to `test/integration/test_battle_scene.gd`:

```gdscript
func test_decision_timer_ticks_down_while_player_is_deciding():
	var save = PlayerSave.new_game("TimerTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	scene._player_action_pending = true
	scene._reset_decision_timer()
	assert_eq(scene._decision_timer, BattleRunner.BATTLE_TIME_LIMIT, "resets to the full 120s")

	scene._process(10.0)
	assert_almost_eq(scene._decision_timer, BattleRunner.BATTLE_TIME_LIMIT - 10.0, 0.001)

	scene._process(9999.0)
	assert_eq(scene._decision_timer, 0.0, "clamps at 0, never goes negative")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func test_decision_timer_does_not_tick_while_not_player_action_pending():
	var save = PlayerSave.new_game("TimerTest2", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	scene._player_action_pending = false
	scene._decision_timer = 50.0
	scene._process(10.0)
	assert_eq(scene._decision_timer, 50.0, "doesn't tick during an AI turn")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path . -gselect=test_battle_scene -gunit_test_name=test_decision_timer_ticks_down_while_player_is_deciding -glog=1`
Expected: FAIL - `_reset_decision_timer` doesn't exist yet ("Invalid call. Nonexistent function").

- [ ] **Step 3: Implement the timer field + `_process()`**

In `scripts/battle/battle_scene.gd`, add near the other `_pending_*`/`_player_action_pending` fields (find `var _player_action_pending: bool = false` and add right after it):

```gdscript
var _player_action_pending: bool = false
# Visual-only decision countdown - the original force-passed the turn at 0
# (a real gameplay mechanic, frame217's onClipEvent(enterFrame)); this port
# deliberately doesn't port that half, since the whole turn-based flow
# already removed real-time pressure everywhere else. Ticks down only
# while it's the player's own decision window.
var _decision_timer: float = 0.0
```

Add a new `_process()` (this scene has no existing one - if a later task also needs `_process()`, both bodies must live in the SAME single `_process()` function, since GDScript only allows one):

```gdscript
func _process(delta: float) -> void:
	if _player_action_pending:
		_decision_timer = maxf(_decision_timer - delta, 0.0)
```

Add `_reset_decision_timer()` near `_on_unit_clicked`/the radial-menu functions is fine, or right after `_process()`:

```gdscript
func _reset_decision_timer() -> void:
	_decision_timer = BattleRunner.BATTLE_TIME_LIMIT
```

Call it wherever `_player_action_pending` is first set true for a new decision window - that's in `_battle_loop()`'s player-turn branch. Find:
```gdscript
		if runner.is_player_turn():
			_player_action_pending = true
			turn_label.text = "Your move"
```
Change to:
```gdscript
		if runner.is_player_turn():
			_player_action_pending = true
			_reset_decision_timer()
			turn_label.text = "Your move"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path . -gselect=test_battle_scene -gunit_test_name=test_decision_timer_ticks_down_while_player_is_deciding -glog=1`
then
Run: `godot --headless -s addons/gut/gut_cmdln.gd --path . -gselect=test_battle_scene -gunit_test_name=test_decision_timer_does_not_tick_while_not_player_action_pending -glog=1`
Expected: both PASS

- [ ] **Step 5: Add the visual countdown ring + label**

In `scenes/battle_scene.tscn`, add two new `ext_resource` lines (the ring texture, plus a font size override isn't needed - reuse defaults):
```
[ext_resource type="Texture2D" path="res://assets/ui/battle/battle_pbar_full.png" id="4_countdownring"]
```
Add new nodes as children of `BottomBar/Panel3` (which is currently an empty 320x110 `TextureRect` with no children - find its declaration and add these two nodes right after it in the file, as `parent="BottomBar/Panel3"`):
```
[node name="CountdownRing" type="TextureRect" parent="BottomBar/Panel3"]
layout_mode = 0
offset_left = 20.0
offset_top = 20.0
offset_right = 90.0
offset_bottom = 90.0
mouse_filter = 2
texture = ExtResource("4_countdownring")
expand_mode = 1
stretch_mode = 5

[node name="CountdownLabel" type="Label" parent="BottomBar/Panel3"]
layout_mode = 0
offset_left = 20.0
offset_top = 45.0
offset_right = 90.0
offset_bottom = 65.0
mouse_filter = 2
horizontal_alignment = 1
theme_override_font_sizes/font_size = 16
theme_override_colors/font_color = Color(0.9, 0.9, 0.85, 1)
```
In `battle_scene.gd`, add an `@onready` next to the other bottom-bar ones (`@onready var _pass_ring: Control = $BottomBar/PassRing`):
```gdscript
@onready var _countdown_label: Label = $BottomBar/Panel3/CountdownLabel
```
Then update `_process()` to also refresh the label text:
```gdscript
func _process(delta: float) -> void:
	if _player_action_pending:
		_decision_timer = maxf(_decision_timer - delta, 0.0)
	_countdown_label.text = str(int(ceil(_decision_timer)))
```
(Setting the label text every frame regardless of `_player_action_pending` is intentional and cheap - it keeps showing the last value, e.g. "0", during the AI's turn, rather than needing a separate hide/show toggle.)

- [ ] **Step 6: Run the full GUT suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path .`
Expected: all tests pass.

- [ ] **Step 7: Manual visual check**

Run the game (or the debug battle-jump entry point: `godot --path . res://scenes/battle_scene.tscn -- --battle=100`) and confirm the ring + counting-down number appear in the bottom-right panel during your turn, and the number stops moving (but stays visible at its last value) during the AI's turn.

- [ ] **Step 8: Document the deliberate divergence**

In `NEXT_PHASES.md`, find the "Battle screen niceties" bullet (or its current DONE-marked state if earlier tasks already updated it) and add a note next to the countdown item: it's visual-only, doesn't force-pass on expiry, matching this plan's spec.

- [ ] **Step 9: Commit**

```bash
git add scripts/battle/battle_scene.gd scenes/battle_scene.tscn test/integration/test_battle_scene.gd NEXT_PHASES.md
git commit -m "feat: visual decision countdown (no force-pass)

BattleRunner.BATTLE_TIME_LIMIT was a dead constant - now battle_scene.gd
ticks a _decision_timer down via _process(delta) while
_player_action_pending is true, reset at the start of each new decision
window, displayed as a ring (assets/ui/battle/battle_pbar_full.png,
extracted and unused until now) + numeric label in the bottom bar's
previously-empty Panel3.

Deliberately does NOT force-pass the turn at 0 like the original did -
this port's whole turn-based flow already removed real-time pressure
everywhere else, and reintroducing it here wasn't asked for. Documented
in NEXT_PHASES.md.

GUT suite green."
```

---

## Task 3: Hover ring fade + turn-gating

**Files:**
- Modify: `scripts/battle/battle_scene.gd`
- Modify: `scenes/battle/unit_overlay.tscn` (Ring node's default `visible`/`modulate`)
- Test: `test/integration/test_battle_scene.gd`

**Interfaces:**
- Consumes: `battle_scene.gd`'s existing `_rings: Dictionary`, `_on_unit_hovered(slot, entered)`, `_player_action_pending`.
- Produces: `_ring_fade_tweens: Dictionary` (slot -> `Tween`) - not consumed elsewhere, but keep the name if Task 4 or later ever needs to know a ring is mid-fade.

Source-verified this session (`frame_217/PlaceObject3_3394_450` and 5 sibling files, one per battle slot): the ring fades in at `+20`/frame and out at `-5`/frame (30fps → ~0.17s in, ~0.67s out), and **only fades in while it's the player's own decision window** (`_root.InBattle == false`, matching this port's `_player_action_pending == true`) - fade-OUT is never gated, it always plays regardless of turn. The current `_on_unit_hovered` shows the ring on any hover with no turn check at all - a real behavioral gap from source.

- [ ] **Step 1: Write the failing test**

Add to `test/integration/test_battle_scene.gd`:

```gdscript
func test_hover_ring_fades_in_only_during_player_decision_window():
	var save = PlayerSave.new_game("RingFadeTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	var ring: Control = scene._rings[2]  # battle 100's enemy slot (Prison Guard)
	assert_eq(ring.modulate.a, 0.0, "starts invisible")

	# Not the player's turn - hovering must not start a fade-in.
	scene._player_action_pending = false
	scene._on_unit_hovered(2, true)
	await scene.get_tree().create_timer(0.3).timeout
	assert_eq(ring.modulate.a, 0.0, "no fade-in outside the player's decision window")

	# The player's turn - hovering fades it in.
	scene._player_action_pending = true
	scene._on_unit_hovered(2, true)
	await scene.get_tree().create_timer(0.3).timeout
	assert_almost_eq(ring.modulate.a, 1.0, 0.05, "faded in during the decision window")

	# Fade-out is never gated, even outside the decision window.
	scene._player_action_pending = false
	scene._on_unit_hovered(2, false)
	await scene.get_tree().create_timer(0.8).timeout
	assert_almost_eq(ring.modulate.a, 0.0, 0.05, "fades back out regardless of turn state")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path . -gselect=test_battle_scene -gunit_test_name=test_hover_ring_fades_in_only_during_player_decision_window -glog=1`
Expected: FAIL - `ring.modulate.a` starts at `1.0` (default `Color.WHITE` modulate) since `unit_overlay.tscn`'s `Ring` currently uses `visible = false` instead of a transparent modulate, and `_on_unit_hovered` currently just flips `.visible` with no fade at all.

- [ ] **Step 3: Change Ring's default state**

In `scenes/battle/unit_overlay.tscn`, change the `Ring` node from:
```
[node name="Ring" type="Control" parent="."]
layout_mode = 0
mouse_filter = 2
visible = false
```
to:
```
[node name="Ring" type="Control" parent="."]
layout_mode = 0
mouse_filter = 2
modulate = Color(1, 1, 1, 0)
```
(Always `visible = true` now by default, just fully transparent - `queue_redraw()`/the `draw` signal still only matters when the node is actually visible, which it now always is; `modulate.a = 0` makes it invisible on screen exactly as before, but tween-able.)

- [ ] **Step 4: Implement the fade in `_on_unit_hovered`**

Find `battle_scene.gd`'s `_on_unit_hovered`:
```gdscript
func _on_unit_hovered(slot: int, entered: bool) -> void:
	var ring: Control = _rings.get(slot)
	var unit: CombatUnit = units.get(slot)
	if ring == null or unit == null or not unit.active:
		return
	ring.visible = entered
	ring.queue_redraw()
	var overlay: Control = _overlays[slot]
	var existing: Node = overlay.get_node_or_null("HoverInfo")
	if existing:
		existing.queue_free()
	if entered:
		...
```
Replace the `ring.visible = entered` line and add the fade + gating, and gate the existing "Lvl. N" label the same way (only created when the ring is actually going to fade IN, i.e. `entered and _player_action_pending`):
```gdscript
func _on_unit_hovered(slot: int, entered: bool) -> void:
	var ring: Control = _rings.get(slot)
	var unit: CombatUnit = units.get(slot)
	if ring == null or unit == null or not unit.active:
		return
	ring.queue_redraw()
	var showing: bool = entered and _player_action_pending
	if _ring_fade_tweens.has(slot):
		_ring_fade_tweens[slot].kill()
	var tween: Tween = create_tween()
	tween.tween_property(ring, "modulate:a", 1.0 if showing else 0.0, RING_FADE_IN_TIME if showing else RING_FADE_OUT_TIME)
	_ring_fade_tweens[slot] = tween
	var overlay: Control = _overlays[slot]
	var existing: Node = overlay.get_node_or_null("HoverInfo")
	if existing:
		existing.queue_free()
	if showing:
		var info: Label = Label.new()
		info.name = "HoverInfo"
		info.text = "Lvl. %d" % unit.plevel
		info.position = Vector2(-40, -8)
		info.size = Vector2(80, 16)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_theme_font_size_override("font_size", 11)
		info.add_theme_color_override("font_color", RING_COLORS[_relation_to_player(slot)])
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(info)
```
Add the two constants near `ORB_RADIUS`/`ORB_ARC_START` (find that `const` block and add these alongside it):
```gdscript
# Source-verified (frame_217/PlaceObject3_3394_450 and 5 sibling files):
# the hover ring fades in at +20/frame and out at -5/frame at the
# original's 30fps - a ~4x faster fade-in than fade-out.
const RING_FADE_IN_TIME: float = 0.17
const RING_FADE_OUT_TIME: float = 0.67
```
Add the new dictionary field next to `_rings`:
```gdscript
var _rings: Dictionary = {}  # slot -> ring Control (hover indicator)
var _ring_fade_tweens: Dictionary = {}  # slot -> in-flight fade Tween
```

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path . -gselect=test_battle_scene -gunit_test_name=test_hover_ring_fades_in_only_during_player_decision_window -glog=1`
Expected: PASS

- [ ] **Step 6: Run the full GUT suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path .`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add scripts/battle/battle_scene.gd scenes/battle/unit_overlay.tscn test/integration/test_battle_scene.gd
git commit -m "fix: hover ring fades asymmetrically, only during the player's own turn

Source-verified (frame_217/PlaceObject3_3394_450 and 5 sibling per-slot
clip files): the original's hover ring fades in at +20/frame and out at
-5/frame (30fps - ~0.17s in, ~0.67s out), and only fades in while it's
the player's own decision window (InBattle == false, matching this
port's _player_action_pending). The current port showed the ring on any
hover regardless of whose turn it was - a real behavioral gap from
source, not just missing polish. Fade-out is never gated, matching
source (a ring that started showing right as your turn ends still fades
out normally).

unit_overlay.tscn's Ring node switches from visible=false (instant
toggle) to modulate=Color(1,1,1,0) (tween-able transparency).

GUT suite green."
```

---

## Task 4: Radial menu fades out on hover-leave (replaces click-away)

**Files:**
- Modify: `scripts/battle/battle_scene.gd`
- Modify: `scenes/battle_scene.tscn` (add a one-shot `Timer` node)
- Test: `test/integration/test_battle_scene.gd`

**Interfaces:**
- Consumes: Task 3's `RING_FADE_OUT_TIME` constant (reused for the menu's own fade-out duration, since the real duration lives in a shared symbol's internal timeline this session's investigation couldn't reach - see spec).
- Produces: `_is_point_over_radial_menu_area(global_point: Vector2) -> bool` - a pure predicate, split out specifically so it's testable without simulating real mouse input (same reasoning as `ItemSlot._drag_payload()`).

The project owner directly verified against the live original game: moving the mouse away from the clicked unit and its fanned-out orbs fades the radial menu out, rather than this session's earlier click-away guess (`_unhandled_input()`, added before this verification happened). A naive "left the unit's own hit area" check would close the menu the instant the player moves toward an orb to click it (orbs sit ~62px out from the unit, well outside its own hit area) - the predicate must check the unit's hit area **and every orb**.

- [ ] **Step 1: Write the failing test**

Add to `test/integration/test_battle_scene.gd`:

```gdscript
func test_is_point_over_radial_menu_area():
	var save = PlayerSave.new_game("MenuAreaTest", 0)
	save.skill_points = 8
	TalentTree.learn(save, 0)
	TalentTree.learn(save, 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	scene._player_action_pending = true
	scene._on_unit_clicked(2)  # battle 100's enemy slot (Prison Guard)
	assert_not_null(scene._radial_menu, "menu opened")

	var overlay: Control = scene._overlays[2]
	var unit_center: Vector2 = overlay.hit_button.get_global_rect().get_center()
	assert_true(scene._is_point_over_radial_menu_area(unit_center), "over the unit's own hit area")

	var orb: Control = scene._radial_menu.get_child(0)
	var orb_center: Vector2 = orb.get_global_rect().get_center()
	assert_true(scene._is_point_over_radial_menu_area(orb_center), "over an orb, well outside the unit's hit area")

	assert_false(scene._is_point_over_radial_menu_area(Vector2(-1000, -1000)), "nowhere near either")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func test_radial_menu_fades_out_on_hover_leave():
	var save = PlayerSave.new_game("MenuFadeTest", 0)
	save.skill_points = 8
	TalentTree.learn(save, 0)
	TalentTree.learn(save, 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	scene._player_action_pending = true
	scene._on_unit_clicked(2)
	assert_not_null(scene._radial_menu)

	# Directly invoke the same handler _process() would call once the
	# leave-grace timer fires - avoids waiting on real timer duration in
	# the test while still exercising the real fade-then-free logic.
	scene._start_radial_menu_fade_out()
	await scene.get_tree().create_timer(scene.RING_FADE_OUT_TIME + 0.1).timeout
	assert_null(scene._radial_menu, "faded out and freed")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path . -gselect=test_battle_scene -gunit_test_name=test_is_point_over_radial_menu_area -glog=1`
Expected: FAIL - `_is_point_over_radial_menu_area` doesn't exist yet.

- [ ] **Step 3: Add the Timer node**

In `scenes/battle_scene.tscn`, add a new node as a child of `BottomBar`'s parent (the root `BattleScene` node) - anywhere in the file after the `BattleScene` node declaration, e.g. right after the `Battlefield` node:
```
[node name="RadialMenuLeaveTimer" type="Timer" parent="."]
wait_time = 0.15
one_shot = true
```
Add the connection at the bottom of the file, alongside the other `[connection]` lines:
```
[connection signal="timeout" from="RadialMenuLeaveTimer" to="." method="_start_radial_menu_fade_out"]
```

- [ ] **Step 4: Implement the predicate + process loop + fade-out**

In `scripts/battle/battle_scene.gd`, add the `@onready` next to `_pass_ring`:
```gdscript
@onready var _radial_menu_leave_timer: Timer = $RadialMenuLeaveTimer
```
Add a field to remember which unit slot the currently-open menu belongs to (find `var _radial_menu: Control = null` and add right after):
```gdscript
var _radial_menu: Control = null
var _radial_menu_owner_slot: int = -1
```
Set it in `_on_unit_clicked`, right where `_radial_menu` itself gets created:
```gdscript
	_radial_menu = Control.new()
	_radial_menu.position = SLOT_POSITIONS.get(slot, Vector2(400, 300))
	_radial_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radial_menu_owner_slot = slot
	battlefield.add_child(_radial_menu)
```
Remove the `_unhandled_input()` function entirely (it was this session's click-away guess, made before the live-game verification):
```gdscript
# DELETE THIS WHOLE FUNCTION:
func _unhandled_input(event: InputEvent) -> void:
	if _radial_menu == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_radial_menu()
```
Add the predicate, the process-loop hookup, and the fade-out, near `_close_radial_menu`:
```gdscript
# Pure predicate (no engine side effects) so it's directly testable - see
# ItemSlot._drag_payload() for the same "split for testability" reasoning.
# The orbs fan out ~62px from the unit's own hit area, well outside it, so
# checking the unit alone would close the menu the instant the player
# moves toward an orb to click it.
func _is_point_over_radial_menu_area(global_point: Vector2) -> bool:
	if _radial_menu == null:
		return false
	var overlay: Control = _overlays.get(_radial_menu_owner_slot)
	if overlay != null and overlay.hit_button.get_global_rect().has_point(global_point):
		return true
	for orb in _radial_menu.get_children():
		if orb is Control and orb.get_global_rect().has_point(global_point):
			return true
	return false


func _start_radial_menu_fade_out() -> void:
	if _radial_menu == null:
		return
	var tween: Tween = create_tween()
	tween.tween_property(_radial_menu, "modulate:a", 0.0, RING_FADE_OUT_TIME)
	tween.tween_callback(_close_radial_menu)
```
Update `_process()` (already added in Task 2 - fold this in, don't add a second `_process()`):
```gdscript
func _process(delta: float) -> void:
	if _player_action_pending:
		_decision_timer = maxf(_decision_timer - delta, 0.0)
	_countdown_label.text = str(int(ceil(_decision_timer)))
	if _radial_menu != null:
		if _is_point_over_radial_menu_area(get_global_mouse_position()):
			_radial_menu_leave_timer.stop()
			_radial_menu.modulate.a = 1.0
		elif _radial_menu_leave_timer.is_stopped():
			_radial_menu_leave_timer.start()
```
`_close_radial_menu()` needs to reset the owner slot too:
```gdscript
func _close_radial_menu() -> void:
	if _radial_menu != null:
		_radial_menu.queue_free()
		_radial_menu = null
	_radial_menu_owner_slot = -1
```

- [ ] **Step 5: Remove the now-obsolete click-away test**

In `test/integration/test_battle_scene.gd`, delete `test_radial_menu_closes_on_click_away` (the whole function, lines ~196-222 per this session's earlier work) - it tests behavior this task deliberately removes. The two new tests from Step 1 replace its coverage.

- [ ] **Step 6: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path . -gselect=test_battle_scene -glog=1`
Expected: PASS for `test_is_point_over_radial_menu_area` and `test_radial_menu_fades_out_on_hover_leave`; `test_radial_menu_closes_on_click_away` no longer exists so it can't fail.

- [ ] **Step 7: Run the full GUT suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path .`
Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add scripts/battle/battle_scene.gd scenes/battle_scene.tscn test/integration/test_battle_scene.gd
git commit -m "fix: radial menu fades out on hover-leave, not click-elsewhere

Replaces this session's earlier click-away guess (_unhandled_input(),
added before the original's real behavior was confirmed) with the
project owner's directly-verified live-game mechanic: moving the mouse
away from the clicked unit AND every one of its fanned-out orbs fades
the menu out. A naive 'left the unit' check would close it the instant
the player moves toward an orb (they sit ~62px outside the unit's own
hit area) - _is_point_over_radial_menu_area() checks both.

A 0.15s one-shot Timer (RadialMenuLeaveTimer) debounces brief gap-
crossing between the unit and its orbs before starting the fade, reusing
Task 3's RING_FADE_OUT_TIME for the menu's own fade duration (the real
duration lives inside a shared symbol's internal timeline this session's
source investigation couldn't reach).

test_radial_menu_closes_on_click_away removed (tests behavior this task
deliberately replaces); test_is_point_over_radial_menu_area and
test_radial_menu_fades_out_on_hover_leave cover the new mechanic.

GUT suite green."
```

---

## Task 5: Buff icon extraction

**Files:**
- Create: `dev/urchin_dev/swf/extract/buff_icons.py`
- Modify: `pyproject.toml` (register the `extract_buff_icons` script entry, matching `extract_item_icons`'s existing entry)
- Create (generated by running the script, not hand-written): `assets/ui/buffs/*.png`

**Interfaces:**
- Consumes: nothing from other tasks in this plan.
- Produces: `assets/ui/buffs/<internal_name>.png` files - Task 6 loads these by path.

This is a Python/`ffdec` extraction task, not GDScript - no GUT tests apply. Verification is direct file-output inspection, matching how `item_icons.py`/`faces.py` were verified when they were built.

- [ ] **Step 1: Confirm the frame-label-to-`internal_name` correspondence by hand**

Run:
```sh
uv run python3 -c '
from urchin_dev import WEB_SWF_XML
from urchin_dev.swf import snapshot_timeline

xml = WEB_SWF_XML.read_text()
_snaps, labels = snapshot_timeline(xml, 100, set())
print(len(labels))
for name in ["FIRESAM", "TWINGUARDIANS", "SHATTERBOLT"]:
    print(name, labels.get(name))
'
```
Expected: prints a count near 419, and each of those 3 names resolves to a frame number. Cross-check `FIRESAM` against `dev/converted_json/buffs.json`'s buff id 1 (`"internal_name": "FIRESAM"`) - confirms the label really does match the buff's own name, not a coincidence, before writing the full extraction script.

- [ ] **Step 2: Write `buff_icons.py`**

Create `dev/urchin_dev/swf/extract/buff_icons.py`, closely mirroring `dev/urchin_dev/swf/extract/item_icons.py`'s structure (same header-comment convention, same `run()` helper, same `snapshot_timeline`-based label lookup):

```python
# The original per-buff icon sheet: DefineSprite 100 (nested inside
# DefineSprite 104, "KrinBuffShower", at depth 4 named "buffIcon" -
# frame42/sonny2_addNewBuffKrin.txt's buffIcon.gotoAndStop(buffId)), one
# labeled frame per buff, labeled by the buff's own internal_name (e.g.
# frame label "FIRESAM" matches buff id 1's internal_name in buffs.json
# exactly - confirmed by hand before writing this script). Writes
# assets/ui/buffs/<internal_name>.png.
#
# Same rendering approach as item_icons.py/faces.py: export the sprite
# directly via ffdec's own renderer (not reassembled shape-by-shape), then
# trim each frame to its own opaque bounds. 400 ShowFrameTags carry 419
# FrameLabelTags - some frames have more than one label (aliases); every
# label found gets its own output file pointing at that frame's content,
# so an aliased buff still gets a real icon rather than being skipped.
#
# Requires ffdec (~/.local/bin/ffdec). Run: uv run extract_buff_icons
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

OUT_DIR = REPO_ROOT / "assets" / "ui" / "buffs"
BUFF_ICON_SPRITE = 100
ZOOM = 2.0


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
    _snaps, labels = snapshot_timeline(xml, BUFF_ICON_SPRITE, set())
    print(f"buff icon labels: {len(labels)}", file=sys.stderr)

    work_dir = Path(tempfile.mkdtemp(prefix="buff_icons_"))
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
                str(BUFF_ICON_SPRITE),
                "-export",
                "sprite",
                str(frames_dir),
                str(WEB_SWF),
            ]
        )
        sprite_frames_dir = frames_dir / f"DefineSprite_{BUFF_ICON_SPRITE}"

        OUT_DIR.mkdir(parents=True, exist_ok=True)
        written: dict[str, str] = {}
        missing = []
        for label, frame in labels.items():
            src = sprite_frames_dir / f"{frame}.png"
            if not src.exists():
                missing.append((label, frame))
                continue
            file_name = re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_") + ".png"
            img = Image.open(src)
            bbox = img.getchannel("A").getbbox()
            img = (
                img.crop(bbox)
                if bbox is not None
                else Image.new("RGBA", (1, 1), (0, 0, 0, 0))
            )
            img.save(OUT_DIR / file_name)
            written[label] = file_name
        print(f"buff icons written: {len(written)}", file=sys.stderr)
        if missing:
            print(f"missing source frames: {missing}", file=sys.stderr)
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Register the script entry point**

In `pyproject.toml`, find the `[project.scripts]` section's `extract_item_icons = "..."` line and add a new line right after it, matching the same format:
```toml
extract_buff_icons = "urchin_dev.swf.extract.buff_icons:main"
```

- [ ] **Step 4: Run the extraction**

Run: `uv run extract_buff_icons`
Expected: prints `buff icon labels: ~419` and `buff icons written: ~419` (some labels may collapse to the same sanitized filename if two internal_names differ only in characters the sanitizer strips - that's fine and matches the same tolerance `item_icons.py` already has). Spot-check a couple of the specific buffs already confirmed in Step 1:
```sh
file assets/ui/buffs/FIRESAM.png assets/ui/buffs/TWINGUARDIANS.png assets/ui/buffs/SHATTERBOLT.png
```
Expected: all three exist as real PNG files, not zero-byte or missing.

- [ ] **Step 5: Visually spot-check a couple of icons**

Open 2-3 of the extracted PNGs (any image viewer, or read them via the Read tool) and confirm they look like real, distinct icon art (not all identical, not blank) - same due diligence `item_icons.py`'s Ancient Cage/A Broken Pipe checks used.

- [ ] **Step 6: Commit**

```bash
git add dev/urchin_dev/swf/extract/buff_icons.py pyproject.toml assets/ui/buffs/
git commit -m "feat: extract the original per-buff icon sheet (DefineSprite 100)

The original doesn't use a family/polarity fallback scheme for buff
icons at all - frame42/sonny2_addNewBuffKrin.txt shows a real per-buff
icon sheet (DefineSprite 100, nested inside KrinBuffShower's DefineSprite
104 at depth 4 named 'buffIcon', .gotoAndStop(buffId)), 400 ShowFrameTags
with 419 FrameLabelTags named by the buff's own internal_name (e.g.
frame label 'FIRESAM' matches buff id 1's internal_name in buffs.json
exactly - confirmed by hand before writing this script).

Same extraction approach as item_icons.py/faces.py: ffdec's own sprite
renderer, trimmed to each frame's opaque bounds - not reassembled
shape-by-shape. Writes assets/ui/buffs/<internal_name>.png. Some of the
419 labels alias the same frame (400 frames < 419 labels) - every label
still gets its own output file, same tolerance item_icons.py already has
for its own label variance.

Run via: uv run extract_buff_icons"
```

---

## Task 6: Buff icons over units (UI wiring)

**Files:**
- Create: `scripts/entities/buff_icons.gd`
- Modify: `scenes/battle/unit_overlay.tscn` (new icon row)
- Modify: `scripts/battle/unit_overlay.gd`
- Test: `test/unit/test_buff_icons.gd` (new file)
- Test: `test/integration/test_unit_overlay.gd` (new file, if `unit_overlay.gd` has no existing test file - check first with `fd -g "test_unit_overlay*" test/`; if one already exists, add to it instead)

**Interfaces:**
- Consumes: Task 5's `assets/ui/buffs/<internal_name>.png` files, `CombatUnit.buff_slots` (existing, `Array` of `{"cd": int, "buff_id": int, "buff_value": float, "shield_buff_value": float}`), `CombatUnit.ELEMENT_ORDER`/`MenuTheme.ELEMENT_COLORS` (existing), `Buff` resource fields (`internal_name`, `display_name`, `tooltip_description`, `element_type: CombatUnit.Element`).
- Produces: `BuffIcons.icon_for(buff: Buff) -> Texture2D` (static, class_name `BuffIcons`), `UnitOverlay.refresh_buffs(unit: CombatUnit, buffs_by_id: Dictionary) -> void`.

Source-verified mechanism (spec's Task 4 Background): up to 7 icon slots per unit, sorted by remaining duration (`cd`) descending, 17px pitch from a 110px offset flipped by team side, each tinted by the buff's element color, showing a remaining-turns counter and a name+description tooltip.

- [ ] **Step 1: Write the failing unit test for `BuffIcons.icon_for()`**

Create `test/unit/test_buff_icons.gd`:

```gdscript
# BuffIcons.icon_for() resolves a Buff to its real extracted icon
# (dev/urchin_dev/swf/extract/buff_icons.py - assets/ui/buffs/<internal_name>.png).
extends GutTest


func test_icon_for_returns_a_real_texture_for_a_real_buff():
	var buff: Buff = BuffManagerAuto.buffs_by_internal_name.get("FIRESAM")
	assert_not_null(buff, "FIRESAM exists in the real buff data")
	var texture: Texture2D = BuffIcons.icon_for(buff)
	assert_not_null(texture, "resolves to a real icon texture")


func test_icon_for_returns_null_for_unknown_buff():
	var fake_buff: Buff = Buff.new()
	fake_buff.internal_name = "NOT_A_REAL_BUFF_NAME"
	assert_null(BuffIcons.icon_for(fake_buff), "no icon exists for a made-up name")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path . -gselect=test_buff_icons -glog=1`
Expected: FAIL - `BuffIcons` class doesn't exist yet.

- [ ] **Step 3: Implement `BuffIcons`**

Create `scripts/entities/buff_icons.gd`:

```gdscript
# buff_icons.gd
# Resolves a Buff to its real icon, extracted from the original's own
# per-buff icon sheet (DefineSprite 100 - see
# dev/urchin_dev/swf/extract/buff_icons.py). No family/polarity fallback
# scheme - every buff either has a real extracted icon or (a handful of
# buffs the original itself never assigned a distinct frame to) doesn't,
# in which case this returns null and the caller skips that buff's icon.
class_name BuffIcons
extends RefCounted

const ICON_DIR: String = "res://assets/ui/buffs/"


static func icon_for(buff: Buff) -> Texture2D:
	if buff == null or buff.internal_name.is_empty():
		return null
	var path: String = "%s%s.png" % [ICON_DIR, buff.internal_name]
	if not ResourceLoader.exists(path):
		return null
	return load(path)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path . -gselect=test_buff_icons -glog=1`
Expected: PASS

- [ ] **Step 5: Add the icon row to `unit_overlay.tscn`**

In `scenes/battle/unit_overlay.tscn`, add a new `HBoxContainer` as a child of the root `UnitOverlay` node, after `HitButton`'s declaration:
```
[node name="BuffRow" type="HBoxContainer" parent="."]
layout_mode = 0
offset_left = -60.0
offset_top = -100.0
offset_right = 60.0
offset_bottom = -84.0
mouse_filter = 2
theme_override_constants/separation = 1
```
(7 slots at a tight pitch fit comfortably in this 120px-wide row; exact pixel-perfect positioning isn't critical here since this is new UI with no original on-screen reference to match pixel-for-pixel, unlike the health/name bars above it.)

- [ ] **Step 6: Implement `unit_overlay.gd`'s buff row refresh**

Modify `scripts/battle/unit_overlay.gd`:
```gdscript
extends Control
class_name UnitOverlay

const MAX_BUFF_ICONS: int = 7

@onready var ring: Control = $Ring
@onready var name_label: Label = $NameLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_value: Label = $HealthValue
@onready var focus_bar: ProgressBar = $FocusBar
@onready var hit_button: Button = $HitButton
@onready var buff_row: HBoxContainer = $BuffRow


func setup(unit_name: String) -> void:
	name_label.text = unit_name


# Refreshes the buff-icon row from the unit's own buff_slots, sorted by
# remaining duration (cd) descending, capped at MAX_BUFF_ICONS - matches
# frame42/sonny2_addNewBuffKrin.txt's BUFFARRAYK.sortOn("CD", DESCENDING)
# + the 7-slot cap exactly. Each icon is modulate-tinted by the buff's
# element color (Godot tints at runtime - no per-element art baked into
# the extracted PNGs), with the remaining-turns count and a
# name+description tooltip. Buffs with no cd (expired/inactive slots,
# buff_id == 0) are skipped entirely.
func refresh_buffs(unit: CombatUnit, buffs_by_id: Dictionary) -> void:
	for child in buff_row.get_children():
		child.queue_free()
	if unit == null:
		return
	var active_slots: Array = []
	for slot in unit.buff_slots:
		if int(slot.get("cd", 0)) > 0 and int(slot.get("buff_id", 0)) != 0:
			active_slots.append(slot)
	active_slots.sort_custom(func(a, b): return int(a["cd"]) > int(b["cd"]))
	for i in mini(active_slots.size(), MAX_BUFF_ICONS):
		var slot: Dictionary = active_slots[i]
		var buff: Buff = buffs_by_id.get(int(slot["buff_id"]))
		if buff == null:
			continue
		var icon_texture: Texture2D = BuffIcons.icon_for(buff)
		if icon_texture == null:
			continue
		var icon_rect: TextureRect = TextureRect.new()
		icon_rect.texture = icon_texture
		icon_rect.custom_minimum_size = Vector2(16, 16)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var element_index: CombatUnit.Element = buff.element_type
		if element_index != -1:
			icon_rect.modulate = MenuTheme.ELEMENT_COLORS[element_index]
		icon_rect.tooltip_text = "%s (%d turns)\n%s" % [buff.display_name, int(slot["cd"]), buff.tooltip_description]
		var counter: Label = Label.new()
		counter.text = str(int(slot["cd"]))
		counter.add_theme_font_size_override("font_size", 8)
		counter.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_rect.add_child(counter)
		buff_row.add_child(icon_rect)
```

- [ ] **Step 7: Wire the refresh call from `battle_scene.gd`**

`unit_overlay.gd`'s `refresh_buffs()` needs to be called every time bars refresh. `battle_scene.gd`'s `_refresh_bars()` already loops per-slot updating `_health_bars[slot]`/`_focus_bars[slot]` (separate Dictionaries, not `_overlays[slot]`'s own child references), so the overlay itself needs a fresh lookup via `_overlays[slot]`. Find:
```gdscript
func _refresh_bars(snap: bool = true) -> void:
	for slot in _visuals:
		var unit: CombatUnit = units.get(slot)
		if unit == null:
			continue
		if snap and int(_display_hp.get(slot, 0)) != int(unit.life_n):
			_log("bar snap: slot=%d (%s) hp %d -> %d" % [
				slot, unit.player_name, int(_display_hp.get(slot, 0)), int(unit.life_n),
			])
		if snap:
			_display_hp[slot] = unit.life_n
		var health: ProgressBar = _health_bars[slot]
		health.max_value = unit.life_u
		health.value = _display_hp.get(slot, unit.life_n)
		_health_values[slot].text = str(int(_display_hp.get(slot, unit.life_n)))
		var focus: ProgressBar = _focus_bars[slot]
		focus.max_value = max(unit.focus_u, 1)
		focus.value = unit.focus_n
		_update_stun_visual(slot, unit, _visuals[slot])
```
Add one line at the end of the loop body:
```gdscript
func _refresh_bars(snap: bool = true) -> void:
	for slot in _visuals:
		var unit: CombatUnit = units.get(slot)
		if unit == null:
			continue
		if snap and int(_display_hp.get(slot, 0)) != int(unit.life_n):
			_log("bar snap: slot=%d (%s) hp %d -> %d" % [
				slot, unit.player_name, int(_display_hp.get(slot, 0)), int(unit.life_n),
			])
		if snap:
			_display_hp[slot] = unit.life_n
		var health: ProgressBar = _health_bars[slot]
		health.max_value = unit.life_u
		health.value = _display_hp.get(slot, unit.life_n)
		_health_values[slot].text = str(int(_display_hp.get(slot, unit.life_n)))
		var focus: ProgressBar = _focus_bars[slot]
		focus.max_value = max(unit.focus_u, 1)
		focus.value = unit.focus_n
		_update_stun_visual(slot, unit, _visuals[slot])
		_overlays[slot].refresh_buffs(unit, BuffManagerAuto.buffs_by_id)
```

- [ ] **Step 8: Write the integration test**

First check whether a test file for `unit_overlay.gd` already exists:
```sh
fd -g "test_unit_overlay*" test/
```
If none exists, create `test/integration/test_unit_overlay.gd`:
```gdscript
# UnitOverlay's buff-icon row (scenes/battle/unit_overlay.tscn) -
# .claude/plan_battle_screen_niceties.md Task 4.
extends GutTest

const UnitOverlayScene = preload("res://scenes/battle/unit_overlay.tscn")


func test_refresh_buffs_populates_sorted_by_duration_capped_at_seven():
	var overlay: UnitOverlay = add_child_autofree(UnitOverlayScene.instantiate())
	var unit := CombatUnit.new()
	unit.buff_slots = [
		{"cd": 3, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0},   # FIRESAM
		{"cd": 10, "buff_id": 0, "buff_value": 0.0, "shield_buff_value": 0.0},  # 0 = empty slot, skipped
	]
	var buff_a := Buff.new()
	buff_a.internal_name = "FIRESAM"
	buff_a.display_name = "The Immortal Flame"
	buff_a.tooltip_description = "test"
	buff_a.element_type = CombatUnit.Element.FIRE
	var buffs_by_id: Dictionary = {1: buff_a}

	overlay.refresh_buffs(unit, buffs_by_id)
	assert_eq(overlay.buff_row.get_child_count(), 1, "one real active buff shown, the empty slot skipped")


func test_refresh_buffs_clears_expired_buffs():
	var overlay: UnitOverlay = add_child_autofree(UnitOverlayScene.instantiate())
	var unit := CombatUnit.new()
	var buff_a := Buff.new()
	buff_a.internal_name = "FIRESAM"
	buff_a.element_type = CombatUnit.Element.FIRE
	unit.buff_slots = [{"cd": 1, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0}]
	overlay.refresh_buffs(unit, {1: buff_a})
	assert_eq(overlay.buff_row.get_child_count(), 1)

	unit.buff_slots = []  # buff expired
	overlay.refresh_buffs(unit, {1: buff_a})
	assert_eq(overlay.buff_row.get_child_count(), 0, "cleared once the buff is gone")
```

- [ ] **Step 9: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path . -gselect=test_unit_overlay -glog=1`
Expected: PASS

- [ ] **Step 10: Run the full GUT suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path .`
Expected: all tests pass.

- [ ] **Step 11: Manual visual check**

Run `godot --path . res://scenes/battle_scene.tscn -- --battle=104` (Doctor Leath's battle, has real scripted buffs applying during the fight per this session's earlier work) and confirm icons appear over units as buffs land, tinted by element, with a working tooltip.

- [ ] **Step 12: Commit**

```bash
git add scripts/entities/buff_icons.gd scenes/battle/unit_overlay.tscn scripts/battle/unit_overlay.gd scripts/battle/battle_scene.gd test/unit/test_buff_icons.gd test/integration/test_unit_overlay.gd
git commit -m "feat: buff icons over units, matching KrinBuffShower exactly

BuffIcons.icon_for() resolves a Buff to its real extracted icon
(assets/ui/buffs/<internal_name>.png, from the previous task's
extraction) - no family/polarity fallback scheme, matching the original's
own mechanism.

unit_overlay.tscn gains a BuffRow (HBoxContainer); unit_overlay.gd's new
refresh_buffs() populates it from CombatUnit.buff_slots, sorted by
remaining duration descending and capped at 7 - matching
frame42/sonny2_addNewBuffKrin.txt's BUFFARRAYK.sortOn(\"CD\", DESCENDING)
+ 7-slot loop exactly. Each icon is modulate-tinted by the buff's element
color, shows the remaining-turns count, and a name+description tooltip.
battle_scene.gd's per-unit bar refresh now also calls
overlay.refresh_buffs().

GUT suite green."
```

---

## Task 7: Combat log panel

**Files:**
- Create: `scenes/battle/combat_log_panel.tscn`
- Create: `scripts/battle/combat_log_panel.gd`
- Modify: `scenes/battle_scene.tscn` (instance the panel + add a toggle button in `BottomBar/Panel3`)
- Modify: `scripts/battle/battle_scene.gd`
- Test: `test/unit/test_combat_log_panel.gd` (new file)
- Test: `test/integration/test_battle_scene.gd`

**Interfaces:**
- Consumes: `BattleRunner.EventType`/`BattleManager.ResultType` enums (existing), `battle_scene.gd`'s `units: Dictionary` (slot -> `CombatUnit`, for name resolution).
- Produces: `CombatLogPanel.append_event(event: Dictionary, units: Dictionary) -> void`, `CombatLogPanel.toggle() -> void` - not consumed by any other task in this plan.

First scrollable-text panel in the project (confirmed this session - zero `RichTextLabel`/`ScrollContainer` usage anywhere else). Toggleable, off by default, per the project owner's explicit choice. The formatter mirrors `_play_events()`'s existing `match` structure exactly so every event type it already animates also gets a log line.

- [ ] **Step 1: Write the failing test for the formatter (pure logic, no scene needed)**

Create `test/unit/test_combat_log_panel.gd`:

```gdscript
# CombatLogPanel's event->text formatter - mirrors battle_scene.gd's
# _play_events() match structure so every animated event type also gets
# a readable log line. .claude/plan_battle_screen_niceties.md Task 5.
extends GutTest

const CombatLogPanelScene = preload("res://scenes/battle/combat_log_panel.tscn")

var units: Dictionary


func before_each():
	var caster := CombatUnit.new()
	caster.player_name = "Veradux"
	var target := CombatUnit.new()
	target.player_name = "Grulnak"
	units = {1: caster, 2: target}


func test_format_damage_move_line():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
		"move_name": "Acid Slash",
		"result": {"type": BattleManager.ResultType.DAMAGE, "amount": 42.0, "did_crit": false, "target_died": false},
	}
	assert_eq(panel._format_line(event, units), "Veradux hits Grulnak with Acid Slash for 42")


func test_format_miss_move_line():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
		"move_name": "Acid Slash",
		"result": {"type": BattleManager.ResultType.MISS},
	}
	assert_eq(panel._format_line(event, units), "Veradux's Acid Slash misses Grulnak")


func test_format_death_line():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {"type": BattleRunner.EventType.DEATH, "slot": 2}
	assert_eq(panel._format_line(event, units), "Grulnak falls")


func test_format_speech_line():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {"type": BattleRunner.EventType.SPEECH, "speaker_slot": 1, "say": "Watch out!"}
	assert_eq(panel._format_line(event, units), "Veradux: Watch out!")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path . -gselect=test_combat_log_panel -glog=1`
Expected: FAIL - `combat_log_panel.tscn` doesn't exist yet.

- [ ] **Step 3: Create the scene**

Create `scenes/battle/combat_log_panel.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/battle/combat_log_panel.gd" id="1_log"]

[node name="CombatLogPanel" type="PanelContainer"]
custom_minimum_size = Vector2(240, 160)
visible = false
mouse_filter = 2
script = ExtResource("1_log")

[node name="Scroll" type="ScrollContainer" parent="."]
layout_mode = 2

[node name="LogText" type="RichTextLabel" parent="Scroll"]
custom_minimum_size = Vector2(224, 300)
layout_mode = 2
size_flags_vertical = 3
bbcode_enabled = false
scroll_following = true
```

- [ ] **Step 4: Implement `combat_log_panel.gd`**

Create `scripts/battle/combat_log_panel.gd`:
```gdscript
# combat_log_panel.gd
# A toggleable, live-narrated combat log - the first scrollable-text panel
# in the project. Mirrors battle_scene.gd's _play_events() event-type
# match exactly, so every event type that already drives animation/audio
# also gets a readable line here. Off/hidden by default.
extends PanelContainer
class_name CombatLogPanel

@onready var _log_text: RichTextLabel = $Scroll/LogText


func toggle() -> void:
	visible = not visible


# Appends one line for an event, if that event type produces a readable
# line at all (phase_advanced/battle_ended don't - same events
# _play_events() plays a sound/does nothing visible for, respectively).
func append_event(event: Dictionary, units: Dictionary) -> void:
	var line: String = _format_line(event, units)
	if line.is_empty():
		return
	if _log_text.text != "":
		_log_text.text += "\n"
	_log_text.text += line


func _unit_name(units: Dictionary, slot: int) -> String:
	var unit: CombatUnit = units.get(slot)
	return unit.player_name if unit != null else "???"


func _format_line(event: Dictionary, units: Dictionary) -> String:
	match event.get("type"):
		BattleRunner.EventType.MOVE:
			return _format_move_line(event, units)
		BattleRunner.EventType.STUNNED:
			return "%s is stunned" % _unit_name(units, int(event["caster_slot"]))
		BattleRunner.EventType.MOVE_FAILED:
			return "%s doesn't have enough %s" % [
				_unit_name(units, int(event["caster_slot"])), str(event.get("reason", "")),
			]
		BattleRunner.EventType.DISPEL:
			return "%s's buffs are dispelled" % _unit_name(units, int(event["target_slot"]))
		BattleRunner.EventType.DEATH:
			return "%s falls" % _unit_name(units, int(event["slot"]))
		BattleRunner.EventType.SPEECH:
			return "%s: %s" % [_unit_name(units, int(event.get("speaker_slot", 0))), str(event.get("say", ""))]
		_:
			return ""


func _format_move_line(event: Dictionary, units: Dictionary) -> String:
	var caster_name: String = _unit_name(units, int(event["caster_slot"]))
	var target_name: String = _unit_name(units, int(event["target_slot"]))
	var move_name: String = str(event.get("move_name", "a move"))
	var result: Dictionary = event.get("result", {})
	match result.get("type"):
		BattleManager.ResultType.DAMAGE:
			return "%s hits %s with %s for %d" % [caster_name, target_name, move_name, int(result.get("amount", 0))]
		BattleManager.ResultType.HEAL:
			return "%s heals %s for %d" % [caster_name, target_name, int(result.get("amount", 0))]
		BattleManager.ResultType.FOCUS:
			return "%s restores %s's focus by %d" % [caster_name, target_name, int(result.get("amount", 0))]
		BattleManager.ResultType.MISS:
			return "%s's %s misses %s" % [caster_name, move_name, target_name]
		_:
			return ""
```

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path . -gselect=test_combat_log_panel -glog=1`
Expected: PASS

- [ ] **Step 6: Wire the panel + toggle button into `battle_scene.tscn`/`battle_scene.gd`**

In `scenes/battle_scene.tscn`, add the ext_resource:
```
[ext_resource type="PackedScene" path="res://scenes/battle/combat_log_panel.tscn" id="5_combatlog"]
```
Instance it as a child of the root `BattleScene` node (anywhere after `BottomBar`'s declaration):
```
[node name="CombatLogPanel" parent="." instance=ExtResource("5_combatlog")]
layout_mode = 1
offset_left = 20.0
offset_top = 20.0
offset_right = 260.0
offset_bottom = 180.0
```
Add a small toggle button as a child of `BottomBar/Panel3` (alongside Task 2's `CountdownRing`/`CountdownLabel`):
```
[node name="LogToggleButton" type="Button" parent="BottomBar/Panel3"]
layout_mode = 0
offset_left = 260.0
offset_top = 20.0
offset_right = 300.0
offset_bottom = 60.0
text = "Log"
tooltip_text = "Toggle the combat log"
```
Add the connection at the bottom of the file:
```
[connection signal="pressed" from="BottomBar/Panel3/LogToggleButton" to="." method="_on_log_toggle_pressed"]
```
In `battle_scene.gd`, add the `@onready` next to `_countdown_label`:
```gdscript
@onready var _combat_log: CombatLogPanel = $CombatLogPanel
```
Add the handler near `_on_pass_pressed`/`_on_retreat_pressed`:
```gdscript
func _on_log_toggle_pressed() -> void:
	_combat_log.toggle()
```
Feed it live events - find `_play_events()` (the function that already matches on every event type to drive animation) and add one line at the top of its loop body, before the existing `match event["type"]:`:
```gdscript
func _play_events(events: Array) -> void:
	for event in events:
		_combat_log.append_event(event, units)
		match event["type"]:
```

- [ ] **Step 7: Write the integration test**

Add to `test/integration/test_battle_scene.gd`:
```gdscript
func test_combat_log_toggle_and_live_narration():
	var save = PlayerSave.new_game("LogTest", 0)
	save.skill_points = 8
	TalentTree.learn(save, 0)
	TalentTree.learn(save, 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	assert_false(scene._combat_log.visible, "off by default")
	scene._on_log_toggle_pressed()
	assert_true(scene._combat_log.visible, "toggled on")
	scene._on_log_toggle_pressed()
	assert_false(scene._combat_log.visible, "toggled back off")

	var player: CombatUnit = scene.units[1]
	player.ai_enabled = true
	player.move_pool_attack = TalentTree.get_known_move_ids(save)
	player.cooldowns_attack = []
	for i in player.move_pool_attack.size():
		player.cooldowns_attack.append(0)

	await wait_for_signal(scene.battle_finished, 30)
	assert_ne(scene._combat_log._log_text.text, "", "narrated at least one line over the course of a real battle")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path . -gselect=test_battle_scene -gunit_test_name=test_combat_log_toggle_and_live_narration -glog=1`
Expected: PASS

- [ ] **Step 9: Run the full GUT suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd --path .`
Expected: all tests pass.

- [ ] **Step 10: Manual visual check**

Run `godot --path . res://scenes/battle_scene.tscn -- --battle=100`, toggle the log button, and confirm the scrolling panel narrates the fight readably as it plays, staying scrolled to the bottom.

- [ ] **Step 11: Update `NEXT_PHASES.md`**

Mark the whole "Battle screen niceties" bullet DONE, summarizing all 5 items (matching how earlier plans in this project close out - see e.g. the "Item click-n-drag" or "Cutscenes" bullets for the expected style: what shipped, what deliberately diverged from source and why).

- [ ] **Step 12: Commit**

```bash
git add scenes/battle/combat_log_panel.tscn scripts/battle/combat_log_panel.gd scenes/battle_scene.tscn scripts/battle/battle_scene.gd test/unit/test_combat_log_panel.gd test/integration/test_battle_scene.gd NEXT_PHASES.md
git commit -m "feat: toggleable live combat log panel

First RichTextLabel/ScrollContainer panel in the project - no existing
pattern to copy, built fresh. CombatLogPanel._format_line() mirrors
battle_scene.gd's _play_events() event-type match exactly, so every
event type that already drives animation/audio also gets a readable
line (\"Veradux hits Grulnak with Acid Slash for 42\", \"Grulnak falls\",
etc). append_event() is called from _play_events() itself, so the log
narrates live as the fight plays, not after the fact.

Off/hidden by default, toggled via a new button in the bottom bar's
Panel3 (LogToggleButton), per the project owner's explicit choice.

Closes out all 5 battle-screen-niceties items - NEXT_PHASES.md updated.

GUT suite green."
```
