# test_hotbar_respec.gd - the hotbar's Respec button in the Hub, which runs the
# original's DefineButton2_3179 on(release): the cost, the two refusals, the
# reset and the jump to the Abilities Window.
extends GutTest

const GameScene = preload("res://scenes/game.tscn")

var _previous_save: PlayerSave


func before_each():
	_previous_save = GameData.current_save
	GameData.current_save = PlayerSave.new_game("Respec", 0)


func after_each():
	GameData.current_save = _previous_save
	GameTooltip.hide_tooltip()


# A Hub in a viewport of the Stage's size. In the test runner's own viewport,
# GUT's panel covers part of the hotbar and takes the click.
func _hub() -> Control:
	var stage := SubViewport.new()
	stage.size = Vector2i(800, 575)
	add_child_autofree(stage)
	var hub: Control = GameScene.instantiate()
	stage.add_child(hub)
	await wait_process_frames(2)
	return hub


func _respec_button(hub: Control) -> BaseButton:
	return hub.get_node("Hotbar").get_node("%RespecButton")


func _mouse_button(control: Control, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = control.get_global_rect().get_center()
	event.global_position = event.position
	control.get_viewport().push_input(event, true)


func _click(control: Control) -> void:
	_mouse_button(control, true)
	_mouse_button(control, false)


# A level 5 player with two talents learned and a move of its own on the bar.
# The respec costs round(0.7 * 10 * 5^1.5) = 78 euros at level 5.
func _trained_save(euro: float) -> PlayerSave:
	var save: PlayerSave = GameData.current_save
	save.level = 5
	save.skill_points = 10
	TalentTree.learn(save, 0)
	TalentTree.learn(save, 1)
	save.move_matrix[2] = save.move_matrix2[save.move_matrix2.size() - 1]
	save.euro = euro
	return save


# Every field of the save that a respec writes.
func _respec_fields(save: PlayerSave) -> Dictionary:
	return {
		"euro": save.euro,
		"skill_points": save.skill_points,
		"stat_points": save.stat_points,
		"move_matrix": save.move_matrix.duplicate(),
		"move_matrix2": save.move_matrix2.duplicate(),
		"talent_main_array": save.talent_main_array.duplicate(),
		"skill_adder_matrix": save.skill_adder_matrix.duplicate(),
		"buff_adder_matrix": save.buff_adder_matrix.duplicate(),
		"stat_allocated": save.stat_allocated.duplicate(),
		"respec_set": save.respec_set,
		"last_respec_day": save.last_respec_day,
	}


func test_the_hub_banner_sits_where_the_navigation_frame_places_the_clip():
	var hub: Control = await _hub()
	var banner: CombatTextBanner = hub.get_node("CombatTextBanner")
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CombatTextBanner.LAYOUT_PATH))
	assert_eq(banner.placement, "hub")
	assert_false(banner.visible, "the banner waits on its empty frame")
	banner.show_text("x")
	banner.set_process(false)
	banner.advance(10.0 / float(layout["fps"]))
	var hub_place: Dictionary = layout["positions"]["hub"]
	assert_almost_eq(banner.position, Vector2(hub_place["x"], hub_place["y"]), Vector2(0.001, 0.001), "frame 12 is in place")
	assert_almost_eq(banner.position, Vector2(400.0, 48.95), Vector2(0.001, 0.001))


# Frame 181 places the banner at depth 1610: over KRINMENU at 175, which holds
# every Window, and under the Info card, krinNavFadeSpeech at 1651.
func test_the_hub_banner_draws_over_the_windows_and_the_hotbar_and_under_the_info_card():
	var hub: Control = await _hub()
	var banner: int = hub.get_node("CombatTextBanner").get_index()
	for over: String in ["InventoryWindow", "AbilitiesWindow", "AchievementsWindow", "StoreWindow", "Hotbar"]:
		assert_gt(banner, hub.get_node(over).get_index(), over)
	assert_lt(banner, hub.get_node("HubCard").get_index())


func test_a_click_with_enough_money_respecs_and_opens_the_abilities_window():
	var save: PlayerSave = _trained_save(100.0)
	var hub: Control = await _hub()
	_click(_respec_button(hub))
	var starting_moves: Array = TalentTree.STARTING_MOVES[save.player_class]
	assert_eq(save.euro, 22.0, "100 less the 78 cost")
	assert_eq(save.skill_points, 9, "level - 1 + 5 starting points")
	assert_eq(save.stat_points, 28, "givePoints(5, true)")
	assert_eq(save.move_matrix, starting_moves + [0, 0, 0, 0, 0, 0], "the two starting moves are the only moves on the bar")
	assert_eq(save.move_matrix2, starting_moves, "the two starting moves are the only known moves")
	for node: int in TalentTree.NODE_ARRAY_SIZE:
		assert_eq(TalentTree.get_rank(save, node), 0, "talent %d" % node)
	assert_eq(save.buff_adder_matrix, TalentTree._zero_array(TalentTree.NODE_ARRAY_SIZE), "passives cleared")
	assert_true(hub.get_node("AbilitiesWindow").visible, "the Abilities Window opens")
	assert_eq(hub.get_node("AbilitiesWindow")._ability_points_value.text, "9", "the Window shows the new points")
	var banner: CombatTextBanner = hub.get_node("CombatTextBanner")
	assert_true(banner.is_up())
	assert_eq(banner.label.text, Strings.menu(67))


