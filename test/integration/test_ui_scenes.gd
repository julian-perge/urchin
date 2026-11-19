# Integration tests for the rebuilt UI layer: main menu, the zone-hub shell
# (game.tscn), the 7 per-zone scenes with SWF-extracted orb positions, the
# hotbar, and the zone map.
extends GutTest

const MainMenuScene = preload("res://scenes/main_menu.tscn")
const GameScene = preload("res://scenes/game.tscn")
const OPEN_FACE := "res://assets/ui/zone_map/zone_button_open.png"
const LOCKED_FACE := "res://assets/ui/zone_map/zone_button_locked.png"
const ACHIEVEMENTS_FILE = "user://test_ui_scenes_achievements.cfg"


func before_each():
	GameData.current_save = PlayerSave.new_game("UiTest", 0)
	ZoneManager.auto_switch_scenes = false
	ZoneManager.current_zone = 1


func after_each():
	GameData.current_save = null
	ZoneManager.auto_switch_scenes = true
	ZoneManager.pending_battle = {}
	GameTooltip.hide_tooltip()


func test_main_menu_builds_slot_rows():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	var rows = menu.get_node("SlotPanel/Rows").get_children()
	assert_eq(rows.size(), GameData.NUM_SLOTS, "one row per save slot")
	assert_false(menu.get_node("SlotPanel").has_node("Layout"), "the slot buttons VBox is gone")
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


# The slot tests write saves to a folder of their own. A run that does not use
# `uv run gut` shares the real user://, and this folder keeps it off the real saves.
const MENU_SAVE_DIR: String = "user://test_main_menu_saves/"


const TITLE_CAPTIONS: String = "TitlePanel/Captions"
const BACK_PANELS: Array[String] = ["ModePanel", "ManualPanel", "NamePanel", "SlotPanel", "NewGamePanel", "OptionsPanel"]


# The original opens on mainMenu, root frame 46, whose captions are MENU[18],
# MENU[20] and MENU[91] (frame_46/DoAction_3.as:2-6). The two links to the
# publisher's site between them are left out (ADR 0002).
func test_main_menu_opens_on_the_title():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	assert_true(menu.get_node("TitlePanel").visible, "the menu opens on the title")
	assert_eq(menu.get_node(TITLE_CAPTIONS + "/PlaySlot/Caption").text, "Start!")
	assert_eq(menu.get_node(TITLE_CAPTIONS + "/GameManualSlot/Caption").text, "Game Manual")
	assert_eq(menu.get_node(TITLE_CAPTIONS + "/CreditsSlot/Caption").text, "Credits")
	assert_eq(menu.get_node(TITLE_CAPTIONS).get_child_count(), 3, "and no other caption")
	for panel in BACK_PANELS:
		assert_false(menu.get_node(panel).visible, "%s starts hidden" % panel)


# The title's first caption goes to subMenu (DefineButton2_2692 on(release)),
# New Game and Load Game, MENU[21] and MENU[22] (frame_56/DoAction.as:1-2).
func test_play_on_the_title_shows_new_game_and_load_game():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	menu.get_node(TITLE_CAPTIONS + "/PlaySlot/HitButton").pressed.emit()
	assert_true(menu.get_node("ModePanel").visible, "Play shows the choice")
	assert_false(menu.get_node("TitlePanel").visible, "in place of the title")
	assert_eq(menu.get_node("ModePanel/Captions/NewGameSlot/Caption").text, "New Game")
	assert_eq(menu.get_node("ModePanel/Captions/LoadGameSlot/Caption").text, "Load Game")


# The choice shows the logo, sprite 321, where the port once typed "Sonny 2".
# Its third caption, PvP Arena (edit text 2705), is left out with the arena
# (docs/adr/0006-leave-out-the-pvp-arena.md).
func test_the_choice_shows_the_logo_and_no_arena_caption():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	var choice: ModePanel = menu.get_node("ModePanel")
	assert_false(choice.has_node("Title"), "the 'Sonny 2' Label is gone")
	var logo: TextureRect = choice.get_node("Logo")
	assert_eq(logo.texture.resource_path, "res://assets/ui/menu/logo.png")
	assert_eq(choice.get_node("Captions").get_child_count(), 2, "New Game and Load Game only")
	assert_eq(choice.global_position, Vector2.ZERO, "the choice sits at the Stage's top left")
	assert_eq(choice.size, Vector2(800.0, 575.0))


# Credits opens a Screen the port does not have yet, so a click on it leaves
# the title up (spec/107-title-slots.md, The title).
func test_credits_leaves_the_title_up():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	var title: TitlePanel = menu.get_node("TitlePanel")
	watch_signals(title)
	menu.get_node(TITLE_CAPTIONS + "/CreditsSlot/HitButton").pressed.emit()
	assert_signal_emitted(title, "credits_pressed")
	assert_true(title.visible, "the title stays up")
	for panel in BACK_PANELS:
		assert_false(menu.get_node(panel).visible, "%s stays hidden" % panel)


# The title's Game Manual button, 2693, goes to designMenu, root frame 124
# (spec/107-game-manual.md).
func test_game_manual_on_the_title_shows_the_manual():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	menu.get_node(TITLE_CAPTIONS + "/GameManualSlot/HitButton").pressed.emit()
	assert_true(menu.get_node("ManualPanel").visible, "Game Manual shows the manual")
	assert_false(menu.get_node("TitlePanel").visible, "in place of the title")
	assert_eq(menu.get_node("ManualPanel/Body").text, "Please select a topic.")


# frame_124/DoAction.as sets the body to EXPLAINEXTRA on every entry to
# designMenu, so a topic read before Back does not stay on the next open.
func test_the_manual_asks_for_a_topic_again_on_each_open():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	var game_manual: Button = menu.get_node(TITLE_CAPTIONS + "/GameManualSlot/HitButton")
	game_manual.pressed.emit()
	menu.get_node("ManualPanel/Topics/Topic1/HitButton").pressed.emit()
	assert_ne(menu.get_node("ManualPanel/Body").text, "Please select a topic.", "a topic is shown")
	menu.get_node("ManualPanel/Back/HitButton").pressed.emit()
	game_manual.pressed.emit()
	assert_eq(menu.get_node("ManualPanel/Body").text, "Please select a topic.")


