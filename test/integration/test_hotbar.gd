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
