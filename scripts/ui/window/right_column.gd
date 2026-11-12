# The right column that the Inventory, Store and Victory Windows share
# (spec/107-window-shell.md, RightColumn): the "Your Inventory" Panel with 36
# item slots, and the money bar with the euro sign, the amount, and the sell
# and delete slots. right_column.tscn places the root at the Panel's top left
# on the Stage, and test_screen_rects.gd checks every piece against the SWF.
#
# Slot i shows PlayerSave.item_array[i], so an item keeps its grid cell as in
# the original. populate() fills the slots from a compact list instead.
class_name RightColumn
extends Control

signal item_selected(slot: ItemSlot)
# This signal carries the item and not the slot, because a drag from the equip
# doll onto the sell slot (_drop_data below) has no ItemSlot. The click and the
# drop both emit it, and the host reacts in one place. The store host also
# refreshes its wares after a sale, which this column does not know about.
signal sell_pressed(item: GameItem)
signal delete_pressed(slot: ItemSlot)

const ItemSlotScene: PackedScene = preload("res://scenes/ui/item_slot.tscn")
const SLOTS_PER_ROW: int = 6
var selected_slot: ItemSlot = null
# The 36 slots in grid order, row by row.
var slots: Array[ItemSlot] = []

@onready var amount_label: Label = $Amount
@onready var sell_button: Button = $SellSlot
@onready var delete_button: Button = $DeleteSlot
# _can_drop_data shows a price in the sell slot's tooltip during a drag. This
# is the tooltip that right_column.tscn gives the slot, which a sale or the end
# of the drag puts back.
@onready var _default_sell_tooltip: String = sell_button.tooltip_text


func _ready() -> void:
	$Title.text = Strings.menu(14)
	for row: Node in $Grid.get_children():
		for column in SLOTS_PER_ROW:
			var slot: ItemSlot = ItemSlotScene.instantiate()
			slot.name = "Slot%d" % column
			slot.slot_clicked.connect(_on_slot_clicked)
			# ItemSlot's drag and drop reads these to know where a drag came
			# from. A slot never moves, so they are set once here.
			slot.set_meta("drag_source", "inventory")
			slot.set_meta("drag_index", slots.size())
			row.add_child(slot)
			slots.append(slot)


func _on_sell_pressed() -> void:
	if selected_slot != null and selected_slot.item != null:
		sell_pressed.emit(selected_slot.item)


func _on_delete_pressed() -> void:
	if selected_slot != null and selected_slot.item != null:
		delete_pressed.emit(selected_slot)


# Fills the slots in order with the given items and clears the rest.
func populate(items: Array) -> void:
	for i in slots.size():
		slots[i].set_item(items[i] if i < items.size() else null)
		slots[i].set_selected(false)
	selected_slot = null


# Fills slot i from item_array[i]. Each slot's "save_index" meta points back at
# its item_array cell.
func populate_from_save(save: PlayerSave, items_by_id: Dictionary) -> void:
	for i in slots.size():
		var slot: ItemSlot = slots[i]
		slot.set_meta("save_index", i)
		var item_id: int = int(save.item_array[i]) if i < save.item_array.size() else 0
		slot.set_item(items_by_id.get(item_id) if item_id != 0 else null)
		slot.set_selected(false)
	selected_slot = null


# The original shows the amount as a plain number with no thousands separators
# (DefineSprite_3142/frame_1/DoAction.as:267).
func set_gold(amount: float) -> void:
	amount_label.text = str(int(amount))


func show_sell_button(value: bool) -> void:
	sell_button.visible = value


func _on_slot_clicked(slot: ItemSlot) -> void:
	if selected_slot != null:
		selected_slot.set_selected(false)
	selected_slot = slot if slot.item != null else null
	if selected_slot != null:
		selected_slot.set_selected(true)
		item_selected.emit(selected_slot)


# The sell slot is a drop target. The root's mouse_filter is PASS, so Godot
# asks the root too. Over the sell slot, a dragged item shows its sale price in
# the slot's tooltip, and a drop sells it through sell_pressed, as a click does.
# A hidden sell slot keeps its rect, so a host that hides it would still sell
# on a drop there without the visibility check.
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not data.get("item"):
		return false
	if not _over_shown_sell_slot(at_position):
		return false
	var item: GameItem = data["item"]
	sell_button.tooltip_text = "Sell for €%d" % int(ceil(item.price * 0.15))
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _over_shown_sell_slot(at_position):
		return
	var item: GameItem = data.get("item")
	if item == null:
		return
	sell_pressed.emit(item)
	sell_button.tooltip_text = _default_sell_tooltip


func _over_shown_sell_slot(at_position: Vector2) -> bool:
	return sell_button.visible and sell_button.get_rect().has_point(at_position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		sell_button.tooltip_text = _default_sell_tooltip
