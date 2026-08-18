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
# Carries the item itself, not the slot - a drag-to-sell-button drop (see
# _drop_data() below) has no ItemSlot to point at when the drag came from
# the equip doll, only the item. Both the button click and the drag drop
# go through this one signal, so whichever host owns this panel only needs
# one place (its own _on_sell_pressed) to react - store_window.gd's also
# calls refresh_store() after, which this panel has no business knowing
# about, hence the signal instead of calling GameData.sell_item() directly.
signal sell_pressed(item: GameItem)
signal delete_pressed(slot: ItemSlot)

const ItemSlotScene: PackedScene = preload("res://scenes/ui/item_slot.tscn")
const GRID_SLOTS: int = 36
# Mirrors inventory.tscn's own SellItemButton.tooltip_text default - restored
# after a drag-to-sell preview (_can_drop_data below) or a cancelled drag.
const _DEFAULT_SELL_TOOLTIP: String = "Sell Item\nSelect an item, then click here to sell it for 15% of its price."

@onready var inventory_grid: GridContainer = $InventoryGrid
@onready var gold_label: Label = $GoldLabel
@onready var sell_button: Button = $SellItemButton
@onready var delete_button: Button = $DeleteItemButton

var selected_slot: ItemSlot = null


func _ready():
	for i in GRID_SLOTS:
		var slot: ItemSlot = ItemSlotScene.instantiate()
		slot.slot_clicked.connect(_on_slot_clicked)
		# Drag source/target identity (ItemSlot._get_drag_data/_drop_data) -
		# grid position never changes once instantiated, so this is set
		# once here rather than repeated every populate_from_save() alongside
		# the equivalent save_index meta.
		slot.set_meta("drag_source", "inventory")
		slot.set_meta("drag_index", i)
		inventory_grid.add_child(slot)


func _on_sell_pressed() -> void:
	if selected_slot != null and selected_slot.item != null:
		sell_pressed.emit(selected_slot.item)


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


# Sell button as a drag-drop target (this panel's own mouse_filter is PASS,
# not IGNORE, so it - not just its child slots - can be asked). Hovering an
# item over the sell button previews the price in its tooltip; dropping
# sells it through the same sell_pressed signal the button click uses, so
# whichever host owns this panel reacts identically either way (see
# sell_pressed's own comment above for why this isn't a direct
# GameData.sell_item() call).
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not data.get("item"):
		return false
	if not sell_button.get_rect().has_point(at_position):
		return false
	var item: GameItem = data["item"]
	sell_button.tooltip_text = "Sell for €%d" % int(ceil(item.price * 0.15))
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not sell_button.get_rect().has_point(at_position):
		return
	var item: GameItem = data.get("item")
	if item == null:
		return
	sell_pressed.emit(item)
	sell_button.tooltip_text = _DEFAULT_SELL_TOOLTIP


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		sell_button.tooltip_text = _DEFAULT_SELL_TOOLTIP
