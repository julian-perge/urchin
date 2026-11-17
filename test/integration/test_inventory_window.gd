extends GutTest

const SCENE = preload("res://scenes/ui/menu/inventory_window.tscn")


func after_each() -> void:
	GameData.current_save = null


func test_the_window_uses_the_shared_shell_and_its_close_signal() -> void:
	var window: Control = add_child_autofree(SCENE.instantiate())
	var shells: Array[Node] = window.find_children("*", "WindowShell", true, false)
	assert_eq(shells.size(), 1)
	if shells.size() != 1:
		return
	assert_eq(window.find_children("*", "ShellPanel", true, false).size(), 5)
	shells[0].close_pressed.emit()
	assert_false(window.visible)


func test_the_member_info_uses_the_extracted_level_and_class_strings() -> void:
	GameData.current_save = PlayerSave.new_game("Inventory", 0)
	GameData.current_save.level = 12
	var window: Control = add_child_autofree(SCENE.instantiate())
	window.refresh()
	assert_eq(window._name_label.text, Party.PLAYER_NAME)
	assert_eq(window._level_label.text, "%s12 %s" % [Strings.menu(0), Strings.text("CLASS", 0)])


func test_refresh_keeps_the_scene_slots_and_their_click_connections() -> void:
	GameData.current_save = PlayerSave.new_game("Inventory", 0)
	var window: Control = add_child_autofree(SCENE.instantiate())
	window.refresh()
	var slots: Array[Node] = window.equip_view.find_children("*", "ItemSlot", true, false)
	assert_eq(slots.size(), 7)
	watch_signals(window.equip_view)
	for i in 7:
		var slot: ItemSlot = window.equip_view.get_node("Slot%d" % i)
		slot.slot_clicked.emit(slot)
		assert_signal_emitted_with_parameters(window.equip_view, "equip_slot_clicked", [i])
		assert_eq(int(slot.get_meta("drag_index")), i)
		assert_eq(slot.get_meta("drag_source"), "equip")
	window.refresh()
	assert_eq(window.equip_view.find_children("*", "ItemSlot", true, false), slots)


# The doll's placement is the record's, which extract_screen_rects fits from the
# SWF's 31 part clips. test_screen_rects.gd checks the union rect of its art.
func _inventory_record() -> Dictionary:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/screen_rects.json"))
	return record["scenes"]["res://scenes/ui/menu/inventory_window.tscn"]["pieces"]


func test_the_doll_stands_where_the_part_placements_put_it_behind_the_scene_slots() -> void:
	GameData.current_save = PlayerSave.new_game("Inventory", 0)
	var window: Control = add_child_autofree(SCENE.instantiate())
	var doll: Node2D = window.equip_view.get_node("Doll")
	var placed: Dictionary = _inventory_record()["LeftPanel/Content/EquipDollView/Doll"]
	assert_almost_eq(doll.global_position, Vector2(placed["position"][0], placed["position"][1]), Vector2(0.01, 0.01))
	assert_almost_eq(doll.scale, Vector2(placed["scale"][0], placed["scale"][1]), Vector2(0.0001, 0.0001))
	for i in 7:
		assert_lt(doll.get_index(), window.equip_view.get_node("Slot%d" % i).get_index())


func test_the_window_keeps_the_scene_doll_and_has_no_second_one() -> void:
	GameData.current_save = PlayerSave.new_game("Inventory", 0)
	var window: Control = add_child_autofree(SCENE.instantiate())
	var dolls: Array[Node] = window.equip_view.find_children("*", "CharacterVisual", true, false)
	assert_eq(dolls.size(), 1)
	window.refresh()
	assert_eq(window.equip_view.find_children("*", "CharacterVisual", true, false), dolls)


func test_the_doll_is_dressed_by_refresh_as_the_players_model() -> void:
	GameData.current_save = PlayerSave.new_game("Inventory", 0)
	var window: Control = add_child_autofree(SCENE.instantiate())
	var doll: CharacterVisual = window.equip_view.get_node("Doll")
	assert_eq(doll.get_bounds().size, Vector2.ZERO, "an undressed doll draws nothing")
	window.refresh()
	assert_gt(doll.get_bounds().size.x, 0.0)


# The experience fill is the sprite 2867, which the original scales to
# experience / 100 of the bar's width (DefineSprite_3142/frame_1/
# PlaceObject2_2867_1419), and the percent is Math.round of the experience.
func test_the_experience_fill_and_percent_follow_the_experience() -> void:
	var width: float = MenuMath.load_math()["experience_bar"]["width"]
	var left: float = _inventory_record()["ExpFill"]["rect"][0]
	var cases: Array[Array] = [[0.0, "0%"], [37.6, "38%"], [100.0, "100%"]]
	for case: Array in cases:
		GameData.current_save = PlayerSave.new_game("Inventory", 0)
		GameData.current_save.experience = case[0]
		var window: Control = add_child_autofree(SCENE.instantiate())
		window.refresh()
		var fill: Control = window.get_node("ExpFill")
		assert_almost_eq(fill.size.x, case[0] / 100.0 * width, 0.5, "fill width at %s" % case[0])
		assert_almost_eq(fill.global_position.x, left, 0.01, "the fill grows from its left edge")
		assert_eq((window.get_node("ExpPercent") as Label).text, case[1])


func test_the_experience_label_is_the_extracted_string() -> void:
	var window: Control = add_child_autofree(SCENE.instantiate())
	assert_eq((window.get_node("ExperienceLabel") as Label).text, Strings.menu(17))


func test_an_experience_over_the_bar_fills_no_more_than_the_bar() -> void:
	GameData.current_save = PlayerSave.new_game("Inventory", 0)
	var window: Control = add_child_autofree(SCENE.instantiate())
	var full: float = (window.get_node("ExpFill") as Control).size.x
	GameData.current_save.experience = 130.0
	window.refresh()
	assert_almost_eq((window.get_node("ExpFill") as Control).size.x, full, 0.01)


func test_a_click_on_a_scene_equip_slot_unequips_the_item() -> void:
	GameData.current_save = PlayerSave.new_game("Inventory", 0)
	var item: GameItem = null
	for candidate: GameItem in ItemManagerAuto.items_by_id.values():
		if candidate.required_level <= 1 and candidate.required_unit_id == 0 and Equipment.slot_for_item(candidate) != -1:
			item = candidate
			break
	assert_not_null(item)
	if item == null:
		return
	GameData.current_save.item_array[0] = item.id
	var window: Control = add_child_autofree(SCENE.instantiate())
	assert_eq(GameData.equip_from_inventory(0), Equipment.EquipResult.OK)
	var equip_index: int = Equipment.slot_for_item(item)
	var slot: ItemSlot = window.equip_view.get_node("Slot%d" % equip_index)
	slot.slot_clicked.emit(slot)
	assert_eq(int(GameData.current_save.equip_array[equip_index]), 0)
	assert_eq(int(GameData.current_save.item_array[0]), item.id)