# Returns one message for each panel whose Back does not swap that panel for
# the title.
func _back_problems(menu: Control) -> Array[String]:
	var found: Array[String] = []
	for panel_name in BACK_PANELS:
		var panel: Control = menu.get_node(panel_name)
		menu._show_screen(panel)
		(panel.get_node("Back/HitButton") as Button).pressed.emit()
		if not menu.get_node("TitlePanel").visible:
			found.append("%s: Back does not show the title" % panel_name)
		if panel.visible:
			found.append("%s: Back leaves the panel up" % panel_name)
	return found


# Back goes to mainMenu from every menu frame that places it
# (DefineButton2_2702 on(release), line 2).
func test_back_on_every_panel_shows_the_title():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	assert_eq(_back_problems(menu), [] as Array[String])


func test_control_a_back_with_no_target_fails_the_back_check():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	(menu.get_node("SlotPanel/Back") as MenuBack).pressed.disconnect(menu._on_back_pressed)
	assert_eq(_back_problems(menu), [
		"SlotPanel: Back does not show the title",
		"SlotPanel: Back leaves the panel up",
	] as Array[String])


# Each panel's Back is the shared scene, whose own pieces the rect test checks.
# An instance that sets a layout mode loses its root's offsets (docs/agents/godot.md),
# so this checks that each one still covers the Stage from its top left.
func test_every_panel_places_the_shared_back_over_the_whole_stage():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	for panel in BACK_PANELS:
		var back: MenuBack = menu.get_node("%s/Back" % panel)
		assert_eq(back.global_position, Vector2.ZERO, "%s Back position" % panel)
		assert_eq(back.size, Vector2(800.0, 575.0), "%s Back size" % panel)
		assert_eq((back.get_node("Caption") as Label).text, "Back", "%s Back caption, MENU[26]" % panel)


# The background and the title are the shared scenes too, at the Stage's top left.
func test_the_menu_places_the_shared_background_and_the_title_at_the_stage_origin():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	for path in ["Background", "TitlePanel"]:
		var piece: Control = menu.get_node(path)
		assert_eq(piece.global_position, Vector2.ZERO, "%s position" % path)
		assert_eq(piece.size, Vector2(800.0, 575.0), "%s size" % path)


# A caption's Glow and DropShadow are a black outline and a black shadow on the
# MenuCaption variation of the project Theme (spec/107-title-slots.md, The
# caption look), so no scene sets them itself.
func test_menu_captions_take_their_outline_and_shadow_from_the_theme():
	var theme: Theme = ThemeDB.get_project_theme()
	assert_eq(theme.get_type_variation_base("MenuCaption"), &"Label")
	assert_eq(theme.get_color("font_color", "MenuCaption"), Color.WHITE)
	assert_eq(theme.get_color("font_outline_color", "MenuCaption"), Color.BLACK)
	assert_eq(theme.get_color("font_shadow_color", "MenuCaption"), Color.BLACK)
	assert_eq(theme.get_constant("outline_size", "MenuCaption"), 4, "the outline for the Glow")
	assert_eq(theme.get_constant("shadow_outline_size", "MenuCaption"), 4, "the shadow is as wide as the outline")
	assert_eq(theme.get_constant("shadow_offset_x", "MenuCaption"), 1, "the shadow for the DropShadow")
	assert_eq(theme.get_constant("shadow_offset_y", "MenuCaption"), 1)
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	var captions: Array[String] = [
		"ModePanel/Back/Caption",
		"ModePanel/Captions/NewGameSlot/Caption",
		"ModePanel/Captions/LoadGameSlot/Caption",
		"SlotPanel/Back/Caption",
	]
	for slot in range(1, GameData.NUM_SLOTS + 1):
		for node in ["SlotLabel", "Number"]:
			captions.append("SlotPanel/Rows/Row%d/%s" % [slot, node])
	for slot in ["PlaySlot", "GameManualSlot", "CreditsSlot"]:
		captions.append("%s/%s/Caption" % [TITLE_CAPTIONS, slot])
	for path in captions:
		var caption: Label = menu.get_node(path)
		assert_eq(caption.theme_type_variation, &"MenuCaption", path)
		for override in ["font_color", "font_outline_color", "font_shadow_color"]:
			assert_false(caption.has_theme_color_override(override), "%s sets no %s" % [path, override])
		assert_false(caption.has_theme_constant_override("outline_size"), "%s sets no outline size" % path)


# Each rect is an edit text, a hit button or a shape that root frame 64
# (nameMenu) places. The rect test checks the choice, frame 56.
func test_the_name_screen_uses_the_frame_64_rects():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	var texts: Dictionary = {
		"NamePanel/OkLabel": Rect2(339.4, 330.1, 121.25, 51.3),
	}
	for path in texts:
		var label: Label = menu.get_node(path)
		assert_almost_eq(label.position, texts[path].position, Vector2(0.01, 0.01), "%s position" % path)
		assert_almost_eq(label.size.x, texts[path].size.x, 0.01, "%s width" % path)
	var boxes: Dictionary = {
		"NamePanel/NameInput": Rect2(185.55, 252.2, 426.1, 45.25),
		"NamePanel/OkButton": Rect2(368.33, 336.6, 61.83, 30.0),
	}
	for path in boxes:
		var box: Control = menu.get_node(path)
		assert_almost_eq(box.position, boxes[path].position, Vector2(0.01, 0.01), "%s position" % path)
		assert_almost_eq(box.size, boxes[path].size, Vector2(0.01, 0.01), "%s size" % path)


