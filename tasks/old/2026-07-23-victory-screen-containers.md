# Victory Screen: Native Godot Containers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `scripts/battle/victory_screen.gd` off imperative runtime Control-building and give it a real `.tscn` (it currently has none at all - `battle_scene.gd` instantiates it via
`preload("res://scripts/battle/victory_screen.gd").new()`). This is the third and final `MenuTheme`-helper caller - once this lands, `MenuTheme.add_texture_rect`/`add_label` have zero remaining
callers anywhere in the project and can be deleted from `menu_theme.gd` entirely (this plan does that deletion as its last task).

**Architecture:** Everything in the current `_ready()` is static (fixed count, fixed position, never changes after construction) and moves into a new `scenes/battle/victory_screen.tscn`: the
backdrop, left/middle panel textures, all the fixed labels, the money/exp value labels (only their `.text` is dynamic, set once by `setup()`), and the Proceed button. The one piece that is
genuinely dynamic - `_build_experience_rows()`, which builds 1-3 rows (one per fighter: the player plus 0-2 deployed companions) - does NOT stay as raw `MenuTheme.add_label`/`add_texture_rect`
calls. Instead it becomes a new reusable `scenes/battle/victory_experience_row.tscn` (portrait + name + level + exp track/fill + percent, laid out once in the editor) instanced once per fighter,
matching the same reusable-`PackedScene` pattern already used for `ItemSlot` and `talent_node.tscn` earlier in this phase - this is what lets `MenuTheme`'s two helpers become fully dead project-wide
rather than surviving as a dynamic-content exception. `_build_drop_slots()` (already using the existing `ItemSlotScene` `PackedScene` pattern, count varies per battle's rolled drops) and
`inventory_panel` (already `preload("res://scenes/ui/inventory.tscn").instantiate()`) are both already correctly architected and stay untouched.

**Tech Stack:** Godot 4.7, GDScript, GUT 9.6.1 (headless test runner vendored at `addons/gut/`).

## Global Constraints

- `test/integration/test_battle_scene.gd`'s `test_full_battle_scene_run` must keep passing unchanged. On a WIN outcome it does `scene.get_node_or_null("VictoryScreen")` (the node name is set
  explicitly by `battle_scene.gd`, not by the scene file - unaffected by this plan), then reads `victory._drop_slots` and calls `victory._on_drop_clicked(drop, save)` - neither touches anything
  this plan changes. The battle's WIN outcome is probabilistic (AI-driven), so this assertion block may or may not execute on any given test run - that is pre-existing behavior, not something to
  fix. No test file needs modification.
- This is a pure refactor (behavior-preserving) - no new functionality, no rendering/behavior change anywhere.
- Confirmed via `rg -n "MenuTheme\.(add_texture_rect|add_label)" scripts/` before writing this plan: `victory_screen.gd` is the ONLY remaining caller of either helper anywhere in `scripts/` (11
  call sites total: 9 inside `_ready()`, which this plan makes static, and 5 inside `_build_experience_rows()`, which this plan replaces with the new reusable row scene). After this plan's Task 1
  and Task 2 land, zero callers remain, which is what makes Task 4's deletion from `menu_theme.gd` safe.
