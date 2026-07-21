# Abilities Window: Native Godot Containers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `scripts/ui/menu/abilities_window.gd` + `scenes/ui/menu/abilities_window.tscn` off imperative runtime Control-building, as the third increment of the "UI architecture: native Godot Containers instead of code-built controls" phase in `NEXT_PHASES.md` (`item_slot.gd`/`store_window.gd`/`inventory_panel.gd` are already done - see `docs/superpowers/plans/2026-07-21-store-ui-containers.md` and `docs/superpowers/plans/2026-07-21-inventory-panel-containers.md` for the established conventions this plan follows).

**Architecture:** Unlike the prior two increments, this screen has THREE different kinds of content, each converted differently:
1. **Genuinely static chrome** (backdrop, close button, panel textures, title labels, the attribute rows) - converts directly into the `.tscn`, exactly like before.
2. **The 28-node talent tree.** Node positions sit on an IRREGULAR pitch (`TREE_COLUMNS_X`/`TREE_ROWS_Y` are hand-tuned per-column/per-row offset arrays, not a uniform grid) - a `GridContainer` cannot express this, so positions stay a code-computed formula. Each node's VISUAL STYLE is data-dependent (recomputed every `refresh()` from the player's live talent progress - color-coded by element, filled/hollow by rank) so the styling call stays in code too. What DOES move: the repeated node's STRUCTURE (a circular button + a rank-count label sitting on it) becomes a small reusable `talent_node.tscn`, instanced 28 times via `PackedScene` - the exact same pattern `ItemSlot` already established - with only position-assignment and per-instance signal-binding remaining in the loop.
3. **The 8-socket wheel** is ALSO irregularly spaced and ALSO fully data-dependent in styling, but unlike the tree it has no reusable child structure at all (a bare `Button`, no label overlay) - there is no static content to extract, so it is a deliberate, documented exception that stays exactly as it is today.
4. **The 5-row ability pool list**, by contrast, IS on a uniform pitch (`POOL_ROW_HEIGHT` constant spacing) and its row style never varies with data (only `.text`/`.visible` change) - a genuine `VBoxContainer` + shared static `StyleBoxFlat` conversion, matching the sell/delete button precedent from the store increment.

**Tech Stack:** Godot 4.7, GDScript, GUT 9.6.1 (headless test runner vendored at `addons/gut/`).

## Global Constraints

- `AbilitiesWindow`'s tests must keep passing unchanged: `test/integration/test_ui_scenes.gd`'s `test_abilities_window_edits_action_bar` calls `window.refresh()`, reads `window._pool_move_ids`, calls `window._on_socket_pressed(0)` and `window._on_pool_row_pressed(0)` directly - these method names/signatures and the `_pool_move_ids` field must not change. `test_hotbar_menu_toggle_is_exclusive_and_glows` only checks `.visible` via the parent scene - unaffected by anything in this plan.
- This is a pure refactor (behavior-preserving) except for the deliberate structural change described above (raw `Button.new()` tree nodes become `talent_node.tscn` instances) - no new functionality, no behavior change to what's rendered or how clicks resolve.
- All 3 player classes have exactly 28 talent-tree nodes each (verified: `TalentTree.TREES[0]`, `[1]`, `[2]` all have 28 entries) - the 4-column x 7-row layout is invariant across classes, so baking the loop count/positions as compile-time constants (as the code already does via `TREE_COLUMNS_X`/`TREE_ROWS_Y`) is safe.
- Godot enum literals used below: `TextureRect.EXPAND_IGNORE_SIZE = 1`, `TextureRect.STRETCH_SCALE = 0`, `Control.MOUSE_FILTER_IGNORE = 2`, `HORIZONTAL_ALIGNMENT_LEFT = 0`, `HORIZONTAL_ALIGNMENT_CENTER = 1`, `HORIZONTAL_ALIGNMENT_RIGHT = 2`.
- `Color.lightened(amount)` is `channel + (1.0 - channel) * amount` per R/G/B channel (alpha unchanged) - used below to bake pre-computed hover colors for the 4 static attribute "+" buttons, since their color never changes at runtime (unlike the tree/wheel, whose colors are genuinely dynamic and must stay code-computed).
- Compile-check after every `.gd` edit: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s <script.gd> --path .` (expect a `GameData`/other-autoload "Identifier not found" line - known false positive, not a real error).
- Run the full suite after every task: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`. Confirm the actual baseline count live in whatever worktree this executes in before starting - do not trust a hardcoded number in this document.
- This is a pure refactor - no new failing test to write. Confirm the existing tests are GREEN before touching a file, make the declarative change, confirm they are GREEN again after.

---

### Task 1: Move the static chrome and attribute panel into the scene file

**Files:**
- Modify: `scenes/ui/menu/abilities_window.tscn`
- Modify: `scripts/ui/menu/abilities_window.gd`

**Interfaces:**
- Consumes: nothing external.
- Produces: `_status_label`, `_name_label`, `_level_label`, `_ability_points_value`, `_attribute_points_value`, `_attribute_values` (`Array[Label]`, still populated in `_ready()` but now via `@onready $Path` lookups instead of `MenuTheme.add_label()` calls) - Tasks 2/3 don't depend on any of these, they touch disjoint parts of the same two files.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gtest=test/integration/test_ui_scenes.gd`
Expected: PASS, all tests in that file. Also run without the filter for the full-suite count and note it - you'll compare against this exact number after every task in this plan.