# New Game asks for the name before the slot list (DefineButton2_2707 goes to
# nameMenu and its OK!, DefineButton2_2710, goes to dataMenu), and Back returns
# to the title from either screen.
func test_new_game_asks_for_the_name_before_the_slot_list():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	menu.get_node("ModePanel/Captions/NewGameSlot/HitButton").pressed.emit()
	assert_true(menu.get_node("NamePanel").visible, "New Game opens the name screen")
	assert_false(menu.get_node("ModePanel").visible, "in place of the choice")
	assert_false(menu.get_node("SlotPanel").visible, "before the slot list")
	assert_false(menu.new_game_panel.has_node("NameInput"), "class select no longer asks for the name")
	menu.get_node("NamePanel/Back/HitButton").pressed.emit()
	assert_true(menu.get_node("TitlePanel").visible, "Back on the name screen returns to the title")
	assert_false(menu.get_node("NamePanel").visible)

	menu.get_node("ModePanel/Captions/NewGameSlot/HitButton").pressed.emit()
	menu.get_node("NamePanel/OkButton").pressed.emit()
	assert_true(menu.get_node("SlotPanel").visible, "OK! opens the slot list")
	assert_false(menu.get_node("NamePanel").visible)
	menu.get_node("SlotPanel/Back/HitButton").pressed.emit()
	assert_true(menu.get_node("TitlePanel").visible, "Back on the slot list returns to the title")
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
		menu.get_node("ModePanel/Captions/NewGameSlot/HitButton").pressed.emit()
		menu.name_input.text = "Fresh%d" % slot
		menu.get_node("NamePanel/OkButton").pressed.emit()
		var loaded_before: PlayerSave = GameData.current_save
		_slot_button(menu, slot).pressed.emit()
		assert_true(menu.new_game_panel.visible, "used slot %d goes on to class select" % slot)
		assert_false(menu.get_node("SlotPanel").visible, "slot %d leaves the slot list" % slot)
		assert_same(GameData.current_save, loaded_before, "slot %d loads nothing" % slot)
		assert_not_called(menu, "_enter_game")

		menu.class_picker.get_node("Hydraulic").pressed.emit()
		ZoneManager.pending_battle = {}
		menu.get_node("OptionsPanel/StartButton").pressed.emit()
		assert_false(ZoneManager.pending_battle.is_empty(), "START goes on to the first fight")
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
	menu.get_node("ModePanel/Captions/NewGameSlot/HitButton").pressed.emit()
	menu.get_node("NamePanel/OkButton").pressed.emit()
	_slot_button(menu, 3).pressed.emit()
	menu.class_picker.get_node("Biological").pressed.emit()
	menu.get_node("OptionsPanel/StartButton").pressed.emit()
	assert_false(ZoneManager.pending_battle.is_empty(), "START goes on to the first fight")
	assert_eq(GameData.current_slot, 3, "the new game plays in slot 3")
	assert_false(GameData.has_save(3), "and slot 3 stays empty until it saves")
	_clear_test_slots()


# The Tutorial option is on until the player turns it off (frame_93/DoAction.as:7),
# and this test leaves the toggle alone. With it on, the original's START plays
# CS_INTRO (DefineButton2_2770 on(release), lines 2-6). The clip's end goes to
# IntroSeq, which starts battle 2 with progressFight off
# (frame_165/DoAction.as:2-3). The pick waits in ZoneManager for the Battle screen.
func test_new_game_with_the_tutorial_on_goes_on_to_battle_2_after_cs_intro():
	_write_test_slots([])
	var menu = await _menu_without_scene_change()
	menu.get_node("ModePanel/Captions/NewGameSlot/HitButton").pressed.emit()
	menu.get_node("NamePanel/OkButton").pressed.emit()
	_slot_button(menu, 1).pressed.emit()
	menu.class_picker.get_node("Biological").pressed.emit()
	assert_true(menu.get_node("OptionsPanel/TutorialToggle").button_pressed, "the toggle starts on")
	menu.get_node("OptionsPanel/StartButton").pressed.emit()

	var pick: Dictionary = ZoneManager.pending_battle
	assert_eq(pick.get("battle_id"), 2, "the first fight is battle 2")
	assert_false(pick.get("is_story_progress", true), "and not a Story fight")
	assert_eq(pick.get("cutscene_before"), "CS_INTRO", "with CS_INTRO before it")
	_clear_test_slots()


# IntroSeq puts the Tutorial's two moves on the first two bar slots for battle 2,
# whatever the class, and touches no other slot (frame_165/DoAction.as:6-7).
func test_new_game_with_the_tutorial_on_puts_the_tutorial_moves_on_the_bar():
	_write_test_slots([])
	var menu = await _menu_without_scene_change()
	menu.get_node("ModePanel/Captions/NewGameSlot/HitButton").pressed.emit()
	menu.get_node("NamePanel/OkButton").pressed.emit()
	_slot_button(menu, 1).pressed.emit()
	menu.class_picker.get_node("Hydraulic").pressed.emit()
	menu.get_node("OptionsPanel/StartButton").pressed.emit()

	var bar: Array = GameData.current_save.move_matrix
	var tutorial_moves: Array = ZoneProgression.TUTORIAL_MOVES
	assert_eq(bar.slice(0, tutorial_moves.size()), tutorial_moves, "the Tutorial's two moves lead the bar")
	assert_eq(bar.slice(tutorial_moves.size()).count(0), bar.size() - tutorial_moves.size(), "and no other slot holds a move")
	_clear_test_slots()


# START goes on to the first fight and not to the hub. With the Tutorial off the
# original's START plays CS_INTRO2 (DefineButton2_2770 on(release), lines 7-10).
# That clip's end goes to IntroSeq2 (frame_293/DoAction.as:1), which starts
# battle 100 as a progress fight (frame_180/DoAction.as:2-3). The pick waits in
# ZoneManager for the Battle screen.
func test_new_game_with_the_tutorial_off_goes_on_to_battle_100_after_cs_intro2():
	_write_test_slots([])
	var menu = await _menu_without_scene_change()
	menu.get_node("ModePanel/Captions/NewGameSlot/HitButton").pressed.emit()
	menu.get_node("NamePanel/OkButton").pressed.emit()
	_slot_button(menu, 1).pressed.emit()
	menu.class_picker.get_node("Biological").pressed.emit()
	menu.get_node("OptionsPanel/TutorialToggle").button_pressed = false
	menu.get_node("OptionsPanel/StartButton").pressed.emit()

	var pick: Dictionary = ZoneManager.pending_battle
	assert_eq(pick.get("battle_id"), 100, "the first fight is battle 100")
	assert_true(pick.get("is_story_progress", false), "as a Story fight")
	assert_eq(pick.get("cutscene_before"), "CS_INTRO2", "with CS_INTRO2 before it")
	var bar: Array = GameData.current_save.move_matrix
	var starting_moves: Array = TalentTree.STARTING_MOVES[PlayerSave.PlayerClass.BIOLOGICAL]
	assert_eq(bar.slice(0, starting_moves.size()), starting_moves, "and the class's starting moves stay on the bar")
	assert_eq(bar.slice(starting_moves.size()).count(0), bar.size() - starting_moves.size(), "with no other slot holding a move")
	_clear_test_slots()


