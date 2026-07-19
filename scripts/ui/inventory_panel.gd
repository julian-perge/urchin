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

const PANEL_RECT = Rect2(0, 0, 249.1, 267.1)
const BAR_RECT = Rect2(0, 276.6, 249.1, 50.9)
const GRID_POSITION = Vector2(14.1, 31.1)
const GRID_COLUMNS = 6
const GRID_SLOTS = 36

var inventory_grid: Control
var gold_label: Label
var sell_button: Button
var delete_button: Button

var selected_slot: ItemSlot = null


func _ready():
	custom_minimum_size = Vector2(249.1, 327.5)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuTheme.add_texture_rect(self, "panel_large.png", PANEL_RECT)
	MenuTheme.add_label(
		self, "Your Inventory", Rect2(10, 6, 229, 20), 14,
		Color(0.55, 0.55, 0.55), HORIZONTAL_ALIGNMENT_CENTER
	)
	inventory_grid = Control.new()
	inventory_grid.name = "InventoryGrid"
	inventory_grid.position = GRID_POSITION
	inventory_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inventory_grid)
	for i in GRID_SLOTS:
		var slot: ItemSlot = ItemSlotScene.instantiate()
		slot.position = Vector2(
			(i % GRID_COLUMNS) * MenuTheme.SLOT_STEP,
			floorf(i / float(GRID_COLUMNS)) * MenuTheme.SLOT_STEP
		)
		slot.slot_clicked.connect(_on_slot_clicked)
		inventory_grid.add_child(slot)

	MenuTheme.add_texture_rect(self, "panel_bar.png", BAR_RECT)
	gold_label = MenuTheme.add_label(
		self, "", Rect2(14, 285, 130, 34), 20, Color(1, 0.8, 0)
	)
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sell_button = _add_icon_button("button_sell.png", Vector2(150.6, 287))
	sell_button.name = "SellItemButton"
	sell_button.tooltip_text = "Sell Item\nSelect an item, then click here to sell it for 15% of its price."
	sell_button.pressed.connect(_on_sell_pressed)
	delete_button = _add_icon_button("button_delete.png", Vector2(204.1, 287))
	delete_button.name = "DeleteItemButton"
	delete_button.tooltip_text = "Destroy Item\nSelect an item, then click here to destroy it permanently."
	delete_button.pressed.connect(_on_delete_pressed)


# Icon buttons hover with a white border, like the source's sell/delete
# buttons (references: *_with_tooltip_and_white_corners.png).
func _add_icon_button(art: String, at: Vector2) -> Button:
	var button = Button.new()
	button.icon = MenuTheme.texture(art)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 31)
	button.position = at
	button.custom_minimum_size = MenuTheme.SLOT_SIZE
	button.size = MenuTheme.SLOT_SIZE
	var empty = StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("pressed", empty)
	var hover = StyleBoxFlat.new()
	hover.draw_center = false
	hover.set_border_width_all(2)
	hover.border_color = Color.WHITE
	button.add_theme_stylebox_override("hover", hover)
	add_child(button)
	return button


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
