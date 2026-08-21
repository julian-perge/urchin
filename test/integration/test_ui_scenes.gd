# Integration tests for the rebuilt UI layer: main menu, the zone-hub shell
# (game.tscn), the 7 per-zone scenes with SWF-extracted orb positions, the
# hotbar, and the zone map.
extends GutTest

const MainMenuScene = preload("res://scenes/main_menu.tscn")
const GameScene = preload("res://scenes/game.tscn")

# Story-orb positions extracted from the original SWF's zone-hub sprite
# (sprite 3287) - the scenes must match the source exactly.
const EXPECTED_STORY_POSITIONS = {
	1: Vector2(486.9, 250.7),
	2: Vector2(499.8, 236.7),
	3: Vector2(402.8, 267.6),
	4: Vector2(420.6, 210.2),
	5: Vector2(476.5, 170.8),
	6: Vector2(526.8, 202.6),
	7: Vector2(526.8, 202.6),
}


func before_each():
	GameData.current_save = PlayerSave.new_game("UiTest", 0)
	ZoneManager.auto_start_battles = false
	ZoneManager.current_zone = 1


func after_each():
	GameData.current_save = null
	ZoneManager.auto_start_battles = true
	ZoneManager.pending_battle = {}


func test_main_menu_builds_slot_buttons():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	var buttons = menu.slot_buttons.get_children()
	assert_eq(buttons.size(), GameData.NUM_SLOTS, "one button per save slot")
	assert_false(menu.new_game_panel.visible, "new-game panel starts hidden")
	# Count the cards, not every child - the picker also holds a name label per card.
	var cards = menu.class_picker.get_children().filter(func(c): return c is TextureButton)
	assert_eq(cards.size(), 3, "three class cards")
	assert_eq(menu.difficulty_picker.get_child_count(), 3, "three difficulties")


func test_class_cards_show_the_shared_tooltip_on_hover():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	for class_id in PlayerSave.CLASS_NAMES.size():
		var name: String = PlayerSave.CLASS_NAMES[class_id]
		menu.class_picker.get_node(name).mouse_entered.emit()
		await get_tree().process_frame
		assert_true(GameTooltip._root.visible, "%s card shows the tooltip" % name)
		assert_eq(GameTooltip._sections.get_child_count(), 2, "%s: header plus blurb" % name)
		var header: Label = GameTooltip._sections.get_child(0).get_child(0).get_child(0)
		assert_eq(header.text, name, "header names the class")
		var body: Label = GameTooltip._sections.get_child(1).get_child(0).get_child(0)
		assert_eq(body.text, PlayerSave.CLASS_DESCRIPTIONS[class_id], "body is the class blurb")
		# The rightmost card has no room for its tooltip on the right, and the
		# tooltip has to flip rather than land back over the art it describes.
		var card: TextureButton = menu.class_picker.get_node(name)
		assert_false(
			Rect2(card.global_position, card.size).intersects(
				Rect2(GameTooltip._root.position, GameTooltip._root.size)
			),
			"%s tooltip clears its own card" % name
		)
		menu.class_picker.get_node(name).mouse_exited.emit()
		assert_false(GameTooltip._root.visible, "%s card hides it again" % name)


# The fades are stepped by hand rather than waited on: wait_seconds() races the
# tween against wall clock, and headless runs overshoot it enough to sail past a
# midpoint sample. pause() plus custom_step() advances a fade by an exact delta.
func test_class_cards_fade_their_color_copy_in_and_back_out_on_hover():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	var card: TextureButton = menu.class_picker.get_node("Biological")
	var overlay: TextureRect = card.get_node("Color")
	assert_eq(overlay.modulate.a, 0.0, "the colored copy starts hidden")

	card.mouse_entered.emit()
	var fade_in: Tween = menu._card_fades["Biological"]
	fade_in.pause()
	fade_in.custom_step(menu.CARD_FADE_IN * 0.5)
	assert_almost_eq(overlay.modulate.a, 0.5, 0.01, "half faded in at the halfway point")
	fade_in.custom_step(menu.CARD_FADE_IN * 0.5)
	assert_almost_eq(overlay.modulate.a, 1.0, 0.001, "reaches full color")

	card.mouse_exited.emit()
	var fade_out: Tween = menu._card_fades["Biological"]
	fade_out.pause()
	fade_out.custom_step(menu.CARD_FADE_OUT * 0.5)
	assert_almost_eq(overlay.modulate.a, 0.5, 0.01, "half faded back at the halfway point")
	fade_out.custom_step(menu.CARD_FADE_OUT * 0.5)
	assert_almost_eq(overlay.modulate.a, 0.0, 0.001, "returns to gray")