# Load Game skips the name screen (DefineButton2_2706 goes to dataMenu) and a
# slot only loads when it holds a save, the data.nameUser check in
# DefineButton2_2719 to 2722 on(release), line 12. An empty slot does nothing,
# and shows the original's "< Empty Slot >" (frame_74/DoAction.as:8).
func test_load_game_loads_a_used_slot_and_ignores_an_empty_one():
	_write_test_slots([1])
	var menu = await _menu_without_scene_change()
	menu.get_node("ModePanel/Captions/LoadGameSlot/HitButton").pressed.emit()
	assert_true(menu.get_node("SlotPanel").visible, "Load Game opens the slot list")
	assert_false(menu.get_node("NamePanel").visible, "without asking for a name")
	assert_eq(_slot_row(menu, 3).get_node("SaveName").text, "< Empty Slot >")

	var loaded_before: PlayerSave = GameData.current_save
	_slot_button(menu, 3).pressed.emit()
	assert_not_called(menu, "_enter_game")
	assert_same(GameData.current_save, loaded_before, "the empty slot loads nothing")
	assert_true(menu.get_node("SlotPanel").visible, "and the slot list stays up")
	assert_false(menu.new_game_panel.visible, "and no new game starts")

	_slot_button(menu, 1).pressed.emit()
	assert_called(menu, "_enter_game")
	assert_eq(GameData.current_slot, 1, "the used slot loads")
	assert_eq(GameData.current_save.name_user, "Old1", "with its own save")
	_clear_test_slots()


# Each row is slotNamerText, MENU[23], then the slot's number and the save's
# nameUser, or "< Empty Slot >" when the slot has none (frame_74/DoAction.as:1-11).
# The original shows no level and no zone. "(corrupted)" is the port's own, for
# a slot file that is not a save (spec/107-title-slots.md, Open questions).
func test_slot_rows_show_the_name_or_empty_slot_with_no_level_or_zone():
	_write_test_slots([1, 4])
	ResourceSaver.save(Resource.new(), MENU_SAVE_DIR + "slot2.tres")
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	var names: Array[String] = []
	for slot in range(1, GameData.NUM_SLOTS + 1):
		var row: Control = _slot_row(menu, slot)
		assert_eq(row.get_node("SlotLabel").text, "Slot", "row %d caption, MENU[23]" % slot)
		assert_eq(row.get_node("Number").text, str(slot), "row %d number" % slot)
		assert_eq(row.get_node("HitButton").text, "", "row %d hit button draws no text" % slot)
		names.append(row.get_node("SaveName").text)
	assert_eq(names, ["Old1", "(corrupted)", "< Empty Slot >", "Old4"] as Array[String])
	_clear_test_slots()


# The hit button covers the "Slot" caption and the number, not the name
# (DefineButton2_2719 to 2722), so a click on the name reaches nothing. The
# slots are empty and the menu is in Load Game mode, so a click that does reach
# a hit button loads nothing.
func test_a_click_on_the_name_column_does_nothing():
	_write_test_slots([])
	# GUT's window sits above everything in the root viewport and would take
	# the clicks, so the menu gets a viewport of its own.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 575)
	add_child_autofree(viewport)
	var menu = MainMenuScene.instantiate()
	viewport.add_child(menu)
	await get_tree().process_frame
	menu.get_node("ModePanel/Captions/LoadGameSlot/HitButton").pressed.emit()
	var panel: Control = menu.get_node("SlotPanel")
	watch_signals(panel)
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the panel takes no click")
	assert_eq(panel.get_node("Rows").mouse_filter, Control.MOUSE_FILTER_IGNORE, "nor the column")
	for slot in range(1, GameData.NUM_SLOTS + 1):
		var row: Control = _slot_row(menu, slot)
		var save_name: Label = row.get_node("SaveName")
		var hit: Button = row.get_node("HitButton")
		assert_eq(row.mouse_filter, Control.MOUSE_FILTER_IGNORE, "row %d takes no click" % slot)
		assert_eq(save_name.mouse_filter, Control.MOUSE_FILTER_IGNORE, "row %d name takes no click" % slot)
		assert_false(hit.get_global_rect().intersects(save_name.get_global_rect()), "row %d hit button stays off the name" % slot)
		assert_true(hit.get_global_rect().intersects(row.get_node("SlotLabel").get_global_rect()), "row %d hit button covers the caption" % slot)
		_click(save_name)
		assert_signal_emit_count(panel, "slot_pressed", slot - 1, "a click on row %d's name presses no slot" % slot)
		_click(hit)
		assert_signal_emitted_with_parameters(panel, "slot_pressed", [slot])
		assert_signal_emit_count(panel, "slot_pressed", slot, "a click on row %d's hit button presses it" % slot)
	_clear_test_slots()


# In New Game mode a slot warns on hover with MENU[21] over MENU[25]
# (frame_1/DoAction.as:229 and 233), and in Load Game mode it shows nothing
# (DefineButton2_2719 to 2722 on(rollOver)).
func test_new_game_slots_warn_that_a_new_game_replaces_the_save():
	const WARNING: String = "Warning! Starting a new game in a saved slot will remove your old data! Saved games are stored relative to where you play this game."
	GameTooltip.hide_tooltip()
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	menu.get_node("ModePanel/Captions/LoadGameSlot/HitButton").pressed.emit()
	var slot: Button = _slot_button(menu, 1)
	slot.mouse_entered.emit()
	assert_false(GameTooltip._root.visible, "a Load Game slot doesn't warn")
	slot.mouse_exited.emit()

	menu.get_node("SlotPanel/Back/HitButton").pressed.emit()
	menu.get_node("ModePanel/Captions/NewGameSlot/HitButton").pressed.emit()
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


# The warning opens beside the slot the pointer is on, so it moves down by the
# distance between two rows' hit buttons when the pointer moves between them.
func test_the_new_game_warning_opens_beside_the_hovered_slot():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	menu.get_node("ModePanel/Captions/NewGameSlot/HitButton").pressed.emit()
	menu.get_node("NamePanel/OkButton").pressed.emit()
	var first: Button = _slot_button(menu, 1)
	var third: Button = _slot_button(menu, 3)
	first.mouse_entered.emit()
	await wait_process_frames(2)
	var first_y: float = GameTooltip._root.global_position.y
	first.mouse_exited.emit()
	third.mouse_entered.emit()
	await wait_process_frames(2)
	assert_almost_eq(
		GameTooltip._root.global_position.y - first_y,
		third.global_position.y - first.global_position.y,
		0.01,
		"the warning follows the pointer from slot 1 to slot 3"
	)
	assert_gt(third.global_position.y, first.global_position.y, "slot 3 sits under slot 1")


