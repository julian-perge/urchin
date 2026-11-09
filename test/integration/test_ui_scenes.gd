# Integration tests for the rebuilt UI layer: main menu, the zone-hub shell
# (game.tscn), the 7 per-zone scenes with SWF-extracted orb positions, the
# hotbar, and the zone map.
extends GutTest

const MainMenuScene = preload("res://scenes/main_menu.tscn")
const GameScene = preload("res://scenes/game.tscn")
const ACHIEVEMENTS_FILE = "user://test_ui_scenes_achievements.cfg"

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


# The slot tests write saves, and every checkout shares one user:// folder with
# the player's real saves, so they write to a folder of their own.
const MENU_SAVE_DIR: String = "user://test_main_menu_saves/"


# The original opens on New Game and Load Game, MENU[21] and MENU[22]
# (frame_56/DoAction.as:1-2), with the slot list behind both.
func test_main_menu_opens_on_new_game_and_load_game():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	assert_true(menu.get_node("ModePanel").visible, "the menu opens on the choice")
	assert_eq(menu.get_node("ModePanel/NewGameLabel").text, "New Game")
	assert_eq(menu.get_node("ModePanel/LoadGameLabel").text, "Load Game")
	assert_false(menu.get_node("NamePanel").visible, "the name screen starts hidden")
	assert_false(menu.get_node("SlotPanel").visible, "the slot list starts hidden")


# Each rect is an edit text, a hit button or a shape that root frame 56
# (subMenu), 64 (nameMenu) or 74 (dataMenu) places, and Title's is the logo,
# sprite 321.
func test_main_menu_screens_use_the_frame_56_64_and_74_rects():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	var texts: Dictionary = {
		"ModePanel/Title": Rect2(123.2, 119.8, 549.55, 97.7),
		"ModePanel/NewGameLabel": Rect2(241.0, 290.1, 304.1, 45.6),
		"ModePanel/LoadGameLabel": Rect2(241.0, 350.1, 304.1, 45.6),
		"NamePanel/OkLabel": Rect2(339.4, 330.1, 121.25, 51.3),
		"NamePanel/BackLabel": Rect2(488.15, 532.15, 304.1, 30.85),
		"SlotPanel/BackLabel": Rect2(488.15, 532.15, 304.1, 30.85),
	}
	for path in texts:
		var label: Label = menu.get_node(path)
		assert_almost_eq(label.position, texts[path].position, Vector2(0.01, 0.01), "%s position" % path)
		assert_almost_eq(label.size.x, texts[path].size.x, 0.01, "%s width" % path)
	var boxes: Dictionary = {
		"ModePanel/NewGameButton": Rect2(241.06, 290.7, 302.27, 40.0),
		"ModePanel/LoadGameButton": Rect2(241.06, 350.7, 302.27, 40.0),
		"NamePanel/NameInput": Rect2(185.55, 252.2, 426.1, 45.25),
		"NamePanel/OkButton": Rect2(368.33, 336.6, 61.83, 30.0),
		"NamePanel/BackButton": Rect2(604.44, 534.45, 188.12, 26.8),
		"SlotPanel/BackButton": Rect2(604.44, 534.45, 188.12, 26.8),
	}
	for path in boxes:
		var box: Control = menu.get_node(path)
		assert_almost_eq(box.position, boxes[path].position, Vector2(0.01, 0.01), "%s position" % path)
		assert_almost_eq(box.size, boxes[path].size, Vector2(0.01, 0.01), "%s size" % path)


# New Game asks for the name before the slot list (DefineButton2_2707 goes to
# nameMenu and its OK!, DefineButton2_2710, goes to dataMenu), and Back returns
# to the choice from either screen.
func test_new_game_asks_for_the_name_before_the_slot_list():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	menu.get_node("ModePanel/NewGameButton").pressed.emit()
	assert_true(menu.get_node("NamePanel").visible, "New Game opens the name screen")
	assert_false(menu.get_node("ModePanel").visible, "in place of the choice")
	assert_false(menu.get_node("SlotPanel").visible, "before the slot list")
	assert_false(menu.new_game_panel.has_node("NameInput"), "class select no longer asks for the name")
	menu.get_node("NamePanel/BackButton").pressed.emit()
	assert_true(menu.get_node("ModePanel").visible, "Back on the name screen returns to the choice")
	assert_false(menu.get_node("NamePanel").visible)

	menu.get_node("ModePanel/NewGameButton").pressed.emit()
	menu.get_node("NamePanel/OkButton").pressed.emit()
	assert_true(menu.get_node("SlotPanel").visible, "OK! opens the slot list")
	assert_false(menu.get_node("NamePanel").visible)
	menu.get_node("SlotPanel/BackButton").pressed.emit()
	assert_true(menu.get_node("ModePanel").visible, "Back on the slot list returns to the choice")
	assert_false(menu.get_node("SlotPanel").visible)


