# Inventory Window: Native Godot Containers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `scripts/ui/menu/inventory_window.gd` + `scenes/ui/menu/inventory_window.tscn` off imperative runtime Control-building, as the first of three files that still call `MenuTheme`'s
runtime UI-construction helpers (`add_texture_rect`/`add_label`) - retiring all three is what finally lets those two helpers be deleted from `menu_theme.gd` itself in a later plan (the other two,
`main_menu.gd` and `victory_screen.gd`, are separate follow-up plans; do not touch `menu_theme.gd` in this plan).

**Architecture:** Everything genuinely static (fixed count, fixed position, content that never changes at runtime) moves into the `.tscn`: the backdrop/close/status chrome, the left panel's name/
level/experience-row content, the center panel's stat rows and Piercing/Defense titles, all 16 element-bar tracks (8 "per" + 8 "def", a fixed count that never varies), and all 6 portrait frames
(party ids 0-5, always exactly 6 regardless of the live roster). What stays code-driven: the 16 bar FILLS' height/position (recomputed every `refresh()` from live save data via the unchanged
`_update_bar()`), the 6 portraits' tooltip/modulate (recomputed every `refresh()` from live roster data via the unchanged `_refresh_portraits()`), and the two pieces that were already code-instanced
before this phase even started - `equip_view` (`EquipDollView.new()`, no `.tscn` exists for it) and `inventory_panel` (`preload("res://scenes/ui/inventory.tscn").instantiate()`, matching the
identical pattern already established in `store_window.gd`/`achievements_window.gd`'s siblings).

**Tech Stack:** Godot 4.7, GDScript, GUT 9.6.1 (headless test runner vendored at `addons/gut/`).

## Global Constraints

- `test/integration/test_ui_scenes.gd`'s `test_inventory_window_equips_from_grid_click` must keep passing unchanged - it calls `window.refresh()`, reads `window.inventory_panel.inventory_grid`,
  and calls `window._on_equip_slot_clicked(equip_slot)` - none of these touch the node structure this plan changes. `test_hotbar_menu_toggle_is_exclusive_and_glows` (in the same file) reads
  `game.get_node("InventoryWindow").visible` - unaffected, the root node's name/group are unchanged. No test file needs modification.
- This is a pure refactor (behavior-preserving) - no new functionality, no rendering/behavior change anywhere.
- Constants that MUST be deleted once their only reader (the removed construction code) is gone: `LEFT_PANEL`, `CENTER_PANEL`, `PARTY_BAR`, `STAT_ROWS_Y`, `BAR_WIDTH`, `BAR_STEP`, `EXP_TRACK`,
  `EXP_ZERO_BOX`, `PORTRAIT_FILES`.
- Constants that MUST STAY (still read at runtime after this refactor): `CLASS_NAMES` (read by `refresh()`), `INVENTORY_AT` (read by `_build_inventory()`, unchanged/out of scope),
  `EQUIP_SLOT_CENTERS`/`DOLL_POSITION`/`DOLL_SCALE` (read by `_build_left_panel()`'s remaining `equip_view.setup()` call), `BAR_BLOCK_CENTERS_Y` and `BAR_TRACK_HEIGHT` (both still read by
  `_update_bar()` to compute each fill's bottom edge every refresh), and `EXP_FILL` (still read by `refresh()` as `EXP_FILL.size.x` - the full-width reference the fraction-scaled fill width is
  computed against - do NOT delete this one even though it looks like a pure construction constant).
- Godot enum literals used below: `TextureRect.EXPAND_IGNORE_SIZE = 1`, `TextureRect.STRETCH_SCALE = 0`, `TextureRect.STRETCH_KEEP_ASPECT_CENTERED = 5`, `TextureButton.STRETCH_KEEP_ASPECT_CENTERED = 5`,
  `Control.MOUSE_FILTER_IGNORE = 2`, `Control.MOUSE_FILTER_STOP = 0`, `Control.PRESET_FULL_RECT = 15`, `HORIZONTAL_ALIGNMENT_CENTER = 1`, `HORIZONTAL_ALIGNMENT_RIGHT = 2`,
  `VERTICAL_ALIGNMENT_CENTER = 1`.
- Compile-check after every `.gd` edit: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s <script.gd> --path .` (expect a `GameData`/other-autoload "Identifier not found"
  line - known false positive, not a real error).
- Run the full suite after every task: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`. Confirm the actual baseline count live in whatever
  worktree this executes in before starting - do not trust a hardcoded number in this document.
- This is a pure refactor - no new failing test to write. Confirm the existing tests are GREEN before touching a file, make the declarative change, confirm they are GREEN again after.

---

### Task 1: Move the static chrome, left panel, and center panel content into the scene file

**Files:**
- Modify: `scenes/ui/menu/inventory_window.tscn`
- Modify: `scripts/ui/menu/inventory_window.gd`

**Interfaces:**
- Consumes: nothing external.
- Produces: `_status_label`, `_name_label`, `_level_label`, `_exp_fill`, `_exp_percent`, `_stat_values` (`Array[Label]`) as `@onready $Path` references instead of runtime-built. Tasks 2/3 touch
  disjoint parts of the same two files (the bar block and the party bar respectively) and don't depend on anything from this task.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gtest=test/integration/test_ui_scenes.gd`
Expected: PASS, all tests in that file. Also run without the filter for the full-suite count and note it - you'll compare against this exact number after every task in this plan.

- [ ] **Step 2: Add the static chrome/left-panel/center-panel nodes to `scenes/ui/menu/inventory_window.tscn`**

Read the current file first (currently just an empty `InventoryWindow` root `Control` + script, `groups=["inventory_window", "menu_screen"]`, full-rect anchors). Add the following ext_resources
and child nodes (keep the existing `[gd_scene]`/root node lines - bump `load_steps` to account for the script + 7 textures = `9`):

```
[ext_resource type="Texture2D" path="res://assets/ui/menu/menu_backdrop.png" id="2_backdrop"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/close_x.png" id="3_close"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/panel_large.png" id="4_panellarge"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/panel_center.png" id="5_panelcenter"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/exp_track.png" id="6_exptrack"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/exp_fill.png" id="7_expfill"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/exp_zero_box.png" id="8_expzerobox"]

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

[node name="CloseButton" type="TextureButton" parent="."]
layout_mode = 0
offset_left = 734.5
offset_top = 29.8
offset_right = 771.2
offset_bottom = 66.2
texture_normal = ExtResource("3_close")
ignore_texture_size = true
stretch_mode = 5

[node name="StatusLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 47.5
offset_top = 414.0
offset_right = 747.5
offset_bottom = 434.0
mouse_filter = 2
theme_override_colors/font_color = Color(1, 0.85, 0.3, 1)
theme_override_font_sizes/font_size = 12

[node name="LeftPanel" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 47.5
offset_top = 86.6
offset_right = 296.6
offset_bottom = 353.7
mouse_filter = 2
texture = ExtResource("4_panellarge")
expand_mode = 1
stretch_mode = 0

[node name="NameLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 47.5
offset_top = 92.0
offset_right = 296.6
offset_bottom = 114.0
mouse_filter = 2
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_font_sizes/font_size = 17
horizontal_alignment = 1

[node name="LevelLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 47.5
offset_top = 114.0
offset_right = 296.6
offset_bottom = 132.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.8, 0.8, 0.8, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 1

[node name="ExperienceLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 36.0
offset_top = 285.0
offset_right = 136.0
offset_bottom = 301.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.8, 0.8, 0.8, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 2
text = "Experience:"

[node name="ExpTrack" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 138.5
offset_top = 283.2
offset_right = 267.7
offset_bottom = 302.2
mouse_filter = 2
texture = ExtResource("6_exptrack")
expand_mode = 1
stretch_mode = 0

[node name="ExpFill" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 172.6
offset_top = 283.3
offset_right = 267.7
offset_bottom = 302.0
mouse_filter = 2
texture = ExtResource("7_expfill")
expand_mode = 1
stretch_mode = 0

[node name="ExpZeroBox" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 138.4
offset_top = 282.9
offset_right = 172.7
offset_bottom = 301.6
mouse_filter = 2
texture = ExtResource("8_expzerobox")
expand_mode = 1
stretch_mode = 0

[node name="ExpPercent" type="Label" parent="."]
layout_mode = 0
offset_left = 138.4
offset_top = 282.9
offset_right = 172.7
offset_bottom = 301.6
mouse_filter = 2
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_font_sizes/font_size = 11
horizontal_alignment = 1
vertical_alignment = 1
text = "0%"

[node name="CenterPanel" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 309.0
offset_top = 82.2
offset_right = 492.1
offset_bottom = 408.7
mouse_filter = 2
texture = ExtResource("5_panelcenter")
expand_mode = 1
stretch_mode = 0

[node name="StatLabel0" type="Label" parent="."]
layout_mode = 0
offset_left = 332.0
offset_top = 99.1
offset_right = 412.0
offset_bottom = 115.1
mouse_filter = 2
theme_override_colors/font_color = Color(0.55, 0.85, 0.3, 1)
theme_override_font_sizes/font_size = 12
text = "Vitality:"

[node name="StatValue0" type="Label" parent="."]
layout_mode = 0
offset_left = 388.0
offset_top = 99.1
offset_right = 468.0
offset_bottom = 115.1
mouse_filter = 2
theme_override_colors/font_color = Color(0.55, 0.85, 0.3, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 2
text = "0"

[node name="StatLabel1" type="Label" parent="."]
layout_mode = 0
offset_left = 332.0
offset_top = 116.6
offset_right = 412.0
offset_bottom = 132.6
mouse_filter = 2
theme_override_colors/font_color = Color(0.9, 0.35, 0.3, 1)
theme_override_font_sizes/font_size = 12
text = "Strength:"

[node name="StatValue1" type="Label" parent="."]
layout_mode = 0
offset_left = 388.0
offset_top = 116.6
offset_right = 468.0
offset_bottom = 132.6
mouse_filter = 2
theme_override_colors/font_color = Color(0.9, 0.35, 0.3, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 2
text = "0"

[node name="StatLabel2" type="Label" parent="."]
layout_mode = 0
offset_left = 332.0
offset_top = 134.7
offset_right = 412.0
offset_bottom = 150.7
mouse_filter = 2
theme_override_colors/font_color = Color(0.95, 0.65, 0.2, 1)
theme_override_font_sizes/font_size = 12
text = "Instinct:"

[node name="StatValue2" type="Label" parent="."]
layout_mode = 0
offset_left = 388.0
offset_top = 134.7
offset_right = 468.0
offset_bottom = 150.7
mouse_filter = 2
theme_override_colors/font_color = Color(0.95, 0.65, 0.2, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 2
text = "0"

[node name="StatLabel3" type="Label" parent="."]
layout_mode = 0
offset_left = 332.0
offset_top = 152.9
offset_right = 412.0
offset_bottom = 168.9
mouse_filter = 2
theme_override_colors/font_color = Color(0.75, 0.55, 0.9, 1)
theme_override_font_sizes/font_size = 12
text = "Speed:"

[node name="StatValue3" type="Label" parent="."]
layout_mode = 0
offset_left = 388.0
offset_top = 152.9
offset_right = 468.0
offset_bottom = 168.9
mouse_filter = 2
theme_override_colors/font_color = Color(0.75, 0.55, 0.9, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 2
text = "0"

[node name="StatLabel4" type="Label" parent="."]
layout_mode = 0
offset_left = 332.0
offset_top = 170.3
offset_right = 412.0
offset_bottom = 186.3
mouse_filter = 2
theme_override_colors/font_color = Color(0.55, 0.65, 0.95, 1)
theme_override_font_sizes/font_size = 12
text = "Focus:"

[node name="StatValue4" type="Label" parent="."]
layout_mode = 0
offset_left = 388.0
offset_top = 170.3
offset_right = 468.0
offset_bottom = 186.3
mouse_filter = 2
theme_override_colors/font_color = Color(0.55, 0.65, 0.95, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 2
text = "0"

[node name="PiercingLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 331.8
offset_top = 198.8
offset_right = 451.8
offset_bottom = 214.8
mouse_filter = 2
theme_override_colors/font_color = Color(0.6, 0.6, 0.6, 1)
theme_override_font_sizes/font_size = 13
text = "Piercing"

[node name="DefenseLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 331.8
offset_top = 305.2
offset_right = 451.8
offset_bottom = 321.2
mouse_filter = 2
theme_override_colors/font_color = Color(0.6, 0.6, 0.6, 1)
theme_override_font_sizes/font_size = 13
text = "Defense"

[connection signal="pressed" from="CloseButton" to="." method="hide"]
```

Notes on values: every `offset_*` is copied verbatim from the constants/rects described in this plan's Architecture section (all traced back to the pre-change `LEFT_PANEL`/`CENTER_PANEL`/
`STAT_ROWS_Y`/`EXP_TRACK`/`EXP_ZERO_BOX`/`EXP_FILL`/`MenuTheme.STAT_LABELS`/`MenuTheme.STAT_COLORS` values). `ExpTrack`/`ExpFill`/`ExpZeroBox` all get a static `texture` assignment here (to
`exp_track.png`/`exp_fill.png`/`exp_zero_box.png` respectively, via the three new `ext_resource`s added above) - only each bar's SIZE/position is recomputed live (the fill's width via `refresh()`
reading `EXP_FILL.size.x`, unchanged); the texture itself never changes at runtime, so it belongs in the scene like every other static texture in this task.
`ExpTrack`/`CenterPanel`/`StatLabel*` etc. `mouse_filter = 2` matches `MenuTheme.add_texture_rect`/`add_label`'s unconditional `Control.MOUSE_FILTER_IGNORE` default; `Backdrop` keeps the one
explicit override to `MOUSE_FILTER_STOP` that the removed code applied right after construction.