- [ ] **Step 2: Add the static nodes to `scenes/ui/menu/abilities_window.tscn`**

Read the current file first (currently just an empty `AbilitiesWindow` root `Control` + script, `groups=["abilities_window", "menu_screen"]`, full-rect anchors). Add the following nodes as children of the root (keep the existing `[gd_scene]`/root node lines, just add ext_resources, sub_resources, child nodes, and connections - bump `load_steps` to account for the new resources: 1 script + 4 textures + 8 StyleBoxFlat sub-resources for the four "+" buttons = 13, so `load_steps=13`):

```
[ext_resource type="Texture2D" path="res://assets/ui/menu/menu_backdrop.png" id="2_backdrop"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/close_x.png" id="3_close"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/panel_large.png" id="4_panellarge"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/panel_center.png" id="5_panelcenter"]

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_vitality"]
bg_color = Color(0.55, 0.85, 0.3, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_vitality_hover"]
bg_color = Color(0.6625, 0.8875, 0.475, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_strength"]
bg_color = Color(0.9, 0.35, 0.3, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_strength_hover"]
bg_color = Color(0.925, 0.5125, 0.475, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_instinct"]
bg_color = Color(0.95, 0.65, 0.2, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_instinct_hover"]
bg_color = Color(0.9625, 0.7375, 0.4, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_speed"]
bg_color = Color(0.75, 0.55, 0.9, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_speed_hover"]
bg_color = Color(0.8125, 0.6625, 0.925, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

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
offset_left = 44.9
offset_top = 414.0
offset_right = 744.9
offset_bottom = 434.0
mouse_filter = 2
theme_override_colors/font_color = Color(1, 0.85, 0.3, 1)
theme_override_font_sizes/font_size = 12

[node name="TreeTitle" type="Label" parent="."]
layout_mode = 0
offset_left = 53.6
offset_top = 80.1
offset_right = 285.4
offset_bottom = 102.1
mouse_filter = 2
theme_override_colors/font_color = Color(0.55, 0.55, 0.55, 1)
theme_override_font_sizes/font_size = 15
horizontal_alignment = 1
text = "Ability Tree"

[node name="LeftPanel" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 44.9
offset_top = 112.9
offset_right = 294.0
offset_bottom = 380.0
mouse_filter = 2
texture = ExtResource("4_panellarge")
expand_mode = 1
stretch_mode = 0

[node name="MiddleTopPanel" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 308.6
offset_top = 74.0
offset_right = 491.7
offset_bottom = 312.0
mouse_filter = 2
texture = ExtResource("5_panelcenter")
expand_mode = 1
stretch_mode = 0

[node name="NameLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 308.6
offset_top = 79.7
offset_right = 491.7
offset_bottom = 101.7
mouse_filter = 2
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_font_sizes/font_size = 16
horizontal_alignment = 1

[node name="LevelLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 308.6
offset_top = 99.5
offset_right = 491.7
offset_bottom = 117.5
mouse_filter = 2
theme_override_colors/font_color = Color(0.8, 0.8, 0.8, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 1

[node name="AbilityPointsLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 314.3
offset_top = 122.2
offset_right = 424.3
offset_bottom = 138.2
mouse_filter = 2
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_font_sizes/font_size = 12
text = "Ability Points:"

[node name="AbilityPointsValue" type="Label" parent="."]
layout_mode = 0
offset_left = 400.0
offset_top = 122.2
offset_right = 483.0
offset_bottom = 138.2
mouse_filter = 2
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 2
text = "0"

[node name="AttributePointsLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 314.3
offset_top = 141.2
offset_right = 424.3
offset_bottom = 157.2
mouse_filter = 2
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_font_sizes/font_size = 12
text = "Attribute Points:"

[node name="AttributePointsValue" type="Label" parent="."]
layout_mode = 0
offset_left = 400.0
offset_top = 141.2
offset_right = 483.0
offset_bottom = 157.2
mouse_filter = 2
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 2
text = "0"

[node name="MiddleBottomPanel" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 308.6
offset_top = 322.0
offset_right = 491.7
offset_bottom = 430.0
mouse_filter = 2
texture = ExtResource("5_panelcenter")
expand_mode = 1
stretch_mode = 0

[node name="AttributesTitle" type="Label" parent="."]
layout_mode = 0
offset_left = 308.6
offset_top = 324.0
offset_right = 491.7
offset_bottom = 340.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.55, 0.55, 0.55, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 1
text = "Your Attributes"

[node name="VitalityPlus" type="Button" parent="."]
layout_mode = 0
offset_left = 318.0
offset_top = 341.4
offset_right = 344.0
offset_bottom = 355.4
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0, 0, 0, 1)
theme_override_styles/normal = SubResource("StyleBoxFlat_vitality")
theme_override_styles/hover = SubResource("StyleBoxFlat_vitality_hover")
text = "+"

[node name="VitalityLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 352.0
offset_top = 340.4
offset_right = 432.0
offset_bottom = 356.4
mouse_filter = 2
theme_override_colors/font_color = Color(0.55, 0.85, 0.3, 1)
theme_override_font_sizes/font_size = 12
text = "Vitality:"

[node name="VitalityValue" type="Label" parent="."]
layout_mode = 0
offset_left = 400.0
offset_top = 340.4
offset_right = 480.0
offset_bottom = 356.4
mouse_filter = 2
theme_override_colors/font_color = Color(0.55, 0.85, 0.3, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 2
text = "0"

[node name="StrengthPlus" type="Button" parent="."]
layout_mode = 0
offset_left = 318.0
offset_top = 358.9
offset_right = 344.0
offset_bottom = 372.9
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0, 0, 0, 1)
theme_override_styles/normal = SubResource("StyleBoxFlat_strength")
theme_override_styles/hover = SubResource("StyleBoxFlat_strength_hover")
text = "+"

[node name="StrengthLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 352.0
offset_top = 357.9
offset_right = 432.0
offset_bottom = 373.9
mouse_filter = 2
theme_override_colors/font_color = Color(0.9, 0.35, 0.3, 1)
theme_override_font_sizes/font_size = 12
text = "Strength:"

[node name="StrengthValue" type="Label" parent="."]
layout_mode = 0
offset_left = 400.0
offset_top = 357.9
offset_right = 480.0
offset_bottom = 373.9
mouse_filter = 2
theme_override_colors/font_color = Color(0.9, 0.35, 0.3, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 2
text = "0"

[node name="InstinctPlus" type="Button" parent="."]
layout_mode = 0
offset_left = 318.0
offset_top = 377.1
offset_right = 344.0
offset_bottom = 391.1
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0, 0, 0, 1)
theme_override_styles/normal = SubResource("StyleBoxFlat_instinct")
theme_override_styles/hover = SubResource("StyleBoxFlat_instinct_hover")
text = "+"

[node name="InstinctLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 352.0
offset_top = 376.1
offset_right = 432.0
offset_bottom = 392.1
mouse_filter = 2
theme_override_colors/font_color = Color(0.95, 0.65, 0.2, 1)
theme_override_font_sizes/font_size = 12
text = "Instinct:"

[node name="InstinctValue" type="Label" parent="."]
layout_mode = 0
offset_left = 400.0
offset_top = 376.1
offset_right = 480.0
offset_bottom = 392.1
mouse_filter = 2
theme_override_colors/font_color = Color(0.95, 0.65, 0.2, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 2
text = "0"

[node name="SpeedPlus" type="Button" parent="."]
layout_mode = 0
offset_left = 318.0
offset_top = 395.2
offset_right = 344.0
offset_bottom = 409.2
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0, 0, 0, 1)
theme_override_styles/normal = SubResource("StyleBoxFlat_speed")
theme_override_styles/hover = SubResource("StyleBoxFlat_speed_hover")
text = "+"

[node name="SpeedLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 352.0
offset_top = 394.2
offset_right = 432.0
offset_bottom = 410.2
mouse_filter = 2
theme_override_colors/font_color = Color(0.75, 0.55, 0.9, 1)
theme_override_font_sizes/font_size = 12
text = "Speed:"

[node name="SpeedValue" type="Label" parent="."]
layout_mode = 0
offset_left = 400.0
offset_top = 394.2
offset_right = 480.0
offset_bottom = 410.2
mouse_filter = 2
theme_override_colors/font_color = Color(0.75, 0.55, 0.9, 1)
theme_override_font_sizes/font_size = 12
horizontal_alignment = 2
text = "0"

[node name="RightPanel" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 506.3
offset_top = 112.9
offset_right = 755.4
offset_bottom = 380.0
mouse_filter = 2
texture = ExtResource("4_panellarge")
expand_mode = 1
stretch_mode = 0

[node name="ActionBarTitle" type="Label" parent="."]
layout_mode = 0
offset_left = 516.3
offset_top = 80.1
offset_right = 748.1
offset_bottom = 102.1
mouse_filter = 2
theme_override_colors/font_color = Color(0.55, 0.55, 0.55, 1)
theme_override_font_sizes/font_size = 15
horizontal_alignment = 1
text = "Combat Action Bar"

[node name="PoolTitle" type="Label" parent="."]
layout_mode = 0
offset_left = 516.3
offset_top = 250.1
offset_right = 748.1
offset_bottom = 270.1
mouse_filter = 2
theme_override_colors/font_color = Color(0.55, 0.55, 0.55, 1)
theme_override_font_sizes/font_size = 14
horizontal_alignment = 1
text = "Ability Pool"

[connection signal="pressed" from="CloseButton" to="." method="hide"]
[connection signal="pressed" from="VitalityPlus" to="." method="_on_attribute_plus_pressed" binds=[0]]
[connection signal="pressed" from="StrengthPlus" to="." method="_on_attribute_plus_pressed" binds=[1]]
[connection signal="pressed" from="InstinctPlus" to="." method="_on_attribute_plus_pressed" binds=[2]]
[connection signal="pressed" from="SpeedPlus" to="." method="_on_attribute_plus_pressed" binds=[3]]
```