# In New Game mode every slot goes straight on to class select with the typed
# name, used or not, and asks nothing (DefineButton2_2719 to 2722 on(release),
# lines 3-11). Only the Save button and a victory's autosave write a slot
# (krinHandleData, frame_42/DoAction_20.as:58-126), so the old save stays on
# disk until the new game first saves.
func test_new_game_starts_in_any_used_slot_and_keeps_its_save_until_the_first_save():
	_write_test_slots([1, 2, 3, 4])
	for slot in range(1, GameData.NUM_SLOTS + 1):
		var menu = await _menu_without_scene_change()
		menu.get_node("ModePanel/NewGameButton").pressed.emit()
		menu.name_input.text = "Fresh%d" % slot
		menu.get_node("NamePanel/OkButton").pressed.emit()
		var loaded_before: PlayerSave = GameData.current_save
		menu.slot_buttons.get_child(slot - 1).pressed.emit()
		assert_true(menu.new_game_panel.visible, "used slot %d goes on to class select" % slot)
		assert_false(menu.get_node("SlotPanel").visible, "slot %d leaves the slot list" % slot)
		assert_same(GameData.current_save, loaded_before, "slot %d loads nothing" % slot)
		assert_not_called(menu, "_enter_game")

		menu.class_picker.get_node("Hydraulic").pressed.emit()
		menu.get_node("OptionsPanel/StartButton").pressed.emit()
		assert_called(menu, "_enter_game")
		assert_eq(GameData.current_slot, slot, "the new game plays in slot %d" % slot)
		assert_eq(GameData.current_save.name_user, "Fresh%d" % slot, "under the typed name")
		assert_eq(GameData.current_save.player_class, PlayerSave.PlayerClass.HYDRAULIC, "as the picked class")
		assert_eq(_saved_name(slot), "Old%d" % slot, "slot %d still holds the old save after START" % slot)
		assert_true(GameData.save_game(), "the first save of slot %d" % slot)
		assert_eq(_saved_name(slot), "Fresh%d" % slot, "replaces the old save in slot %d" % slot)
	_clear_test_slots()


# Starting a new game in an empty slot writes nothing either, so a game that
# never saves leaves the slot empty.
func test_starting_a_new_game_in_an_empty_slot_writes_no_save():
	_write_test_slots([])
	var menu = await _menu_without_scene_change()
	menu.get_node("ModePanel/NewGameButton").pressed.emit()
	menu.get_node("NamePanel/OkButton").pressed.emit()
	menu.slot_buttons.get_child(2).pressed.emit()
	menu.class_picker.get_node("Biological").pressed.emit()
	menu.get_node("OptionsPanel/StartButton").pressed.emit()
	assert_called(menu, "_enter_game")
	assert_eq(GameData.current_slot, 3, "the new game plays in slot 3")
	assert_false(GameData.has_save(3), "and slot 3 stays empty until it saves")
	_clear_test_slots()


# Load Game skips the name screen (DefineButton2_2706 goes to dataMenu) and a
# slot only loads when it holds a save, the data.nameUser check in
# DefineButton2_2719 to 2722 on(release), line 12. An empty slot does nothing,
# and shows the original's "< Empty Slot >" (frame_74/DoAction.as:8).
func test_load_game_loads_a_used_slot_and_ignores_an_empty_one():
	_write_test_slots([1])
	var menu = await _menu_without_scene_change()
	menu.get_node("ModePanel/LoadGameButton").pressed.emit()
	assert_true(menu.get_node("SlotPanel").visible, "Load Game opens the slot list")
	assert_false(menu.get_node("NamePanel").visible, "without asking for a name")
	assert_eq(menu.slot_buttons.get_child(2).text, "Slot 3 - < Empty Slot >")

	var loaded_before: PlayerSave = GameData.current_save
	menu.slot_buttons.get_child(2).pressed.emit()
	assert_not_called(menu, "_enter_game")
	assert_same(GameData.current_save, loaded_before, "the empty slot loads nothing")
	assert_true(menu.get_node("SlotPanel").visible, "and the slot list stays up")
	assert_false(menu.new_game_panel.visible, "and no new game starts")

	menu.slot_buttons.get_child(0).pressed.emit()
	assert_called(menu, "_enter_game")
	assert_eq(GameData.current_slot, 1, "the used slot loads")
	assert_eq(GameData.current_save.name_user, "Old1", "with its own save")
	_clear_test_slots()