- [ ] **Step 3: Rewrite `scripts/ui/menu/inventory_window.gd`'s top section, `_ready()`, `_build_chrome()`, `_build_left_panel()`, and `_build_center_panel()`**

Replace lines 1 through 42 (the header comment through `const EXP_FILL`) with:

```gdscript
# inventory_window.gd
# The player inventory screen, rebuilt from frame 1 of the original menu
# clip (DefineSprite 3142 at stage 400.5, 222.4):
# - left panel: name + level/class, the dressed paper doll with the 7 equip
#   slots around it, and the experience bar
# - center panel: the five stats plus the Piercing/Defense element bars
#   (fill math from the frame-1 DoAction, see MenuTheme.bar_fill_fraction)
# - right: the shared InventoryPanel (6x6 grid + money bar + sell/drop)
# - bottom-left bar: party portrait frames (art from sprite 2979 is a
#   backlog item - frames show names for now)
#
# Click an inventory item to equip it into its natural slot; click an equip
# slot to send the item back to the first free inventory cell.
extends Control

const CLASS_NAMES: Array[String] = ["Biological", "Psychological", "Hydraulic"]

const INVENTORY_AT: Vector2 = Vector2(503.5, 81.6)
# playerSlot0-6 centers from the frame-1 dump.
const EQUIP_SLOT_CENTERS: Dictionary[int, Vector2] = {
	0: Vector2(82.2, 172.2),
	2: Vector2(82.2, 212.2),
	6: Vector2(82.2, 252.2),
	5: Vector2(122.2, 252.2),
	1: Vector2(263.1, 172.2),
	3: Vector2(263.1, 212.2),
	4: Vector2(263.1, 252.2),
}
const DOLL_POSITION: Vector2 = Vector2(192.5, 214.4)
const DOLL_SCALE: float = 1.2
const BAR_BLOCK_CENTERS_Y: Dictionary[Variant, Variant] = {"per": 256.0, "def": 360.5}
const BAR_TRACK_HEIGHT: float = 78.0
# Experience row (texts 2869/2863, shapes 2864/2868, fill sprite 2867) - only
# EXP_FILL survives here: refresh() still reads EXP_FILL.size.x as the full
# width the fraction-scaled fill is computed against.
const EXP_FILL: Rect2 = Rect2(172.6, 283.3, 95.1, 18.7)
# PARTY_BAR still feeds the untouched _build_party_bar() (Task 3 removes it
# once that function is rewritten); BAR_WIDTH/BAR_STEP still feed the
# untouched _build_bar_block() (Task 2 removes them).
const PARTY_BAR: Rect2 = Rect2(47.5, 358.2, 249.1, 50.9)
const BAR_WIDTH: float = 10.0
const BAR_STEP: float = 17.1
```

