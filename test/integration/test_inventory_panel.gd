# RightColumn (spec/107-window-shell.md): the sell slot as a drop target, the
# money bar's two Labels, the grid, and the Inventory window that hosts it.
# Over the sell slot, a dragged item shows its price in the slot's tooltip, and
# a drop sells it through sell_pressed, as a click does.
extends GutTest

const RightColumnScene = preload("res://scenes/ui/window/right_column.tscn")


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


func test_the_inventory_window_instances_the_right_column_and_no_copy_of_it():
	var window: Control = add_child_autofree(load("res://scenes/ui/menu/inventory_window.tscn").instantiate())
	var columns: Array[Node] = window.find_children("*", "RightColumn", true, false)
	assert_eq(columns.size(), 1)
	assert_eq(window.right_column, columns[0])
	assert_eq(window.find_children("*", "InventoryPanel", true, false), [] as Array[Node])
	var slots: Array[Node] = window.find_children("*", "ItemSlot", true, false)
	var grid_slots: Array[Node] = slots.filter(func(slot: Node) -> bool: return slot.get_meta("drag_source", "") == "inventory")
	assert_eq(grid_slots.size(), 36, "the window adds no grid slot of its own")