func test_hovering_a_card_again_mid_fade_replaces_the_running_fade():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	var card: TextureButton = menu.class_picker.get_node("Hydraulic")
	var overlay: TextureRect = card.get_node("Color")
	card.mouse_entered.emit()
	var interrupted: Tween = menu._card_fades["Hydraulic"]
	interrupted.pause()
	interrupted.custom_step(menu.CARD_FADE_IN * 0.5)

	card.mouse_exited.emit()
	assert_false(interrupted.is_valid(), "the interrupted fade is killed, not left running")
	card.mouse_entered.emit()
	var latest: Tween = menu._card_fades["Hydraulic"]
	latest.pause()
	latest.custom_step(menu.CARD_FADE_IN)
	assert_almost_eq(overlay.modulate.a, 1.0, 0.001, "the last hover wins outright")


func test_all_zone_scenes_have_source_accurate_orbs():
	for zone_id in range(1, 8):
		var path = str(ZoneManager.ZONES[zone_id]["scene"])
		assert_true(ResourceLoader.exists(path), "zone %d scene exists" % zone_id)
		var zone = add_child_autofree(load(path).instantiate())
		assert_eq(zone.zone_id, zone_id, "zone_id wired")
		var story: Node2D = zone.get_node("StoryFight")
		var store: Node2D = zone.get_node("ItemStore")
		var training: Node2D = zone.get_node("TrainingFight")
		assert_not_null(story)
		assert_not_null(store)
		assert_not_null(training)
		var expected: Vector2 = EXPECTED_STORY_POSITIONS[zone_id]
		assert_almost_eq(story.position.x, expected.x, 0.1, "zone %d story orb x" % zone_id)
		assert_almost_eq(story.position.y, expected.y, 0.1, "zone %d story orb y" % zone_id)
		assert_not_null(zone.get_node("HubArt").texture, "zone %d hub art loads" % zone_id)


func test_game_shell_hosts_current_zone():
	var game = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	assert_eq(game.zone_host.get_child_count(), 1, "zone scene instanced")
	assert_eq(game.zone_host.get_child(0).zone_id, 1)
	ZoneManager.current_zone = 2
	ZoneManager.zone_changed.emit(2)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(game.zone_host.get_child(0).zone_id, 2, "zone swap on zone_changed")
	assert_false(game.get_node("StoreWindow").visible, "store starts hidden")
	assert_false(game.get_node("ZoneMapOverlay").visible, "map overlay starts hidden")


func test_hotbar_shows_progress_from_save():
	GameData.current_save.quest_progress[1] = 3
	var game = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	var hotbar = game.get_node("Hotbar")
	assert_eq(hotbar.zone_title.text, "Zone 1")
	assert_eq(hotbar.zone_subtitle.text, "New Alcatraz: The Iron Prison")
	assert_eq(hotbar.progress_bar.value, 3.0, "quest progress drives the bar")
	assert_eq(hotbar.progress_bar.max_value, 9.0, "zone 1 progress_max")
	assert_eq(hotbar.stage_label.text, "Stage 4")