(`LEFT_PANEL`, `CENTER_PANEL`, `STAT_ROWS_Y`, `EXP_TRACK`, `EXP_ZERO_BOX` are all deleted here - they fed only the now-removed runtime construction. `PARTY_BAR`/`BAR_WIDTH`/`BAR_STEP` MUST STAY
in this task - `_build_bar_block()` and `_build_party_bar()` still read them and are not touched until Tasks 2/3. `PORTRAIT_FILES` also stays for now, Task 3 removes it.)

Then find the `var` declarations block (`var inventory_panel: InventoryPanel` through `var _portrait_frames: Array[ItemSlot] = []`) and replace it with:

```gdscript
var inventory_panel: InventoryPanel
var equip_view: EquipDollView

@onready var _status_label: Label = $StatusLabel
@onready var _name_label: Label = $NameLabel
@onready var _level_label: Label = $LevelLabel
@onready var _exp_fill: TextureRect = $ExpFill
@onready var _exp_percent: Label = $ExpPercent
@onready var _stat_values: Array[Label] = [$StatValue0, $StatValue1, $StatValue2, $StatValue3, $StatValue4]
var _per_fills: Array[ColorRect] = []
var _def_fills: Array[ColorRect] = []
var _portrait_frames: Array[ItemSlot] = []
```