- Godot enum literals used below (confirmed against this project's actual Godot 4.7.1 binary, not assumed from memory): `TextureRect.EXPAND_IGNORE_SIZE = 1`, `TextureRect.STRETCH_SCALE = 0`,
  `TextureRect.STRETCH_KEEP_ASPECT_CENTERED = 5`, `Control.MOUSE_FILTER_STOP = 0`, `Control.MOUSE_FILTER_IGNORE = 2`, `Control.PRESET_FULL_RECT = 15`, `TextServer.AUTOWRAP_WORD_SMART = 3`,
  `HORIZONTAL_ALIGNMENT_LEFT = 0`, `HORIZONTAL_ALIGNMENT_CENTER = 1`, `HORIZONTAL_ALIGNMENT_RIGHT = 2`.
- Compile-check after every `.gd` edit: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s <script.gd> --path .` (expect a `GameData`/other-autoload "Identifier not found"
  line - known false positive, not a real error).
- Run the full suite after every task: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`. Confirm the actual baseline count live in whatever
  worktree this executes in before starting - do not trust a hardcoded number in this document. If a fresh worktree's first run shows unrelated parse errors or a much lower pass count than
  expected, that is a known stale-import-cache artifact - run `/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit --path .` once first to force a full asset reimport, then
  re-run the suite.
- This is a pure refactor - no new failing test to write. Confirm the existing tests are GREEN before touching a file, make the declarative change, confirm they are GREEN again after.

---

### Task 1: Create the reusable `victory_experience_row.tscn`

**Files:**
- Create: `scripts/battle/victory_experience_row.gd`
- Create: `scenes/battle/victory_experience_row.tscn`

**Interfaces:**
- Consumes: nothing external.
- Produces: `class_name VictoryExperienceRow` with a `setup(portrait_file: String, display_name: String, level: int, experience: float) -> void` method. Task 2 instances this scene once per
  fighter and calls `setup()` on each instance - disjoint from this task's own files.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS. Note the exact count - you'll compare against this exact number after every task in this plan.

- [ ] **Step 2: Write `scripts/battle/victory_experience_row.gd`**

```gdscript
# victory_experience_row.gd
# One row of the victory screen's "Character Experience" list (portrait,
# name, level, and an experience bar) - instanced once per fighter by
# victory_screen.gd's _build_experience_rows(), which sets its position
# and calls setup() with that fighter's data.
extends Control
class_name VictoryExperienceRow

@onready var face: TextureRect = $Face
@onready var name_label: Label = $NameLabel
@onready var level_label: Label = $LevelLabel
@onready var exp_fill: TextureRect = $ExpFill
@onready var percent_label: Label = $PercentLabel


func setup(portrait_file: String, display_name: String, level: int, experience: float) -> void:
	face.texture = MenuTheme.texture(portrait_file)
	name_label.text = display_name
	level_label.text = "Lvl. %d" % level
	var fraction: float = clamp(experience / 100.0, 0.0, 1.0)
	exp_fill.size.x = 150.0 * fraction
	percent_label.text = "%d%%" % int(experience)
```

- [ ] **Step 3: Write `scenes/battle/victory_experience_row.tscn`**

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/battle/victory_experience_row.gd" id="1_row"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/exp_track.png" id="2_exptrack"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/exp_fill.png" id="3_expfill"]

[node name="VictoryExperienceRow" type="Control"]
script = ExtResource("1_row")

[node name="Face" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 58.0
offset_top = 0.0
offset_right = 92.0
offset_bottom = 44.0
mouse_filter = 2
expand_mode = 1
stretch_mode = 5

[node name="NameLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 100.0
offset_top = 0.0
offset_right = 250.0
offset_bottom = 16.0
mouse_filter = 2
theme_override_font_sizes/font_size = 13

[node name="LevelLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 100.0
offset_top = 16.0
offset_right = 250.0
offset_bottom = 30.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.8, 0.8, 0.8, 1)
theme_override_font_sizes/font_size = 11

[node name="ExpTrack" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 100.0
offset_top = 32.0
offset_right = 250.0
offset_bottom = 44.0
mouse_filter = 2
texture = ExtResource("2_exptrack")
expand_mode = 1
stretch_mode = 0

[node name="ExpFill" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 100.0
offset_top = 32.0
offset_right = 100.0
offset_bottom = 44.0
mouse_filter = 2
texture = ExtResource("3_expfill")
expand_mode = 1
stretch_mode = 0

[node name="PercentLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 104.0
offset_top = 31.0
offset_right = 164.0
offset_bottom = 44.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.1, 0.1, 0.1, 1)
theme_override_font_sizes/font_size = 9
```

Notes on values: every offset is copied verbatim from the pre-migration code's per-row `Rect2`s, with the shared `y` variable treated as the row's own local origin (`y=0`) since the ROW ITSELF
will be positioned at `Vector2(0, y)` by the code that instances it (Task 2) - `Face` was `Rect2(58, y, 34, 44)` -> local `(58,0)` size `(34,44)`; `NameLabel` was `Rect2(100, y, 150, 16)` -> local
`(100,0)` size `(150,16)`; `LevelLabel` was `Rect2(100, y+16, 150, 14)` -> local `(100,16)`; `ExpTrack` was `Rect2(100, y+32, 150, 12)` -> local `(100,32)`; `ExpFill` was
`Rect2(100, y+32, 150*fraction, 12)` -> local `(100,32)`, starting COLLAPSED (`offset_right == offset_left`, zero width - `setup()` grows it); `PercentLabel` was `Rect2(104, y+31, 60, 13)` -> local
`(104,31)`. `ExpFill`'s texture is static here (unlike the pre-migration code, which re-loaded `"exp_fill.png"` on every construction) - only its WIDTH is dynamic, set by `setup()`.

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/battle/victory_experience_row.gd --path .`
Expected: clean compile - no errors at all (this script doesn't reference any autoload, so it should NOT show even the usual false positive).

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Step 1 (this task adds no new tests and isn't referenced by anything yet).

- [ ] **Step 6: Commit**

```bash
git add scripts/battle/victory_experience_row.gd scenes/battle/victory_experience_row.tscn
git commit -m "feat: add the reusable VictoryExperienceRow scene for the victory screen's fighter list"
```

---

### Task 2: Create `victory_screen.tscn` and rewrite `victory_screen.gd`

**Files:**
- Create: `scenes/battle/victory_screen.tscn`
- Modify: `scripts/battle/victory_screen.gd`

**Interfaces:**
- Consumes: `VictoryExperienceRow` (`scenes/battle/victory_experience_row.tscn`, Task 1) - instanced once per fighter, `.position` set, then `.setup(...)` called.
- Produces: nothing new consumed by a later task in this plan except the fact that `victory_screen.gd` no longer calls `MenuTheme.add_texture_rect`/`add_label` at all - Task 4 relies on this to
  safely delete those two functions from `menu_theme.gd`.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 1's ending count exactly.

- [ ] **Step 2: Write `scenes/battle/victory_screen.tscn`**

```
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/battle/victory_screen.gd" id="1_victory"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/menu_backdrop.png" id="2_backdrop"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/panel_large.png" id="3_panellarge"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/panel_center.png" id="4_panelcenter"]

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_proceed_normal"]
bg_color = Color(0.05, 0.05, 0.06, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_proceed_hover"]
bg_color = Color(0.1, 0.12, 0.1, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[node name="VictoryScreen" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("1_victory")

[node name="Backdrop" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 14.2
offset_top = 14.9
offset_right = 782.7
offset_bottom = 440.0
mouse_filter = 0
texture = ExtResource("2_backdrop")
expand_mode = 1
stretch_mode = 0

[node name="LeftPanel" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 47.5
offset_top = 86.6
offset_right = 296.6
offset_bottom = 353.7
mouse_filter = 2
texture = ExtResource("3_panellarge")
expand_mode = 1
stretch_mode = 0

[node name="ExperienceLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 47.5
offset_top = 92.0
offset_right = 296.6
offset_bottom = 112.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.55, 0.55, 0.55, 1)
theme_override_font_sizes/font_size = 14
horizontal_alignment = 1
text = "Character Experience"

[node name="MiddlePanel" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 309.0
offset_top = 82.2
offset_right = 492.1
offset_bottom = 408.7
mouse_filter = 2
texture = ExtResource("4_panelcenter")
expand_mode = 1
stretch_mode = 0

[node name="DropsLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 316.0
offset_top = 92.0
offset_right = 486.0
offset_bottom = 122.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.75, 0.75, 0.75, 1)
theme_override_font_sizes/font_size = 12
autowrap_mode = 3
text = "Victory! Items that dropped:"

[node name="ClickHintLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 318.0
offset_top = 230.0
offset_right = 484.0
offset_bottom = 270.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.95, 0.75, 0.2, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 1
autowrap_mode = 3
text = "CLICK on the items that you wish to keep!"

[node name="MoneyLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 318.0
offset_top = 276.0
offset_right = 418.0
offset_bottom = 292.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.95, 0.75, 0.2, 1)
theme_override_font_sizes/font_size = 12
text = "Money gained:"

[node name="MoneyValue" type="Label" parent="."]
layout_mode = 0
offset_left = 390.0
offset_top = 276.0
offset_right = 484.0
offset_bottom = 292.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.95, 0.75, 0.2, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 2

[node name="ExpLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 318.0
offset_top = 294.0
offset_right = 418.0
offset_bottom = 310.0
mouse_filter = 2
theme_override_font_sizes/font_size = 12
text = "Exp. gained:"

[node name="ExpValue" type="Label" parent="."]
layout_mode = 0
offset_left = 390.0
offset_top = 294.0
offset_right = 484.0
offset_bottom = 310.0
mouse_filter = 2
theme_override_font_sizes/font_size = 12
horizontal_alignment = 2

[node name="ProceedHintLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 318.0
offset_top = 318.0
offset_right = 484.0
offset_bottom = 358.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.6, 0.6, 0.6, 1)
theme_override_font_sizes/font_size = 11
horizontal_alignment = 1
autowrap_mode = 3
text = "Once you are finished, press below to proceed:"

[node name="ProceedButton" type="Button" parent="."]
layout_mode = 0
offset_left = 342.0
offset_top = 362.0
offset_right = 460.0
offset_bottom = 392.0
theme_override_colors/font_color = Color(0.35, 0.95, 0.25, 1)
theme_override_colors/font_hover_color = Color(0.6, 1.0, 0.5, 1)
theme_override_font_sizes/font_size = 17
theme_override_styles/normal = SubResource("StyleBoxFlat_proceed_normal")
theme_override_styles/hover = SubResource("StyleBoxFlat_proceed_hover")
text = "Proceed!"

[connection signal="pressed" from="ProceedButton" to="." method="_on_proceed_pressed"]
```

Notes on values: every `offset_*` is copied verbatim from the pre-migration code's `Rect2`s (`MenuTheme.BACKDROP_RECT` -> `Backdrop`, `LEFT_PANEL` -> `LeftPanel`, `MIDDLE_PANEL` -> `MiddlePanel`,
each label's own `Rect2` literal). `ExperienceLabel`'s height was written as `20` in the original (`Rect2(LEFT_PANEL.position.x, 92, LEFT_PANEL.size.x, 20)`) giving `offset_bottom = 112`, not the
panel's own height - that is intentional, not a bug, the label rect is independent of the panel rect it sits on. `Backdrop` keeps the explicit `mouse_filter = 0` (`Control.MOUSE_FILTER_STOP`)
override the original code applied right after construction; every other node here was built via `MenuTheme.add_texture_rect`/`add_label`, which always applies `MOUSE_FILTER_IGNORE` (`= 2`) - so
they all get that value explicitly. `ProceedButton` gets ONLY `normal` and `hover` style overrides (matching the original exactly - it never touched `"pressed"`). `MoneyValue`/`ExpValue` are
static shells here - their `.text` is set once by `setup()`, matching the original (`_money_value`/`_exp_value` were assigned the return value of `add_label` and had `.text` set later, never
rebuilt).

- [ ] **Step 3: Rewrite `scripts/battle/victory_screen.gd`**

Replace lines 1 through 36 (the header comment through the `var _exp_value: Label` declaration) with:

```gdscript
# victory_screen.gd
# The post-battle victory overlay (references/2026_07_18_flashpoint/16-18):
# - left panel "Character Experience": portrait + level + XP bar per fighter
# - middle: "Victory! Items that dropped:" with the drop slots - CLICK a
#   drop to keep it (moves into the first free inventory cell), gold
#   call-out text, money/exp gained, and the green Proceed! button
# - right: the shared InventoryPanel
# Reuses the menu chrome (MenuTheme) - the original showed this inside the
# same red menu shell.
extends Control
class_name VictoryScreen

signal proceed_pressed

const ItemSlotScene: PackedScene = preload("res://scenes/ui/item_slot.tscn")
const VictoryExperienceRowScene: PackedScene = preload("res://scenes/battle/victory_experience_row.tscn")

const INVENTORY_AT: Vector2 = Vector2(503.5, 81.6)
const DROP_ORIGIN: Vector2 = Vector2(321.0, 130.0)
const DROP_COLUMNS: int = 4

const PORTRAITS: Dictionary[int, String] = {
	0: "portraits/sonny.png",
	1: "portraits/veradux.png",
	2: "portraits/roald.png",
	3: "portraits/felicity.png",
	4: "portraits/wolfgang.png",
	5: "portraits/amber.png",
}

var inventory_panel: InventoryPanel

var _drop_slots: Array[ItemSlot] = []

@onready var _money_value: Label = $MoneyValue
@onready var _exp_value: Label = $ExpValue
```

(`LEFT_PANEL`/`MIDDLE_PANEL` are deleted here - they fed only the now-static `Backdrop`/`LeftPanel`/`MiddlePanel` texture construction, which no longer runs. `INVENTORY_AT`/`DROP_ORIGIN`/
`DROP_COLUMNS`/`PORTRAITS` all stay - `INVENTORY_AT` positions the still-code-driven `inventory_panel`, `DROP_ORIGIN`/`DROP_COLUMNS` position the still-code-driven drop slots, `PORTRAITS` is read
by `_build_experience_rows()`, unchanged below.)

Replace `_ready()` with:

```gdscript
func _ready():
	inventory_panel = preload("res://scenes/ui/inventory.tscn").instantiate()
	inventory_panel.position = INVENTORY_AT
	add_child(inventory_panel)
	inventory_panel.show_sell_button(false)


func _on_proceed_pressed() -> void:
	proceed_pressed.emit()
```

(Everything else `_ready()` used to build - backdrop, panels, static labels, the Proceed button - is now static in the `.tscn`. `mouse_filter = Control.MOUSE_FILTER_IGNORE` is now the root node's
own `mouse_filter = 2` property in the `.tscn`, set once at scene-load instead of every `_ready()`. `_on_proceed_pressed()` replaces the original's inline `func(): proceed_pressed.emit()` closure -
`.tscn` `[connection]` blocks need a named method, not an anonymous lambda.)

Leave `setup()` completely untouched - it still calls `_build_experience_rows()`/`_build_drop_slots()` and sets `_money_value.text`/`_exp_value.text` exactly as before, now against the
`@onready`-resolved references instead of ones assigned during runtime construction.

Replace `_build_experience_rows()` with:

```gdscript
func _build_experience_rows(save: PlayerSave, party_ids: Array) -> void:
	var fighters: Array[int] = [0]
	for party_id in party_ids:
		fighters.append(int(party_id))
	var y: float = 120.0
	for party_id in fighters:
		var row: VictoryExperienceRow = VictoryExperienceRowScene.instantiate()
		row.position = Vector2(0, y)
		add_child(row)
		var display_name: String
		var level: int
		var experience: float
		if party_id == 0:
			display_name = save.name_user
			level = save.level
			experience = save.experience
		else:
			display_name = str(Party.COMPANIONS.get(party_id, {}).get("name", "?"))
			level = int(save.party_levels[party_id]) if party_id < save.party_levels.size() else 1
			experience = float(save.party_exp[party_id]) if party_id < save.party_exp.size() else 0.0
		row.setup(PORTRAITS.get(party_id, PORTRAITS[0]), display_name, level, experience)
		y += 62.0
```

Leave `_build_drop_slots()` and `_on_drop_clicked()` completely untouched - both are already correctly architected (dynamic count per battle, using the existing `ItemSlotScene` `PackedScene`
pattern) and out of scope for this plan.

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/battle/victory_screen.gd --path .`
Expected: only the known autoload false positive, if anything.

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Task 1's ending count.

- [ ] **Step 6: Commit**

```bash
git add scenes/battle/victory_screen.tscn scripts/battle/victory_screen.gd
git commit -m "refactor: give VictoryScreen a real scene file and move its static chrome into it"
```

---

### Task 3: Update `battle_scene.gd`'s instantiation call site

**Files:**
- Modify: `scripts/battle/battle_scene.gd`

**Interfaces:**
- Consumes: `scenes/battle/victory_screen.tscn` (Task 2).
- Produces: nothing new - Task 4 is a separate file (`menu_theme.gd`) and doesn't depend on this task's specifics beyond "victory_screen.gd has zero remaining `MenuTheme` helper calls," which
  Task 2 already established.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 2's ending count exactly.

- [ ] **Step 2: Update the instantiation call site**

Find this block in `scripts/battle/battle_scene.gd` (around line 913):

```gdscript
		var victory: VictoryScreen = preload("res://scripts/battle/victory_screen.gd").new()
		victory.name = "VictoryScreen"
		victory.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(victory)
		victory.setup(save, rewards, drops, fighting_party)
		victory.proceed_pressed.connect(_on_victory_proceed)
```

Replace it with:

```gdscript
		var victory: VictoryScreen = preload("res://scenes/battle/victory_screen.tscn").instantiate()
		victory.name = "VictoryScreen"
		add_child(victory)
		victory.setup(save, rewards, drops, fighting_party)
		victory.proceed_pressed.connect(_on_victory_proceed)
```

(The `set_anchors_preset(Control.PRESET_FULL_RECT)` call is dropped - the `.tscn`'s root node now has `anchors_preset = 15` baked in, matching what that call used to set at runtime. Everything
else - the node name assignment, `add_child`, `setup()` call, and signal connection - stays exactly as before.)

- [ ] **Step 3: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/battle/battle_scene.gd --path .`
Expected: only the known autoload false positive, if anything.

- [ ] **Step 4: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Task 2's ending count. Pay particular attention to `test_battle_scene.gd`'s `test_full_battle_scene_run` - re-run it a few extra times in isolation if useful
(`-gtest=test/integration/test_battle_scene.gd`), since the WIN-outcome assertions (the only ones this plan actually touches) are gated behind a probabilistic AI-driven battle outcome and won't
necessarily execute on every run.

- [ ] **Step 5: Commit**

```bash
git add scripts/battle/battle_scene.gd
git commit -m "refactor: instantiate VictoryScreen from its new scene file instead of .new()"
```

---

### Task 4: Delete `MenuTheme`'s now-fully-dead runtime helpers and update `NEXT_PHASES.md`

**Files:**
- Modify: `scripts/ui/menu/menu_theme.gd`
- Modify: `NEXT_PHASES.md`

**Interfaces:** none - this is cleanup plus documentation, no other task depends on it.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 3's ending count exactly.

- [ ] **Step 2: Confirm zero remaining callers**

Run: `rg -n "MenuTheme\.(add_texture_rect|add_label)" scripts/`
Expected: NO OUTPUT AT ALL. If anything matches, STOP - do not delete the functions, report back with what still calls them (this would mean either an earlier task in this plan wasn't completed
correctly, or a caller outside `scripts/` exists that wasn't accounted for).

- [ ] **Step 3: Delete `add_texture_rect()` and `add_label()` from `scripts/ui/menu/menu_theme.gd`**

Delete both functions entirely (their full bodies, including the doc comments directly above each). Leave every other member of `menu_theme.gd` untouched - `ELEMENT_COLORS`, `HEAL_COLOR`,
`STAT_LABELS`, `STAT_COLORS`, `bar_fill_fraction()`, `element_display_value()`, `texture()`, `format_money()`, `BACKDROP_RECT`, `CLOSE_RECT`, `SLOT_SIZE`, `SLOT_STEP`, `ORIGIN` are all genuinely
reusable non-construction utilities/constants, still read by multiple screens, and stay regardless.

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/menu/menu_theme.gd --path .`
Expected: clean compile - `menu_theme.gd` doesn't reference any autoload, so this should show no output at all, not even the usual false positive.

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Task 3's ending count.

- [ ] **Step 6: Update `NEXT_PHASES.md`**

Find the "UI architecture: native Godot Containers instead of code-built controls" section's `**In progress**` paragraph (the one most recently extended to mention `main_menu.gd`). Replace the
whole paragraph - this phase's `MenuTheme`-retirement sub-goal is now fully done - with a `**DONE**`-style extension of the existing done-list, e.g.:

```markdown
`scripts/ui/menu/inventory_window.gd`, `scripts/ui/main_menu.gd`, and `scripts/battle/victory_screen.gd` are also migrated, completing the retirement of `menu_theme.gd`'s runtime
`add_texture_rect`/`add_label` helpers (both deleted - zero remaining callers). `victory_screen.gd` didn't have a `.tscn` at all before this - it now has
`scenes/battle/victory_screen.tscn` for its static chrome, plus a new reusable `scenes/battle/victory_experience_row.tscn` (instanced once per fighter, 1-3 depending on the deployed party) for
what used to be raw per-row `MenuTheme` calls, matching the same instanced-`PackedScene` pattern as `ItemSlot`/`talent_node.tscn`. Only the drop slots (`ItemSlotScene`, count varies per battle)
and the embedded `InventoryPanel` stay code-instanced, both already using the established `PackedScene` pattern from the start. `battle_scene.gd`'s instantiation call site was updated from
`.new()` to `preload(...).instantiate()` accordingly.
```

Splice this in place of the prior in-progress note (adjust surrounding prose/punctuation as needed so the section still reads naturally - the exact prior wording doesn't need to be quoted back,
just replaced with the above content in substance). Everything else named in this phase (`battle_scene.gd`'s own bottom-bar/stance-row/pass-ring construction, a SEPARATE piece of work from the
`MenuTheme` retirement) is still pending.

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/menu/menu_theme.gd NEXT_PHASES.md
git commit -m "refactor: delete MenuTheme's now-dead add_texture_rect/add_label helpers"
```