func test_respec_reseeds_the_attributes_from_the_equipped_gear():
	var save: PlayerSave = _trained_save(100.0)
	var wearer: Equipment.Wearer = Equipment.Wearer.for_player(save)
	var weapon: GameItem = null
	for item: GameItem in ItemManagerAuto.items_by_id.values():
		if item.item_type != GameItem.ItemType.MAINHAND:
			continue
		if Equipment.total_stat_bonuses([item.id], ItemManagerAuto.items_by_id) == [0, 0, 0, 0, 0]:
			continue
		if Equipment.can_equip_with_lookup(wearer, item, Equipment.MAIN_HAND_SLOT, ItemManagerAuto.items_by_id) == Equipment.EquipResult.OK:
			weapon = item
			break
	assert_not_null(weapon, "a level 5 player can wield a weapon with attribute bonuses")
	Equipment.equip(wearer, weapon, Equipment.MAIN_HAND_SLOT, ItemManagerAuto.items_by_id)
	var bonuses: Array = Equipment.total_stat_bonuses(save.equip_array, ItemManagerAuto.items_by_id)
	assert_ne(bonuses, [0, 0, 0, 0, 0], "the weapon has attribute bonuses")
	var hub: Control = await _hub()
	_click(_respec_button(hub))
	assert_eq(save.stat_allocated, bonuses)


func test_a_respec_with_the_abilities_window_open_keeps_it_open_and_refreshes_it():
	_trained_save(100.0)
	var hub: Control = await _hub()
	hub.get_node("Hotbar").toggle_menu_screen("abilities_window")
	_click(_respec_button(hub))
	assert_true(hub.get_node("AbilitiesWindow").visible)
	assert_eq(hub.get_node("AbilitiesWindow")._ability_points_value.text, "9")


func test_a_click_with_too_little_money_changes_nothing_and_shows_menu_42():
	var save: PlayerSave = _trained_save(77.0)
	var before: Dictionary = _respec_fields(save)
	var hub: Control = await _hub()
	_click(_respec_button(hub))
	assert_eq(_respec_fields(save), before)
	assert_false(hub.get_node("AbilitiesWindow").visible)
	var banner: CombatTextBanner = hub.get_node("CombatTextBanner")
	assert_true(banner.is_up())
	assert_eq(banner.label.text, Strings.menu(42))


func test_a_release_with_an_item_on_the_cursor_changes_nothing_and_shows_menu_66():
	var save: PlayerSave = _trained_save(100.0)
	var before: Dictionary = _respec_fields(save)
	var equip_before: Array = save.equip_array.duplicate()
	var hub: Control = await _hub()
	var button: BaseButton = _respec_button(hub)
	var item: GameItem = ItemManagerAuto.items_by_id[int(save.equip_array[Equipment.MAIN_HAND_SLOT])]
	var preview := Control.new()
	button.force_drag({"item": item, "source": "equip", "index": Equipment.MAIN_HAND_SLOT}, preview)
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	motion.global_position = motion.position
	button.get_viewport().push_input(motion, true)
	_mouse_button(button, false)
	assert_false(button.get_viewport().gui_is_dragging(), "the release ends the drag")
	assert_eq(_respec_fields(save), before)
	assert_eq(save.equip_array, equip_before, "the item stays where it was")
	assert_false(hub.get_node("AbilitiesWindow").visible)
	var banner: CombatTextBanner = hub.get_node("CombatTextBanner")
	assert_true(banner.is_up())
	assert_eq(banner.label.text, Strings.menu(66))


# The original's bare play() leaves a banner that is up alone, so a second
# refusal while the first one shows does not change the text.
func test_a_refusal_while_the_banner_is_up_leaves_its_text():
	_trained_save(0.0)
	var hub: Control = await _hub()
	var banner: CombatTextBanner = hub.get_node("CombatTextBanner")
	banner.show_text("earlier")
	_click(_respec_button(hub))
	assert_eq(banner.label.text, "earlier")


func test_an_inert_hotbar_ignores_a_click_on_respec():
	var save: PlayerSave = _trained_save(100.0)
	var before: Dictionary = _respec_fields(save)
	var hub: Control = await _hub()
	hub.get_node("Hotbar").set_inert(true)
	_click(_respec_button(hub))
	assert_eq(_respec_fields(save), before)
	assert_false(hub.get_node("CombatTextBanner").is_up())