Notes on values: every `offset_*` comes verbatim from the current `abilities_window.gd`'s `Rect2`/`Vector2` constants (`MenuTheme.BACKDROP_RECT`/`CLOSE_RECT` for `Backdrop`/`CloseButton`, `LEFT_PANEL`/`RIGHT_PANEL`/`MIDDLE_TOP_PANEL`/`MIDDLE_BOTTOM_PANEL`, `ATTRIBUTE_ROWS_Y` for the four rows). The `_hover` StyleBoxFlat colors are `Color.lightened(0.25)` of each base `STAT_COLORS` entry, computed exactly (`channel + (1-channel)*0.25`) since this color pair never changes at runtime - baking it removes the need to call `.lightened()` in code at all. `binds=[0..3]` on the four "+" buttons map directly to `Leveling.Stat.LIFE=0`/`STRENGTH=1`/`MAGIC=2`/`SPEED=3` (confirmed via `scripts/entities/leveling.gd`'s `enum Stat`), matching `ATTRIBUTE_ROWS`' existing row order (Vitality/Strength/Instinct/Speed).

- [ ] **Step 3: Rewrite `scripts/ui/menu/abilities_window.gd`'s top section, `_ready()`, `_build_chrome()`, and `_build_middle()`**

Replace lines 1 through 24 (the header comment through `const CLASS_NAMES`) with:

