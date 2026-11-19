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
# The MENU strings of the delete slot's tooltip (DefineButton2_2858 on(rollOver),
# lines 5-6) and the sell slot's (DefineButton2_3015 on(rollOver), lines 5-13).
const DELETE_TITLE: int = 1
const DELETE_BODY: int = 2
const SELL_TITLE: int = 3
const SELL_FOR: int = 4
const SELL_EMPTY: int = 5
const SLOTS_PER_ROW: int = 6
var selected_slot: ItemSlot = null
# The 36 slots in grid order, row by row.
var slots: Array[ItemSlot] = []

@onready var amount_label: Label = $Amount
@onready var sell_button: Button = $SellSlot
@onready var delete_button: Button = $DeleteSlot
# Whether the sell slot's tooltip shows, and the item whose price it names.
var _sell_tooltip_shown: bool = false
var _sell_tooltip_item: GameItem = null


func _ready() -> void:
	$Title.text = Strings.menu(14)
	sell_button.mouse_entered.connect(func(): _show_sell_tooltip(_held_item()))
	sell_button.mouse_exited.connect(_hide_sell_tooltip)
	delete_button.mouse_entered.connect(func():
		GameTooltip.show_title_and_body(Strings.menu(DELETE_TITLE), Strings.menu(DELETE_BODY), delete_button))
	delete_button.mouse_exited.connect(GameTooltip.hide_tooltip)
	for row: Node in $Grid.get_children():
		for column in SLOTS_PER_ROW:
			var slot: ItemSlot = ItemSlotScene.instantiate()
			slot.name = "Slot%d" % column
			slot.slot_clicked.connect(_on_slot_clicked)
			# ItemSlot's drag and drop reads these to know where a drag came
			# from. A slot never moves, so they are set once here.
			slot.set_meta("drag_source", "inventory")
			slot.set_meta("drag_index", slots.size())
			# A backpack cell shows item 0's tooltip when empty, as the
			# original's cell 2985 does.
			slot.shows_empty_item = true
			row.add_child(slot)
			slots.append(slot)


func _on_sell_pressed() -> void:
	if selected_slot != null and selected_slot.item != null:
		sell_pressed.emit(selected_slot.item)
		if _sell_tooltip_shown:
			_show_sell_tooltip(_held_item())


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
# The sell slot is hidden until the Store shows it. A hidden slot keeps its
# rect, so without the visibility check a drop there would still sell the item.
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not data.get("item"):
		return false
	if not _over_shown_sell_slot(at_position):
		return false
	var item: GameItem = data["item"]
	if not _sell_tooltip_shown or _sell_tooltip_item != item:
		_show_sell_tooltip(item)
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _over_shown_sell_slot(at_position):
		return
	var item: GameItem = data.get("item")
	if item == null:
		return
	sell_pressed.emit(item)
	# The original's sell press empties the mouse and sets the body to MENU[5]
	# while the pointer stays on the slot (DefineButton2_3015 on(press)).
	_show_sell_tooltip(null)


func _over_shown_sell_slot(at_position: Vector2) -> bool:
	return sell_button.visible and sell_button.get_rect().has_point(at_position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _sell_tooltip_item != null:
		_hide_sell_tooltip()


# The original's sell tooltip names the price of the item on the mouse,
# Krin.mouseItem. The port's nearest match is the item being dragged, or else
# the selected item, because a click on the sell slot sells the selected item.
func _held_item() -> GameItem:
	if is_inside_tree() and get_viewport().gui_is_dragging():
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary and data.get("item") is GameItem:
			return data["item"]
	if selected_slot != null:
		return selected_slot.item
	return null


func _show_sell_tooltip(item: GameItem) -> void:
	var body: String = Strings.menu(SELL_EMPTY)
	if item != null:
		body = "%s €%d" % [Strings.menu(SELL_FOR), GameData.sell_price(item)]
	GameTooltip.show_title_and_body(Strings.menu(SELL_TITLE), body, sell_button)
	_sell_tooltip_shown = true
	_sell_tooltip_item = item


func _hide_sell_tooltip() -> void:
	_sell_tooltip_shown = false
	_sell_tooltip_item = null
	GameTooltip.hide_tooltip()
