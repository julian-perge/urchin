# test_hotbar_item_drop.gd - an item drag released on a hotbar button. In the
# original that is a release while Krin.mouseItem is set. Respec and Options
# have their own tests (test_hotbar_respec.gd, test_options_window.gd).
extends GutTest

const GameScene = preload("res://scenes/game.tscn")
const TEST_SAVE_DIR := "user://test_hotbar_item_drop_saves/"

var _previous_save: PlayerSave
var _slot_before: int


func before_each():
	_previous_save = GameData.current_save
	_slot_before = GameData.current_slot
	GameData.current_save = PlayerSave.new_game("Drop", 0)
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)
	GameData.save_dir = TEST_SAVE_DIR
	GameData.current_slot = 1


func after_each():
	GameData.current_save = _previous_save
	GameData.current_slot = _slot_before
	GameData.save_dir = GameData.SAVE_DIR
	for file: String in DirAccess.get_files_at(TEST_SAVE_DIR):
		DirAccess.remove_absolute(TEST_SAVE_DIR + file)
	DirAccess.remove_absolute(TEST_SAVE_DIR)
	GameTooltip.hide_tooltip()


# A Hub in a viewport of the Stage's size. In the test runner's own viewport,
# GUT's panel covers part of the hotbar and takes the release.
func _hub() -> Control:
	var stage := SubViewport.new()
	stage.size = Vector2i(800, 575)
	add_child_autofree(stage)
	var hub: Control = GameScene.instantiate()
	stage.add_child(hub)
	await wait_process_frames(2)
	return hub


# Drags the equipped weapon onto the button and releases it there.
func _release_an_item_drag_on(button: BaseButton) -> void:
	var save: PlayerSave = GameData.current_save
	var item: GameItem = ItemManagerAuto.items_by_id[int(save.equip_array[Equipment.MAIN_HAND_SLOT])]
	button.force_drag({"item": item, "source": "equip", "index": Equipment.MAIN_HAND_SLOT}, Control.new())
	var at: Vector2 = button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	button.get_viewport().push_input(motion, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = at
	release.global_position = at
	button.get_viewport().push_input(release, true)


# The names of the Hub's overlays that show: every Window, the World Map and
# the Info card.
func _open_overlays(hub: Control) -> Array:
	var open: Array = []
	for overlay: CanvasItem in hub.get_tree().get_nodes_in_group("menu_screen"):
		if overlay.visible:
			open.append(overlay.name)
	for overlay: String in ["ZoneMapOverlay", "HubCard"]:
		if (hub.get_node(overlay) as CanvasItem).visible:
			open.append(overlay)
	return open


# Save, Abilities and Achievements (DefineButton2_3183, DefineButton2_3184 and
# DefineButton2_3153 on(release)) show MENU[66] while an item is on the cursor.
# They check it before PauseForScreen, so an inert hotbar refuses too.
func test_save_abilities_and_achievements_refuse_a_dropped_item_with_menu_66():
	for button_name: String in ["SaveButton", "AbilitiesButton", "AchievementsButton"]:
		for inert: bool in [false, true]:
			var context: String = "%s, inert %s" % [button_name, inert]
			var save: PlayerSave = GameData.current_save
			var equip_before: Array = save.equip_array.duplicate()
			var items_before: Array = save.item_array.duplicate()
			var hub: Control = await _hub()
			hub.get_node("Hotbar").set_inert(inert)
			var button: BaseButton = hub.get_node("Hotbar").get_node("%" + button_name)
			_release_an_item_drag_on(button)
			assert_false(button.get_viewport().gui_is_dragging(), context + ": the release ends the drag")
			var banner: CombatTextBanner = hub.get_node("CombatTextBanner")
			assert_true(banner.is_up(), context + ": the banner shows")
			assert_eq(banner.label.text, Strings.menu(66), context)
			assert_eq(_open_overlays(hub), [], context + ": nothing opens")
			assert_false(GameData.has_save(1), context + ": nothing saves")
			assert_eq(save.equip_array, equip_before, context + ": the item stays where it was")
			assert_eq(save.item_array, items_before, context)
			hub.get_parent().free()


# World Map (DefineButton2_3177 on(release)) checks Krin.mouseItem and does
# nothing while an item is on the cursor. Inventory and Quit
# (DefineButton2_3185 and DefineButton2_3178 on(release)) do not check it, so
# in the original they open the Inventory or quit with the item still on the
# cursor. The port's three buttons take no drop, so the drag ends with no
# effect and the item goes back to its slot.
func test_world_map_inventory_and_quit_ignore_a_dropped_item():
	for button_name: String in ["ZoneMapButton", "InventoryButton", "QuitButton"]:
		var save: PlayerSave = GameData.current_save
		var equip_before: Array = save.equip_array.duplicate()
		var hub: Control = await _hub()
		var button: BaseButton = hub.get_node("Hotbar").get_node("%" + button_name)
		_release_an_item_drag_on(button)
		assert_false(button.get_viewport().gui_is_dragging(), button_name + ": the release ends the drag")
		assert_false(hub.get_node("CombatTextBanner").is_up(), button_name + ": no text shows")
		assert_eq(_open_overlays(hub), [], button_name + ": nothing opens")
		assert_true(hub.is_inside_tree(), button_name + ": the Hub stays")
		assert_eq(save.equip_array, equip_before, button_name + ": the item stays where it was")
		hub.get_parent().free()
