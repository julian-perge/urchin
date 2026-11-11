# Store UI: Native Godot Containers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `scripts/ui/store/item_slot.gd` and `scripts/ui/store/store_window.gd` off imperative runtime Control-building and onto declarative `.tscn` scenes with real Godot Container nodes (GridContainer, TextureButton, etc.), as the first increment of the "UI architecture: native Godot Containers instead of code-built controls" phase in `NEXT_PHASES.md`.

**Architecture:** Every node these two files currently build with `Type.new()` + manual `.position`/`.size`/style assignment becomes a real child node declared in the `.tscn`, wired to the script via `@onready var` (or, for the close button's click, a scene-file `[connection]` block instead of a code-side `.connect()` call). The one loop that legitimately needs to stay in code - instancing 15 `ItemSlot` scenes into the catalog grid - keeps doing that, but the grid itself becomes a `GridContainer` so the manual `(i % columns) * step` position math goes away entirely.

**Tech Stack:** Godot 4.7, GDScript, GUT 9.6.1 (headless test runner already vendored at `addons/gut/`).

## Global Constraints

- Out of scope for this plan: `scripts/ui/inventory_panel.gd`, `scripts/ui/menu/equip_doll_view.gd`, `scripts/ui/menu/menu_theme.gd`'s `add_texture_rect`/`add_label` helpers, and any other menu screen (`abilities_window.gd`, `achievements_window.gd`, `hotbar.gd`, `battle_scene.gd`). These still call the `MenuTheme` helpers and construct their own controls at runtime - leave them untouched. `NEXT_PHASES.md` already documents this as an incremental, multi-phase migration; this plan is only the first increment.
- `ItemSlot`'s public interface must not change: `item: GameItem`, `selected: bool`, `show_price: bool`, `set_item()`, `set_selected()`, `slot_clicked` signal. `test/integration/test_store_window.gd`, `test/integration/test_ui_scenes.gd`, and `test/integration/test_battle_scene.gd` all depend on this exact interface for inventory/store/victory-screen drops - do not rename or retype any of these.
- `StoreWindow`'s public interface must not change either: `store_items`, `inventory_panel`, `shop_backdrop` (`TextureRect`, `.texture` settable), `shop_dialogue` (`Label`, `.text` settable), `refresh_store()`. These are read directly by `test/integration/test_store_window.gd`.
- This is a pure refactor (behavior-preserving), not new functionality - there is no new failing test to write for the store-window tasks. The existing test suite already encodes the expected behavior; the correct TDD shape here is: confirm the existing tests are GREEN before touching a file, make the declarative change, confirm they are GREEN again after. Task 1 (the `ItemSlot` highlight) is the one place genuinely new test coverage gets added, because the highlight's hover behavior currently has zero test coverage at all.
- Godot enum literals used below (verify against `TextureRect`/`TextureButton` class docs if anything looks visually wrong after the change): `TextureRect.EXPAND_IGNORE_SIZE = 1`, `TextureRect.STRETCH_SCALE = 0`, `TextureRect.STRETCH_KEEP_ASPECT_COVERED = 6`, `TextureButton.STRETCH_KEEP_ASPECT_CENTERED = 5`, `Control.MOUSE_FILTER_IGNORE = 2`, `HORIZONTAL_ALIGNMENT_LEFT = 0`, `HORIZONTAL_ALIGNMENT_CENTER = 1`.
- Compile-check after every `.gd` edit: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s <script.gd> --path .` (expect a `ZoneManager`/`GameData`/etc. "Identifier not found" line - that's a known `--check-only` autoload false positive, not a real error; any OTHER error is real).
- Run the full suite after every task: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .` - baseline is 83/83 tests, 553 asserts passing. It must stay there (plus whatever Task 1 adds).

---

### Task 1: Move `ItemSlot`'s hover highlight into the scene file

**Files:**
- Modify: `scenes/ui/item_slot.tscn`
- Modify: `scripts/ui/store/item_slot.gd`
- Create: `test/integration/test_item_slot.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `ItemSlot` gets a `Highlight` child node (`TextureRect`, starts `visible = false`) reachable via `slot.get_node("Highlight")` - later tasks don't depend on this, but it's the pattern Task 2/3 follow for `StoreWindow`'s own static nodes.

- [ ] **Step 1: Write the failing test**

Create `test/integration/test_item_slot.gd`:

```gdscript
# ItemSlot's hover highlight now lives in the .tscn as a real "Highlight"
# child node instead of being constructed at runtime in _ready() - this
# locks in that it's wired correctly and still toggles on hover.
extends GutTest

const ItemSlotScene = preload("res://scenes/ui/item_slot.tscn")


func test_highlight_node_exists_and_starts_hidden():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	var highlight: TextureRect = slot.get_node("Highlight")
	assert_not_null(highlight, "Highlight child exists in the scene")
	assert_false(highlight.visible, "highlight starts hidden")


func test_highlight_toggles_on_hover_signals():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	var highlight: TextureRect = slot.get_node("Highlight")
	slot.mouse_entered.emit()
	assert_true(highlight.visible, "highlight shows on mouse_entered")
	slot.mouse_exited.emit()
	assert_false(highlight.visible, "highlight hides on mouse_exited")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gtest=test/integration/test_item_slot.gd`
Expected: FAIL - `get_node("Highlight")` returns null (the node doesn't exist yet), so `assert_not_null` fails and the second test errors on a null highlight.

- [ ] **Step 3: Add the `Highlight` node to the scene**

Read the current `scenes/ui/item_slot.tscn` first (it currently has `load_steps=3`, two `ext_resource` entries, `ItemSlot` root + `ItemIcon` child). Replace its contents with:

```
[gd_scene load_steps=4 format=3 uid="uid://duxqydn2hw6b3"]

[ext_resource type="Texture2D" path="res://assets/ui/menu/slot.png" id="1_slotart"]
[ext_resource type="Script" uid="uid://cp1r30t4t18lj" path="res://scripts/ui/store/item_slot.gd" id="1_script"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/slot_highlight.png" id="3_highlight"]

[node name="ItemSlot" type="TextureRect" groups=["item_slot"]]
custom_minimum_size = Vector2(31, 31)
offset_right = 31.0
offset_bottom = 31.0
mouse_filter = 0
texture = ExtResource("1_slotart")
expand_mode = 1
stretch_mode = 6
script = ExtResource("1_script")

[node name="ItemIcon" type="TextureRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
expand_mode = 1
stretch_mode = 0

[node name="Highlight" type="TextureRect" parent="."]
visible = false
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("3_highlight")
expand_mode = 1
stretch_mode = 0
```

(`expand_mode = 1` / `stretch_mode = 0` on `Highlight` reproduce exactly what the old code set: `TextureRect.EXPAND_IGNORE_SIZE` / `TextureRect.STRETCH_SCALE`.)

- [ ] **Step 4: Simplify `item_slot.gd`**

Replace the full file with:

```gdscript
# item_slot.gd
# One inventory/store grid cell. Holds a GameItem (or nothing), shows its
# icon (slot_image preferred, sprite_image fallback), and reports clicks.
extends Control
class_name ItemSlot

signal slot_clicked(slot: ItemSlot)

@onready var item_icon: TextureRect = $ItemIcon
# The original slot buttons' hover state (shape 2857, a white frame) - now a
# real scene child instead of built at runtime.
@onready var _highlight: TextureRect = $Highlight

var item: GameItem = null
var selected: bool = false
# Price line in the tooltip - only store catalog slots show it (equipped/
# inventory items don't price-tag themselves in the original).
var show_price: bool = false


func _ready():
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(func(): _highlight.visible = true)
	mouse_exited.connect(func(): _highlight.visible = false)
	_refresh()


func set_item(new_item: GameItem) -> void:
	item = new_item
	selected = false
	_refresh()


func set_selected(value: bool) -> void:
	selected = value
	modulate = Color(1.3, 1.3, 0.9) if selected else Color.WHITE


func _refresh() -> void:
	if item_icon == null:
		return
	if item == null:
		item_icon.texture = null
		tooltip_text = ""
		return
	if item.slot_image != null:
		item_icon.texture = item.slot_image
	elif item.sprite_image != null:
		item_icon.texture = item.sprite_image
	else:
		item_icon.texture = null
	# Name, price (catalog only), stat bonus lines, flavor text.
	var lines = [item.display_name]
	if show_price and item.price > 0:
		lines.append("Cost: %d Euros" % int(item.price))
	for stat_line in item.tooltipAlt:
		lines.append(str(stat_line))
	if item.tooltip is String and str(item.tooltip) != "":
		lines.append(str(item.tooltip))
	tooltip_text = "\n".join(lines)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slot_clicked.emit(self)
```

(Removed: the `HIGHLIGHT_TEXTURE` preload constant and the `TextureRect.new()` block in `_ready()` - both now live in the `.tscn`.)

- [ ] **Step 5: Run the new test to verify it passes**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gtest=test/integration/test_item_slot.gd`
Expected: PASS, 2/2 tests.

- [ ] **Step 6: Compile-check and run the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/store/item_slot.gd --path .`
Expected: no output (clean compile).

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, 85/85 tests (83 baseline + 2 new), asserts >= 553 + whatever the 2 new tests add.

- [ ] **Step 7: Commit**

```bash
git add scenes/ui/item_slot.tscn scripts/ui/store/item_slot.gd test/integration/test_item_slot.gd
git commit -m "refactor: move ItemSlot's hover highlight into the scene file"
```

---

### Task 2: Move `StoreWindow`'s static chrome into the scene file

**Files:**
- Modify: `scenes/ui/store/store_window.tscn`
- Modify: `scripts/ui/store/store_window.gd`

**Interfaces:**
- Consumes: nothing new from Task 1.
- Produces: `store_window.gd`'s `shop_backdrop: TextureRect`, `shop_dialogue: Label`, `_status_label: Label` become `@onready` references to scene nodes (`$ShopBackdrop`, `$DescriptionLabel`, `$StatusLabel`) instead of runtime-built. Task 3 builds on this same file pair.

- [ ] **Step 1: Confirm the baseline is green**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gtest=test/integration/test_store_window.gd`
Expected: PASS, all existing tests in that file (this is the "red/green" reference point for a pure refactor - nothing here is a failing test to fix, it's a passing suite that must stay passing).

- [ ] **Step 2: Rewrite `store_window.tscn`**

Read the current `scenes/ui/store/store_window.tscn` first (currently just the empty `StoreWindow` root + script). Replace its contents with:

```
[gd_scene load_steps=6 format=3 uid="uid://brmx4sa7xb3xq"]

[ext_resource type="Script" uid="uid://dci8fqqpbntjm" path="res://scripts/ui/store/store_window.gd" id="1_script"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/menu_backdrop.png" id="2_backdrop"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/close_x.png" id="3_close"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/panel_large.png" id="4_panellarge"]
[ext_resource type="Texture2D" path="res://assets/ui/menu/panel_center.png" id="5_panelcenter"]

[node name="StoreWindow" type="Control" groups=["menu_screen"]]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("1_script")

[node name="Backdrop" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 14.2
offset_top = 14.9
offset_right = 782.7
offset_bottom = 440.0
mouse_filter = 2
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
offset_left = 22.9
offset_top = 81.6
offset_right = 272.0
offset_bottom = 409.1
mouse_filter = 2
texture = ExtResource("4_panellarge")
expand_mode = 1
stretch_mode = 0

[node name="ShopBackdrop" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 34.0
offset_top = 92.0
offset_right = 261.0
offset_bottom = 242.0
clip_contents = true
mouse_filter = 2
expand_mode = 1
stretch_mode = 6

[node name="DescriptionLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 36.0
offset_top = 252.0
offset_right = 259.0
offset_bottom = 402.0
mouse_filter = 2
theme_override_font_sizes/font_size = 11
autowrap_mode = 3
text = "..."

[node name="MiddleTopPanel" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 285.6
offset_top = 81.6
offset_right = 472.2
offset_bottom = 215.0
mouse_filter = 2
texture = ExtResource("5_panelcenter")
expand_mode = 1
stretch_mode = 0

[node name="MiddleBottomPanel" type="TextureRect" parent="."]
layout_mode = 0
offset_left = 285.6
offset_top = 225.0
offset_right = 472.2
offset_bottom = 409.1
mouse_filter = 2
texture = ExtResource("5_panelcenter")
expand_mode = 1
stretch_mode = 0

[node name="PurchaseHintLabel" type="Label" parent="."]
layout_mode = 0
offset_left = 290.2
offset_top = 237.6
offset_right = 467.2
offset_bottom = 267.6
mouse_filter = 2
theme_override_colors/font_color = Color(0.6, 0.6, 0.6, 1)
theme_override_font_sizes/font_size = 10
horizontal_alignment = 1
autowrap_mode = 3
text = "Click on the items to purchase them."

[node name="StoreItems" type="GridContainer" parent="."]
layout_mode = 0
offset_left = 289.6
offset_top = 276.4
offset_right = 472.6
offset_bottom = 383.4
mouse_filter = 2
theme_override_constants/h_separation = 7
theme_override_constants/v_separation = 7
columns = 5

[connection signal="pressed" from="CloseButton" to="." method="_on_exit_pressed"]
```

Notes on values used above: every `offset_*` rect is `position`/`position+size` from the constants already in `store_window.gd` and `MenuTheme` (`BACKDROP_RECT`, `CLOSE_RECT`, `LEFT_PANEL`, `SHOP_BACKDROP_RECT`, `DIALOGUE_RECT`, `MIDDLE_TOP_PANEL`, `MIDDLE_BOTTOM_PANEL`, `PURCHASE_HINT_RECT`, `CATALOG_ORIGIN`). `autowrap_mode = 3` is `TextServer.AUTOWRAP_WORD_SMART` (matches `MenuTheme.add_label`'s `wrap_text = true` path). `StoreItems`'s `h_separation`/`v_separation = 7` reproduces the original 38px pitch given each `ItemSlot`'s `custom_minimum_size = Vector2(31, 31)` (38 - 31 = 7); `offset_right`/`offset_bottom`
on `StoreItems` (472.6/383.4, i.e. 5*31+4*7 wide by 3*31+2*7 tall) are for editor-preview accuracy only - `GridContainer` recomputes its own size from its children at runtime regardless of what's
declared here, so this can't drift out of sync with the actual 15 instanced slots. Node order top-to-bottom matches the original `add_child` call order in `_build_chrome`/`_build_left_panel`/
`_build_middle`, so z-stacking is unchanged.

- [ ] **Step 3: Rewrite `store_window.gd`'s top and `_ready`/build functions**

Replace lines 1 through 145 (everything from the top of the file through the end of `_build_inventory`) with:

```gdscript
# store_window.gd
# Store screen, rebuilt from frame 16 of the original menu clip
# (DefineSprite 3142 at stage 400.5, 222.4):
# - left: the zone's shop backdrop (sprite 3036 frame, via StoreManager)
#   over the large panel, shopkeeper dialogue beneath it
# - middle: the dressed player doll with the 7 equip slots (top panel) and
#   the 15-item shop catalog on a 5x3 grid (bottom panel)
# - right: the shared InventoryPanel (6x6 grid + money bar + sell/drop)
#
# Click a catalog item to buy it; click an inventory item to equip it;
# click an equip slot to unequip. Sell pays 15% of list price (button 3015).
extends Control

signal store_closed

const ItemSlotScene = preload("res://scenes/ui/item_slot.tscn")

const INVENTORY_AT = Vector2(503.5, 81.6)
# 15 catalog slots, 5 columns (3 rows) - keep in sync with StoreItems'
# `columns` property in store_window.tscn.
const CATALOG_SLOTS = 15
# playerSlot0-6 centers from the frame-16 dump.
const EQUIP_SLOT_CENTERS = {
	0: Vector2(301.1, 117.6),
	2: Vector2(301.1, 152.0),
	6: Vector2(301.1, 186.4),
	5: Vector2(335.5, 186.4),
	1: Vector2(456.7, 117.6),
	3: Vector2(456.7, 152.0),
	4: Vector2(456.7, 186.4),
}
const DOLL_POSITION = Vector2(396.5, 162.4)
const DOLL_SCALE = 0.85

@onready var shop_backdrop: TextureRect = $ShopBackdrop
@onready var shop_dialogue: Label = $DescriptionLabel
@onready var store_items: GridContainer = $StoreItems
@onready var _status_label: Label = $StatusLabel

var inventory_panel: InventoryPanel
var equip_view: EquipDollView

var selected_store_slot: ItemSlot = null


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_middle()
	_build_inventory()
	GameData.gold_changed.connect(func(_amount):
		if visible:
			inventory_panel.set_gold(GameData.get_player_gold()))
	GameData.inventory_changed.connect(func():
		if visible:
			refresh_store())
	refresh_store()


func _build_middle() -> void:
	equip_view = EquipDollView.new()
	equip_view.name = "EquipDollView"
	add_child(equip_view)
	equip_view.setup(EQUIP_SLOT_CENTERS, DOLL_POSITION, DOLL_SCALE, true)
	equip_view.equip_slot_clicked.connect(_on_equip_slot_clicked)
	for i in CATALOG_SLOTS:
		var slot: ItemSlot = ItemSlotScene.instantiate()
		slot.show_price = true
		slot.slot_clicked.connect(_on_store_slot_clicked)
		store_items.add_child(slot)


func _build_inventory() -> void:
	inventory_panel = preload("res://scenes/ui/inventory.tscn").instantiate()
	inventory_panel.position = INVENTORY_AT
	add_child(inventory_panel)
	inventory_panel.show_sell_button(true)
	inventory_panel.item_selected.connect(_on_inventory_item_selected)
	inventory_panel.sell_pressed.connect(_on_sell_pressed)
	inventory_panel.delete_pressed.connect(_on_delete_pressed)
```

Leave every function from `open_store()` onward (through `_on_exit_pressed()`) exactly as-is - only the `_on_exit_pressed` function body stays, its wiring moved to the scene's `[connection]` block, so delete the old `close.pressed.connect(_on_exit_pressed)` line along with the rest of `_build_chrome`/`_build_left_panel` (both functions are fully removed, replaced by the block above).

- [ ] **Step 4: Compile-check**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only -s scripts/ui/store/store_window.gd --path .`
Expected: only the known `ZoneManager`-style autoload false positive, if anything - no other errors.

- [ ] **Step 5: Run the store test file and the full suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gtest=test/integration/test_store_window.gd`
Expected: PASS, same tests as Step 1, still green.

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, full suite still green at whatever count Task 1 left it at.

- [ ] **Step 6: Commit**

```bash
git add scenes/ui/store/store_window.tscn scripts/ui/store/store_window.gd
git commit -m "refactor: move StoreWindow's static chrome into the scene file"
```

---

### Task 3: Final verification pass

**Files:** none changed - this task is verification only.

**Interfaces:** none new.

- [ ] **Step 1: Full regression run**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .`
Expected: PASS, every test green, no new failures versus the pre-plan baseline (83/83, 553 asserts) plus Task 1's 2 new tests.

- [ ] **Step 2: Manual visual check**

Per this project's own convention for UI changes (see `CLAUDE.md`/session norms: verify UI changes in the running game, not just tests), launch the game, open the store screen from a zone hub, and confirm by eye: the close X still closes the store, hovering a catalog/inventory slot still shows the white highlight frame, the 15-slot catalog still lays out as a 5-wide/3-tall grid on the original pitch, and the shopkeeper backdrop/dialogue/panels are all still positioned identically to before the refactor.

- [ ] **Step 3: Update `NEXT_PHASES.md`**

In the "UI architecture: native Godot Containers instead of code-built controls" section, add a line noting `item_slot.gd`/`store_window.gd` are done, e.g.:

```markdown
**DONE (2026-07-21):** `scripts/ui/store/item_slot.gd` and `scripts/ui/store/store_window.gd` migrated - `item_slot.tscn` now owns the hover highlight as a real child node, and
`store_window.tscn` now owns every static chrome node (backdrop, close button, panels, labels) plus a `GridContainer` for the 15-slot catalog, leaving the script with only the parts that
genuinely need code (the equip-doll helper and the per-slot `PackedScene` instancing loop). Everything else named in this phase (`inventory_panel.gd`, `abilities_window.gd`,
`achievements_window.gd`, `hotbar.gd`, `battle_scene.gd`, `menu_theme.gd`'s helpers) is still pending.
```

- [ ] **Step 4: Commit**

```bash
git add NEXT_PHASES.md
git commit -m "docs: mark item_slot/store_window container migration done in NEXT_PHASES"
```