# The name field starts at SYSTEM[34], "< Enter Name Here >", each time the name
# screen opens (frame_64/DoAction.as:1, frame_1/DoAction.as:101), and edit text
# 2712 has no HasMaxLength flag, so nothing caps the name's length.
func test_new_game_starts_the_name_at_the_original_prompt_with_no_length_limit():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	menu.get_node("ModePanel/Captions/NewGameSlot/HitButton").pressed.emit()
	assert_eq(menu.name_input.text, "< Enter Name Here >", "the field starts at the prompt")
	assert_eq(menu.name_input.max_length, 0, "with no limit on the name's length")
	menu.name_input.text = "Typed then dropped"
	menu.get_node("NamePanel/Back/HitButton").pressed.emit()
	menu.get_node("ModePanel/Captions/NewGameSlot/HitButton").pressed.emit()
	assert_eq(menu.name_input.text, "< Enter Name Here >", "opening the name screen again resets it")


# OK! goes on without reading the name (DefineButton2_2710 on(release), line
# 2), and the slot button copies it as it is into Krin.nameUser
# (DefineButton2_2722 on(release), line 5), so an untouched field starts a game
# named after the prompt and an emptied one a game with no name.
func test_new_game_keeps_the_name_as_typed_even_untouched_or_empty():
	_write_test_slots([])
	var untouched = await _menu_without_scene_change()
	untouched.get_node("ModePanel/Captions/NewGameSlot/HitButton").pressed.emit()
	_start_from_the_name_screen(untouched)
	assert_eq(GameData.current_save.name_user, "< Enter Name Here >", "an untouched field names the game after the prompt")

	var emptied = await _menu_without_scene_change()
	emptied.get_node("ModePanel/Captions/NewGameSlot/HitButton").pressed.emit()
	emptied.name_input.text = ""
	_start_from_the_name_screen(emptied)
	assert_eq(GameData.current_save.name_user, "", "an emptied field starts a game with no name")

	var spaced = await _menu_without_scene_change()
	spaced.get_node("ModePanel/Captions/NewGameSlot/HitButton").pressed.emit()
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
	var victory = add_child_autofree(load("res://scenes/ui/menu/victory_window.tscn").instantiate())
	var settlement := BattleSettlement.new()
	settlement.fighters[0] = BattleSettlement.FighterExperience.new()
	victory.setup(save, settlement)
	var row: VictoryExpRow = victory.get_node("ExpRows/PlayerSlot/Row")
	assert_eq(row.name_label.text, "Sonny", "the victory screen's player row")

	var abilities = add_child_autofree(load("res://scenes/ui/menu/abilities_window.tscn").instantiate())
	abilities.refresh()
	assert_eq(abilities._name_label.text, "Sonny", "the abilities window")

	var inventory = add_child_autofree(load("res://scenes/ui/menu/inventory_window.tscn").instantiate())
	inventory.refresh()
	assert_eq(inventory._name_label.text, "Sonny", "the inventory window")
	assert_eq(inventory._party_faces[0].tooltip().get("title"), "Sonny", "the player's face in the inventory window")


# Back on settings goes to mainMenu (DefineButton2_2702 on(release), line 2),
# not to class select, the panel the player came from.
func test_back_on_settings_hides_class_select_too():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	menu.get_node("ModePanel/Captions/NewGameSlot/HitButton").pressed.emit()
	menu.get_node("NamePanel/OkButton").pressed.emit()
	_slot_button(menu, 1).pressed.emit()
	menu.class_picker.get_node("Psychological").pressed.emit()
	menu.get_node("OptionsPanel/Back/HitButton").pressed.emit()
	assert_true(menu.get_node("TitlePanel").visible, "Back on settings returns to the title")
	assert_false(menu.options_panel.visible)
	assert_false(menu.new_game_panel.visible, "rather than to class select")


# Clicks OK!, slot 1, the Biological card and START, the way a player finishes
# starting a new game from the name screen.
func _start_from_the_name_screen(menu: Control) -> void:
	menu.get_node("NamePanel/OkButton").pressed.emit()
	_slot_button(menu, 1).pressed.emit()
	menu.class_picker.get_node("Biological").pressed.emit()
	menu.get_node("OptionsPanel/StartButton").pressed.emit()


# A left click on the control's center, pushed through the GUI input of the
# viewport that holds the control.
func _click(control: Control) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = control.get_global_rect().get_center()
		event.global_position = event.position
		control.get_viewport().push_input(event, true)


func _slot_row(menu: Control, slot: int) -> Control:
	return menu.get_node("SlotPanel/Rows/Row%d" % slot)


func _slot_button(menu: Control, slot: int) -> Button:
	return _slot_row(menu, slot).get_node("HitButton")


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
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/screen_rects.json"))
	for zone_id in range(1, 8):
		var path = str(ZoneManager.ZONES[zone_id]["scene"])
		assert_true(ResourceLoader.exists(path), "zone %d scene exists" % zone_id)
		var zone = add_child_autofree(load(path).instantiate())
		assert_eq(zone.zone_id, zone_id, "zone_id wired")
		var story: Node2D = zone.get_node("StoryFight")
		var store: Node2D = zone.get_node("ItemStore")
		assert_not_null(story)
		assert_not_null(store)
		assert_eq(zone.has_node("TrainingFight"), zone_id != 7, "zone %d training orb" % zone_id)
		var position: Array = record["scenes"][path]["pieces"]["StoryFight"]["position"]
		var expected := Vector2(position[0], position[1])
		assert_almost_eq(story.position.x, expected.x, 0.1, "zone %d story orb x" % zone_id)
		assert_almost_eq(story.position.y, expected.y, 0.1, "zone %d story orb y" % zone_id)
		assert_not_null(zone.get_node("HubArt").texture, "zone %d hub art loads" % zone_id)


