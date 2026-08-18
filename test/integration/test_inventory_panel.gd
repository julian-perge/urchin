# InventoryPanel's sell button as a drag-drop target
# (.claude/plan_item_drag_and_drop.md Task 4) - hovering an item over it
# during a drag previews the sell price in its tooltip; dropping sells it
# through the same sell_pressed signal the button click already uses.
extends GutTest

const InventoryPanelScene = preload("res://scenes/ui/inventory.tscn")


func _make_item(price: float) -> GameItem:
	var item: GameItem = ItemManagerAuto.items_by_id.values()[0]
	# Real items have real (varied) prices - pin one down so the expected
	# sell price is a fixed, readable number instead of whatever that
	# particular item happens to cost.
	item = item.duplicate()
	item.price = price
	return item


func test_can_drop_data_over_sell_button_previews_price_and_accepts():
	var panel: InventoryPanel = add_child_autofree(InventoryPanelScene.instantiate())
	var item: GameItem = _make_item(100.0)
	var at_position: Vector2 = panel.sell_button.get_rect().get_center()
	assert_true(panel._can_drop_data(at_position, {"item": item}))
	assert_eq(panel.sell_button.tooltip_text, "Sell for €15", "15%% of 100, rounded up")


func test_can_drop_data_outside_sell_button_rejects_and_leaves_tooltip():
	var panel: InventoryPanel = add_child_autofree(InventoryPanelScene.instantiate())
	var item: GameItem = _make_item(100.0)
	var default_tooltip: String = panel.sell_button.tooltip_text
	assert_false(panel._can_drop_data(Vector2(-500, -500), {"item": item}))
	assert_eq(panel.sell_button.tooltip_text, default_tooltip, "unchanged when not over the button")


func test_drop_data_on_sell_button_emits_sell_pressed_and_resets_tooltip():
	var panel: InventoryPanel = add_child_autofree(InventoryPanelScene.instantiate())
	var item: GameItem = _make_item(100.0)
	var default_tooltip: String = panel.sell_button.tooltip_text
	var at_position: Vector2 = panel.sell_button.get_rect().get_center()
	watch_signals(panel)
	panel._can_drop_data(at_position, {"item": item})  # the real drag flow always previews first
	panel._drop_data(at_position, {"item": item})
	assert_signal_emitted_with_parameters(panel, "sell_pressed", [item])
	assert_eq(panel.sell_button.tooltip_text, default_tooltip, "restored after a completed sell")


func test_drag_end_notification_resets_tooltip():
	var panel: InventoryPanel = add_child_autofree(InventoryPanelScene.instantiate())
	var item: GameItem = _make_item(100.0)
	var default_tooltip: String = panel.sell_button.tooltip_text
	panel._can_drop_data(panel.sell_button.get_rect().get_center(), {"item": item})
	assert_ne(panel.sell_button.tooltip_text, default_tooltip, "price preview showing mid-drag")
	panel._notification(NOTIFICATION_DRAG_END)
	assert_eq(panel.sell_button.tooltip_text, default_tooltip, "restored on a cancelled drag")