# In New Game mode a slot warns on hover with MENU[21] over MENU[25]
# (frame_1/DoAction.as:229 and 233), and in Load Game mode it shows nothing
# (DefineButton2_2719 to 2722 on(rollOver)).
func test_new_game_slots_warn_that_a_new_game_replaces_the_save():
	const WARNING: String = "Warning! Starting a new game in a saved slot will remove your old data! Saved games are stored relative to where you play this game."
	GameTooltip.hide_tooltip()
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	menu.get_node("ModePanel/LoadGameButton").pressed.emit()
	var slot: Button = menu.slot_buttons.get_child(0)
	slot.mouse_entered.emit()
	assert_false(GameTooltip._root.visible, "a Load Game slot doesn't warn")
	slot.mouse_exited.emit()

	menu.get_node("SlotPanel/BackButton").pressed.emit()
	menu.get_node("ModePanel/NewGameButton").pressed.emit()
	menu.get_node("NamePanel/OkButton").pressed.emit()
	slot.mouse_entered.emit()
	assert_true(GameTooltip._root.visible, "a New Game slot warns")
	assert_eq(GameTooltip._sections.get_child_count(), 2, "header plus warning")
	var header: Label = GameTooltip._sections.get_child(0).get_child(0).get_child(0)
	assert_eq(header.text, "New Game")
	var body: Label = GameTooltip._sections.get_child(1).get_child(0).get_child(0)
	assert_eq(body.text, WARNING)
	slot.mouse_exited.emit()
	assert_false(GameTooltip._root.visible, "leaving the slot hides the warning")


# The name field starts at SYSTEM[34], "< Enter Name Here >", each time the name
# screen opens (frame_64/DoAction.as:1, frame_1/DoAction.as:101), and edit text
# 2712 has no HasMaxLength flag, so nothing caps the name's length.
func test_new_game_starts_the_name_at_the_original_prompt_with_no_length_limit():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	menu.get_node("ModePanel/NewGameButton").pressed.emit()
	assert_eq(menu.name_input.text, "< Enter Name Here >", "the field starts at the prompt")
	assert_eq(menu.name_input.max_length, 0, "with no limit on the name's length")
	menu.name_input.text = "Typed then dropped"
	menu.get_node("NamePanel/BackButton").pressed.emit()
	menu.get_node("ModePanel/NewGameButton").pressed.emit()
	assert_eq(menu.name_input.text, "< Enter Name Here >", "opening the name screen again resets it")


# OK! goes on without reading the name (DefineButton2_2710 on(release), line
# 2), and the slot button copies it as it is into Krin.nameUser
# (DefineButton2_2722 on(release), line 5), so an untouched field starts a game
# named after the prompt and an emptied one a game with no name.
func test_new_game_keeps_the_name_as_typed_even_untouched_or_empty():
	_write_test_slots([])
	var untouched = await _menu_without_scene_change()
	untouched.get_node("ModePanel/NewGameButton").pressed.emit()
	_start_from_the_name_screen(untouched)
	assert_eq(GameData.current_save.name_user, "< Enter Name Here >", "an untouched field names the game after the prompt")

	var emptied = await _menu_without_scene_change()
	emptied.get_node("ModePanel/NewGameButton").pressed.emit()
	emptied.name_input.text = ""
	_start_from_the_name_screen(emptied)
	assert_eq(GameData.current_save.name_user, "", "an emptied field starts a game with no name")

	var spaced = await _menu_without_scene_change()
	spaced.get_node("ModePanel/NewGameButton").pressed.emit()
	spaced.name_input.text = " Newbie "
	_start_from_the_name_screen(spaced)
	assert_eq(GameData.current_save.name_user, " Newbie ", "and a typed name keeps its spaces")
	_clear_test_slots()


