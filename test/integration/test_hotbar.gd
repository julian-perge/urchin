# test_hotbar.gd
extends GutTest

const HotbarScene = preload("res://scenes/ui/hotbar.tscn")
const ICONS_PATH: String = "res://assets/ui/hotbar/hotbar_icons.json"
# Each slot with an icon, and the icon's name in hotbar_icons.json.
const ICON_SLOTS: Dictionary[String, String] = {
	"Inventory": "inventory",
	"Abilities": "abilities",
	"Save": "save",
	"Options": "options",
	"Respec": "respec",
	"Achievements": "achievements",
	"ZoneMap": "world_map",
}


func _icons_record() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ICONS_PATH))


# The seconds the hover clip takes to play from the first of `frames` to the last.
func _seconds(frames: Array) -> float:
	return (float(frames[1]) - float(frames[0])) / float(_icons_record()["hover"]["frame_rate"])


func after_each():
	GameTooltip.hide_tooltip()


func test_hover_shows_a_two_section_tooltip_for_inventory_button():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	var button: BaseButton = hotbar.get_node("%InventoryButton")
	button.mouse_entered.emit()
	assert_true(GameTooltip._root.visible)
	assert_eq(GameTooltip._sections.get_child_count(), 2, "title + body")
	button.mouse_exited.emit()
	assert_false(GameTooltip._root.visible)


func test_hover_shows_a_single_section_tooltip_for_a_coming_soon_button():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	var button: BaseButton = hotbar.get_node("%OptionsButton")
	button.mouse_entered.emit()
	assert_eq(GameTooltip._sections.get_child_count(), 1, "single-line caption, no body section")


func test_zone_map_and_quit_buttons_also_show_tooltips():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	for button_name in ["ZoneMapButton", "QuitButton"]:
		var button: BaseButton = hotbar.get_node("%" + button_name)
		button.mouse_entered.emit()
		assert_true(GameTooltip._root.visible, "%s shows a tooltip" % button_name)
		button.mouse_exited.emit()


func test_each_glow_draws_the_colors_of_the_extracted_record_outer_first():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	var icons: Dictionary = _icons_record()["icons"]
	for slot: String in ICON_SLOTS:
		var colors: Array = icons[ICON_SLOTS[slot]]["glow"]
		var layers: Array[Node] = hotbar.get_node(slot + "Slot/Glow").get_children()
		assert_eq(layers.size(), 2, "%s has a wide and a near layer" % slot)
		var wide: Color = (layers[0] as CanvasItem).modulate
		var near: Color = (layers[1] as CanvasItem).modulate
		assert_eq(wide.to_html(false), str(colors[colors.size() - 1]).trim_prefix("#"), "%s wide layer" % slot)
		assert_eq(near.to_html(false), str(colors[0]).trim_prefix("#"), "%s near layer" % slot)


func test_a_glow_layer_draws_its_icon_and_is_wider_than_it():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	var icon: TextureRect = hotbar.get_node("SaveSlot/Icon")
	var layers: Array[Node] = hotbar.get_node("SaveSlot/Glow").get_children()
	var wide: TextureRect = layers[0]
	var near: TextureRect = layers[1]
	assert_eq(wide.texture, icon.texture)
	assert_eq(near.texture, icon.texture)
	assert_gt(near.size.x, icon.size.x, "the near layer has room for its blur")
	assert_gt(wide.size.x, near.size.x, "the wide layer blurs further")
	assert_almost_eq(wide.global_position + wide.size / 2.0, icon.global_position + icon.size / 2.0, Vector2(0.01, 0.01))


func test_hover_fades_the_glow_in_over_the_start_frames_and_the_icon_stays_white():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	var glow: Control = hotbar.get_node("InventorySlot/Glow")
	var start: float = _seconds(_icons_record()["hover"]["start"])
	assert_eq(glow.modulate.a, 0.0, "no Glow before the hover")
	(hotbar.get_node("%InventoryButton") as BaseButton).mouse_entered.emit()
	var tween: Tween = hotbar.hover_tween("Inventory")
	tween.pause()
	tween.custom_step(start / 2.0)
	assert_almost_eq(glow.modulate.a, 0.5, 0.01, "half way through START")
	tween.custom_step(start / 2.0)
	assert_almost_eq(glow.modulate.a, 1.0, 0.001, "the end of START")
	assert_eq((hotbar.get_node("InventorySlot/Icon") as TextureRect).modulate, Color.WHITE)


func test_leaving_fades_the_glow_out_over_the_stop_frames():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	var glow: Control = hotbar.get_node("InventorySlot/Glow")
	var button: BaseButton = hotbar.get_node("%InventoryButton")
	var record: Dictionary = _icons_record()["hover"]
	button.mouse_entered.emit()
	var fade_in: Tween = hotbar.hover_tween("Inventory")
	fade_in.pause()
	fade_in.custom_step(_seconds(record["start"]))
	button.mouse_exited.emit()
	var fade_out: Tween = hotbar.hover_tween("Inventory")
	fade_out.pause()
	var stop: float = _seconds(record["stop"])
	fade_out.custom_step(stop / 2.0)
	assert_almost_eq(glow.modulate.a, 0.5, 0.01, "half way through STOP")
	fade_out.custom_step(stop / 2.0)
	assert_almost_eq(glow.modulate.a, 0.0, 0.001, "the end of STOP")


func test_quit_has_no_glow():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	assert_null(hotbar.get_node_or_null("QuitSlot/Glow"))
	assert_null(hotbar.hover_tween("Quit"))


func test_the_typed_hover_colors_are_gone():
	var constants: Dictionary = (load("res://scripts/ui/hotbar.gd") as Script).get_script_constant_map()
	assert_does_not_have(constants, "HOVER_COLORS")
	assert_does_not_have(constants, "ACTIVE_ICON_COLOR")
