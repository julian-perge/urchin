# Inventory Panel: Native Godot Containers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `scripts/ui/inventory_panel.gd` and `scenes/ui/inventory.tscn` off imperative runtime Control-building and onto a declarative `.tscn` scene with real Godot Container nodes, as the second increment of the "UI architecture: native Godot Containers instead of code-built controls" phase in `NEXT_PHASES.md` (the first increment, `item_slot.gd`/`store_window.gd`, is already done - see `docs/superpowers/plans/2026-07-21-store-ui-containers.md` for the precedent this plan follows).

**Architecture:** Every node `_ready()` currently builds with `Type.new()` + manual `.position`/`.size`/style assignment becomes a real child node declared in the `.tscn`, wired to the script via `@onready var` (or, for the two buttons' clicks, scene-file `[connection]` blocks instead of code-side `.connect()` calls). The one loop that legitimately needs to stay in code - instancing 36 `ItemSlot` scenes into the inventory grid - keeps doing that, but the grid itself becomes a `GridContainer` so the manual `(i % columns) * step` position math goes away entirely, exactly as it did for the store's catalog grid.

**Tech Stack:** Godot 4.7, GDScript, GUT 9.6.1 (headless test runner vendored at `addons/gut/`).

## Global Constraints

- `InventoryPanel`'s public interface must not change: `inventory_grid`, `gold_label`, `sell_button`, `delete_button` (all typed as whatever concrete node type they resolve to - `inventory_grid` becomes `GridContainer`, a `Control` subclass, which is source-compatible with every consumer since they all just call `.get_children()` on it), `item_selected`/`sell_pressed`/`delete_pressed` signals, `populate(items: Array)`, `populate_from_save(save: PlayerSave, items_by_id: Dictionary)`, `set_gold(amount: float)`, `show_sell_button(value: bool)`. Three consumers depend on this exact interface and must not need to change: `scripts/ui/store/store_window.gd`, `scripts/ui/menu/inventory_window.gd`, `scripts/battle/victory_screen.gd`. Out of scope - do not touch any of those three files.
- `test/integration/test_store_window.gd` and `test/integration/test_ui_scenes.gd` already assert on this interface (reading `window.inventory_panel.gold_label`/`.sell_button`/`.inventory_grid`, calling `panel.populate(...)`/`panel._on_slot_clicked(...)`, connecting `panel.item_selected`) and must keep passing unchanged - no test file in this plan needs modification, this is a pure refactor.
- Godot enum literals used below: `TextureRect.EXPAND_IGNORE_SIZE = 1`, `TextureRect.STRETCH_SCALE = 0`, `Control.MOUSE_FILTER_IGNORE = 2`, `HORIZONTAL_ALIGNMENT_CENTER = 1`, `VERTICAL_ALIGNMENT_CENTER = 1`.
- Compile-check after every `.gd` edit: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s <script.gd> --path .` (expect a `GameData`/`ZoneManager`-style "Identifier not found" autoload false positive - not a real error; any OTHER error is real).
- Run the full suite after every task: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`. Confirm the actual baseline count in whatever worktree this executes in before starting (it will differ from any number written here - check it live, do not trust a hardcoded figure from this document).
- This is a pure refactor (behavior-preserving) - there is no new failing test to write. The correct TDD shape is: confirm the existing tests are GREEN before touching a file, make the declarative change, confirm they are GREEN again after.

---

### Task 1: Move `InventoryPanel`'s static chrome and grid into the scene file

**Files:**
- Modify: `scenes/ui/inventory.tscn`
- Modify: `scripts/ui/inventory_panel.gd`

**Interfaces:**
- Consumes: nothing external - this is the only task with code changes in this plan.
- Produces: `inventory_grid: GridContainer`, `gold_label: Label`, `sell_button: Button`, `delete_button: Button` as `@onready` references (`$InventoryGrid`, `$GoldLabel`, `$SellItemButton`, `$DeleteItemButton`) instead of runtime-built. `SellItemButton.pressed`/`DeleteItemButton.pressed` wired via the scene's own `[connection]` blocks.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gtest=test/integration/test_store_window.gd`
Expected: PASS, all tests in that file (this is the reference point for a pure refactor - nothing here is a failing test to fix, it's a passing suite that must stay passing). Also run without the `-gtest` filter for the full-suite count and note it - you'll compare against this exact number after the change.

- [ ] **Step 2: Rewrite `scenes/ui/inventory.tscn`**

Read the current `scenes/ui/inventory.tscn` first (currently just an empty `InventoryPanel` root Control + script, `custom_minimum_size = Vector2(249.1, 327.5)`, `offset_right = 249.0`, `offset_bottom = 328.0`, `mouse_filter = 2`). Replace its contents with:

```
[gd_scene load_steps=8 format=3 uid="uid://bwra17qajnemg"]

[ext_resource type="Script" path="res://scripts/ui/inventory_panel.gd" id="1_invpanel"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/panel_large.png" id="2_panellarge"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/panel_bar.png" id="3_panelbar"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/button_sell.png" id="4_sell"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/button_delete.png" id="5_delete"]

[sub_resource type="StyleBoxEmpty" id="StyleBoxEmpty_flat"]

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_hover"]
draw_center = false
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(1, 1, 1, 1)

[node name="InventoryPanel" type="Control"]
custom_minimum_size = Vector2(249.1, 327.5)
offset_right = 249.0
offset_bottom = 328.0
mouse_filter = 2
script = ExtResource("1_invpanel")

[node name="PanelBackground" type="TextureRect" parent="."]
layout_mode = 0
offset_right = 249.1
offset_bottom = 267.1
mouse_filter = 2
texture = ExtResource("2_panellarge")
expand_mode = 1
stretch_mode = 0

[node name="TitleLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 10.0
offset_top = 6.0
offset_right = 239.0
offset_bottom = 26.0
mouse_filter = 2
theme_override_colors/font_color = Color(0.55, 0.55, 0.55, 1)
theme_override_font_sizes/font_size = 14
horizontal_alignment = 1
text = "Your Inventory"

[node name="InventoryGrid" type="GridContainer" parent="."]
layout_mode = 0
offset_left = 14.1
offset_top = 31.1
offset_right = 235.1
offset_bottom = 252.2
mouse_filter = 2
theme_override_constants/h_separation = 7
theme_override_constants/v_separation = 7
columns = 6

[node name="BarBackground" type="TextureRect" parent="."]
layout_mode = 0
offset_top = 276.6
offset_right = 249.1
offset_bottom = 327.5
mouse_filter = 2
texture = ExtResource("3_panelbar")
expand_mode = 1
stretch_mode = 0

[node name="GoldLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 14.0
offset_top = 285.0
offset_right = 144.0
offset_bottom = 319.0
mouse_filter = 2
theme_override_colors/font_color = Color(1, 0.8, 0, 1)
theme_override_font_sizes/font_size = 20
vertical_alignment = 1

[node name="SellItemButton" type="Button" parent="."]
layout_mode = 0
offset_left = 150.6
offset_top = 287.0
offset_right = 181.6
offset_bottom = 318.0
custom_minimum_size = Vector2(31, 31)
theme_override_constants/icon_max_width = 31
theme_override_styles/normal = SubResource("StyleBoxEmpty_flat")
theme_override_styles/pressed = SubResource("StyleBoxEmpty_flat")
theme_override_styles/hover = SubResource("StyleBoxFlat_hover")
icon = ExtResource("4_sell")
expand_icon = true
icon_alignment = 1
tooltip_text = "Sell Item\nSelect an item, then click here to sell it for 15% of its price."

[node name="DeleteItemButton" type="Button" parent="."]
layout_mode = 0
offset_left = 204.1
offset_top = 287.0
offset_right = 235.1
offset_bottom = 318.0
custom_minimum_size = Vector2(31, 31)
theme_override_constants/icon_max_width = 31
theme_override_styles/normal = SubResource("StyleBoxEmpty_flat")
theme_override_styles/pressed = SubResource("StyleBoxEmpty_flat")
theme_override_styles/hover = SubResource("StyleBoxFlat_hover")
icon = ExtResource("5_delete")
expand_icon = true
icon_alignment = 1
tooltip_text = "Destroy Item\nSelect an item, then click here to destroy it permanently."

[connection signal="pressed" from="SellItemButton" to="." method="_on_sell_pressed"]
[connection signal="pressed" from="DeleteItemButton" to="." method="_on_delete_pressed"]
```

Notes on values used above, all copied verbatim from the pre-change `inventory_panel.gd`'s constants: `PANEL_RECT = Rect2(0, 0, 249.1, 267.1)` -> `PanelBackground` offsets; `BAR_RECT = Rect2(0, 276.6, 249.1, 50.9)` -> `BarBackground` offsets (`276.6+50.9=327.5`); `GRID_POSITION = Vector2(14.1, 31.1)` -> `InventoryGrid` position; the gold/sell/delete positions and colors/font sizes come straight from the removed `_ready()`/`_add_icon_button()` calls (`Rect2(14, 285, 130, 34)` for the gold label -> `offset_right = 14+130=144`, `offset_bottom = 285+34=319`; `Vector2(150.6, 287)`/`Vector2(204.1, 287)` for the two buttons, both `+31` for their `offset_right`/`offset_bottom` since `SLOT_SIZE = Vector2(31, 31)`). `InventoryGrid`'s `h_separation`/`v_separation = 7` reproduces the original 38px `SLOT_STEP` pitch given each `ItemSlot`'s `custom_minimum_size = Vector2(31, 31)` (38 - 31 = 7) - same math as the store's catalog grid. `InventoryGrid`'s `offset_right`/`offset_bottom` (235.1/252.2, i.e. `14.1 + 6*31+5*7` by `31.1 + 6*31+5*7`) are for editor-preview accuracy only - `GridContainer` recomputes its own size from its 36 children at runtime regardless of what's declared here. The two buttons previously got a FRESH `StyleBoxEmpty`/`StyleBoxFlat` built per call in `_add_icon_button()` (called twice) - here they share ONE `StyleBoxEmpty` and ONE `StyleBoxFlat` sub-resource each, which is behaviorally identical (both were visually identical white-border-on-hover styles) and removes the duplication.

- [ ] **Step 3: Rewrite `scripts/ui/inventory_panel.gd`**

Replace the full file with:

```gdscript
# inventory_panel.gd
# The "Your Inventory" column shared by the menu screens (inventory window,
# store window), rebuilt to the original menu geometry (DefineSprite 3142):
# large panel with a 6x6 slot grid on a 38 px pitch, and the money bar below
# with the euro readout plus the sell (gold euro) and drop (red X) buttons.
# The panel's stage position is (503.5, 81.6); everything in here is
# relative to that root.
#
# Slots are index-preserving: slot i shows PlayerSave.item_array[i], exactly
# like the original (items keep their grid cell). populate() with a compact
# list still works for hosts that don't care about save indices.
extends Control
class_name InventoryPanel

signal item_selected(slot: ItemSlot)
signal sell_pressed(slot: ItemSlot)
signal delete_pressed(slot: ItemSlot)

const ItemSlotScene = preload("res://scenes/ui/item_slot.tscn")
const GRID_SLOTS = 36

@onready var inventory_grid: GridContainer = $InventoryGrid
@onready var gold_label: Label = $GoldLabel
@onready var sell_button: Button = $SellItemButton
@onready var delete_button: Button = $DeleteItemButton

var selected_slot: ItemSlot = null


func _ready():
	for i in GRID_SLOTS:
		var slot: ItemSlot = ItemSlotScene.instantiate()
		slot.slot_clicked.connect(_on_slot_clicked)
		inventory_grid.add_child(slot)


func _on_sell_pressed() -> void:
	if selected_slot != null and selected_slot.item != null:
		sell_pressed.emit(selected_slot)


func _on_delete_pressed() -> void:
	if selected_slot != null and selected_slot.item != null:
		delete_pressed.emit(selected_slot)


# Fills the grid slots in order with the given items (extra slots cleared).
func populate(items: Array) -> void:
	var index = 0
	for child in inventory_grid.get_children():
		if child is ItemSlot:
			child.set_item(items[index] if index < items.size() else null)
			child.set_selected(false)
			index += 1
	selected_slot = null


# Index-preserving fill straight from the save: slot i <- item_array[i].
# Each slot's "save_index" metadata points back at its item_array cell.
func populate_from_save(save: PlayerSave, items_by_id: Dictionary) -> void:
	var slots = inventory_grid.get_children()
	for i in slots.size():
		var slot = slots[i]
		if not slot is ItemSlot:
			continue
		slot.set_meta("save_index", i)
		var item_id = int(save.item_array[i]) if i < save.item_array.size() else 0
		slot.set_item(items_by_id.get(item_id) if item_id != 0 else null)
		slot.set_selected(false)
	selected_slot = null


func set_gold(amount: float) -> void:
	gold_label.text = "€ %s" % MenuTheme.format_money(int(amount))


func show_sell_button(value: bool) -> void:
	sell_button.visible = value


func _on_slot_clicked(slot: ItemSlot) -> void:
	if selected_slot != null:
		selected_slot.set_selected(false)
	selected_slot = slot if slot.item != null else null
	if selected_slot != null:
		selected_slot.set_selected(true)
		item_selected.emit(selected_slot)
```

Removed: `PANEL_RECT`/`BAR_RECT`/`GRID_POSITION`/`GRID_COLUMNS` constants and the `_add_icon_button()` helper function (all now live in the `.tscn`); the `custom_minimum_size`/`mouse_filter` lines that used to open `_ready()` (the scene root already carries both, so re-setting them at runtime was redundant even before this change - safe to drop). `GRID_SLOTS` is retained (still drives the instancing loop count) and must stay in sync with `InventoryGrid.columns = 6` in the `.tscn` (36 / 6 = 6 rows).

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/inventory_panel.gd --path .`
Expected: only the known autoload false positive, if anything - no other errors.

- [ ] **Step 5: Run the store/UI test files and the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gtest=test/integration/test_store_window.gd`
Expected: PASS, same tests as Step 1, still green.

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, full suite still green at the exact count you noted in Step 1 (this task adds no new tests).

- [ ] **Step 6: Commit**

```bash
git add scenes/ui/inventory.tscn scripts/ui/inventory_panel.gd
git commit -m "refactor: move InventoryPanel's static chrome and grid into the scene file"
```

---

### Task 2: Final verification pass

**Files:** none changed - this task is verification only.

**Interfaces:** none new.

- [ ] **Step 1: Full regression run**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, every test green, matching Task 1's noted baseline exactly (no new failures, no new tests either - this whole plan is a pure refactor).

- [ ] **Step 2: Manual visual check**

Launch the game (or render `scenes/ui/inventory.tscn`/`scenes/ui/store/store_window.tscn` headlessly to a screenshot) and confirm by eye: the panel background/title/6x6 grid/money bar/sell+delete buttons are all still positioned identically to before the refactor, hovering a slot still shows its highlight, and the sell/delete buttons still show a white hover border with no visible background otherwise.

- [ ] **Step 3: Update `NEXT_PHASES.md`**

In the "UI architecture: native Godot Containers instead of code-built controls" section, extend the existing `**DONE (2026-07-21):**` line's own paragraph (don't add a second separate DONE paragraph) to also mention `inventory_panel.gd`, e.g. change:

```markdown
**DONE (2026-07-21):** `scripts/ui/store/item_slot.gd` and `scripts/ui/store/store_window.gd` migrated - `item_slot.tscn` now owns the hover highlight as a real child node, and
`store_window.tscn` now owns every static chrome node (backdrop, close button, panels, labels) plus a `GridContainer` for the 15-slot catalog, leaving the script with only the parts that
genuinely need code (the equip-doll helper and the per-slot `PackedScene` instancing loop). Everything else named in this phase (`inventory_panel.gd`, `abilities_window.gd`,
`achievements_window.gd`, `hotbar.gd`, `battle_scene.gd`, `menu_theme.gd`'s helpers) is still pending.
```

to:

```markdown
**DONE (2026-07-21):** `scripts/ui/store/item_slot.gd`, `scripts/ui/store/store_window.gd`, and `scripts/ui/inventory_panel.gd` migrated - `item_slot.tscn` now owns the hover highlight
as a real child node, `store_window.tscn` now owns every static chrome node (backdrop, close button, panels, labels) plus a `GridContainer` for the 15-slot catalog, and `inventory.tscn` now
owns its panel/title/money-bar chrome plus a `GridContainer` for the 6x6 slot grid - each script keeps only the parts that genuinely need code (per-slot `PackedScene` instancing loops, the
equip-doll helper). Everything else named in this phase (`abilities_window.gd`, `achievements_window.gd`, `hotbar.gd`, `battle_scene.gd`, `menu_theme.gd`'s helpers) is still pending.
```

- [ ] **Step 4: Commit**

```bash
git add NEXT_PHASES.md
git commit -m "docs: mark inventory_panel container migration done in NEXT_PHASES"
```
