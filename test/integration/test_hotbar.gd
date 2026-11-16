# test_hotbar.gd - GameTooltip wiring and the icon hover for the bottom hotbar.
extends GutTest

const HotbarScene = preload("res://scenes/ui/hotbar.tscn")
const OrbScene = preload("res://scenes/orb.tscn")
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


# The Glows of `slot` on frame `frame` of its hover clip, from the record.
func _glows(slot: String, frame: int) -> Array:
	return _icons_record()["icons"][ICON_SLOTS[slot]]["frames"][frame - 1]


# The layer that draws Glow `index` of `slot`: the one over the icon for an
# inner Glow, and the one under it for an outer Glow.
func _layer(hotbar: Control, slot: String, index: int, inner: bool) -> TextureRect:
	return hotbar.get_node(slot + ("Slot/InnerGlow" if inner else "Slot/Glow")).get_child(index)


func _visible_layers(hotbar: Control, slot: String) -> int:
	var count: int = 0
	for holder: String in ["Glow", "InnerGlow"]:
		for layer: CanvasItem in hotbar.get_node(slot + "Slot/" + holder).get_children():
			count += int(layer.visible)
	return count


# Steps the hover tween of `slot` by `frames` frame times of the clip.
func _step(hotbar: Control, slot: String, frames: int) -> void:
	var tween: Tween = hotbar.hover_tween(slot)
	tween.pause()
	tween.custom_step(frames / float(_icons_record()["hover"]["frame_rate"]))


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


func test_an_icon_at_rest_shows_frame_1_and_draws_no_glow_layer():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	for slot: String in ICON_SLOTS:
		assert_eq(hotbar.hover_frame(slot), 1, slot)
		assert_eq(_visible_layers(hotbar, slot), 0, "%s draws no shader at rest" % slot)


# The last frame of START is the frame the clip holds while the pointer is on
# the button.
func test_the_held_hover_draws_each_glow_of_the_record_on_its_side_of_the_icon():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	var held: int = int(_icons_record()["hover"]["start"][1])
	for slot: String in ICON_SLOTS:
		hotbar.show_hover_frame(slot, held)
		var icon: TextureRect = hotbar.get_node(slot + "Slot/Icon")
		var glows: Array = _glows(slot, held)
		assert_eq(_visible_layers(hotbar, slot), glows.size(), "%s shows one layer for each Glow" % slot)
		for index: int in glows.size():
			var glow: Dictionary = glows[index]
			var layer: TextureRect = _layer(hotbar, slot, index, glow["inner"])
			var material: ShaderMaterial = layer.material
			var where: String = "%s Glow %d" % [slot, index]
			assert_true(layer.visible, where)
			assert_eq(material.get_shader_parameter("inner"), glow["inner"], where)
			assert_almost_eq(float(material.get_shader_parameter("strength")), float(glow["strength"]), 0.0001, where)
			var blur: Vector2 = material.get_shader_parameter("blur")
			assert_almost_eq(blur * icon.size, Vector2.ONE * float(glow["blur"]), Vector2(0.001, 0.001), where)
			var low: Color = material.get_shader_parameter("low")
			var high: Color = material.get_shader_parameter("high")
			if glow.has("gradient"):
				var stops: Array = glow["gradient"]
				assert_eq(low.to_html(), str(stops[0]["color"]).trim_prefix("#") + "%02x" % int(stops[0]["alpha"]), where)
				assert_eq(high.to_html(), str(stops[1]["color"]).trim_prefix("#") + "%02x" % int(stops[1]["alpha"]), where)
			else:
				assert_eq(low.to_html(), str(glow["color"]).trim_prefix("#") + "00", where)
				assert_eq(high.to_html(), str(glow["color"]).trim_prefix("#") + "ff", where)


func test_an_outer_layer_has_room_for_the_widest_blur_and_an_inner_layer_is_the_icon():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	for slot: String in ICON_SLOTS:
		var icon: TextureRect = hotbar.get_node(slot + "Slot/Icon")
		var widest: float = 0.0
		for glows: Array in _icons_record()["icons"][ICON_SLOTS[slot]]["frames"]:
			for glow: Dictionary in glows:
				widest = maxf(widest, float(glow["blur"]))
		for index: int in _glows(slot, 1).size():
			var under: TextureRect = _layer(hotbar, slot, index, false)
			var over: TextureRect = _layer(hotbar, slot, index, true)
			assert_eq(under.texture, icon.texture, slot)
			assert_eq(over.texture, icon.texture, slot)
			assert_almost_eq(under.global_position, icon.global_position - Vector2.ONE * widest / 2.0, Vector2(0.01, 0.01), slot)
			assert_almost_eq(under.size, icon.size + Vector2.ONE * widest, Vector2(0.01, 0.01), slot)
			assert_almost_eq(over.global_position, icon.global_position, Vector2(0.01, 0.01), slot)
			assert_almost_eq(over.size, icon.size, Vector2(0.01, 0.01), slot)
			var grow: Vector2 = (under.material as ShaderMaterial).get_shader_parameter("grow")
			assert_almost_eq(grow, under.size / icon.size, Vector2(0.0001, 0.0001), slot)


# The square is under the outer Glows, the icon is over them, the inner Glows
# are over the icon, and the hit button is over all of them.
func test_each_slot_draws_its_glows_around_its_icon_in_the_order_of_the_filters():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	for slot: String in ICON_SLOTS:
		var order: Array[String] = []
		for node: Node in hotbar.get_node(slot + "Slot").get_children():
			order.append(str(node.name))
		assert_eq(order, ["Square", "Glow", "Icon", "InnerGlow", slot + "Button"], slot)