func test_zone_7_has_only_the_orbs_the_japan_frame_places():
	var zone = add_child_autofree(load(str(ZoneManager.ZONES[7]["scene"])).instantiate())
	var orbs: Dictionary = {}
	for child in zone.get_children():
		if child is OrbBase:
			orbs[str(child.name)] = child
	assert_eq(orbs.keys(), ["StoryFight", "ItemStore"], "the story and shop orbs and nothing else")
	assert_true(orbs.get("StoryFight") is StoryFightOrb, "the story orb fights the next story battle")
	assert_true(orbs.get("ItemStore") is ItemStoreOrb, "the shop orb opens the store")


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
	assert_almost_eq(hotbar.zone_fill.scale.x, 3.0 / 9.0, 0.0001, "quest progress drives the bar")
	assert_eq(hotbar.zone_fill.scale.y, 1.0, "the fill keeps its height")
	assert_eq(hotbar.zone_fill.pivot_offset, Vector2.ZERO, "the fill grows from its left edge")
	assert_eq(hotbar.stage_label.text, "Stage 4")


# Each slot button loads its slot and goes to the Navigation frame
# (DefineButton2_2719 to 2722 on(release), lines 15 and 32), and that frame
# builds the panel's three strings and its bar from the loaded save's zone
# (frame_181/DoAction.as:5-14). So right after a load the panel names the saved
# zone, whatever zone the game showed before.
func test_hotbar_shows_the_saved_zone_right_after_a_load():
	GameData.current_save.section_in = 4
	GameData.current_save.quest_progress[1] = 3
	GameData.current_save.quest_progress[4] = 6
	var game = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	assert_eq(game.zone_host.get_child(0).zone_id, 4, "the hub opened on the saved zone")
	var hotbar = game.get_node("Hotbar")
	assert_eq(hotbar.zone_title.text, "Zone 4")
	assert_eq(hotbar.zone_subtitle.text, "Labyrinth: Tunnel of Illusions")
	assert_almost_eq(hotbar.zone_fill.scale.x, 6.0 / 9.0, 0.0001, "zone 4's progress, not zone 1's")
	assert_eq(hotbar.stage_label.text, "Stage 7")


func test_hotbar_ignores_the_zone_another_slot_left_behind():
	ZoneManager.current_zone = 2
	GameData.current_save.section_in = 4
	GameData.current_save.quest_progress[1] = 3
	GameData.current_save.quest_progress[4] = 6
	var game = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	assert_eq(game.zone_host.get_child(0).zone_id, 4, "the hub opened on the saved zone")
	var hotbar = game.get_node("Hotbar")
	assert_eq(hotbar.zone_title.text, "Zone 4")
	assert_eq(hotbar.zone_subtitle.text, "Labyrinth: Tunnel of Illusions")
	assert_almost_eq(hotbar.zone_fill.scale.x, 6.0 / 9.0, 0.0001, "zone 4's progress, not zone 2's")
	assert_eq(hotbar.stage_label.text, "Stage 7")


# Re-Load after a game over reads the slot back from disk while ZoneManager
# still holds the zone the fight was lost in. The original's Re-Load goes to
# the same Navigation frame as a load from the menu (DefineButton2_2791
# on(release), lines 4-7), so its panel names the saved zone too.
func test_hotbar_shows_the_saved_zone_after_a_game_over_reload():
	var save_dir: String = "user://test_ui_scenes_reload_saves/"
	GameData.save_dir = save_dir
	DirAccess.make_dir_recursive_absolute(save_dir)
	GameData.new_game(1, "ReloadZone")
	GameData.current_save.section_in = 4
	GameData.current_save.quest_progress[4] = 6
	assert_true(GameData.save_game(), "the test slot was written")
	GameData.current_save.section_in = 2
	ZoneManager.current_zone = 2

	var game_over: GameOverScreen = autofree(load("res://scenes/battle/game_over_screen.tscn").instantiate())
	assert_eq(game_over.reload_last_save(), "res://scenes/game.tscn", "Re-Load opens the hub")
	var game = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	assert_eq(game.zone_host.get_child(0).zone_id, 4, "the hub opened on the saved zone")
	var hotbar = game.get_node("Hotbar")
	assert_eq(hotbar.zone_title.text, "Zone 4")
	assert_eq(hotbar.zone_subtitle.text, "Labyrinth: Tunnel of Illusions")
	assert_almost_eq(hotbar.zone_fill.scale.x, 6.0 / 9.0, 0.0001, "zone 4's progress, not zone 2's")
	assert_eq(hotbar.stage_label.text, "Stage 7")

	GameData.current_slot = -1
	DirAccess.remove_absolute(save_dir + "slot1.tres")
	DirAccess.remove_absolute(save_dir)
	GameData.save_dir = GameData.SAVE_DIR


# The original caps the bar at the zone's progressMax but not the stage text,
# which adds one to the raw quest progress (frame_181/DoAction.as:7-14). So a
# beaten zone 1, at progress 10, shows a full bar and Stage 11.
func test_hotbar_stage_keeps_counting_past_a_beaten_zone():
	GameData.current_save.quest_progress[1] = 10
	var game = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	var hotbar = game.get_node("Hotbar")
	assert_almost_eq(hotbar.zone_fill.scale.x, 9.0 / 9.0, 0.0001, "the bar stops at zone 1's progress_max")
	assert_eq(hotbar.stage_label.text, "Stage 11")


# The panel's name line is ZONES[zone], then ": ", then ZONES2[zone]
# (frame_181/DoAction.as:13), and these are those strings from
# frame_41/DoAction.as:123-136. Zone 3's name there is "Ivory Line " with a
# trailing space, so its line reads "Ivory Line : The Train".
func test_hotbar_names_every_zone_with_the_original_strings():
	var expected: Dictionary = {
		1: "New Alcatraz: The Iron Prison",
		2: "Oberursel: The Frozen Village",
		3: "Ivory Line : The Train",
		4: "Labyrinth: Tunnel of Illusions",
		5: "Hew: The Dystopia",
		6: "Il Sanctus: The Supreme Court",
		7: "Sho'Tul Shelf: The Divided Cliff",
	}
	var game = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	var hotbar = game.get_node("Hotbar")
	for zone_id in expected:
		ZoneManager.current_zone = zone_id
		ZoneManager.zone_changed.emit(zone_id)
		assert_eq(hotbar.zone_subtitle.text, expected[zone_id], "zone %d" % zone_id)