# The original calls the player "Sonny" everywhere in the game, Krin.NameSets[0]
# (frame_42/DoAction_17.as:45), which no save carries: the victory screen's
# player row (DefineSprite_3142/frame_9/PlaceObject3_3002_1197
# onClipEvent(load), lines 2 and 15), the abilities screen
# (DefineSprite_3142/frame_25/DoAction.as:7 and 16), the inventory screen
# (DefineSprite_3142/frame_1/DoAction.as:89 and 250) and the player's portrait
# tooltip there (DefineButton2_2895 on(rollOver), line 13). Only the slot list
# shows the typed name.
func test_the_game_calls_the_player_sonny_whatever_the_save_is_named():
	var save: PlayerSave = PlayerSave.new_game("< Enter Name Here >", 0)
	GameData.current_save = save
	var victory = add_child_autofree(load("res://scenes/battle/victory_screen.tscn").instantiate())
	victory.setup(save, {}, [], [])
	var rows: Array = victory.get_children().filter(func(child): return child is VictoryExperienceRow)
	assert_eq(rows.size(), 1, "one experience row, the player's")
	if rows.size() == 1:
		assert_eq(rows[0].name_label.text, "Sonny", "the victory screen's player row")

	var abilities = add_child_autofree(load("res://scenes/ui/menu/abilities_window.tscn").instantiate())
	abilities.refresh()
	assert_eq(abilities._name_label.text, "Sonny", "the abilities window")

	var inventory = add_child_autofree(load("res://scenes/ui/menu/inventory_window.tscn").instantiate())
	inventory.refresh()
	assert_eq(inventory._name_label.text, "Sonny", "the inventory window")
	assert_eq(inventory._portrait_frames[0].tooltip_text, "Sonny", "the player's portrait in the inventory window")


# Class select and settings place the same Back as the other menu frames, edit
# text 2703 over hit button 2702 at depths 35 and 36 of root frames 84
# (classMenu) and 93 (optionsMenu), captioned MENU[26] (frame_46/DoAction.as:1).
func test_class_select_and_settings_back_use_the_frame_84_and_93_rects():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	for panel in ["NewGamePanel", "OptionsPanel"]:
		var label: Label = menu.get_node("%s/BackLabel" % panel)
		assert_eq(label.text, "Back", "%s Back caption" % panel)
		assert_almost_eq(label.position, Vector2(488.15, 532.15), Vector2(0.01, 0.01), "%s Back text position" % panel)
		assert_almost_eq(label.size.x, 304.1, 0.01, "%s Back text width" % panel)
		var button: Button = menu.get_node("%s/BackButton" % panel)
		assert_true(button.flat, "%s Back is a bare hit area under its text" % panel)
		assert_almost_eq(button.position, Vector2(604.44, 534.45), Vector2(0.01, 0.01), "%s Back hit area position" % panel)
		assert_almost_eq(button.size, Vector2(188.12, 26.8), Vector2(0.01, 0.01), "%s Back hit area size" % panel)


# Back on class select and on settings goes to mainMenu in the original
# (DefineButton2_2702 on(release), line 2), so both return to the first screen.
func test_back_on_class_select_and_settings_returns_to_the_first_screen():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	menu.get_node("ModePanel/NewGameButton").pressed.emit()
	menu.get_node("NamePanel/OkButton").pressed.emit()
	menu.slot_buttons.get_child(0).pressed.emit()
	menu.get_node("NewGamePanel/BackButton").pressed.emit()
	assert_true(menu.get_node("ModePanel").visible, "Back on class select returns to the first screen")
	assert_false(menu.new_game_panel.visible)

	menu.get_node("ModePanel/NewGameButton").pressed.emit()
	menu.get_node("NamePanel/OkButton").pressed.emit()
	menu.slot_buttons.get_child(0).pressed.emit()
	menu.class_picker.get_node("Psychological").pressed.emit()
	menu.get_node("OptionsPanel/BackButton").pressed.emit()
	assert_true(menu.get_node("ModePanel").visible, "Back on settings returns to the first screen")
	assert_false(menu.options_panel.visible)
	assert_false(menu.new_game_panel.visible, "rather than to class select")


# Clicks OK!, slot 1, the Biological card and START, the way a player finishes
# starting a new game from the name screen.
func _start_from_the_name_screen(menu: Control) -> void:
	menu.get_node("NamePanel/OkButton").pressed.emit()
	menu.slot_buttons.get_child(0).pressed.emit()
	menu.class_picker.get_node("Biological").pressed.emit()
	menu.get_node("OptionsPanel/StartButton").pressed.emit()


