# RightColumn (spec/107-window-shell.md): the sell slot as a drop target, the
# money bar's two Labels, the grid, and the Inventory window that hosts it.
# Over the sell slot, a dragged item shows its price in the slot's tooltip, and
# a drop sells it through sell_pressed, as a click does.
extends GutTest

const RightColumnScene = preload("res://scenes/ui/window/right_column.tscn")
const InventoryWindowScene = preload("res://scenes/ui/menu/inventory_window.tscn")


func after_each():
	GameData.current_save = null


func _make_item(price: float) -> GameItem:
	var item: GameItem = ItemManagerAuto.items_by_id.values()[0]
	# Real items have real (varied) prices - pin one down so the expected
	# sell price is a fixed, readable number instead of whatever that
	# particular item happens to cost.
	item = item.duplicate()
	item.price = price
	return item


func test_can_drop_data_over_sell_button_previews_price_and_accepts():
	var panel: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	var item: GameItem = _make_item(100.0)
	var at_position: Vector2 = panel.sell_button.get_rect().get_center()
	assert_true(panel._can_drop_data(at_position, {"item": item}))
	assert_eq(panel.sell_button.tooltip_text, "Sell for €15", "15%% of 100, rounded up")


func test_can_drop_data_outside_sell_button_rejects_and_leaves_tooltip():
	var panel: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	var item: GameItem = _make_item(100.0)
	var default_tooltip: String = panel.sell_button.tooltip_text
	assert_false(panel._can_drop_data(Vector2(-500, -500), {"item": item}))
	assert_eq(panel.sell_button.tooltip_text, default_tooltip, "unchanged when not over the button")


func test_drop_data_on_sell_button_emits_sell_pressed_and_resets_tooltip():
	var panel: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	var item: GameItem = _make_item(100.0)
	var default_tooltip: String = panel.sell_button.tooltip_text
	var at_position: Vector2 = panel.sell_button.get_rect().get_center()
	watch_signals(panel)
	panel._can_drop_data(at_position, {"item": item})  # the real drag flow always previews first
	panel._drop_data(at_position, {"item": item})
	assert_signal_emitted_with_parameters(panel, "sell_pressed", [item])
	assert_eq(panel.sell_button.tooltip_text, default_tooltip, "restored after a completed sell")


func test_drag_end_notification_resets_tooltip():
	var panel: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	var item: GameItem = _make_item(100.0)
	var default_tooltip: String = panel.sell_button.tooltip_text
	panel._can_drop_data(panel.sell_button.get_rect().get_center(), {"item": item})
	assert_ne(panel.sell_button.tooltip_text, default_tooltip, "price preview showing mid-drag")
	panel._notification(NOTIFICATION_DRAG_END)
	assert_eq(panel.sell_button.tooltip_text, default_tooltip, "restored on a cancelled drag")


# The SWF draws the euro sign and the amount as two fields, 2861 and 2862, and
# sets the amount to a plain number (DefineSprite_3142/frame_1/DoAction.as:267).
func test_the_euro_sign_and_the_amount_are_two_labels_and_the_amount_has_no_commas():
	var column: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	column.set_gold(1234567.0)
	assert_eq((column.get_node("EuroSign") as Label).text, "€")
	assert_eq(column.amount_label, column.get_node("Amount"))
	assert_eq(column.amount_label.text, "1234567")
	column.set_gold(0.0)
	assert_eq(column.amount_label.text, "0")


func test_show_sell_button_shows_and_hides_the_sell_slot():
	var column: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	column.show_sell_button(false)
	assert_false(column.sell_button.visible)
	column.show_sell_button(true)
	assert_true(column.sell_button.visible)


func test_the_grid_holds_36_slots_in_save_order():
	var column: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	assert_eq(column.slots.size(), 36)
	assert_eq(column.slots[7], column.get_node("Grid/Row1/Slot1"), "slot 7 is row 1, column 1")
	assert_eq(int(column.slots[35].get_meta("drag_index")), 35)


func test_the_title_reads_menu_14():
	var column: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	assert_eq((column.get_node("Title") as Label).text, Strings.menu(14))
	assert_ne(Strings.menu(14), "")


func test_populate_fills_the_slots_in_order_and_clears_the_selection():
	var column: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	var item: GameItem = _make_item(10.0)
	column.populate([item])
	assert_eq(column.slots[0].item, item)
	assert_null(column.slots[1].item)
	column._on_slot_clicked(column.slots[0])
	assert_true(column.slots[0].selected)
	column.populate([item])
	assert_null(column.selected_slot)
	assert_false(column.slots[0].selected)


# test_screen_rects.gd checks right_column.tscn on its own, so this test checks
# that the Inventory window does not move it.
func test_the_inventory_window_puts_the_right_column_where_the_swf_does():
	var window: Control = add_child_autofree(InventoryWindowScene.instantiate())
	await wait_process_frames(2)
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/screen_rects.json"))
	var rect: Array = record["scenes"]["res://scenes/ui/window/right_column.tscn"]["pieces"]["TallPanel"]["rect"]
	assert_almost_eq(window.right_column.global_position, Vector2(rect[0], rect[1]), Vector2(0.5, 0.5))


func _window_with_item_in_slot_0() -> Array:
	GameData.current_save = PlayerSave.new_game("InventoryTest", 0)
	var item: GameItem = null
	for candidate: GameItem in ItemManagerAuto.items_by_id.values():
		if candidate.price > 0.0:
			item = candidate
			break
	GameData.current_save.item_array[0] = item.id
	var window: Control = add_child_autofree(InventoryWindowScene.instantiate())
	window.refresh()
	window.right_column.selected_slot = window.right_column.slots[0]
	return [window, item]


# The sell and delete slots reach the window through the [connection] lines in
# right_column.tscn and inventory_window.tscn.
func test_the_sell_slot_sells_the_selected_item_through_the_window():
	var made: Array = _window_with_item_in_slot_0()
	var item: GameItem = made[1]
	var euro_before: float = GameData.current_save.euro
	made[0].right_column.sell_button.pressed.emit()
	assert_eq(int(GameData.current_save.item_array[0]), 0)
	assert_eq(GameData.current_save.euro, euro_before + ceil(item.price * 0.15))


func test_the_delete_slot_destroys_the_selected_item_through_the_window():
	var made: Array = _window_with_item_in_slot_0()
	var euro_before: float = GameData.current_save.euro
	made[0].right_column.delete_button.pressed.emit()
	assert_eq(int(GameData.current_save.item_array[0]), 0)
	assert_eq(GameData.current_save.euro, euro_before)


func test_the_inventory_window_instances_the_right_column_and_no_copy_of_it():
	var window: Control = add_child_autofree(InventoryWindowScene.instantiate())
	var columns: Array[Node] = window.find_children("*", "RightColumn", true, false)
	assert_eq(columns.size(), 1)
	assert_eq(window.right_column, columns[0])
	assert_eq(window.find_children("*", "InventoryPanel", true, false), [] as Array[Node])
	var slots: Array[Node] = window.find_children("*", "ItemSlot", true, false)
	var grid_slots: Array[Node] = slots.filter(func(slot: Node) -> bool: return slot.get_meta("drag_source", "") == "inventory")
	assert_eq(grid_slots.size(), 36, "the window adds no grid slot of its own")