func test_inventory_window_equips_from_grid_click():
	var item = _find_basic_equippable()
	assert_not_null(item, "an unrestricted level-1 equippable exists")
	GameData.current_save.item_array[0] = item.id
	var window = add_child_autofree(load("res://scenes/ui/menu/inventory_window.tscn").instantiate())
	window.refresh()
	var slot: ItemSlot = window.right_column.slots[0]
	assert_eq(slot.item.id, item.id, "grid slot 0 mirrors item_array[0]")
	window.right_column._on_slot_clicked(slot)
	var equip_slot = Equipment.slot_for_item(item)
	assert_eq(int(GameData.current_save.equip_array[equip_slot]), item.id, "click equips into the natural slot")
	assert_eq(int(GameData.current_save.item_array[0]), 0, "inventory cell emptied")
	window._on_equip_slot_clicked(equip_slot)
	assert_eq(int(GameData.current_save.equip_array[equip_slot]), 0, "equip slot click unequips")
	assert_eq(int(GameData.current_save.item_array[0]), item.id, "item returns to the first free cell")


# An empty equip slot holds item 0, so the original titles its tooltip with
# item 0's name, ITEMNAME[0] "None" (frame_1/DoAction.as:1606), over the
# slot's own type, ITEMSS[IPS - 2] (DefineButton2_2981 on(rollOver), lines
# 4-9). The head slot's IPS is 2, which makes its type "Headwear".
func test_an_empty_equip_slot_names_its_slot_type():
	var window = add_child_autofree(load("res://scenes/ui/menu/inventory_window.tscn").instantiate())
	window.refresh()
	var head_slot: ItemSlot = null
	for child in window.equip_view.get_children():
		if child is ItemSlot and int(child.get_meta("equip_index")) == Equipment.EquipSlot.HEAD:
			head_slot = child
	assert_not_null(head_slot, "the inventory has a head slot")
	assert_null(head_slot.item, "and a new game leaves it empty")
	head_slot.mouse_entered.emit()
	assert_eq(_tooltip_texts(), ["None", "Headwear"], "item 0's name over the slot's type")
	head_slot.mouse_exited.emit()


# Plate n shows ACH[n] over ACHDESC[n] (DefineButton2_3137 on(rollOver),
# lines 5-7, and DefineSprite_3142/frame_45/DoAction.as:4) in place of a
# native tooltip.
func test_achievement_plates_show_the_name_over_the_description():
	var window = add_child_autofree(load("res://scenes/ui/menu/achievements_window.tscn").instantiate())
	var plate: Control = window._plates[1]
	assert_eq(plate.tooltip_text, "", "no native tooltip")
	plate.mouse_entered.emit()
	assert_eq(_tooltip_texts(), [Achievements.NAMES[1], Achievements.DESCRIPTIONS[1]], "Black Magic over its description")
	plate.mouse_exited.emit()
	assert_false(GameTooltip._root.visible, "leaving the plate hides it")


# The hub's orbs show the original's titles over their descriptions: Next
# Battle, SYSTEM[13] and [14] (DefineButton2_3188 on(rollOver)), Training
# Fight, SYSTEM[29] and [30] (DefineButton2_3186), and Item Store, SYSTEM[15]
# and [16] (DefineButton2_3187), from frame_1/DoAction.as:80-97.
func test_zone_orbs_show_the_original_titles_over_their_descriptions():
	var zone = add_child_autofree(load(str(ZoneManager.ZONES[1]["scene"])).instantiate())
	await get_tree().process_frame
	var expected: Dictionary = {
		"StoryFight": ["Next Battle", "Click here to enter the next progress battle of this zone."],
		"TrainingFight": ["Training Fight", "Click here to fight an enemy for training."],
		"ItemStore": ["Item Store", "Click here to buy and sell items."],
	}
	for orb_name in expected:
		var hit_box: Control = zone.get_node(orb_name).get_node("Control")
		assert_eq(hit_box.tooltip_text, "", "%s has no native tooltip" % orb_name)
		hit_box.mouse_entered.emit()
		assert_eq(_tooltip_texts(), expected[orb_name], orb_name)
		hit_box.mouse_exited.emit()


func _tooltip_texts() -> Array:
	var texts: Array = []
	if not GameTooltip._root.visible:
		return texts
	for section in GameTooltip._sections.get_children():
		for label in section.get_child(0).get_children():
			texts.append(label.text)
	return texts


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


func test_hotbar_menu_toggle_is_exclusive():
	var game = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	var hotbar = game.get_node("Hotbar")
	hotbar.toggle_menu_screen("abilities_window")
	assert_true(game.get_node("AbilitiesWindow").visible, "abilities opens")
	hotbar.toggle_menu_screen("inventory_window")
	assert_false(game.get_node("AbilitiesWindow").visible, "one menu screen at a time")
	assert_true(game.get_node("InventoryWindow").visible)
	hotbar.toggle_menu_screen("inventory_window")
	assert_false(game.get_node("InventoryWindow").visible, "second press closes")


# The original has no open-Window state on the hotbar (spec/107-hub.md, The
# hotbar), so the icon and its hover Glow stay as they are when a button opens
# its Window.
func test_a_hotbar_icon_stays_white_while_its_window_is_open():
	var game = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	var hotbar = game.get_node("Hotbar")
	for slot: String in ["Inventory", "Abilities", "Achievements"]:
		(hotbar.get_node("%" + slot + "Button") as BaseButton).pressed.emit()
		await get_tree().process_frame
		assert_true(game.get_node(slot + "Window").visible, "%s opens its Window" % slot)
		var icon: TextureRect = hotbar.get_node(slot + "Slot/Icon")
		assert_eq(icon.modulate, Color.WHITE, "%s icon" % slot)
		assert_eq(icon.self_modulate, Color.WHITE, "%s icon" % slot)
		assert_eq(hotbar.hover_frame(slot), 1, "%s shows the frame with no Glow" % slot)
		for holder: String in ["Glow", "InnerGlow"]:
			for layer: CanvasItem in hotbar.get_node(slot + "Slot/" + holder).get_children():
				assert_false(layer.visible, "%s %s layer" % [slot, holder])


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


