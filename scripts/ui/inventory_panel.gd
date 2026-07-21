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

const ItemSlotScene: PackedScene = preload("res://scenes/ui/item_slot.tscn")
const GRID_SLOTS: int = 36

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
	var index: int = 0
	for child in inventory_grid.get_children():
		if child is ItemSlot:
			child.set_item(items[index] if index < items.size() else null)
			child.set_selected(false)
			index += 1
	selected_slot = null


# Index-preserving fill straight from the save: slot i <- item_array[i].
# Each slot's "save_index" metadata points back at its item_array cell.
func populate_from_save(save: PlayerSave, items_by_id: Dictionary) -> void:
	var slots: Array[Node] = inventory_grid.get_children()
	for i in slots.size():
		var slot: Node = slots[i]
		if not slot is ItemSlot:
			continue
		slot.set_meta("save_index", i)
		var item_id: int = int(save.item_array[i]) if i < save.item_array.size() else 0
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