(`_per_fills`/`_def_fills`/`_portrait_frames` stay as plain `var`s populated by Tasks 2/3's remaining code, not `@onready`, since their target nodes don't exist in the scene until those tasks add
them - trying to `@onready` them now would fail at `_ready()` time with a null reference.)

The current file's function order is `_ready()`, `_build_chrome()`, `_build_left_panel()`, `_build_center_panel()`, `_build_bar_block()`, `_build_party_bar()`, `_build_inventory()`, `refresh()`,
and everything after. This step touches four of those by NAME, not by line range - do not delete or reorder `_build_bar_block()`/`_build_party_bar()`, they stay exactly where they are in the file
for Tasks 2/3 to edit (Task 2 rewrites `_build_bar_block()`, Task 3 rewrites `_build_party_bar()`) - leave both completely untouched in this task:

1. Replace `_ready()`'s body with:

```gdscript
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_left_panel()
	_build_center_panel()
	_build_party_bar()
	_build_inventory()
	GameData.inventory_changed.connect(_refresh_if_visible)
	GameData.gold_changed.connect(func(_amount): _refresh_if_visible())
	visibility_changed.connect(func():
		if visible:
			refresh())
```

(`_build_chrome()` is deleted entirely, so its call is gone too; `_build_left_panel()`/`_build_center_panel()`/`_build_party_bar()`/`_build_inventory()` stay called from here, in their original
order - the first two shrink to just their dynamic remainder in the next steps, `_build_party_bar()`/`_build_inventory()` are completely unchanged, out of scope for this task.)

2. Delete `_build_chrome()` entirely (the whole function, start to end) - everything it built is now static in the `.tscn`.

3. Replace `_build_left_panel()` with just its remaining dynamic content:

```gdscript
func _build_left_panel() -> void:
	equip_view = EquipDollView.new()
	equip_view.name = "EquipDollView"
	add_child(equip_view)
	equip_view.setup(EQUIP_SLOT_CENTERS, DOLL_POSITION, DOLL_SCALE)
	equip_view.equip_slot_clicked.connect(_on_equip_slot_clicked)
```

4. Replace `_build_center_panel()` with just its remaining dynamic content:

```gdscript
func _build_center_panel() -> void:
	_per_fills = _build_bar_block(BAR_BLOCK_CENTERS_Y["per"])
	_def_fills = _build_bar_block(BAR_BLOCK_CENTERS_Y["def"])
```

