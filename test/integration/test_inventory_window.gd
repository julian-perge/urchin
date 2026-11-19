extends GutTest

const SCENE = preload("res://scenes/ui/menu/inventory_window.tscn")


func after_each() -> void:
	GameData.current_save = null
	GameData.menu_party_id = Party.PLAYER_PARTY_ID


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


# The stat names are SYSTEM[0] to [4] plus ":" in the original's menu script
# (DefineSprite_3142/frame_25/DoAction.as), read here from strings.json itself.
func test_the_stat_names_are_the_system_strings_with_a_colon() -> void:
	var system: Array = JSON.parse_string(FileAccess.get_file_as_string(Strings.STRINGS_FILE))["SYSTEM"]
	var window: Control = add_child_autofree(SCENE.instantiate())
	var names: Node = window.get_node("CenterPanel/Content/StatNames")
	assert_eq(names.get_child_count(), 5)
	for i in 5:
		assert_eq((names.get_node("Row%d/Label" % i) as Label).text, system[i] + ":")


func test_the_stat_values_are_the_players_stats_in_order() -> void:
	GameData.current_save = PlayerSave.new_game("Inventory", 0)
	var save: PlayerSave = GameData.current_save
	save.life = 11.0
	save.strength = 22.0
	save.magic = 33.0
	save.speed = 44.0
	save.focus = 55.0
	var window: Control = add_child_autofree(SCENE.instantiate())
	window.refresh()
	var values: Node = window.get_node("CenterPanel/Content/StatValues")
	var shown: Array[String] = []
	for i in 5:
		shown.append((values.get_node("Row%d/Label" % i) as Label).text)
	assert_eq(shown, ["11", "22", "33", "44", "55"])


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


# Each element bar takes the save's per or def for its element and the level
# (DefineSprite_3142/frame_1/DoAction.as:103-125).
func test_refresh_sets_every_element_bar_from_the_saves_per_and_def() -> void:
	var save: PlayerSave = PlayerSave.new_game("Inventory", 0)
	save.level = 3
	save.per[CombatUnit.Element.FIRE] = 50.0
	save.def[CombatUnit.Element.ICE] = 100.0
	GameData.current_save = save
	var window: Control = add_child_autofree(SCENE.instantiate())
	window.refresh()
	var math: Dictionary = MenuMath.load_math()
	var fire_x: float = MenuMath.x_for(50.0, 3, math)
	var fire: ElementBar = window.get_node("PerBars/Bars/Bar%d" % CombatUnit.Element.FIRE)
	assert_almost_eq((fire.get_node("Bar") as ColorRect).size.y, MenuMath.layer_heights(fire_x, math)["bar"], 0.001)
	assert_eq(fire.tooltip()["title"], "%s %s: 195" % [Strings.text("ELEMENTS", CombatUnit.Element.FIRE), Strings.system(5)])
	var ice_x: float = MenuMath.x_for(100.0, 3, math)
	var ice: ElementBar = window.get_node("DefBars/Bars/Bar%d" % CombatUnit.Element.ICE)
	assert_almost_eq((ice.get_node("Gbar") as ColorRect).size.y, MenuMath.layer_heights(ice_x, math)["gbar"], 0.001)
	assert_eq(ice.tooltip()["body"], Strings.text("DEFTIP", MenuMath.defense_tip(ice_x, math)))
	var untouched: ElementBar = window.get_node("PerBars/Bars/Bar%d" % CombatUnit.Element.ICE)
	assert_almost_eq((untouched.get_node("Gbar") as ColorRect).size.y, MenuMath.layer_heights(MenuMath.x_for(0.0, 3, math), math)["gbar"], 0.001)


func test_the_sixteen_bars_are_the_elements_in_order_with_their_own_stat() -> void:
	var window: Control = add_child_autofree(SCENE.instantiate())
	for k in 8:
		assert_eq((window.get_node("PerBars/Bars/Bar%d" % k) as ElementBar)._kind, ElementBar.Kind.PIERCING)
		assert_eq((window.get_node("DefBars/Bars/Bar%d" % k) as ElementBar)._kind, ElementBar.Kind.DEFENSE)
		assert_eq((window.get_node("PerBars/Bars/Bar%d" % k) as ElementBar)._element, k)


# A plain click on a party face selects the member (DefineButton2_2895
# on(press) lines 30-37). The left panel then shows that member's name, level,
# class (CLASS[ClassStats - 1]), stats and gear, and the equip slots act on
# that member's gear (DefineButton2_2981 on(press)).
func _window_with_felicity_selected() -> Control:
	GameData.current_save = PlayerSave.new_game("Inventory", 0)
	GameData.current_save.party_roster = [0, 1, 2, 3, -1, -1]
	var window: Control = add_child_autofree(SCENE.instantiate())
	window.refresh()
	var face: PartyFace = window._party_faces[3]
	assert_eq(face.party_id, 3)
	face.chosen.emit(3, false)
	return window


func test_a_click_on_a_companions_face_shows_that_companion() -> void:
	var window: Control = _window_with_felicity_selected()
	var felicity: Dictionary = Party.COMPANIONS[3]
	assert_eq(GameData.menu_party_id, 3)
	assert_eq(window._name_label.text, felicity["name"])
	assert_eq(window._level_label.text, "%s22 %s" % [Strings.menu(0), Strings.text("CLASS", felicity["unit_id"] - 1)])
	var shown: Array = []
	for label: Label in window._stat_values:
		shown.append(int(label.text))
	assert_eq(shown, [40, 150, 40, 171, 125], "Felicity's stats in the original at level 22")
	for i in 7:
		var slot: ItemSlot = window.equip_view.get_node("Slot%d" % i)
		var item_id: int = int(felicity["equipment"][i])
		assert_eq(slot.item.id if slot.item != null else 0, item_id, "equip slot %d shows her gear" % i)


func test_the_equip_slots_act_on_the_selected_companion() -> void:
	var window: Control = _window_with_felicity_selected()
	var save: PlayerSave = GameData.current_save
	var player_gear: Array = save.equip_array.duplicate()
	var slot: ItemSlot = window.equip_view.get_node("Slot5")
	var blade_id: int = int(Party.COMPANIONS[3]["equipment"][5])
	slot.slot_clicked.emit(slot)
	assert_eq(int(save.party_equip[3][5]), 0, "the click unequipped Felicity's main hand")
	assert_true(save.item_array.has(blade_id))
	assert_eq(save.equip_array, player_gear, "the player's gear is untouched")
	assert_eq(GameData.equip_from_inventory(save.item_array.find(blade_id)), Equipment.EquipResult.OK)
	assert_eq(int(save.party_equip[3][5]), blade_id, "an inventory click equips onto Felicity")


func test_reopening_the_window_selects_the_player_again() -> void:
	var window: Control = _window_with_felicity_selected()
	window.hide()
	window.show()
	assert_eq(GameData.menu_party_id, Party.PLAYER_PARTY_ID)
	assert_eq(window._name_label.text, Party.PLAYER_NAME)
