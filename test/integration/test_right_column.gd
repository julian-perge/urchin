# RightColumn (spec/107-window-shell.md): the sell slot as a drop target, the
# money bar's two Labels, the grid, and the Inventory and Victory hosts.
# test_store_window.gd checks the Store host.
# Over the sell slot, a dragged item shows its price in the shared tooltip, and
# a drop sells it through sell_pressed, as a click does.
extends GutTest

const RightColumnScene = preload("res://scenes/ui/window/right_column.tscn")
const InventoryWindowScene = preload("res://scenes/ui/menu/inventory_window.tscn")


func after_each():
	GameData.current_save = null
	GameTooltip.hide_tooltip()


func _make_item(price: float) -> GameItem:
	var item: GameItem = ItemManagerAuto.items_by_id.values()[0]
	# Real items have real (varied) prices - pin one down so the expected
	# sell price is a fixed, readable number instead of whatever that
	# particular item happens to cost.
	item = item.duplicate()
	item.price = price
	return item


func _menu(index: int) -> String:
	var strings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://dev/converted_json/strings.json"))
	return strings["MENU"][index]


func _tooltip_texts() -> Array:
	var texts: Array = []
	for section in GameTooltip._sections.get_children():
		for label in section.get_child(0).get_children():
			texts.append(label.text)
	return texts


# DefineButton2_3015 on(rollOver): MENU[3] over MENU[4] + " €" + the price,
# which is Math.ceil(KRINITEM[5] * 0.15).
func test_can_drop_data_over_sell_button_previews_price_and_accepts():
	var panel: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	panel.show_sell_button(true)
	var item: GameItem = _make_item(100.0)
	var at_position: Vector2 = panel.sell_button.get_rect().get_center()
	assert_true(panel._can_drop_data(at_position, {"item": item}))
	assert_eq(_tooltip_texts(), [_menu(3), _menu(4) + " €15"], "15%% of 100, rounded up")


func test_can_drop_data_outside_sell_button_rejects_and_shows_no_tooltip():
	var panel: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	var item: GameItem = _make_item(100.0)
	assert_false(panel._can_drop_data(Vector2(-500, -500), {"item": item}))
	assert_false(GameTooltip._root.visible, "no tooltip when not over the button")


# The original's sell press empties the mouse and sets the body to MENU[5]
# (DefineButton2_3015 on(press)).
func test_drop_data_on_sell_button_emits_sell_pressed_and_shows_the_empty_text():
	var panel: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	panel.show_sell_button(true)
	var item: GameItem = _make_item(100.0)
	var at_position: Vector2 = panel.sell_button.get_rect().get_center()
	watch_signals(panel)
	panel._can_drop_data(at_position, {"item": item})  # the real drag flow always previews first
	panel._drop_data(at_position, {"item": item})
	assert_signal_emitted_with_parameters(panel, "sell_pressed", [item])
	assert_eq(_tooltip_texts(), [_menu(3), _menu(5)], "the body goes back to MENU[5] after a sale")


func test_drag_end_notification_hides_the_price_preview():
	var panel: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	panel.show_sell_button(true)
	var item: GameItem = _make_item(100.0)
	panel._can_drop_data(panel.sell_button.get_rect().get_center(), {"item": item})
	assert_true(GameTooltip._root.visible, "price preview showing mid-drag")
	panel._notification(NOTIFICATION_DRAG_END)
	assert_false(GameTooltip._root.visible, "hidden on a cancelled drag")


# The character is the one extract_screen_rects read from edit text 2861, so the
# test does not type it.
func _euro_sign_in_the_swf() -> String:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/screen_rects.json"))
	return record["scenes"]["res://scenes/ui/window/right_column.tscn"]["pieces"]["EuroSign"]["text"]


# The SWF draws the euro sign and the amount as two fields, 2861 and 2862, and
# sets the amount to a plain number (DefineSprite_3142/frame_1/DoAction.as:267).
func test_the_euro_sign_and_the_amount_are_two_labels_and_the_amount_has_no_commas():
	var column: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	column.set_gold(1234567.0)
	assert_eq((column.get_node("EuroSign") as Label).text, _euro_sign_in_the_swf(), "the SWF's own character, from the rect record")
	assert_eq(column.amount_label, column.get_node("Amount"))
	assert_eq(column.amount_label.text, "1234567")
	column.set_gold(0.0)
	assert_eq(column.amount_label.text, "0")


func test_show_sell_button_shows_and_hides_the_sell_slot():
	var column: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	assert_false(column.sell_button.visible, "hidden until a host shows it")
	column.show_sell_button(true)
	assert_true(column.sell_button.visible)
	column.show_sell_button(false)
	assert_false(column.sell_button.visible)
	column.show_sell_button(true)
	assert_true(column.sell_button.visible)


func test_a_hidden_sell_slot_refuses_a_drop_and_sells_nothing():
	var column: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	var item: GameItem = _make_item(100.0)
	var at_position: Vector2 = column.sell_button.get_rect().get_center()
	column.show_sell_button(false)
	watch_signals(column)
	assert_false(column._can_drop_data(at_position, {"item": item}))
	column._drop_data(at_position, {"item": item})
	assert_signal_not_emitted(column, "sell_pressed")
	assert_false(GameTooltip._root.visible, "a hidden sell slot shows no price")


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


# KRINMENU's inventory frame does not place the sell slot (depth 1281). Only
# the shop frame does (spec/107-window-shell.md, RightColumn).
func test_the_inventory_window_hides_the_sell_slot_and_refuses_a_drop_on_it():
	var made: Array = _window_with_item_in_slot_0()
	var column: RightColumn = made[0].right_column
	assert_false(column.sell_button.visible)
	var at_position: Vector2 = column.sell_button.get_rect().get_center()
	assert_false(column._can_drop_data(at_position, {"item": made[1]}))


# The delete slot reaches the window through the [connection] lines in
# right_column.tscn and inventory_window.tscn.
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
	var slots: Array[Node] = window.find_children("*", "ItemSlot", true, false)
	var grid_slots: Array[Node] = slots.filter(func(slot: Node) -> bool: return slot.get_meta("drag_source", "") == "inventory")
	assert_eq(grid_slots.size(), 36, "the window adds no grid slot of its own")


func _right_column_rect() -> Array:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/screen_rects.json"))
	return record["scenes"]["res://scenes/ui/window/right_column.tscn"]["pieces"]["TallPanel"]["rect"]


# The win frame shows the right column with no sell slot.
func test_the_victory_window_instances_the_right_column_with_the_sell_slot_hidden():
	var victory: Control = add_child_autofree(load("res://scenes/ui/menu/victory_window.tscn").instantiate())
	await wait_process_frames(2)
	var columns: Array[Node] = victory.find_children("*", "RightColumn", true, false)
	assert_eq(columns.size(), 1)
	assert_eq(victory.right_column, columns[0])
	assert_eq(victory.right_column.owner, victory, "the column is a node of victory_window.tscn")
	assert_false(victory.right_column.sell_button.visible)
	var rect: Array = _right_column_rect()
	assert_almost_eq(victory.right_column.global_position, Vector2(rect[0], rect[1]), Vector2(0.5, 0.5))
