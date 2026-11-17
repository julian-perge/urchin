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


func test_the_doll_stands_at_its_stage_position_behind_the_scene_slots() -> void:
	GameData.current_save = PlayerSave.new_game("Inventory", 0)
	var window: Control = add_child_autofree(SCENE.instantiate())
	var doll: Node2D = window.equip_view.get_node("Doll")
	assert_almost_eq(doll.global_position, window.DOLL_POSITION, Vector2(0.01, 0.01))
	for i in 7:
		assert_lt(doll.get_index(), window.equip_view.get_node("Slot%d" % i).get_index())


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