func test_roll_over_plays_the_start_frames_at_the_clips_rate_and_the_icon_stays_white():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	var start: Array = _icons_record()["hover"]["start"]
	(hotbar.get_node("%InventoryButton") as BaseButton).mouse_entered.emit()
	assert_eq(hotbar.hover_frame("Inventory"), int(start[0]), "START shows its first frame at once")
	_step(hotbar, "Inventory", 2)
	assert_eq(hotbar.hover_frame("Inventory"), int(start[0]) + 2, "two frame times later")
	_step(hotbar, "Inventory", int(start[1]) - int(start[0]) - 2)
	assert_eq(hotbar.hover_frame("Inventory"), int(start[1]), "the end of START")
	assert_eq((hotbar.get_node("InventorySlot/Icon") as TextureRect).modulate, Color.WHITE)


func test_roll_out_plays_the_stop_frames_and_ends_with_no_glow():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	var button: BaseButton = hotbar.get_node("%InventoryButton")
	var stop: Array = _icons_record()["hover"]["stop"]
	button.mouse_entered.emit()
	button.mouse_exited.emit()
	assert_eq(hotbar.hover_frame("Inventory"), int(stop[0]), "STOP shows its first frame at once")
	assert_eq(_visible_layers(hotbar, "Inventory"), 1, "the first frame of STOP still glows")
	_step(hotbar, "Inventory", 5)
	assert_eq(hotbar.hover_frame("Inventory"), int(stop[0]) + 5, "five frame times later")
	_step(hotbar, "Inventory", int(stop[1]) - int(stop[0]) - 5)
	assert_eq(hotbar.hover_frame("Inventory"), int(stop[1]), "the end of STOP")
	assert_eq(_visible_layers(hotbar, "Inventory"), 0, "the last frame of STOP has no strength")


func test_leaving_during_the_start_run_stops_it():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	var button: BaseButton = hotbar.get_node("%InventoryButton")
	button.mouse_entered.emit()
	var start_run: Tween = hotbar.hover_tween("Inventory")
	button.mouse_exited.emit()
	assert_false(start_run.is_valid(), "the START run no longer moves the Glow")
	assert_true(hotbar.hover_tween("Inventory").is_valid(), "the STOP run plays")


# A viewport of the Stage's size for a test that clicks. In the test runner's
# own viewport, GUT's panel covers part of the hotbar and takes the click.
func _stage() -> SubViewport:
	var stage := SubViewport.new()
	stage.size = Vector2i(800, 575)
	add_child_autofree(stage)
	return stage


# A left click on the control's center, pushed through its viewport's GUI input.
func _click(control: Control) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = control.get_global_rect().get_center()
		event.global_position = event.position
		control.get_viewport().push_input(event, true)


func test_an_inert_hotbar_ignores_a_click_on_each_button_and_takes_it_again_after():
	var hotbar: Control = HotbarScene.instantiate()
	_stage().add_child(hotbar)
	await wait_process_frames(2)
	for button_name: String in [
		"InventoryButton", "AbilitiesButton", "SaveButton", "OptionsButton",
		"RespecButton", "AchievementsButton", "ZoneMapButton", "QuitButton",
	]:
		var button: BaseButton = hotbar.get_node("%" + button_name)
		watch_signals(button)
		hotbar.set_inert(true)
		_click(button)
		assert_signal_not_emitted(button, "pressed", button_name)
		hotbar.set_inert(false)
		# A press on Quit leaves the scene this test runs in.
		if button_name == "QuitButton":
			assert_false(button.disabled, button_name)
			continue
		_click(button)
		assert_signal_emitted(button, "pressed", button_name)


func test_an_inert_hotbar_makes_an_orb_ignore_a_click_and_take_it_again_after():
	var stage: SubViewport = _stage()
	var hotbar: Control = HotbarScene.instantiate()
	stage.add_child(hotbar)
	var orb: OrbBase = partial_double(OrbScene).instantiate()
	stage.add_child(orb)
	orb.position = Vector2(200.0, 200.0)
	await wait_process_frames(2)
	hotbar.set_inert(true)
	_click(orb.get_node("Control"))
	assert_not_called(orb, "interact")
	hotbar.set_inert(false)
	_click(orb.get_node("Control"))
	assert_called(orb, "interact")


# The orb also takes a click through its Area2D (orb.tscn, input_event), which
# only fires where no Control takes the mouse first. The SubViewport of the
# test above does no physics picking, so this test calls the handler itself.
func test_an_inert_hotbar_makes_an_orb_ignore_a_click_on_its_area_and_take_it_again_after():
	add_child_autofree(HotbarScene.instantiate())
	var hotbar: Control = get_tree().get_first_node_in_group("hotbar")
	var orb: OrbBase = add_child_autofree(partial_double(OrbScene).instantiate())
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	hotbar.set_inert(true)
	orb._on_input_event(orb.get_viewport(), press, 0)
	assert_not_called(orb, "interact")
	hotbar.set_inert(false)
	orb._on_input_event(orb.get_viewport(), press, 0)
	assert_called(orb, "interact")


func test_quit_has_no_glow():
	var hotbar: Control = add_child_autofree(HotbarScene.instantiate())
	assert_null(hotbar.get_node_or_null("QuitSlot/Glow"))
	assert_null(hotbar.hover_tween("Quit"))


func test_the_typed_hover_values_are_gone():
	var constants: Dictionary = (load("res://scripts/ui/hotbar.gd") as Script).get_script_constant_map()
	for constant: String in ["HOVER_COLORS", "ACTIVE_ICON_COLOR", "GLOW_RADII", "GLOW_STRENGTH", "GLOW_PAD"]:
		assert_does_not_have(constants, constant)