# frame_449/DoAction.as sends a zone whose linked zone is not beaten to
# underGF's "blank" face and clears its canUse, so the release script
# (DefineButton2_4155 on(release)) does nothing for it. The map reads the
# unlocks each time it opens.
func test_zone_map_button_states_follow_unlocks():
	var game = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	var map = game.get_node("ZoneMapOverlay")
	var zones = map.get_node("Zones")
	assert_eq(zones.get_child_count(), 7)
	map.visible = true
	await get_tree().process_frame
	assert_eq(_zone_face(zones, 1), OPEN_FACE, "zone 1 always shows the open face")
	assert_eq(_zone_face(zones, 2), LOCKED_FACE, "zone 2 shows the blank face at start")
	assert_true(zones.get_node("Zone2").disabled, "zone 2 takes no click at start")
	var zone_before: int = ZoneManager.current_zone
	zones.get_node("Zone2").pressed.emit()
	assert_eq(ZoneManager.current_zone, zone_before, "a press on a locked zone does not change the zone")
	assert_true(map.visible, "a press on a locked zone leaves the map up")

	GameData.current_save.quest_progress[1] = 10
	map.visible = false
	map.visible = true
	await get_tree().process_frame
	assert_eq(_zone_face(zones, 2), OPEN_FACE, "zone 2 shows the open face after the boss")
	assert_false(zones.get_node("Zone2").disabled, "zone 2 takes clicks after the boss")
	assert_true(is_instance_valid(map.get_node("Connectors")), "connector lines node exists and drew without error")


# DefineButton2_4155 on(rollOver) sets the tooltip's title to ZONES[sectionID]
# and its text to ZONES2[sectionID], with no canUse check, and on(rollOut)
# clears it.
func test_a_zone_shows_its_name_in_the_tooltip_open_or_locked():
	var game = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	var map = game.get_node("ZoneMapOverlay")
	map.visible = true
	var strings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Strings.STRINGS_FILE))
	var zones = map.get_node("Zones")
	assert_true(zones.get_node("Zone2").disabled, "zone 2 is locked for this check")
	for zone_id: int in [1, 2]:
		zones.get_node("Zone%d" % zone_id).mouse_entered.emit()
		assert_true(GameTooltip._root.visible, "zone %d shows the tooltip" % zone_id)
		var lines: Array[String] = []
		for label: Label in GameTooltip._sections.find_children("*", "Label", true, false):
			lines.append(label.text)
		assert_eq(lines, [strings["ZONES"][zone_id], strings["ZONES2"][zone_id]], "zone %d" % zone_id)
		zones.get_node("Zone%d" % zone_id).mouse_exited.emit()
		assert_false(GameTooltip._root.visible, "zone %d hides the tooltip on roll out" % zone_id)


# lineMC's DropShadow comes from zone_map.json, which extract_zone_map writes
# from the SWF. The connectors draw it as the lines again, moved by its distance
# at its angle, inside one group tinted to its colour at its alpha times its
# strength.
func test_the_zone_links_read_their_shadow_from_the_record():
	var game = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	var connectors = game.get_node("ZoneMapOverlay/Connectors")
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(connectors.RECORD_FILE))
	var shadow: Dictionary = record["line_shadow"]
	var offset: Vector2 = Vector2.from_angle(deg_to_rad(float(shadow["angle"]))) * float(shadow["distance"])
	assert_almost_eq(connectors.get_node("Shadow/Lines").position, offset, Vector2(0.001, 0.001))
	var color: Color = Color.html(str(shadow["color"]))
	color.a = float(shadow["alpha"]) * float(shadow["strength"])
	var tint: Color = connectors.get_node("Shadow").self_modulate
	assert_true(tint.is_equal_approx(color), "shadow colour %s, record %s" % [tint, color])


func _zone_face(zones: Node, zone_id: int) -> String:
	return (zones.get_node("Zone%d/Art" % zone_id) as TextureRect).texture.resource_path


# Root frame overMap places only the map and the tooltip, so the Stage colour
# shows around the map's frame. The original has no close button.
func test_the_world_map_hides_the_zone_art_and_has_no_close_button():
	var game = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	var map = game.get_node("ZoneMapOverlay")
	map.visible = true
	assert_false(game.get_node("ZoneHost").visible, "the zone art hides while the map shows")
	assert_null(map.get_node_or_null("CloseButton"), "the map has no close button")
	map.visible = false
	assert_true(game.get_node("ZoneHost").visible, "the zone art shows again when the map closes")


# The victory frame's rows: the player's at the top (PlaceObject3_3002_1197),
# then friendlySlotsFFTT[0] and [1] (_1111 and _1154). A row whose fighter
# does not exist is hidden and keeps its place (onClipEvent(load), lines 3-6).
func test_the_victory_rows_show_the_fighters_and_hide_the_rest_in_place():
	var save: PlayerSave = PlayerSave.new_game("VictoryRows", 0)
	var settlement := BattleSettlement.new()
	settlement.fighting_party.assign([1])
	var player := BattleSettlement.FighterExperience.new()
	player.experience_before = 30.0
	player.level_before = 2
	settlement.fighters[0] = player
	var veradux := BattleSettlement.FighterExperience.new()
	veradux.experience_before = 55.0
	veradux.level_before = 4
	settlement.fighters[1] = veradux
	var victory = add_child_autofree(load("res://scenes/ui/menu/victory_window.tscn").instantiate())
	victory.setup(save, settlement)
	await wait_process_frames(2)
	var player_row: VictoryExpRow = victory.get_node("ExpRows/PlayerSlot/Row")
	var first: VictoryExpRow = victory.get_node("ExpRows/CompanionSlot0/Row")
	var second: VictoryExpRow = victory.get_node("ExpRows/CompanionSlot1/Row")
	assert_true(player_row.visible)
	assert_eq(player_row.level_label.text, Strings.menu(0) + "2", "the player's level before the win")
	assert_true(first.visible)
	assert_eq(first.name_label.text, str(Party.COMPANIONS[1]["name"]))
	assert_eq(first.percent_label.text, "55%", "Veradux's experience before the win")
	assert_false(second.visible, "no second companion fought")
	var hidden_y: float = victory.get_node("ExpRows/CompanionSlot1").global_position.y - victory.global_position.y

	settlement.fighting_party.assign([1, 2])
	settlement.fighters[2] = BattleSettlement.FighterExperience.new()
	var both = add_child_autofree(load("res://scenes/ui/menu/victory_window.tscn").instantiate())
	both.setup(save, settlement)
	await wait_process_frames(2)
	assert_true(both.get_node("ExpRows/CompanionSlot1/Row").visible, "the second companion fought")
	var shown_y: float = both.get_node("ExpRows/CompanionSlot1").global_position.y - both.global_position.y
	assert_almost_eq(hidden_y, shown_y, 0.01, "the hidden row's slot keeps its place")