```gdscript
# abilities_window.gd
# The abilities screen, rebuilt from frame 25 of the original menu clip
# (DefineSprite 3142 at stage 400.5, 222.4):
# - left: the class ability tree ('talenttreefull' sprite 3100 - 28 nodes,
#   4 columns x 7 rows on a 52 x 40 pitch at stage 45.4, 74.2), learn with
#   a click (TalentTree.learn rules: prerequisites, level tiers, 1 point)
# - middle: name/level, Ability Points (skill points) and Attribute Points
#   (stat points), plus the four attribute rows with '+' spend buttons
#   (frame-25 buttons 3068/3071/3070/3069 - no Focus row in the original)
# - right: the Combat Action Bar wheel ('selector' sprite 3109 - 8 sockets
#   on a 49.5 px ring at stage 630.6, 172.2) and the Ability Pool list
#   ('talentPool' sprite 3120 at stage 523.6, 274.2)
#
# Click a pool ability to place it in the first free socket; click a socket
# to send its ability back to the pool.
extends Control

const TREE_ORIGIN = Vector2(45.4, 74.2)
const TREE_COLUMNS_X = [41.4, 93.4, 145.4, 197.4]
const TREE_ROWS_Y = [49.9, 89.8, 129.8, 169.8, 209.8, 249.8, 289.9]
const NODE_SIZE = Vector2(32, 32)

const WHEEL_CENTER = Vector2(630.6, 172.2)
# thing0-7 offsets inside the 'selector' clip.
const WHEEL_OFFSETS = [
	Vector2(0.0, -49.2), Vector2(34.8, -34.9), Vector2(49.5, 0.0),
	Vector2(35.0, 35.3), Vector2(0.0, 49.8), Vector2(-35.2, 35.1),
	Vector2(-49.5, 0.0), Vector2(-35.0, -34.7),
]
const SOCKET_SIZE = Vector2(30, 30)

const POOL_RECT = Rect2(523.6, 274.2, 214.0, 128.0)
const POOL_VISIBLE_ROWS = 5
const POOL_ROW_HEIGHT = 25.0

const CLASS_NAMES = ["Biological", "Psychological", "Hydraulic"]
```

(`ATTRIBUTE_ROWS`, `ATTRIBUTE_ROWS_Y`, `LEFT_PANEL`, `RIGHT_PANEL`, `MIDDLE_TOP_PANEL`, `MIDDLE_BOTTOM_PANEL` are deleted here - they fed only the now-removed runtime construction. `POOL_ROW_HEIGHT` is KEPT (not deleted) even though this task doesn't touch anything that displays it: `_build_wheel_panel()`'s pool-row-instancing loop still reads it and is left completely untouched until Task 3 deletes that loop - removing the constant now would break compilation of code this task isn't supposed to modify yet. Do NOT add a `TalentNodeScene` preload constant in this task either - `scenes/ui/menu/talent_node.tscn` doesn't exist until Task 2 creates it; that const is added there, not here.)

Then find the `var` declarations block (`var _tree_buttons: Array[Button] = []` through `var _status_label: Label`) and replace it with:

```gdscript
var _tree_buttons: Array[Button] = []
var _tree_rank_labels: Array[Label] = []
var _tree_lines: Control
var _socket_buttons: Array[Button] = []
var _pool_rows: Array[Button] = []
var _pool_scroll: int = 0
var _pool_move_ids: Array = []

@onready var _name_label: Label = $NameLabel
@onready var _level_label: Label = $LevelLabel
@onready var _ability_points_value: Label = $AbilityPointsValue
@onready var _attribute_points_value: Label = $AttributePointsValue
@onready var _attribute_values: Array[Label] = [$VitalityValue, $StrengthValue, $InstinctValue, $SpeedValue]
```

