# Rich Tooltip Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every tooltip in the game (items, hotbar, abilities screen,
in-battle orbs, buff icons) with a shared, section-based rich tooltip that
matches the original's title-bar / colored-info-bar / body look, instead of
today's plain single-panel `AbilityTooltip` (abilities screen only) and
Godot's bare `tooltip_text` popup (everywhere else).

**Architecture:** One new autoload, `GameTooltip` (a `CanvasLayer` scene),
owns the only tooltip UI in the game. Every caller builds a small,
plain-data `sections` array (each section a background color plus one or
more independently-colored text lines) and calls
`GameTooltip.show_sections(sections, anchor)` / `GameTooltip.hide_tooltip()`
on hover. A new `TooltipTheme` class holds the palette as named constants,
recovered from the original's own tooltip clip (see the spec).

**Tech Stack:** Godot 4.7.2, GDScript, GUT (test framework, vendored in
`addons/gut`).

**Spec:** `docs/superpowers/specs/2026-08-20-rich-tooltip-rework-design.md`

## Global Constraints

- The section/line data model is exact and used verbatim by every task: a
  tooltip is `Array[Dictionary]` sections; a section is `{"bg_color":
  Color, "lines": Array[Dictionary]}`; a line is `{"text": String,
  "color": Color}`. No task invents a different shape.
- Every background and text color used anywhere in this plan comes from
  `TooltipTheme`'s named constants (`scripts/ui/tooltip_theme.gd`, built in
  Task 1) - no task hardcodes its own `Color(...)` literal for a tooltip
  section or line.
- `GameTooltip`'s public API is exactly two methods:
  `show_sections(sections: Array, anchor: Control, icon: Texture2D = null,
  icon_color: Color = Color.WHITE) -> void` and `hide_tooltip() -> void`.
  No task adds a third public method without updating this plan first.
- No pytest suite exists in this repo - all verification is GUT tests
  (`test/unit/`, `test/integration/`), run via:
  `/Applications/Godot.app/Contents/MacOS/Godot --headless -s
  res://addons/gut/gut_cmdln.gd --path . -gselect=<file>` (add
  `-gunit_test_name=<name>` to run one test).