# A partial double of the menu whose _enter_game does nothing, because the real
# one changes the scene and would take the test runner down with it.
func _menu_without_scene_change() -> Control:
	var menu = partial_double(MainMenuScene).instantiate()
	stub(menu, "_enter_game").to_do_nothing()
	add_child_autofree(menu)
	await get_tree().process_frame
	return menu


# Points GameData at the test folder, empties it and saves "Old<slot>" into each
# listed slot, so a menu built afterwards finds those slots used and the rest
# empty.
func _write_test_slots(slots: Array) -> void:
	GameData.save_dir = MENU_SAVE_DIR
	DirAccess.make_dir_recursive_absolute(MENU_SAVE_DIR)
	for slot in range(1, GameData.NUM_SLOTS + 1):
		DirAccess.remove_absolute(MENU_SAVE_DIR + "slot%d.tres" % slot)
	for slot in slots:
		GameData.new_game(slot, "Old%d" % slot)
		assert_true(GameData.save_game(), "test slot %d written" % slot)
	GameData.current_save = PlayerSave.new_game("UiTest", 0)
	GameData.current_slot = -1


# Reads the slot file itself rather than Godot's resource cache, so the name is
# what is on disk.
func _saved_name(slot: int) -> String:
	var save: Resource = ResourceLoader.load(MENU_SAVE_DIR + "slot%d.tres" % slot, "", ResourceLoader.CACHE_MODE_IGNORE)
	return save.name_user if save is PlayerSave else ""


func _clear_test_slots() -> void:
	for slot in range(1, GameData.NUM_SLOTS + 1):
		DirAccess.remove_absolute(MENU_SAVE_DIR + "slot%d.tres" % slot)
	DirAccess.remove_absolute(MENU_SAVE_DIR)
	GameData.save_dir = GameData.SAVE_DIR
	GameData.current_slot = -1


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


# The map hides the zones past its cap rather than locking them. mb6 hides
# itself on Easy, and mb7 unless the save is Heroic with Legend earned
# (DefineSprite_4173/frame_1, the onClipEvent(load) handlers of
# PlaceObject3_4160_85 and PlaceObject3_4160_91).
func test_zone_map_hides_zone_6_on_easy_and_zone_7_without_heroic_legend():
	var previous_path: String = ZoneManager.achievements_path
	if FileAccess.file_exists(ACHIEVEMENTS_FILE):
		DirAccess.remove_absolute(ACHIEVEMENTS_FILE)
	ZoneManager.achievements_path = ACHIEVEMENTS_FILE
	var game = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	var map = game.get_node("ZoneMapOverlay")
	var save: PlayerSave = GameData.current_save

	save.difficulty = CombatUnit.Difficulty.EASY
	assert_eq(_shown_zones(map), [1, 2, 3, 4, 5], "Easy hides zones 6 and 7")
	save.difficulty = CombatUnit.Difficulty.NORMAL
	assert_eq(_shown_zones(map), [1, 2, 3, 4, 5, 6], "Normal hides zone 7")
	save.difficulty = CombatUnit.Difficulty.HARD
	assert_eq(_shown_zones(map), [1, 2, 3, 4, 5, 6], "Heroic hides zone 7 without Legend")

	Achievements.unlock(4, ACHIEVEMENTS_FILE)
	assert_eq(_shown_zones(map), [1, 2, 3, 4, 5, 6, 7], "Heroic shows zone 7 with Legend")
	save.difficulty = CombatUnit.Difficulty.NORMAL
	assert_eq(_shown_zones(map), [1, 2, 3, 4, 5, 6], "Normal hides zone 7 with Legend")
	save.difficulty = CombatUnit.Difficulty.EASY
	assert_eq(_shown_zones(map), [1, 2, 3, 4, 5], "Easy hides zones 6 and 7 with Legend")

	ZoneManager.achievements_path = previous_path
	DirAccess.remove_absolute(ACHIEVEMENTS_FILE)


# Reopens the map so it refreshes its buttons, then lists the zones it shows.
func _shown_zones(map: Control) -> Array:
	map.visible = false
	map.visible = true
	var shown: Array = []
	for button in map.get_node("Zones").get_children():
		if button.visible:
			shown.append(int(button.name.trim_prefix("Zone")))
	return shown


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