(`_build_bar_block()` itself is Task 2's job to rewrite - for THIS task, leave it completely untouched, still building tracks/fills at runtime exactly as before. This task's `_build_center_panel()`
change only removes the now-static parts - the panel texture, the 5 stat label/value pairs, and the Piercing/Defense titles - while still calling the unchanged `_build_bar_block()` twice, so the
file compiles and the bars still render (via the old code path) until Task 2 replaces that function's body too.)

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/menu/inventory_window.gd --path .`
Expected: only the known autoload false positive, if anything - no other errors.

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Step 1 (this task adds no new tests).

- [ ] **Step 6: Commit**

```bash
git add scenes/ui/menu/inventory_window.tscn scripts/ui/menu/inventory_window.gd
git commit -m "refactor: move InventoryWindow's static chrome and panel content into the scene file"
```

---

### Task 2: Move the 16 element-bar tracks and fills into the scene file

**Files:**
- Modify: `scenes/ui/menu/inventory_window.tscn`
- Modify: `scripts/ui/menu/inventory_window.gd` (`_build_bar_block()`)

**Interfaces:**
- Consumes: `_per_fills`/`_def_fills: Array[ColorRect]` vars from Task 1 (currently populated by calling `_build_bar_block()` twice from `_build_center_panel()` - that call site is untouched by
  this task, only `_build_bar_block()`'s own body changes).
- Produces: nothing new consumed by Task 3 (disjoint: Task 3 only touches `_build_party_bar()`).

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 1's ending count exactly.

- [ ] **Step 2: Add the 16 track and 16 fill nodes to `scenes/ui/menu/inventory_window.tscn`**

Add these 32 `ColorRect` nodes anywhere after the nodes added in Task 1 (order doesn't matter for correctness - they don't overlap any other chrome). Every track uses the same fixed dark color;
every fill uses its column's element color and starts at zero height (both will be resized every `refresh()` call by the unchanged `_update_bar()`):

```
[node name="PerTrack0" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 335.65
offset_top = 217.0
offset_right = 345.65
offset_bottom = 295.0
mouse_filter = 2
color = Color(0.07, 0.07, 0.08, 1)

[node name="PerFill0" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 335.65
offset_top = 295.0
offset_right = 345.65
offset_bottom = 295.0
mouse_filter = 2
color = Color(0.75294119, 0, 0, 1)

[node name="PerTrack1" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 352.75
offset_top = 217.0
offset_right = 362.75
offset_bottom = 295.0
mouse_filter = 2
color = Color(0.07, 0.07, 0.08, 1)

[node name="PerFill1" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 352.75
offset_top = 295.0
offset_right = 362.75
offset_bottom = 295.0
mouse_filter = 2
color = Color(0.98431373, 0.58431375, 0.78431374, 1)

[node name="PerTrack2" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 369.85
offset_top = 217.0
offset_right = 379.85
offset_bottom = 295.0
mouse_filter = 2
color = Color(0.07, 0.07, 0.08, 1)

[node name="PerFill2" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 369.85
offset_top = 295.0
offset_right = 379.85
offset_bottom = 295.0
mouse_filter = 2
color = Color(0.40784314, 0.79607844, 0.95686275, 1)

[node name="PerTrack3" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 386.95
offset_top = 217.0
offset_right = 396.95
offset_bottom = 295.0
mouse_filter = 2
color = Color(0.07, 0.07, 0.08, 1)

[node name="PerFill3" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 386.95
offset_top = 295.0
offset_right = 396.95
offset_bottom = 295.0
mouse_filter = 2
color = Color(1, 0.4, 0, 1)

[node name="PerTrack4" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 404.05
offset_top = 217.0
offset_right = 414.05
offset_bottom = 295.0
mouse_filter = 2
color = Color(0.07, 0.07, 0.08, 1)

[node name="PerFill4" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 404.05
offset_top = 295.0
offset_right = 414.05
offset_bottom = 295.0
mouse_filter = 2
color = Color(1, 0.8, 0, 1)

[node name="PerTrack5" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 421.15
offset_top = 217.0
offset_right = 431.15
offset_bottom = 295.0
mouse_filter = 2
color = Color(0.07, 0.07, 0.08, 1)

[node name="PerFill5" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 421.15
offset_top = 295.0
offset_right = 431.15
offset_bottom = 295.0
mouse_filter = 2
color = Color(0.52156866, 0.41960785, 0.2784314, 1)

[node name="PerTrack6" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 438.25
offset_top = 217.0
offset_right = 448.25
offset_bottom = 295.0
mouse_filter = 2
color = Color(0.07, 0.07, 0.08, 1)

[node name="PerFill6" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 438.25
offset_top = 295.0
offset_right = 448.25
offset_bottom = 295.0
mouse_filter = 2
color = Color(0.4, 0.3019608, 0.5019608, 1)

[node name="PerTrack7" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 455.35
offset_top = 217.0
offset_right = 465.35
offset_bottom = 295.0
mouse_filter = 2
color = Color(0.07, 0.07, 0.08, 1)

[node name="PerFill7" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 455.35
offset_top = 295.0
offset_right = 465.35
offset_bottom = 295.0
mouse_filter = 2
color = Color(0.31372550, 0.5137255, 0.28627452, 1)

[node name="DefTrack0" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 335.65
offset_top = 321.5
offset_right = 345.65
offset_bottom = 399.5
mouse_filter = 2
color = Color(0.07, 0.07, 0.08, 1)

[node name="DefFill0" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 335.65
offset_top = 399.5
offset_right = 345.65
offset_bottom = 399.5
mouse_filter = 2
color = Color(0.75294119, 0, 0, 1)

[node name="DefTrack1" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 352.75
offset_top = 321.5
offset_right = 362.75
offset_bottom = 399.5
mouse_filter = 2
color = Color(0.07, 0.07, 0.08, 1)

[node name="DefFill1" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 352.75
offset_top = 399.5
offset_right = 362.75
offset_bottom = 399.5
mouse_filter = 2
color = Color(0.98431373, 0.58431375, 0.78431374, 1)

[node name="DefTrack2" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 369.85
offset_top = 321.5
offset_right = 379.85
offset_bottom = 399.5
mouse_filter = 2
color = Color(0.07, 0.07, 0.08, 1)

[node name="DefFill2" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 369.85
offset_top = 399.5
offset_right = 379.85
offset_bottom = 399.5
mouse_filter = 2
color = Color(0.40784314, 0.79607844, 0.95686275, 1)

[node name="DefTrack3" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 386.95
offset_top = 321.5
offset_right = 396.95
offset_bottom = 399.5
mouse_filter = 2
color = Color(0.07, 0.07, 0.08, 1)

[node name="DefFill3" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 386.95
offset_top = 399.5
offset_right = 396.95
offset_bottom = 399.5
mouse_filter = 2
color = Color(1, 0.4, 0, 1)

[node name="DefTrack4" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 404.05
offset_top = 321.5
offset_right = 414.05
offset_bottom = 399.5
mouse_filter = 2
color = Color(0.07, 0.07, 0.08, 1)

[node name="DefFill4" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 404.05
offset_top = 399.5
offset_right = 414.05
offset_bottom = 399.5
mouse_filter = 2
color = Color(1, 0.8, 0, 1)

[node name="DefTrack5" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 421.15
offset_top = 321.5
offset_right = 431.15
offset_bottom = 399.5
mouse_filter = 2
color = Color(0.07, 0.07, 0.08, 1)

[node name="DefFill5" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 421.15
offset_top = 399.5
offset_right = 431.15
offset_bottom = 399.5
mouse_filter = 2
color = Color(0.52156866, 0.41960785, 0.2784314, 1)

[node name="DefTrack6" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 438.25
offset_top = 321.5
offset_right = 448.25
offset_bottom = 399.5
mouse_filter = 2
color = Color(0.07, 0.07, 0.08, 1)

[node name="DefFill6" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 438.25
offset_top = 399.5
offset_right = 448.25
offset_bottom = 399.5
mouse_filter = 2
color = Color(0.4, 0.3019608, 0.5019608, 1)

[node name="DefTrack7" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 455.35
offset_top = 321.5
offset_right = 465.35
offset_bottom = 399.5
mouse_filter = 2
color = Color(0.07, 0.07, 0.08, 1)

[node name="DefFill7" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 455.35
offset_top = 399.5
offset_right = 465.35
offset_bottom = 399.5
mouse_filter = 2
color = Color(0.31372550, 0.5137255, 0.28627452, 1)
```

Notes on values: `x(k) = 400.5 + (k-3.5)*17.1 - 5` for `k=0..7` gives `[335.65, 352.75, 369.85, 386.95, 404.05, 421.15, 438.25, 455.35]` - the SAME 8 x-positions for both the "per" and "def"
blocks. "per" block: `top = 256.0 - 39.0 = 217.0`, bottom edge `217.0 + 78.0 = 295.0`. "def" block: `top = 360.5 - 39.0 = 321.5`, bottom edge `321.5 + 78.0 = 399.5`. Each track is `217.0`/`321.5` to
`295.0`/`399.5` (78px tall, matching `BAR_TRACK_HEIGHT`). Each fill starts collapsed at its block's bottom edge (`offset_top == offset_bottom`, zero height) - `_update_bar()` (unchanged, still in
the script) grows it upward from there every `refresh()`. Fill colors are `MenuTheme.ELEMENT_COLORS[k]` converted from hex to Godot `Color` float components (`Color("C40000")` -> `Color(0.75294119,
0, 0, 1)`, etc., k=0..7 = Physical/Magic/Ice/Fire/Lightning/Earth/Shadow/Poison) - identical for both blocks at the same `k`. No `tooltip_text` is set on any fill - `_update_bar()` always
overwrites it with the live numeric value before the bars are ever shown, so a static placeholder here would never be visible and isn't worth adding.

- [ ] **Step 3: Rewrite `_build_bar_block()` in `scripts/ui/menu/inventory_window.gd`**

Replace the full function with:

```gdscript
# One block of 8 element bars (called once for "per", once for "def" - see
# _build_center_panel()) - fetches the pre-built track/fill pairs for that
# block instead of constructing them; fill heights/positions are set every
# refresh() by _update_bar(), unchanged below.
func _build_bar_block(center_y: float) -> Array[ColorRect]:
	var prefix: String = "Per" if center_y == BAR_BLOCK_CENTERS_Y["per"] else "Def"
	var fills: Array[ColorRect] = []
	for k in 8:
		fills.append(get_node("%sFill%d" % [prefix, k]))
	return fills
```

Leave `_update_bar()` (the function right after `_build_bar_block()`) completely untouched - it still reads `BAR_BLOCK_CENTERS_Y`/`BAR_TRACK_HEIGHT` and sets `fill.size.y`/`fill.position.y`/
`fill.tooltip_text` exactly as before.

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/menu/inventory_window.gd --path .`
Expected: only the known autoload false positive.

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Task 1's ending count.

- [ ] **Step 6: Commit**

```bash
git add scenes/ui/menu/inventory_window.tscn scripts/ui/menu/inventory_window.gd
git commit -m "refactor: move InventoryWindow's element-bar tracks and fills into the scene file"
```

---

### Task 3: Move the party bar chrome and 6 portrait frames into the scene file

**Files:**
- Modify: `scenes/ui/menu/inventory_window.tscn`
- Modify: `scripts/ui/menu/inventory_window.gd` (`_build_party_bar()`, top-of-file constants)

**Interfaces:**
- Consumes: nothing from Task 2 (disjoint region of the same two files).
- Produces: nothing new consumed later - Task 4 is verification only.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 2's ending count exactly.

- [ ] **Step 2: Add the party bar texture and 6 portrait frames to `scenes/ui/menu/inventory_window.tscn`**

Add one new `ext_resource` for `panel_bar.png` and one for `item_slot.tscn` (the reusable slot scene from an earlier increment), plus 6 for the portrait images, then the party bar background and
6 `ItemSlot` instances each with a `Face` child:

```
[ext_resource type="Texture2D" path="res://assets/ui/menu/panel_bar.png" id="6_partybar"]
[ext_resource type="PackedScene" path="res://scenes/ui/item_slot.tscn" id="7_itemslot"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/portraits/sonny.png" id="8_sonny"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/portraits/veradux.png" id="9_veradux"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/portraits/roald.png" id="10_roald"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/portraits/felicity.png" id="11_felicity"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/portraits/wolfgang.png" id="12_wolfgang"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/portraits/amber.png" id="13_amber"]

[node name="PartyBar" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 47.5
offset_top = 358.2
offset_right = 296.6
offset_bottom = 409.1
mouse_filter = 2
texture = ExtResource("6_partybar")
expand_mode = 1
stretch_mode = 0

[node name="Portrait0" parent="." instance=ExtResource("7_itemslot")]
offset_left = 56.7
offset_top = 369.4
offset_right = 87.7
offset_bottom = 400.4

[node name="Face" type="TextureRect" parent="Portrait0"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 2.0
offset_top = 2.0
offset_right = -2.0
offset_bottom = -2.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("8_sonny")
expand_mode = 1
stretch_mode = 5

[node name="Portrait1" parent="." instance=ExtResource("7_itemslot")]
offset_left = 96.7
offset_top = 369.4
offset_right = 127.7
offset_bottom = 400.4

[node name="Face" type="TextureRect" parent="Portrait1"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 2.0
offset_top = 2.0
offset_right = -2.0
offset_bottom = -2.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("9_veradux")
expand_mode = 1
stretch_mode = 5

[node name="Portrait2" parent="." instance=ExtResource("7_itemslot")]
offset_left = 136.7
offset_top = 369.4
offset_right = 167.7
offset_bottom = 400.4

[node name="Face" type="TextureRect" parent="Portrait2"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 2.0
offset_top = 2.0
offset_right = -2.0
offset_bottom = -2.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("10_roald")
expand_mode = 1
stretch_mode = 5

[node name="Portrait3" parent="." instance=ExtResource("7_itemslot")]
offset_left = 176.7
offset_top = 369.4
offset_right = 207.7
offset_bottom = 400.4

[node name="Face" type="TextureRect" parent="Portrait3"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 2.0
offset_top = 2.0
offset_right = -2.0
offset_bottom = -2.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("11_felicity")
expand_mode = 1
stretch_mode = 5

[node name="Portrait4" parent="." instance=ExtResource("7_itemslot")]
offset_left = 216.7
offset_top = 369.4
offset_right = 247.7
offset_bottom = 400.4

[node name="Face" type="TextureRect" parent="Portrait4"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 2.0
offset_top = 2.0
offset_right = -2.0
offset_bottom = -2.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("12_wolfgang")
expand_mode = 1
stretch_mode = 5

[node name="Portrait5" parent="." instance=ExtResource("7_itemslot")]
offset_left = 256.7
offset_top = 369.4
offset_right = 287.7
offset_bottom = 400.4

[node name="Face" type="TextureRect" parent="Portrait5"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 2.0
offset_top = 2.0
offset_right = -2.0
offset_bottom = -2.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("13_amber")
expand_mode = 1
stretch_mode = 5
```

Notes on values: `PARTY_BAR = Rect2(47.5, 358.2, 249.1, 50.9)` -> `offset_right = 47.5+249.1 = 296.6`, `offset_bottom = 358.2+50.9 = 409.1`. Each `PortraitN`'s position is `Vector2(72.2 + 40.0*i,
384.9) - SLOT_SIZE/2` where `SLOT_SIZE = Vector2(31, 31)` (`MenuTheme.SLOT_SIZE`), i.e. `Vector2(56.7 + 40.0*i, 369.4)` for `i=0..5` giving x = `56.7, 96.7, 136.7, 176.7, 216.7, 256.7` - each 31x31
(`offset_right`/`offset_bottom` = position + 31). `Portrait0`..`Portrait5` are INSTANCES of `item_slot.tscn` (not new `Button`/`TextureRect` nodes) - when instancing a scene inside another scene
file, only the OVERRIDDEN properties (here just the position/size offsets) need to be listed under the `[node ... instance=ExtResource(...)]` line; everything else comes from `item_slot.tscn`
itself, unchanged. Each portrait's `Face` child is additional content specific to THIS scene, added on top of the instanced `ItemSlot` (which already has its own `ItemIcon`/`Highlight` children
from `item_slot.tscn` - `Face` is a third, sibling child here, layered visually on top since it's added last). `Face`'s local anchors/offsets reproduce the original code's
`set_anchors_preset(Control.PRESET_FULL_RECT); offset_left = 2; offset_top = 2; offset_right = -2; offset_bottom = -2` exactly.

- [ ] **Step 3: Rewrite `_build_party_bar()` and remove `PORTRAIT_FILES` in `scripts/ui/menu/inventory_window.gd`**

Delete the `const PORTRAIT_FILES: Dictionary[Variant, Variant] = {...}` block (right before `_build_party_bar()`) entirely - its 6 texture paths are now baked directly into the `Face` children in
the `.tscn`, nothing in code reads this dictionary anymore.

Replace `_build_party_bar()` with:

```gdscript
func _build_party_bar() -> void:
	_portrait_frames = [$Portrait0, $Portrait1, $Portrait2, $Portrait3, $Portrait4, $Portrait5]
```

Leave `_refresh_portraits()` (the function after `refresh()`) completely untouched - it still sets `.tooltip_text`/`.modulate` on each frame exactly as before.

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/menu/inventory_window.gd --path .`
Expected: only the known autoload false positive.

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Task 2's ending count.

- [ ] **Step 6: Commit**

```bash
git add scenes/ui/menu/inventory_window.tscn scripts/ui/menu/inventory_window.gd
git commit -m "refactor: move InventoryWindow's party bar and portrait frames into the scene file"
```

---

### Task 4: Final verification pass

**Files:** none changed - this task is verification only.

**Interfaces:** none new.

- [ ] **Step 1: Full regression run**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, every test green, matching Task 1's noted baseline exactly (no new failures, no new tests - this whole plan is a pure refactor).

- [ ] **Step 2: Manual visual check**

Launch the game (or render `scenes/ui/menu/inventory_window.tscn` headlessly to a screenshot with a save loaded) and confirm by eye: backdrop/close/status/left panel/center panel are positioned
identically to before, the name/level/experience row and all 5 stat rows show correct live values, both 8-bar element blocks (Piercing/Defense) grow from the correct baseline with the correct
per-element colors, and all 6 portrait frames show their correct fixed art with correct live tooltip/dimming based on the roster.

- [ ] **Step 3: Update `NEXT_PHASES.md`**

`inventory_window.gd` is the first of three `MenuTheme`-helper callers being migrated - do NOT mark the "UI architecture" phase's `menu_theme.gd` item done yet (`main_menu.gd` and
`victory_screen.gd` still call `add_texture_rect`/`add_label`). Instead, add a new bullet under the same "UI architecture: native Godot Containers instead of code-built controls" section noting
progress, e.g.:

```markdown
**In progress (2026-07-23) - retiring `MenuTheme`'s runtime helpers:** `add_texture_rect`/`add_label` (`menu_theme.gd`) exist only because their remaining callers still build Controls at runtime;
`scripts/ui/menu/inventory_window.gd` is now migrated (`inventory_window.tscn` owns its static chrome, 16 element-bar tracks/fills, and 6 fixed portrait frames - only the bars' fill
height/position and the portraits' tooltip/dimming stay code-driven, both genuinely live-save-dependent). `scripts/ui/main_menu.gd` and `scripts/battle/victory_screen.gd` (the latter has no
`.tscn` yet at all - it's instantiated straight from the script) still call these helpers and are separate follow-up plans; once both are migrated, `add_texture_rect`/`add_label` can be deleted
from `menu_theme.gd` entirely.
```

- [ ] **Step 4: Commit**

```bash
git add NEXT_PHASES.md
git commit -m "docs: note InventoryWindow's progress retiring MenuTheme's runtime helpers"
```