- `GameTooltip` is a persistent autoload - it exists for the whole GUT run,
  not just one test. Any test that calls `show_sections()` must call
  `GameTooltip.hide_tooltip()` before it ends (in the test body, or in an
  `after_each()` if the file doesn't already have one for something else).
- Task 1 must land (implemented, reviewed, committed) before Tasks 2-6
  start - they all call `GameTooltip`/`TooltipTheme`, which Task 1 creates.
  Tasks 2-6 have no dependency on each other.
- Every task that removes a call site's `tooltip_text` usage must also
  remove any now-dead helper function it leaves behind (e.g.
  `battle_scene.gd`'s `_move_tooltip()` in Task 5) - don't leave unused
  code.

---

### Task 1: `TooltipTheme` palette + `GameTooltip` shared autoload

**Files:**
- Create: `scripts/ui/tooltip_theme.gd`
- Create: `scenes/ui/game_tooltip.tscn`
- Create: `scripts/ui/game_tooltip.gd`
- Modify: `project.godot` (register the `GameTooltip` autoload)
- Test: `test/integration/test_game_tooltip.gd`

**Interfaces:**
- Produces: `TooltipTheme` (class_name, `RefCounted`) with constants
  `BG_HEADER`, `BG_COST`, `BG_BODY`, `BG_NEXT_RANK`, `TEXT_TITLE`,
  `TEXT_SUBHEADER`, `TEXT_BODY`, `TEXT_STAT`, `TEXT_FLAVOR` (all `Color`).
  Every later task's exact colors come from here.
- Produces: the global autoload `GameTooltip` with
  `show_sections(sections: Array, anchor: Control, icon: Texture2D = null,
  icon_color: Color = Color.WHITE) -> void` and `hide_tooltip() -> void`.
  Every later task calls these two methods and nothing else.

- [ ] **Step 1: Write `scripts/ui/tooltip_theme.gd`**

```gdscript
# tooltip_theme.gd
# Shared tooltip palette, recovered from the original's own KrinToolTipper
# clip (DefineSprite 2717): two backer graphics (a black body, alpha
# 230/255, and a white-gray-white gradient used for a glossy header-style
# bar) recolored per section via additive ColorTransforms rather than
# separate art. Background colors below are each gradient's own recorded
# midpoint stop (170,170,170) with the same additive transform the source
# applies at that stop - not an arbitrary flat-color guess. Text colors are
# pixel-sampled from reference captures (the source's own TextFormat.color
# values are buried in undecompiled AS2 bytecode) - see
# docs/superpowers/specs/2026-08-20-rich-tooltip-rework-design.md.
class_name TooltipTheme
extends RefCounted

const BG_HEADER: Color = Color(170.0 / 255.0, 170.0 / 255.0, 170.0 / 255.0, 217.0 / 255.0)
const BG_COST: Color = Color(139.0 / 255.0, 164.0 / 255.0, 170.0 / 255.0, 217.0 / 255.0)
const BG_BODY: Color = Color(0.0, 0.0, 0.0, 230.0 / 255.0)
const BG_NEXT_RANK: Color = Color(50.0 / 255.0, 40.0 / 255.0, 53.0 / 255.0, 230.0 / 255.0)

const TEXT_TITLE: Color = Color(0.08, 0.08, 0.08)
const TEXT_SUBHEADER: Color = Color(0.08, 0.08, 0.12)
const TEXT_BODY: Color = Color(0.96, 0.96, 0.96)
const TEXT_STAT: Color = Color(0.98, 0.78, 0.08)
const TEXT_FLAVOR: Color = Color(0.7, 0.98, 0.27)
```

- [ ] **Step 2: Write `scenes/ui/game_tooltip.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/game_tooltip.gd" id="1_script"]

[node name="GameTooltip" type="CanvasLayer"]
layer = 100
script = ExtResource("1_script")

[node name="Root" type="HBoxContainer" parent="."]
visible = false
mouse_filter = 2
theme_override_constants/separation = 8

[node name="IconBacking" type="ColorRect" parent="Root"]
custom_minimum_size = Vector2(32, 32)
layout_mode = 2
mouse_filter = 2
visible = false

[node name="Icon" type="TextureRect" parent="Root/IconBacking"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
offset_left = 2.0
offset_top = 2.0
offset_right = -2.0
offset_bottom = -2.0
mouse_filter = 2
expand_mode = 1
stretch_mode = 5

[node name="Sections" type="VBoxContainer" parent="Root"]
custom_minimum_size = Vector2(220, 0)
layout_mode = 2
mouse_filter = 2
theme_override_constants/separation = 0
```

Root is an `HBoxContainer` directly (not a plain `Control` wrapping one) -
its own `.position`/`.visible` are what `game_tooltip.gd` sets, so there's
no need for an extra wrapper node. No `layout_mode` on `Root` itself -
matches the existing `ability_tooltip.tscn`'s root node, which also has
none (a bare Control-family root under a non-Container parent doesn't need
one in this codebase's existing scenes).

- [ ] **Step 3: Write `scripts/ui/game_tooltip.gd`**

```gdscript
# game_tooltip.gd
# Shared rich tooltip, replacing both the abilities-screen's old single-panel
# AbilityTooltip and every other tooltip's plain Godot tooltip_text (which
# can only render one uniform box, one text color - it can't reproduce the
# original's title-bar/colored-info-bar/body look at all). A tooltip is a
# stack of sections (scripts/ui/tooltip_theme.gd's colors); each section is
# its own background box holding one or more independently-colored lines -
# see docs/superpowers/specs/2026-08-20-rich-tooltip-rework-design.md.
extends CanvasLayer
class_name GameTooltip

const EDGE_MARGIN: float = 4.0

@onready var _root: HBoxContainer = $Root
@onready var _icon_backing: ColorRect = $Root/IconBacking
@onready var _icon: TextureRect = $Root/IconBacking/Icon
@onready var _sections: VBoxContainer = $Root/Sections


# sections: Array[Dictionary], each {"bg_color": Color, "lines":
# Array[Dictionary]} where a line is {"text": String, "color": Color}.
# anchor: the hovered control, used to position this tooltip beside it.
# icon/icon_color are optional - only the abilities screen uses them today.
func show_sections(sections: Array, anchor: Control, icon: Texture2D = null, icon_color: Color = Color.WHITE) -> void:
	for child in _sections.get_children():
		child.queue_free()
	for section in sections:
		var panel: PanelContainer = PanelContainer.new()
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = section["bg_color"]
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		panel.add_theme_stylebox_override("panel", style)
		var lines_box: VBoxContainer = VBoxContainer.new()
		for line in section["lines"]:
			var label: Label = Label.new()
			label.text = line["text"]
			label.add_theme_color_override("font_color", line["color"])
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lines_box.add_child(label)
		panel.add_child(lines_box)
		_sections.add_child(panel)
	_icon_backing.visible = icon != null
	if icon != null:
		_icon.texture = icon
		_icon_backing.color = icon_color
	_root.visible = true
	_position_near(anchor)


func hide_tooltip() -> void:
	_root.visible = false


func _position_near(anchor: Control) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var pos: Vector2 = anchor.global_position + Vector2(anchor.size.x + 8.0, 0.0)
	var tooltip_size: Vector2 = _root.size
	pos.x = clampf(pos.x, EDGE_MARGIN, maxf(EDGE_MARGIN, viewport_size.x - tooltip_size.x - EDGE_MARGIN))
	pos.y = clampf(pos.y, EDGE_MARGIN, maxf(EDGE_MARGIN, viewport_size.y - tooltip_size.y - EDGE_MARGIN))
	_root.position = pos
```

`hide_tooltip`, not `hide` - `hide()`/`show()` are `CanvasItem` built-ins
already in scope on this node; shadowing them would be confusing to call
correctly.

- [ ] **Step 4: Register the autoload**

In `project.godot`'s `[autoload]` section, append (after `LogManagerAuto`,
matching the existing append-at-the-end convention):

```
GameTooltip="*res://scenes/ui/game_tooltip.tscn"
```

- [ ] **Step 5: Write `test/integration/test_game_tooltip.gd`**

```gdscript
# test_game_tooltip.gd
extends GutTest


func after_each():
	GameTooltip.hide_tooltip()


func _sections_fixture() -> Array:
	return [
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": "Title", "color": TooltipTheme.TEXT_TITLE}]},
		{"bg_color": TooltipTheme.BG_BODY, "lines": [
			{"text": "Line one", "color": TooltipTheme.TEXT_BODY},
			{"text": "Line two", "color": TooltipTheme.TEXT_STAT},
		]},
	]


func test_show_sections_builds_one_panel_per_section_with_right_colors_and_lines():
	var anchor: Control = add_child_autofree(Control.new())
	anchor.position = Vector2(100, 100)
	anchor.size = Vector2(30, 30)

	GameTooltip.show_sections(_sections_fixture(), anchor)

	assert_eq(GameTooltip._sections.get_child_count(), 2, "one PanelContainer per section")
	var header_panel: PanelContainer = GameTooltip._sections.get_child(0)
	var header_style: StyleBoxFlat = header_panel.get_theme_stylebox("panel")
	assert_eq(header_style.bg_color, TooltipTheme.BG_HEADER)
	var header_label: Label = header_panel.get_child(0).get_child(0)
	assert_eq(header_label.text, "Title")
	assert_eq(header_label.get_theme_color("font_color"), TooltipTheme.TEXT_TITLE)

	var body_panel: PanelContainer = GameTooltip._sections.get_child(1)
	var body_style: StyleBoxFlat = body_panel.get_theme_stylebox("panel")
	assert_eq(body_style.bg_color, TooltipTheme.BG_BODY)
	var body_lines: VBoxContainer = body_panel.get_child(0)
	assert_eq(body_lines.get_child_count(), 2)
	assert_eq(body_lines.get_child(0).text, "Line one")
	assert_eq(body_lines.get_child(1).get_theme_color("font_color"), TooltipTheme.TEXT_STAT)


func test_show_sections_clears_previous_sections_on_a_second_call():
	var anchor: Control = add_child_autofree(Control.new())
	GameTooltip.show_sections(_sections_fixture(), anchor)
	GameTooltip.show_sections(
		[{"bg_color": TooltipTheme.BG_BODY, "lines": [{"text": "Only", "color": TooltipTheme.TEXT_BODY}]}], anchor
	)
	assert_eq(GameTooltip._sections.get_child_count(), 1, "old sections cleared, not accumulated")


func test_icon_shows_only_when_provided():
	var anchor: Control = add_child_autofree(Control.new())
	var texture: Texture2D = load("res://assets/ui/abilities/Leading_Strike.png")

	GameTooltip.show_sections(_sections_fixture(), anchor, texture, Color.RED)
	assert_true(GameTooltip._icon_backing.visible, "icon shown when provided")
	assert_eq(GameTooltip._icon.texture, texture)
	assert_eq(GameTooltip._icon_backing.color, Color.RED)

	GameTooltip.show_sections(_sections_fixture(), anchor)
	assert_false(GameTooltip._icon_backing.visible, "icon hidden when omitted")


func test_show_sections_makes_the_tooltip_visible_and_hide_tooltip_hides_it():
	var anchor: Control = add_child_autofree(Control.new())
	GameTooltip.show_sections(_sections_fixture(), anchor)
	assert_true(GameTooltip._root.visible)
	GameTooltip.hide_tooltip()
	assert_false(GameTooltip._root.visible)


func test_position_clamps_at_the_right_and_bottom_edges():
	var anchor: Control = add_child_autofree(Control.new())
	anchor.position = Vector2(790, 590)
	anchor.size = Vector2(30, 30)
	GameTooltip.show_sections(_sections_fixture(), anchor)
	var viewport_size: Vector2 = GameTooltip.get_viewport().get_visible_rect().size
	assert_true(
		GameTooltip._root.position.x + GameTooltip._root.size.x <= viewport_size.x,
		"tooltip stays inside the viewport's right edge"
	)
	assert_true(
		GameTooltip._root.position.y + GameTooltip._root.size.y <= viewport_size.y,
		"tooltip stays inside the viewport's bottom edge"
	)


func test_position_clamps_at_the_left_and_top_edges():
	var anchor: Control = add_child_autofree(Control.new())
	anchor.position = Vector2(-50, -50)
	anchor.size = Vector2(10, 10)
	GameTooltip.show_sections(_sections_fixture(), anchor)
	assert_true(GameTooltip._root.position.x >= 0.0, "never positioned off the left edge")
	assert_true(GameTooltip._root.position.y >= 0.0, "never positioned off the top edge")
```

- [ ] **Step 6: Run the new tests**

Run:
`/Applications/Godot.app/Contents/MacOS/Godot --headless -s
res://addons/gut/gut_cmdln.gd --path . -gselect=test_game_tooltip.gd`

Expected: all pass. If a positioning test fails, check `_root.size` at the
point `_position_near()` reads it - Godot's container layout should have
already resolved synchronously by then (matches how the pre-existing
`AbilityTooltip` positions itself with no wait), but if it hasn't, that's
a real bug to fix here, not a test to loosen.

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/tooltip_theme.gd scenes/ui/game_tooltip.tscn scripts/ui/game_tooltip.gd project.godot test/integration/test_game_tooltip.gd
git commit -m "feat: add the shared GameTooltip autoload and TooltipTheme palette"
```

---

### Task 2: `GameItem.slot_type_display_name()` + item slot tooltip retrofit

**Files:**
- Modify: `scripts/entities/game_item.gd`
- Modify: `scripts/ui/store/item_slot.gd`
- Test: `test/unit/test_game_item.gd` (new)
- Test: `test/integration/test_item_slot.gd` (add tests; existing tests are
  untouched - none of them reference `tooltip_text`)

**Interfaces:**
- Consumes: `TooltipTheme`'s constants, `GameTooltip.show_sections()` /
  `.hide_tooltip()` (Task 1).
- Produces: `GameItem.slot_type_display_name() -> String`.

- [ ] **Step 1: Write the failing test for `slot_type_display_name()`**

Create `test/unit/test_game_item.gd`:

```gdscript
# test_game_item.gd
extends GutTest


func test_slot_type_display_name_covers_every_equip_slot():
	var item := GameItem.new()
	item.item_type = GameItem.ItemType.MAINHAND
	assert_eq(item.slot_type_display_name(), "Primary Arms")
	item.item_type = GameItem.ItemType.TWOHAND
	assert_eq(item.slot_type_display_name(), "Two-Handed Arms")
	item.item_type = GameItem.ItemType.OFFHAND
	assert_eq(item.slot_type_display_name(), "Secondary Arms")
	item.item_type = GameItem.ItemType.HEAD
	assert_eq(item.slot_type_display_name(), "Headwear")
	item.item_type = GameItem.ItemType.CHEST
	assert_eq(item.slot_type_display_name(), "Bodywear")
	item.item_type = GameItem.ItemType.HAND
	assert_eq(item.slot_type_display_name(), "Gloves")
	item.item_type = GameItem.ItemType.LEGS
	assert_eq(item.slot_type_display_name(), "Leggings")
	item.item_type = GameItem.ItemType.FOOT
	assert_eq(item.slot_type_display_name(), "Footwear")
	item.item_type = GameItem.ItemType.TOOL
	assert_eq(item.slot_type_display_name(), "Tool")


func test_slot_type_display_name_is_empty_for_none():
	var item := GameItem.new()
	item.item_type = GameItem.ItemType.NONE
	assert_eq(item.slot_type_display_name(), "")
```

- [ ] **Step 2: Run it to verify it fails**

Run:
`/Applications/Godot.app/Contents/MacOS/Godot --headless -s
res://addons/gut/gut_cmdln.gd --path . -gselect=test_game_item.gd`

Expected: FAIL - `slot_type_display_name` doesn't exist yet (script error,
not an assertion failure - that's fine, it's the expected shape of "not
implemented yet").

- [ ] **Step 3: Add `slot_type_display_name()` to `game_item.gd`**

Append after the existing `@export` block (after `@export var stats:
Dictionary`):

```gdscript

# Display name for this item's equip slot, mirroring
# scripts/editor/items.gd's item_type_map (reversed). "" for NONE - no
# slot line is shown for those items (see item_slot.gd).
const _SLOT_TYPE_NAMES: Dictionary[ItemType, String] = {
	ItemType.TOOL: "Tool",
	ItemType.HEAD: "Headwear",
	ItemType.CHEST: "Bodywear",
	ItemType.HAND: "Gloves",
	ItemType.LEGS: "Leggings",
	ItemType.FOOT: "Footwear",
	ItemType.MAINHAND: "Primary Arms",
	ItemType.OFFHAND: "Secondary Arms",
	ItemType.TWOHAND: "Two-Handed Arms",
}


func slot_type_display_name() -> String:
	return _SLOT_TYPE_NAMES.get(item_type, "")
```

- [ ] **Step 4: Run the test again to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Write the failing tests for the item-slot tooltip retrofit**

Append to `test/integration/test_item_slot.gd` (after the existing
`func after_each(): GameData.current_save = null` - rename nothing, just
add a second `after_each` line inside that SAME function, since GDScript
only allows one `after_each()` per file):

```gdscript
func after_each():
	GameData.current_save = null
	GameTooltip.hide_tooltip()


func test_hover_shows_a_tooltip_for_a_filled_slot():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	var item: GameItem = ItemManagerAuto.items_by_id.values()[0]
	slot.set_item(item)
	slot.mouse_entered.emit()
	assert_true(GameTooltip._root.visible, "tooltip shown for a real item")
	var header_label: Label = GameTooltip._sections.get_child(0).get_child(0).get_child(0)
	assert_eq(header_label.text, item.display_name)


func test_hover_on_an_empty_slot_shows_no_tooltip():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	slot.mouse_entered.emit()
	assert_false(GameTooltip._root.visible, "nothing to show for an empty slot")


func test_hover_exit_hides_the_tooltip():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	var item: GameItem = ItemManagerAuto.items_by_id.values()[0]
	slot.set_item(item)
	slot.mouse_entered.emit()
	slot.mouse_exited.emit()
	assert_false(GameTooltip._root.visible, "hidden on mouse exit")


func test_tooltip_skips_the_type_line_for_a_none_type_item():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	var item: GameItem = GameItem.new()
	item.display_name = "Test Consumable"
	item.item_type = GameItem.ItemType.NONE
	slot.set_item(item)
	slot.mouse_entered.emit()
	# This item has no tooltipAlt/tooltip/price content either, so a correct
	# build produces exactly one section (the header) - the type line and
	# the body both use TooltipAlt/tooltip/price data this item doesn't
	# have, so counting sections is the real assertion here, not checking
	# for a specific missing bg_color (the type line uses BG_HEADER, same
	# as the title section it'd sit next to - checking "no BG_COST section"
	# would pass even if the skip were broken, since BG_COST is never used
	# by item tooltips at all).
	assert_eq(GameTooltip._sections.get_child_count(), 1, "just the header - no type line for NONE, no body with nothing to show")
```

The existing `func after_each(): GameData.current_save = null` at line 57
of this file gets replaced by the combined version above (one function,
both lines) - don't leave two `after_each()` definitions in the same file.

- [ ] **Step 6: Run the new tests to verify they fail**

Same GUT command with `-gselect=test_item_slot.gd`. Expected: FAIL - the
tooltip tests fail because `_refresh()` still sets `tooltip_text`, not
`GameTooltip` sections (`GameTooltip._root.visible` stays false).

- [ ] **Step 7: Rework `item_slot.gd`'s tooltip building**

Replace the whole file's `_ready()` and `_refresh()`, and add a new
`_tooltip_sections()` helper:

```gdscript
func _ready():
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(func():
		_highlight.visible = true
		if item != null:
			GameTooltip.show_sections(_tooltip_sections(), self))
	mouse_exited.connect(func():
		_highlight.visible = false
		GameTooltip.hide_tooltip())
	_refresh()
```

```gdscript
func _refresh() -> void:
	if item_icon == null:
		return
	if item == null:
		item_icon.texture = null
		return
	if item.slot_image != null:
		item_icon.texture = item.slot_image
	elif item.sprite_image != null:
		item_icon.texture = item.sprite_image
	else:
		item_icon.texture = null
```

```gdscript
# Built fresh on hover rather than kept in sync on every _refresh() - the
# tooltip only needs to exist while the mouse is actually over this slot.
func _tooltip_sections() -> Array:
	var sections: Array = [
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": item.display_name, "color": TooltipTheme.TEXT_TITLE}]},
	]
	if item.item_type != GameItem.ItemType.NONE:
		sections.append({
			"bg_color": TooltipTheme.BG_HEADER,
			"lines": [{
				"text": "Lvl. %d %s" % [item.required_level, item.slot_type_display_name()],
				"color": TooltipTheme.TEXT_SUBHEADER,
			}],
		})
	var body_lines: Array = []
	if show_price and item.price > 0:
		body_lines.append({"text": "Cost: %d Euros" % int(item.price), "color": TooltipTheme.TEXT_STAT})
	for stat_line in item.tooltipAlt:
		body_lines.append({"text": str(stat_line), "color": TooltipTheme.TEXT_STAT})
	if item.tooltip is String and str(item.tooltip) != "":
		body_lines.append({"text": str(item.tooltip), "color": TooltipTheme.TEXT_FLAVOR})
	if not body_lines.is_empty():
		sections.append({"bg_color": TooltipTheme.BG_BODY, "lines": body_lines})
	return sections
```

- [ ] **Step 8: Run all `test_item_slot.gd` tests to verify they pass**

Same command as Step 6. Expected: PASS, including the pre-existing
highlight/drag-drop tests (unaffected by this change).

- [ ] **Step 9: Commit**

```bash
git add scripts/entities/game_item.gd scripts/ui/store/item_slot.gd test/unit/test_game_item.gd test/integration/test_item_slot.gd
git commit -m "feat: item slots use the shared rich tooltip"
```

---

### Task 3: Hotbar tooltip retrofit

**Files:**
- Modify: `scenes/ui/hotbar.tscn`
- Modify: `scripts/ui/hotbar.gd`
- Test: `test/integration/test_hotbar.gd` (new)

**Interfaces:**
- Consumes: `TooltipTheme`'s constants, `GameTooltip.show_sections()` /
  `.hide_tooltip()` (Task 1).

- [ ] **Step 1: Write the failing tests**

Create `test/integration/test_hotbar.gd`:

```gdscript
# test_hotbar.gd
extends GutTest

const HotbarScene = preload("res://scenes/ui/hotbar.tscn")


func after_each():
	GameTooltip.hide_tooltip()


func test_hover_shows_a_two_section_tooltip_for_inventory_button():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	var button: Button = hotbar.get_node("%InventoryButton")
	button.mouse_entered.emit()
	assert_true(GameTooltip._root.visible)
	assert_eq(GameTooltip._sections.get_child_count(), 2, "title + body")
	button.mouse_exited.emit()
	assert_false(GameTooltip._root.visible)


func test_hover_shows_a_single_section_tooltip_for_a_coming_soon_button():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	var button: Button = hotbar.get_node("%OptionsButton")
	button.mouse_entered.emit()
	assert_eq(GameTooltip._sections.get_child_count(), 1, "single-line caption, no body section")


func test_zone_map_and_quit_buttons_also_show_tooltips():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	for button_name in ["ZoneMapButton", "QuitButton"]:
		var button: Button = hotbar.get_node("%" + button_name)
		button.mouse_entered.emit()
		assert_true(GameTooltip._root.visible, "%s shows a tooltip" % button_name)
		button.mouse_exited.emit()
```

- [ ] **Step 2: Run to verify they fail**

Run:
`/Applications/Godot.app/Contents/MacOS/Godot --headless -s
res://addons/gut/gut_cmdln.gd --path . -gselect=test_hotbar.gd`

Expected: FAIL - `%OptionsButton`/`%ZoneMapButton`/`%QuitButton` lookups
either don't resolve yet (ZoneMapButton/QuitButton have no unique name in
the scene today) or the button has no tooltip wiring yet.

- [ ] **Step 3: Add unique names to `ZoneMapButton` and `QuitButton`**

In `scenes/ui/hotbar.tscn`, add `unique_name_in_owner = true` as the first
property line of both `[node name="ZoneMapButton" ...]` and `[node
name="QuitButton" ...]` (every other hotbar button already has this - only
these two are missing it).

- [ ] **Step 4: Remove the scene-authored `tooltip_text` properties**

In `scenes/ui/hotbar.tscn`, delete the `tooltip_text = "..."` line from
each of: `InventoryButton`, `AbilitiesButton`, `SaveButton`,
`OptionsButton`, `RespecButton`, `AchievementsButton`, `ZoneMapButton`,
`QuitButton`.

- [ ] **Step 5: Wire tooltips in `hotbar.gd`**

Add the captions constant (near `HOVER_COLORS`) and wire it in `_ready()`:

```gdscript
# Tooltip captions per button: [title] for a single-line caption, or
# [title, body] for a 2-section tooltip. These are the same strings the
# scene file used to carry as plain tooltip_text - kept here now that
# GameTooltip needs sections, not a joined string.
const TOOLTIP_CAPTIONS: Dictionary[String, Array] = {
	"InventoryButton": ["Inventory", "Click here to manage equipment."],
	"AbilitiesButton": ["Abilities", "Click here to manage abilities and attributes."],
	"SaveButton": ["Save Game", "Click here to save your progress."],
	"OptionsButton": ["Coming soon"],
	"RespecButton": ["Coming soon"],
	"AchievementsButton": ["Achievements", "Click here to view your achievements."],
	"ZoneMapButton": ["World map"],
	"QuitButton": ["Quit", "Click here to return to the save select screen."],
}
```

```gdscript
func _ready():
	ZoneManager.zone_changed.connect(_on_zone_changed)
	ZoneManager.zone_unlocked.connect(func(_zone): _refresh(ZoneManager.current_zone))
	GameData.save_loaded.connect(func(_slot): _refresh(ZoneManager.current_zone))
	for button_name in HOVER_COLORS:
		_setup_icon_glow(get_node("%" + button_name))
	for button_name in TOOLTIP_CAPTIONS:
		_setup_tooltip(get_node("%" + button_name), TOOLTIP_CAPTIONS[button_name])
	_wire_screen_visibility.call_deferred()
	_refresh(ZoneManager.current_zone)
```

Add the new helper (near `_setup_icon_glow`):

```gdscript
func _setup_tooltip(button: Button, caption: Array) -> void:
	var sections: Array = [
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": caption[0], "color": TooltipTheme.TEXT_TITLE}]},
	]
	if caption.size() > 1:
		sections.append({"bg_color": TooltipTheme.BG_BODY, "lines": [{"text": caption[1], "color": TooltipTheme.TEXT_BODY}]})
	button.mouse_entered.connect(func(): GameTooltip.show_sections(sections, button))
	button.mouse_exited.connect(GameTooltip.hide_tooltip)
```

Note `HOVER_COLORS` (6 buttons) and `TOOLTIP_CAPTIONS` (8 buttons) are
different sets - `ZoneMapButton` and `QuitButton` have no hover-glow color
and were never in the `HOVER_COLORS` loop, so this is a second, separate
loop over the full caption set, not an extension of the glow loop.

- [ ] **Step 6: Run the tests again to verify they pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add scenes/ui/hotbar.tscn scripts/ui/hotbar.gd test/integration/test_hotbar.gd
git commit -m "feat: hotbar buttons use the shared rich tooltip"
```

---

### Task 4: Abilities screen retrofit (`AbilityTooltipBuilder` + `abilities_window.gd`)

**Files:**
- Modify: `scripts/ui/menu/ability_tooltip_builder.gd`
- Modify: `scripts/ui/menu/abilities_window.gd`
- Modify: `scenes/ui/menu/abilities_window.tscn`
- Delete: `scenes/ui/menu/ability_tooltip.tscn` (+ its `.uid` file if present)
- Delete: `scripts/ui/menu/ability_tooltip.gd` (+ its `.uid` file if present)
- Test: `test/unit/test_ability_tooltip_builder.gd` (rewrite)
- Leave untouched: `test/unit/test_ability_tooltip_fields.gd` (tests
  `Ability.tooltip_description`/`tooltip_cost` directly - unrelated to the
  builder or the tooltip scene)

**Interfaces:**
- Consumes: `TooltipTheme`'s constants, `GameTooltip.show_sections()` /
  `.hide_tooltip()` (Task 1).
- Produces: `AbilityTooltipBuilder.build_sections(node, save, move, buff) ->
  Dictionary` (`{"sections": Array, "icon_color": Color}`), replacing
  `build_fields()`.

- [ ] **Step 1: Rewrite the failing tests first**

Replace `test/unit/test_ability_tooltip_builder.gd` entirely:

```gdscript
# test_ability_tooltip_builder.gd
extends GutTest


func _section_texts(result: Dictionary) -> Array:
	var texts: Array = []
	for section in result["sections"]:
		for line in section["lines"]:
			texts.append(line["text"])
	return texts


func test_active_node_fields_at_rank_zero():
	var save: PlayerSave = PlayerSave.new_game("Test", 0)
	var node: Dictionary = TalentTree.get_talent_node(0, 0).duplicate()
	node["_node_index"] = 0
	var move: Ability = MoveManagerAuto.get_move(TalentTree.granted_move_id(node, 1))
	var result: Dictionary = AbilityTooltipBuilder.build_sections(node, save, move, null)
	var texts: Array = _section_texts(result)
	assert_has(texts, move.display_name)
	assert_has(texts, move.tooltip_cost)
	assert_has(texts, move.tooltip_description)
	assert_has(texts, "Next Tier (Lvl. 1)")


func test_passive_node_at_max_rank_shows_max():
	var save: PlayerSave = PlayerSave.new_game("Test", 0)
	# Node 1 in class 0's tree is the INTEGRITY passive, max_rank 4.
	var node: Dictionary = TalentTree.get_talent_node(0, 1).duplicate()
	node["_node_index"] = 1
	save.talent_main_array[1] = 4
	var buff: Buff = BuffManagerAuto.get_buff_by_name(TalentTree.granted_buff_name(node, 4))
	var result: Dictionary = AbilityTooltipBuilder.build_sections(node, save, null, buff)
	var texts: Array = _section_texts(result)
	assert_has(texts, "Integrity")
	assert_has(texts, "Passive")
	assert_has(texts, "MAX")
	# Verified fact, not a bug: every tree-passive buff's tooltip_description
	# is empty in the source data (AS3 undefined -> "" via Buff._text()) - so
	# no body section is built at all for this hover.
	for section in result["sections"]:
		assert_ne(section["bg_color"], TooltipTheme.BG_BODY, "no description text, so no body section")


func test_pool_row_hover_has_no_next_rank_section():
	var move: Ability = MoveManagerAuto.get_move(1)
	var result: Dictionary = AbilityTooltipBuilder.build_sections({}, null, move, null)
	for section in result["sections"]:
		assert_ne(section["bg_color"], TooltipTheme.BG_NEXT_RANK, "no rank progress to show outside a tree-node hover")
```

- [ ] **Step 2: Run to verify it fails**

Run:
`/Applications/Godot.app/Contents/MacOS/Godot --headless -s
res://addons/gut/gut_cmdln.gd --path . -gselect=test_ability_tooltip_builder.gd`

Expected: FAIL - `build_sections` doesn't exist yet (only `build_fields`).

- [ ] **Step 3: Rewrite `ability_tooltip_builder.gd`**

```gdscript
# ability_tooltip_builder.gd
# Pure data builder for the abilities screen's rich tooltip (talent tree
# node / action-bar wheel socket / ability pool row hover). No Node/scene
# dependency on purpose - abilities_window.gd consumes build_sections()'s
# output directly; GUT tests target this directly.
class_name AbilityTooltipBuilder
extends RefCounted


# node: a TalentTree node dict, or {} for a pool-row/wheel-socket hover
#   (no rank progress to show - no next-rank section in that case).
# save: used to read the node's current rank (ignored when node is {}).
# move: the resolved Ability for this hover - for a TREE node hover, the
#   CALLER must resolve the rank-specific move id first (see
#   TalentTree.granted_move_id()) - this builder does not do that
#   resolution itself, it only formats whatever move it's given.
# buff: the resolved Buff for a passive node hover, or null for an active
#   node / pool row / wheel socket hover.
# Returns {"sections": Array, "icon_color": Color} - icon_color is kept
# separate from the section list since the icon isn't itself a section.
static func build_sections(node: Dictionary, save: PlayerSave, move: Ability, buff: Buff) -> Dictionary:
	var is_passive: bool = not node.is_empty() and TalentTree.is_passive(node)
	var title: String
	var description: String
	var cost: String
	if is_passive:
		title = str(node["buff_family"]).capitalize()
		description = buff.tooltip_description if buff != null else ""
		cost = "Passive"
	else:
		title = move.display_name if move != null else "?"
		description = move.tooltip_description if move != null else ""
		cost = move.tooltip_cost if move != null else ""
	var next_rank_text: String = ""
	if not node.is_empty():
		var rank: int = TalentTree.get_rank(save, node.get("_node_index", -1)) if save != null else 0
		var max_rank: int = int(node.get("max_rank", 0))
		if rank >= max_rank:
			next_rank_text = "MAX"
		else:
			next_rank_text = "Next Tier (Lvl. %d)" % TalentTree.required_level(node, rank)
	var element_index: CombatUnit.Element = -1
	if not is_passive and move != null:
		element_index = move.damage_element_type
	var element_color: Color = MenuTheme.ELEMENT_COLORS[element_index] if element_index != -1 else Color(0.6, 0.6, 0.4)

	var sections: Array = [
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": title, "color": TooltipTheme.TEXT_TITLE}]},
	]
	if not cost.is_empty():
		sections.append({"bg_color": TooltipTheme.BG_COST, "lines": [{"text": cost, "color": TooltipTheme.TEXT_SUBHEADER}]})
	if not description.is_empty():
		sections.append({"bg_color": TooltipTheme.BG_BODY, "lines": [{"text": description, "color": TooltipTheme.TEXT_BODY}]})
	if not next_rank_text.is_empty():
		sections.append({"bg_color": TooltipTheme.BG_NEXT_RANK, "lines": [{"text": next_rank_text, "color": TooltipTheme.TEXT_STAT}]})
	return {"sections": sections, "icon_color": element_color}
```

- [ ] **Step 4: Run the test again to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Retrofit `abilities_window.gd`**

Remove the field `@onready var _tooltip: AbilityTooltip = $AbilityTooltip`.

Change every `mouse_exited.connect(_tooltip.hide)` (3 call sites: inside
`_build_tree_panel()`, `_build_wheel_panel()`, and the pool-row loop in
`_ready()`) to `mouse_exited.connect(GameTooltip.hide_tooltip)`.

Replace `_on_tree_node_hovered()`:

```gdscript
func _on_tree_node_hovered(node_index: int) -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	var tree: Array = TalentTree.TREES.get(save.player_class, TalentTree.TREES[PlayerSave.PlayerClass.BIOLOGICAL])
	if node_index >= tree.size():
		return
	var node: Dictionary = tree[node_index].duplicate()
	node["_node_index"] = node_index
	var rank: int = TalentTree.get_rank(save, node_index)
	var move: Ability = null
	var buff: Buff = null
	if TalentTree.is_passive(node):
		if rank > 0:
			buff = BuffManagerAuto.get_buff_by_name(TalentTree.granted_buff_name(node, rank))
	else:
		move = MoveManagerAuto.get_move(TalentTree.granted_move_id(node, max(rank, 1)))
	var button: Button = _tree_buttons[node_index]
	var result: Dictionary = AbilityTooltipBuilder.build_sections(node, save, move, buff)
	var icon_path: String = "%s%s.png" % [ICON_DIR, _tree_node_icon_key(node)]
	var icon: Texture2D = load(icon_path) if ResourceLoader.exists(icon_path) else null
	GameTooltip.show_sections(result["sections"], button, icon, result["icon_color"])
```

Replace `_on_socket_hovered()`:

```gdscript
func _on_socket_hovered(socket_index: int) -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	var move_id: int = int(save.move_matrix[socket_index]) if socket_index < save.move_matrix.size() else 0
	if move_id == 0:
		return
	var move: Ability = MoveManagerAuto.get_move(move_id)
	if move == null:
		return
	var button: Button = _socket_buttons[socket_index]
	var result: Dictionary = AbilityTooltipBuilder.build_sections({}, save, move, null)
	var icon_path: String = "%s%s.png" % [ICON_DIR, _sanitize_icon_key(move.display_name)]
	var icon: Texture2D = load(icon_path) if ResourceLoader.exists(icon_path) else null
	GameTooltip.show_sections(result["sections"], button, icon, result["icon_color"])
```

Replace `_on_pool_row_hovered()`:

```gdscript
func _on_pool_row_hovered(row_index: int) -> void:
	var pool_index: int = _pool_scroll + row_index
	if pool_index >= _pool_move_ids.size():
		return
	var move: Ability = MoveManagerAuto.get_move(_pool_move_ids[pool_index])
	if move == null:
		return
	var save: PlayerSave = GameData.current_save
	var row: Button = _pool_rows[row_index]
	var result: Dictionary = AbilityTooltipBuilder.build_sections({}, save, move, null)
	var icon_path: String = "%s%s.png" % [ICON_DIR, _sanitize_icon_key(move.display_name)]
	var icon: Texture2D = load(icon_path) if ResourceLoader.exists(icon_path) else null
	GameTooltip.show_sections(result["sections"], row, icon, result["icon_color"])
```

- [ ] **Step 6: Remove the `AbilityTooltip` node and its ext_resource from the scene**

In `scenes/ui/menu/abilities_window.tscn`:
- Delete the `[ext_resource type="PackedScene" path="res://scenes/ui/menu/ability_tooltip.tscn" id="6_tooltip"]` line.
- Delete the `[node name="AbilityTooltip" parent="." instance=ExtResource("6_tooltip")]` block (its `layout_mode = 0` and `z_index = 100` lines go with it).
- Decrement the header's `load_steps` count by 1 (one fewer ext_resource).

- [ ] **Step 7: Delete the superseded `AbilityTooltip` files**

```bash
git rm scenes/ui/menu/ability_tooltip.tscn scenes/ui/menu/ability_tooltip.tscn.uid scripts/ui/menu/ability_tooltip.gd scripts/ui/menu/ability_tooltip.gd.uid
```

(Omit any `.uid` path that doesn't exist - `git rm` on a nonexistent path
just errors harmlessly; drop it from the command if so.)

- [ ] **Step 8: Grep for any other reference to the deleted files/class**

```bash
rg -n "ability_tooltip|AbilityTooltip\b" --glob '!*.md' .
```

Expected: only `AbilityTooltipBuilder` matches remain (a different class,
kept). If anything else references the deleted scene/script/class (for
example a project-wide scene-smoke-test that enumerates every `.tscn`),
update or remove that reference too.

- [ ] **Step 9: Run the abilities-screen test suite**

Run each of these (one `-gselect` per invocation):

```
/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gselect=test_ability_tooltip_builder.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gselect=test_ability_tooltip_fields.gd
```

Expected: both pass - `test_ability_tooltip_fields.gd` was never touched
and should be unaffected. Also run the project's scene-smoke test if
Step 8 found one touching `abilities_window.tscn`.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: abilities screen uses the shared rich tooltip, retire AbilityTooltip"
```

---

### Task 5: Battle-orb tooltip retrofit

**Files:**
- Modify: `scripts/battle/battle_scene.gd`
- Modify: `test/integration/test_battle_scene.gd`

**Interfaces:**
- Consumes: `TooltipTheme`'s constants, `GameTooltip.show_sections()` /
  `.hide_tooltip()` (Task 1).

- [ ] **Step 1: Update the one affected test first**

`test_radial_orb_tooltip_includes_the_moves_description` (added in the
prior battle-orb-fixes commit) currently reads `orb.tooltip_text`, which
this task removes. Replace it:

```gdscript
func test_radial_orb_tooltip_includes_the_moves_description():
	var save = PlayerSave.new_game("OrbDescTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	scene._player_action_pending = true
	scene._on_unit_clicked(2)  # battle 100's enemy slot (Prison Guard)

	var move: Ability = MoveManagerAuto.get_move(1)  # Leading Strike, battle 100's bar slot 0
	assert_false(move.tooltip_description.is_empty(), "sanity: the move actually has description text")
	var orb: Button = scene._radial_menu.get_child(0)
	orb.mouse_entered.emit()
	var texts: Array = []
	for section in GameTooltip._sections.get_children():
		for label in section.get_child(0).get_children():
			texts.append(label.text)
	assert_has(texts, move.tooltip_description, "the orb's tooltip carries the move's real description, not just name+cost")

	GameTooltip.hide_tooltip()
	GameData.current_save = null
	ZoneManager.auto_start_battles = true
```

The other 3 orb tests added in that commit
(`test_radial_orb_shows_the_moves_icon_art_not_initials`,
`test_radial_orb_position_is_keyed_by_bar_index_not_by_a_compacted_list_position`,
`test_radial_menu_still_opens_when_every_equipped_move_is_on_cooldown`)
don't touch `tooltip_text` - leave them exactly as they are.

- [ ] **Step 2: Run it to verify it fails**

Run:
`/Applications/Godot.app/Contents/MacOS/Godot --headless -s
res://addons/gut/gut_cmdln.gd --path . -gselect=test_battle_scene.gd
-gunit_test_name=test_radial_orb_tooltip_includes_the_moves_description`

Expected: FAIL - `orb.mouse_entered.emit()` doesn't show anything yet
(nothing is connected to it), so `GameTooltip._sections` stays empty.

- [ ] **Step 3: Retrofit `battle_scene.gd`**

In `_on_unit_clicked()`, replace this line:

```gdscript
		orb.tooltip_text = _move_tooltip(move)
```

with:

```gdscript
		var sections: Array = _move_tooltip_sections(move)
		orb.mouse_entered.connect(func(): GameTooltip.show_sections(sections, orb))
		orb.mouse_exited.connect(GameTooltip.hide_tooltip)
```

Replace the `_move_tooltip()` function with:

```gdscript
func _move_tooltip_sections(move: Ability) -> Array:
	var cost_line: String = "This move costs nothing"
	if move.focus_cost > 0:
		cost_line = "This move costs %d Focus" % int(move.focus_cost)
	var sections: Array = [
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": move.display_name, "color": TooltipTheme.TEXT_TITLE}]},
		{"bg_color": TooltipTheme.BG_COST, "lines": [{"text": cost_line, "color": TooltipTheme.TEXT_SUBHEADER}]},
	]
	var body_lines: Array = []
	if not move.tooltip_description.is_empty():
		body_lines.append({"text": move.tooltip_description, "color": TooltipTheme.TEXT_BODY})
	if move.cooldown_turns > 0:
		body_lines.append({"text": "Cooldown: %d turns" % move.cooldown_turns, "color": TooltipTheme.TEXT_BODY})
	if not body_lines.is_empty():
		sections.append({"bg_color": TooltipTheme.BG_BODY, "lines": body_lines})
	return sections
```

- [ ] **Step 4: Run the test again to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Run the full battle-scene suite**

Run:
`/Applications/Godot.app/Contents/MacOS/Godot --headless -s
res://addons/gut/gut_cmdln.gd --path . -gselect=test_battle_scene.gd`

Expected: all pass, including the 3 untouched orb tests from Step 1.

- [ ] **Step 6: Commit**

```bash
git add scripts/battle/battle_scene.gd test/integration/test_battle_scene.gd
git commit -m "feat: in-battle ability orbs use the shared rich tooltip"
```

---

### Task 6: Buff-icon tooltip retrofit

**Files:**
- Modify: `scripts/battle/unit_overlay.gd`
- Modify: `test/integration/test_unit_overlay.gd`

**Interfaces:**
- Consumes: `TooltipTheme`'s constants, `GameTooltip.show_sections()` /
  `.hide_tooltip()` (Task 1).

- [ ] **Step 1: Update the two affected tests first**

In `test/integration/test_unit_overlay.gd`, add an `after_each()` (the
file has none today) and update
`test_refresh_buffs_includes_buff_id_zero_and_sorts_by_duration_descending`,
which reads `tooltip_text` directly:

```gdscript
func after_each():
	GameTooltip.hide_tooltip()


func test_refresh_buffs_includes_buff_id_zero_and_sorts_by_duration_descending():
	# buff_id 0 is a real buff (TWINGUARDIANS, dev/converted_json/buffs.json) -
	# not an empty-slot sentinel (that's buff_id -1, see CombatUnit's slot
	# init) - so it must show up like any other active buff.
	var overlay: UnitOverlay = add_child_autofree(UnitOverlayScene.instantiate())
	var unit := CombatUnit.new()
	unit.buff_slots = [
		{"cd": 3, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0},   # FIRESAM, shorter
		{"cd": 7, "buff_id": 0, "buff_value": 0.0, "shield_buff_value": 0.0},   # TWINGUARDIANS, longer
		{"cd": 0, "buff_id": -1, "buff_value": 0.0, "shield_buff_value": 0.0},  # real empty-slot sentinel, skipped
	]
	var buff_twin: Buff = _make_buff("TWINGUARDIANS", "Twin Guardians", CombatUnit.Element.EARTH)
	var buff_fire: Buff = _make_buff("FIRESAM", "The Immortal Flame", CombatUnit.Element.FIRE)
	var buffs_by_id: Dictionary = {0: buff_twin, 1: buff_fire}

	overlay.refresh_buffs(unit, buffs_by_id)

	assert_eq(overlay.buff_row.get_child_count(), 2, "both real active buffs shown, the empty slot skipped")
	var first: TextureRect = overlay.buff_row.get_child(0)
	var second: TextureRect = overlay.buff_row.get_child(1)

	first.mouse_entered.emit()
	var first_title: Label = GameTooltip._sections.get_child(0).get_child(0).get_child(0)
	assert_string_contains(first_title.text, "Twin Guardians", "higher cd (7) sorts first")
	first.mouse_exited.emit()

	second.mouse_entered.emit()
	var second_title: Label = GameTooltip._sections.get_child(0).get_child(0).get_child(0)
	assert_string_contains(second_title.text, "The Immortal Flame", "lower cd (3) sorts second")
	second.mouse_exited.emit()
```

The other 3 tests in this file
(`test_refresh_buffs_caps_at_seven_icons`,
`test_refresh_buffs_skips_rebuild_when_state_is_unchanged`,
`test_refresh_buffs_clears_expired_buffs`) don't touch `tooltip_text` -
leave them as they are.

- [ ] **Step 2: Run it to verify it fails**

Run:
`/Applications/Godot.app/Contents/MacOS/Godot --headless -s
res://addons/gut/gut_cmdln.gd --path . -gselect=test_unit_overlay.gd
-gunit_test_name=test_refresh_buffs_includes_buff_id_zero_and_sorts_by_duration_descending`

Expected: FAIL - `GameTooltip._sections` is empty, `mouse_entered` isn't
wired to anything yet.

- [ ] **Step 3: Retrofit `unit_overlay.gd`**

In `refresh_buffs()`, replace this line:

```gdscript
		icon_rect.tooltip_text = "%s (%d turns)\n%s" % [buff.display_name, int(slot["cd"]), buff.tooltip_description]
```

with:

```gdscript
		var sections: Array = [
			{"bg_color": TooltipTheme.BG_HEADER, "lines": [{
				"text": "%s (%d turns)" % [buff.display_name, int(slot["cd"])],
				"color": TooltipTheme.TEXT_TITLE,
			}]},
		]
		if not buff.tooltip_description.is_empty():
			sections.append({"bg_color": TooltipTheme.BG_BODY, "lines": [{"text": buff.tooltip_description, "color": TooltipTheme.TEXT_BODY}]})
		icon_rect.mouse_entered.connect(func(): GameTooltip.show_sections(sections, icon_rect))
		icon_rect.mouse_exited.connect(GameTooltip.hide_tooltip)
```

- [ ] **Step 4: Run the test again to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Run the full unit-overlay suite**

Run:
`/Applications/Godot.app/Contents/MacOS/Godot --headless -s
res://addons/gut/gut_cmdln.gd --path . -gselect=test_unit_overlay.gd`

Expected: all 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/battle/unit_overlay.gd test/integration/test_unit_overlay.gd
git commit -m "feat: buff icons use the shared rich tooltip"
```

---

## Final Verification

After Task 6, run the whole suite once:

`/Applications/Godot.app/Contents/MacOS/Godot --headless -s
res://addons/gut/gut_cmdln.gd --path .`

Expected: every test passes, matching the count before this plan started
plus the tests this plan added (no test was deleted, only 2 were rewritten
in place - one in Task 4, one in Task 5, one in Task 6).