(`_status_label` is dropped from this block - Task 3 doesn't need it moved yet, but since `_build_chrome()` is being deleted in this step, add `@onready var _status_label: Label = $StatusLabel` here too, right after `_attribute_values`.)

The current file's function order is `_ready()`, `_build_chrome()`, `_build_tree_panel()`, `_build_middle()`, `_build_wheel_panel()`, `_make_scroll_button()`, `_style_circle_button()`, then `refresh()` and everything after. This step touches three of those by NAME, not by line range - do not delete or reorder `_build_tree_panel()` or `_build_wheel_panel()`, they stay exactly where they are in the file (both get edited by name in Step 4 below, and again in Tasks 2/3):

1. Replace `_ready()`'s body with:

```gdscript
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_tree_panel()
	_build_wheel_panel()
	visibility_changed.connect(func():
		if visible:
			refresh())
```

2. Delete `_build_chrome()` entirely (the whole function, start to end) - everything it built is now static in the `.tscn`.

3. Delete `_build_middle()` entirely (the whole function, start to end) - same reason. `_build_tree_panel()` sits between `_build_chrome()` and `_build_middle()` in the file and `_build_wheel_panel()` sits right after `_build_middle()` - leave both of those two functions in place untouched for now, you'll edit (not delete) them in the next step.

- [ ] **Step 4: Strip the now-duplicated title/panel lines from `_build_tree_panel()` and `_build_wheel_panel()`, then compile-check**

`_build_tree_panel()` and `_build_wheel_panel()` still have their OLD title-label/panel-texture construction calls at the top - Step 2 already put that exact content into the `.tscn` as static nodes, so leaving both copies in place would draw everything twice. Edit these two functions (don't delete them, don't touch anything else inside them):

1. In `_build_tree_panel()`, delete its first two statements - the `MenuTheme.add_label(self, "Ability Tree", ...)` call and the `MenuTheme.add_texture_rect(self, "panel_large.png", LEFT_PANEL)` call. Leave everything from `_tree_lines = Control.new()` onward untouched (the node-building loop, `_tree_lines` construction) - Task 2 rewrites that part. The function should now start directly with `_tree_lines = Control.new()`.

2. In `_build_wheel_panel()`, delete its first three statements - the `MenuTheme.add_label(self, "Combat Action Bar", ...)` call, the `MenuTheme.add_texture_rect(self, "panel_large.png", RIGHT_PANEL)` call, and the `MenuTheme.add_label(self, "Ability Pool", ...)` call. Leave everything from `for i in WHEEL_OFFSETS.size():` onward untouched (the socket loop, `var pool_backdrop` and everything after it, including the pool-row loop that still reads `POOL_ROW_HEIGHT`) - Task 3 rewrites that part. The function should now start directly with `for i in WHEEL_OFFSETS.size():`.

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/menu/abilities_window.gd --path .`
Expected: only the known autoload false positive - no other errors. `talent_node.tscn` is NOT referenced anywhere in this task (see the note at the end of Step 3), so there is nothing left in this file, after the edits above, that depends on anything Task 2 or Task 3 haven't built yet.

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Step 1 (this task adds no new tests).

- [ ] **Step 6: Commit**

```bash
git add scenes/ui/menu/abilities_window.tscn scripts/ui/menu/abilities_window.gd
git commit -m "refactor: move AbilitiesWindow's static chrome and attribute panel into the scene file"
```

---

### Task 2: Talent tree nodes become a reusable instanced scene

**Files:**
- Create: `scenes/ui/menu/talent_node.tscn`
- Modify: `scripts/ui/menu/abilities_window.tscn` (add the `TreeLines` node + its `draw` connection)
- Modify: `scripts/ui/menu/abilities_window.gd` (`_build_tree_panel()`)

**Interfaces:**
- Consumes: nothing from Task 1 beyond the file states it left behind.
- Produces: a `const TalentNodeScene = preload("res://scenes/ui/menu/talent_node.tscn")` line, added in this task's Step 4 (not Task 1 - `talent_node.tscn` doesn't exist before this task creates it in Step 2). Nothing else is consumed by Task 3 (disjoint: Task 3 only touches `_build_wheel_panel()`).

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 1's ending count exactly.

- [ ] **Step 2: Create `scenes/ui/menu/talent_node.tscn`**

```
[gd_scene load_steps=1 format=3]

[node name="TalentNode" type="Button"]
custom_minimum_size = Vector2(32, 32)
offset_right = 32.0
offset_bottom = 32.0

[node name="RankLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 18.0
offset_top = 20.0
offset_right = 48.0
offset_bottom = 34.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.9, 0.9, 0.6, 1)
theme_override_font_sizes/font_size = 9
```

`RankLabel`'s offsets are relative to `TalentNode`'s own top-left corner (a `Control` child's `offset_*` is always local to its parent) - this reproduces the original code's `Rect2(button.position + Vector2(18, 20), Vector2(30, 14))` exactly, since that was ALSO `button.position` (the node's own origin) plus the same local offset, just computed in the parent's (the window's) coordinate space instead of the button's. Both are the same math: the label sits at local `(18, 20)`, size `(30, 14)`, relative to its node's origin, extending slightly past the 32x32 button's own bottom-right corner - matching the original visual (no `clip_contents` was ever set, so this was already true before this refactor).

- [ ] **Step 3: Add `TreeLines` to `scenes/ui/menu/abilities_window.tscn`**

Add this node anywhere after the other nodes added in Task 1 (order relative to the static chrome doesn't matter - it draws lines behind/among the tree, which is a disjoint screen region from the middle/right panels):

```
[node name="TreeLines" type="Control" parent="."]
layout_mode = 0
offset_right = 800.0
offset_bottom = 600.0
mouse_filter = 2

[connection signal="draw" from="TreeLines" to="." method="_draw_tree_lines"]
```

(Full-window-sized so `draw_line()` calls at absolute tree-node coordinates land correctly - the original `_tree_lines` was also just `Control.new()` with no explicit size, which defaults to a 0x0 rect; Godot still dispatches `draw` signal on ANY `CanvasItem` regardless of its declared `size` since `_draw()`/the `draw` signal fire once per frame the node is in the tree and visible, not gated by rect bounds - but drawing outside a Control's rect can be clipped by an ancestor's `clip_contents`. Nothing in this scene tree sets `clip_contents = true`, so this matches the original's behavior. Setting an explicit full-window `offset_right`/`offset_bottom` here is just for editor-preview clarity, not a functional requirement.)

- [ ] **Step 4: Add the `TalentNodeScene` preload and rewrite `_build_tree_panel()` in `scripts/ui/menu/abilities_window.gd`**

First, add this line right after `extends Control` at the top of the file (before the `const TREE_ORIGIN` line):

```gdscript
const TalentNodeScene = preload("res://scenes/ui/menu/talent_node.tscn")
```

This wasn't added in Task 1 because the scene file it points to didn't exist yet - it does now, from this task's Step 2.

Next, find the `var _tree_lines: Control` declaration (a plain, unassigned var - Task 1 kept it that way since `_build_tree_panel()` still constructed it manually via `Control.new()` at the time) and change it to an `@onready` reference to the new scene node from this task's Step 3:

```gdscript
@onready var _tree_lines: Control = $TreeLines
```

Then replace the full `_build_tree_panel()` function (after Task 1's Step 4 already stripped its title/panel-texture lines, it should now start with `_tree_lines = Control.new()`) with:

```gdscript
func _build_tree_panel() -> void:
	var tree: Array = TalentTree.TREES.get(_player_class(), TalentTree.TREES[0])
	for node_index in tree.size():
		var node_button: Button = TalentNodeScene.instantiate()
		node_button.position = _node_center(node_index) - NODE_SIZE / 2.0
		node_button.pressed.connect(_on_tree_node_pressed.bind(node_index))
		_style_circle_button(node_button, Color(0.1, 0.1, 0.11), Color(0.3, 0.3, 0.32))
		add_child(node_button)
		_tree_buttons.append(node_button)
		_tree_rank_labels.append(node_button.get_node("RankLabel"))
```

(Removed: the `_tree_lines = Control.new(); _tree_lines.mouse_filter = ...; _tree_lines.draw.connect(...); add_child(_tree_lines)` lines - `_tree_lines` is now the `@onready` reference from Task 1's Step 3, already wired to `_draw_tree_lines` via the scene's own `[connection]` block from this task's Step 3. Removed the separate `MenuTheme.add_label(self, "", Rect2(button.position + Vector2(18, 20), ...))` call - the rank label now comes for free as `TalentNode`'s `RankLabel` child, fetched via `node_button.get_node("RankLabel")`.)

- [ ] **Step 5: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/menu/abilities_window.gd --path .`
Expected: only the known autoload false positive.

- [ ] **Step 6: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Task 1's ending count.

- [ ] **Step 7: Commit**

```bash
git add scenes/ui/menu/talent_node.tscn scenes/ui/menu/abilities_window.tscn scripts/ui/menu/abilities_window.gd
git commit -m "refactor: give AbilitiesWindow's talent tree nodes a reusable instanced scene"
```

---

### Task 3: Ability pool becomes a VBoxContainer; wheel sockets stay code-driven by design

**Files:**
- Modify: `scenes/ui/menu/abilities_window.tscn`
- Modify: `scripts/ui/menu/abilities_window.gd` (`_build_wheel_panel()`)

**Interfaces:**
- Consumes: nothing from Task 2 (disjoint region of the same two files).
- Produces: nothing new consumed later - Task 4 is verification only.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, matching Task 2's ending count exactly.

- [ ] **Step 2: Add the pool backdrop, row list, and scroll buttons to `scenes/ui/menu/abilities_window.tscn`**

Add two new sub-resources (a shared normal/hover `StyleBoxFlat` pair for all 5 pool rows - their look never varies with data, only `.text`/`.visible` do) and the new nodes:

```
[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_poolrow"]
bg_color = Color(0.5, 0.5, 0.52, 1)
corner_radius_top_left = 9
corner_radius_top_right = 9
corner_radius_bottom_right = 9
corner_radius_bottom_left = 9
content_margin_left = 10.0

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_poolrow_hover"]
bg_color = Color(0.65, 0.65, 0.67, 1)
corner_radius_top_left = 9
corner_radius_top_right = 9
corner_radius_bottom_right = 9
corner_radius_bottom_left = 9
content_margin_left = 10.0

[node name="PoolBackdrop" type="ColorRect" parent="."]
layout_mode = 0
offset_left = 523.6
offset_top = 274.2
offset_right = 737.6
offset_bottom = 402.2
mouse_filter = 2
color = Color(0.06, 0.06, 0.065, 1)

[node name="PoolRows" type="VBoxContainer" parent="."]
layout_mode = 0
offset_left = 526.6
offset_top = 277.2
offset_right = 712.6
offset_bottom = 387.2
mouse_filter = 2
theme_override_constants/separation = 3

[node name="PoolRow0" type="Button" parent="PoolRows"]
custom_minimum_size = Vector2(186, 22)
layout_mode = 2
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.08, 0.08, 0.08, 1)
theme_override_styles/normal = SubResource("StyleBoxFlat_poolrow")
theme_override_styles/hover = SubResource("StyleBoxFlat_poolrow_hover")
alignment = 0

[node name="PoolRow1" type="Button" parent="PoolRows"]
custom_minimum_size = Vector2(186, 22)
layout_mode = 2
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.08, 0.08, 0.08, 1)
theme_override_styles/normal = SubResource("StyleBoxFlat_poolrow")
theme_override_styles/hover = SubResource("StyleBoxFlat_poolrow_hover")
alignment = 0

[node name="PoolRow2" type="Button" parent="PoolRows"]
custom_minimum_size = Vector2(186, 22)
layout_mode = 2
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.08, 0.08, 0.08, 1)
theme_override_styles/normal = SubResource("StyleBoxFlat_poolrow")
theme_override_styles/hover = SubResource("StyleBoxFlat_poolrow_hover")
alignment = 0

[node name="PoolRow3" type="Button" parent="PoolRows"]
custom_minimum_size = Vector2(186, 22)
layout_mode = 2
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.08, 0.08, 0.08, 1)
theme_override_styles/normal = SubResource("StyleBoxFlat_poolrow")
theme_override_styles/hover = SubResource("StyleBoxFlat_poolrow_hover")
alignment = 0

[node name="PoolRow4" type="Button" parent="PoolRows"]
custom_minimum_size = Vector2(186, 22)
layout_mode = 2
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.08, 0.08, 0.08, 1)
theme_override_styles/normal = SubResource("StyleBoxFlat_poolrow")
theme_override_styles/hover = SubResource("StyleBoxFlat_poolrow_hover")
alignment = 0

[node name="ScrollUpButton" type="Button" parent="."]
layout_mode = 0
offset_left = 715.6
offset_top = 277.2
offset_right = 734.6
offset_bottom = 337.2
text = "^"

[node name="ScrollDownButton" type="Button" parent="."]
layout_mode = 0
offset_left = 715.6
offset_top = 339.2
offset_right = 734.6
offset_bottom = 399.2
text = "v"

[connection signal="pressed" from="PoolRows/PoolRow0" to="." method="_on_pool_row_pressed" binds=[0]]
[connection signal="pressed" from="PoolRows/PoolRow1" to="." method="_on_pool_row_pressed" binds=[1]]
[connection signal="pressed" from="PoolRows/PoolRow2" to="." method="_on_pool_row_pressed" binds=[2]]
[connection signal="pressed" from="PoolRows/PoolRow3" to="." method="_on_pool_row_pressed" binds=[3]]
[connection signal="pressed" from="PoolRows/PoolRow4" to="." method="_on_pool_row_pressed" binds=[4]]
[connection signal="pressed" from="ScrollUpButton" to="." method="_on_pool_scrolled" binds=[-1]]
[connection signal="pressed" from="ScrollDownButton" to="." method="_on_pool_scrolled" binds=[1]]
```

Bump `load_steps` again to account for the 2 new sub-resources (13 + 2 = 15).

Notes on values: `PoolBackdrop`'s rect is `POOL_RECT` verbatim (`Rect2(523.6, 274.2, 214.0, 128.0)`, offset_right/bottom = position+size). `PoolRows`' position is `POOL_RECT.position + Vector2(3, 3)` = `(526.6, 277.2)` (matching the original per-row `Vector2(3, 3 + i * POOL_ROW_HEIGHT)` offset baseline); each row's `custom_minimum_size` width is `POOL_RECT.size.x - 28 = 186`, height `POOL_ROW_HEIGHT - 3 = 22`; `separation = 3` reproduces the gap between consecutive rows exactly (`22 + 3 = 25 = POOL_ROW_HEIGHT`, matching the original pitch). `ScrollUpButton`/`ScrollDownButton` positions are `POOL_RECT.position + Vector2(POOL_RECT.size.x - 22, 3)` = `(715.6, 277.2)` and `POOL_RECT.position + Vector2(POOL_RECT.size.x - 22, POOL_RECT.size.y - 63)` = `(715.6, 339.2)`, both `Vector2(19, 60)` sized (matching `_make_scroll_button`'s constants) - neither had any style override in the original code, so none is added here (both keep Godot's default `Button` look, same as before).

- [ ] **Step 3: Rewrite `_build_wheel_panel()` in `scripts/ui/menu/abilities_window.gd`**

Replace the full function (after Task 1's Step 4 already stripped its title/panel-texture lines, it should now start with `for i in WHEEL_OFFSETS.size():`) with:

```gdscript
# The wheel's 8 sockets sit on a circular (non-uniform) pitch and their style
# is 100% data-dependent - recomputed every refresh() from whichever move is
# currently equipped, with no reusable child structure (a bare Button, no
# label overlay) - unlike the talent tree nodes, there is no static content
# here to extract into the scene, so this stays code-driven by design.
func _build_wheel_panel() -> void:
	for i in WHEEL_OFFSETS.size():
		var socket = Button.new()
		socket.custom_minimum_size = SOCKET_SIZE
		socket.size = SOCKET_SIZE
		socket.position = WHEEL_CENTER + WHEEL_OFFSETS[i] - SOCKET_SIZE / 2.0
		socket.pressed.connect(_on_socket_pressed.bind(i))
		_style_circle_button(socket, Color(0.09, 0.09, 0.1), Color(0.22, 0.22, 0.24))
		add_child(socket)
		_socket_buttons.append(socket)
```

Then find the `var _pool_rows: Array[Button] = []` declaration (added back in Task 1's Step 3) and change it to an `@onready` reference gathering the five static rows:

```gdscript
@onready var _pool_rows: Array[Button] = [
	$PoolRows/PoolRow0, $PoolRows/PoolRow1, $PoolRows/PoolRow2, $PoolRows/PoolRow3, $PoolRows/PoolRow4,
]
```

Delete the now-unused `_make_scroll_button()` function entirely (its only callers - the two `scroll_up`/`scroll_down` construction lines - no longer exist; both buttons' clicks are wired via the scene's own `[connection]` blocks added in Step 2).

Finally, delete the `const POOL_ROW_HEIGHT = 25.0` line from the top of the file (added in Task 1, kept there because `_build_wheel_panel()`'s old pool-row loop still needed it at the time) - the rewritten `_build_wheel_panel()` above no longer reads it anywhere, and neither does anything else in the file.

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/menu/abilities_window.gd --path .`
Expected: only the known autoload false positive.

- [ ] **Step 5: Run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, same count as Task 2's ending count (this task adds no new tests, but `test_abilities_window_edits_action_bar` directly exercises `_on_pool_row_pressed`/`_pool_move_ids` - a real functional check that the row wiring still works).

- [ ] **Step 6: Commit**

```bash
git add scenes/ui/menu/abilities_window.tscn scripts/ui/menu/abilities_window.gd
git commit -m "refactor: move AbilitiesWindow's ability pool into a VBoxContainer"
```

---

### Task 4: Final verification pass

**Files:** none changed - this task is verification only.

**Interfaces:** none new.

- [ ] **Step 1: Full regression run**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, every test green, matching Task 1's noted baseline exactly (no new failures, no new tests - this whole plan is a pure refactor).

- [ ] **Step 2: Manual visual check**

Launch the game (or render `scenes/ui/menu/abilities_window.tscn` headlessly to a screenshot) and confirm by eye: backdrop/close/panels/titles are all positioned identically to before, the 28 talent-tree nodes still sit at their original irregular grid positions with rank labels and prerequisite lines drawn correctly, the 8 wheel sockets still ring correctly around their center, and the 5-row ability pool list (plus its scroll buttons) still lines up inside its panel at the original pitch.

- [ ] **Step 3: Update `NEXT_PHASES.md`**

In the "UI architecture: native Godot Containers instead of code-built controls" section, extend the existing `**DONE (2026-07-21):**` paragraph to also mention `abilities_window.gd`, e.g. change the sentence listing completed files/screens to read:

```markdown
**DONE (2026-07-21):** `scripts/ui/store/item_slot.gd`, `scripts/ui/store/store_window.gd`, `scripts/ui/inventory_panel.gd`, and `scripts/ui/menu/abilities_window.gd` migrated - `item_slot.tscn` now owns
the hover highlight as a real child node, `store_window.tscn` now owns every static chrome node plus a `GridContainer` for the 15-slot catalog, `inventory.tscn` now owns its panel/title/money-bar
chrome plus a `GridContainer` for the 6x6 slot grid, and `abilities_window.tscn` now owns its static chrome/attribute panel plus a `VBoxContainer` for the 5-row ability pool - the 28-node talent
tree keeps its irregular-pitch positions and fully data-dependent per-node styling in code (via a new reusable `talent_node.tscn`, the same instanced-`PackedScene` pattern as `ItemSlot`), and the
8-socket wheel stays entirely code-driven by design (no static content or reusable child structure to extract). Everything else named in this phase (`achievements_window.gd`, `hotbar.gd`,
`battle_scene.gd`, `menu_theme.gd`'s helpers) is still pending.
```

- [ ] **Step 4: Commit**

```bash
git add NEXT_PHASES.md
git commit -m "docs: mark abilities_window container migration done in NEXT_PHASES"
```