func test_inventory_window_equips_from_grid_click():
	var item = _find_basic_equippable()
	assert_not_null(item, "an unrestricted level-1 equippable exists")
	GameData.current_save.item_array[0] = item.id
	var window = add_child_autofree(load("res://scenes/ui/menu/inventory_window.tscn").instantiate())
	window.refresh()
	var slot: ItemSlot = window.inventory_panel.inventory_grid.get_child(0)
	assert_eq(slot.item.id, item.id, "grid slot 0 mirrors item_array[0]")
	window.inventory_panel._on_slot_clicked(slot)
	var equip_slot = Equipment.slot_for_item(item)
	assert_eq(int(GameData.current_save.equip_array[equip_slot]), item.id, "click equips into the natural slot")
	assert_eq(int(GameData.current_save.item_array[0]), 0, "inventory cell emptied")
	window._on_equip_slot_clicked(equip_slot)
	assert_eq(int(GameData.current_save.equip_array[equip_slot]), 0, "equip slot click unequips")
	assert_eq(int(GameData.current_save.item_array[0]), item.id, "item returns to the first free cell")


func test_abilities_window_edits_action_bar():
	var window = add_child_autofree(load("res://scenes/ui/menu/abilities_window.tscn").instantiate())
	window.refresh()
	assert_eq(GameData.current_save.move_matrix.slice(0, 2), [1, 6], "new game seeds the bar")
	assert_eq(window._pool_move_ids, [], "both known moves already on the bar")
	window._on_socket_pressed(0)
	assert_eq(int(GameData.current_save.move_matrix[0]), 0, "socket click removes the move")
	assert_eq(window._pool_move_ids, [1], "removed move lands in the pool")
	window._on_pool_row_pressed(0)
	assert_eq(int(GameData.current_save.move_matrix[0]), 1, "pool click fills the first free socket")
	assert_eq(window._pool_move_ids, [], "pool empties again")


func test_achievements_window_builds_ten_plates():
	var window = add_child_autofree(load("res://scenes/ui/menu/achievements_window.tscn").instantiate())
	assert_eq(window._plates.size(), Achievements.ACHIEVEMENT_COUNT)


func test_hotbar_menu_toggle_is_exclusive_and_glows():
	var game = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	var hotbar = game.get_node("Hotbar")
	hotbar.toggle_menu_screen("abilities_window")
	assert_true(game.get_node("AbilitiesWindow").visible, "abilities opens")
	assert_true(hotbar._button_glows["AbilitiesButton"]["glow"].visible, "abilities icon glows")
	hotbar.toggle_menu_screen("inventory_window")
	assert_false(game.get_node("AbilitiesWindow").visible, "one menu screen at a time")
	assert_true(game.get_node("InventoryWindow").visible)
	assert_false(hotbar._button_glows["AbilitiesButton"]["glow"].visible, "old glow off")
	assert_true(hotbar._button_glows["InventoryButton"]["glow"].visible, "new glow on")
	hotbar.toggle_menu_screen("inventory_window")
	assert_false(game.get_node("InventoryWindow").visible, "second press closes")
	assert_false(hotbar._button_glows["InventoryButton"]["glow"].visible)


# First unrestricted level-1 wearable in the item set (deterministic pick:
# lowest id wins).
func _find_basic_equippable() -> GameItem:
	var best: GameItem = null
	for item in ItemManagerAuto.items_by_id.values():
		if item.required_level > 1 or item.required_unit_id != 0:
			continue
		if Equipment.slot_for_item(item) == -1:
			continue
		if best == null or item.id < best.id:
			best = item
	return best


func test_zone_map_button_states_follow_unlocks():
	var game = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	var map = game.get_node("ZoneMapOverlay")
	var zones = map.get_node("Zones")
	assert_eq(zones.get_child_count(), 7)
	assert_false(zones.get_node("Zone1").disabled, "zone 1 always unlocked")
	assert_true(zones.get_node("Zone2").disabled, "zone 2 locked at start")
	GameData.current_save.quest_progress[1] = 10
	ZoneManager.zone_unlocked.emit(2)
	await get_tree().process_frame
	assert_false(zones.get_node("Zone2").disabled, "zone 2 unlocks after the boss")

	# Connectors._draw() only runs while the panel (and so the whole subtree)
	# is visible - exercise it for real rather than just trusting the node
	# paths it hardcodes (Zone%d under ../Zones) line up with zone_map.tscn.
	map.visible = true
	await get_tree().process_frame
	assert_true(is_instance_valid(map.get_node("Connectors")), "connector lines node exists and drew without error")
