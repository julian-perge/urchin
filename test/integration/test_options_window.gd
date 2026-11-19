# The in-game Options Window (spec/379-options-window.md): the options label of
# the original menu clip. test_screen_rects.gd checks where each piece lands.
# This file checks the texts, the rows and how the hotbar opens it.
extends GutTest

const OptionsScene: PackedScene = preload("res://scenes/ui/menu/options_window.tscn")
const GameScene: PackedScene = preload("res://scenes/game.tscn")
const TEST_SAVE_DIR := "user://test_options_window_saves/"

var _save_before: PlayerSave
var _slot_before: int
var _menu: Array


func before_each() -> void:
	_save_before = GameData.current_save
	_slot_before = GameData.current_slot
	GameData.current_save = PlayerSave.new_game("Options")
	_menu = JSON.parse_string(FileAccess.get_file_as_string(Strings.STRINGS_FILE))["MENU"]


func after_each() -> void:
	GameData.current_save = _save_before
	GameData.current_slot = _slot_before
	GameData.save_dir = GameData.SAVE_DIR
	if DirAccess.dir_exists_absolute(TEST_SAVE_DIR):
		for file: String in DirAccess.get_files_at(TEST_SAVE_DIR):
			DirAccess.remove_absolute(TEST_SAVE_DIR + file)
		DirAccess.remove_absolute(TEST_SAVE_DIR)
	AudioManagerAuto.sound_enabled = true
	AudioManagerAuto.stop_music()


func _window() -> Control:
	var window: Control = add_child_autofree(OptionsScene.instantiate())
	window.visible = true
	return window


func _text(window: Control, node: String) -> String:
	return (window.get_node(node) as Label).text


# The frame's script fills every field each time the menu clip goes to the
# options label (DefineSprite_3142/frame_39/DoAction.as).
func test_every_text_reads_its_menu_entry() -> void:
	var window: Control = _window()
	assert_eq(_text(window, "Heading"), _menu[33])
	assert_eq(_text(window, "SoundLabel"), _menu[27])
	assert_eq(_text(window, "AutosaveLabel"), _menu[35])
	assert_eq(_text(window, "DifficultyLabel"), _menu[78])
	assert_eq(_text(window, "HelpText"), _menu[34])


func test_the_values_follow_the_save_each_time_the_window_shows() -> void:
	var window: Control = _window()
	for difficulty: int in 3:
		for sound: bool in [true, false]:
			for autosave: bool in [true, false]:
				GameData.current_save.difficulty = difficulty
				GameData.current_save.sound = sound
				GameData.current_save.autosave = autosave
				window.visible = false
				window.visible = true
				var where: String = "difficulty %d, sound %s, autosave %s" % [difficulty, sound, autosave]
				assert_eq(_text(window, "SoundValue"), _menu[29 if sound else 30], where)
				assert_eq(_text(window, "AutosaveValue"), _menu[29 if autosave else 30], where)
				assert_eq(_text(window, "DifficultyValue"), _menu[79 + difficulty], where)


# DefineButton2_3131 on(release): off stops every sound, and on starts the menu
# music from the start of its rotation.
func test_sound_turns_every_sound_off_and_back_on_with_the_menu_music() -> void:
	var window: Control = _window()
	AudioManagerAuto.play_battle_music(false)
	(window.get_node("SoundButton") as BaseButton).pressed.emit()
	assert_false(GameData.current_save.sound, "the save keeps the setting")
	assert_false(AudioManagerAuto.sound_enabled, "and the audio follows it")
	assert_eq(AudioManagerAuto._music_mode, AudioManagerAuto.MusicMode.NONE, "the music stops")
	assert_eq(_text(window, "SoundValue"), _menu[30])

	AudioManagerAuto._rotation_counter = 5
	(window.get_node("SoundButton") as BaseButton).pressed.emit()
	assert_true(GameData.current_save.sound)
	assert_true(AudioManagerAuto.sound_enabled)
	assert_eq(AudioManagerAuto._music_mode, AudioManagerAuto.MusicMode.MENU, "the menu music starts")
	assert_eq(AudioManagerAuto._rotation_counter, 1, "from the first track of the rotation")
	assert_eq(_text(window, "SoundValue"), _menu[29])


# DefineButton2_2772 on(release) flips Krin.autoSaver, which Proceed reads.
func test_autosave_flips_the_setting_proceed_reads() -> void:
	var window: Control = _window()
	(window.get_node("AutosaveButton") as BaseButton).pressed.emit()
	assert_false(GameData.current_save.autosave)
	assert_eq(_text(window, "AutosaveValue"), _menu[30])
	(window.get_node("AutosaveButton") as BaseButton).pressed.emit()
	assert_true(GameData.current_save.autosave)
	assert_eq(_text(window, "AutosaveValue"), _menu[29])


# ADR 0011 leaves out Effects and Graphics, and the frame has no button for the
# difficulty, so the Window has exactly two buttons besides the close X.
func test_the_window_has_only_the_sound_and_autosave_buttons() -> void:
	var window: Control = _window()
	var buttons: Array[String] = []
	for button: Node in window.find_children("*", "BaseButton", true, false):
		buttons.append(str(window.get_path_to(button)))
	buttons.sort()
	assert_eq(buttons, ["AutosaveButton", "SoundButton", "WindowShell/CloseButton"])


func test_the_close_x_hides_the_window() -> void:
	var window: Control = _window()
	(window.get_node("WindowShell/CloseButton") as BaseButton).pressed.emit()
	assert_false(window.visible)


# DefineButton2_3180 on(release) sends the menu clip to the options label. The
# port's hotbar Windows close on a second press.
func test_the_hotbar_options_button_opens_the_window_and_a_second_press_closes_it() -> void:
	var game: Control = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	var button: BaseButton = game.get_node("Hotbar").get_node("%OptionsButton")
	var window: Control = game.get_node("OptionsWindow")
	assert_false(window.visible)
	button.pressed.emit()
	assert_true(window.visible, "Options opens the Window")
	button.pressed.emit()
	assert_false(window.visible, "a second press closes it")


# The hotbar drew Options at half alpha while it did nothing. The SWF places the
# slot at full alpha, as the other working buttons are.
func test_the_options_slot_is_not_dimmed() -> void:
	var game: Control = add_child_autofree(GameScene.instantiate())
	await get_tree().process_frame
	assert_eq((game.get_node("Hotbar/OptionsSlot") as CanvasItem).modulate, Color.WHITE)


# The original saves Krin.sound with the game (frame_42/DoAction_20.as:296), and
# addSound plays nothing while it is false (frame_42/DoAction.as:3).
func test_loading_a_save_sets_the_sound_from_it() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)
	GameData.save_dir = TEST_SAVE_DIR
	GameData.current_slot = 1
	GameData.current_save.sound = false
	assert_true(GameData.save_game())
	AudioManagerAuto.sound_enabled = true
	assert_true(GameData.load_game(1))
	assert_false(AudioManagerAuto.sound_enabled)


# DefineButton2_3180 on(release) refuses with MENU[66] while an item is on the
# cursor, before it checks PauseForScreen. In the port that is a drag from an
# Inventory or equipment slot that ends on the button.
func test_options_refuses_a_release_with_an_item_on_the_cursor() -> void:
	var save: PlayerSave = PlayerSave.new_game("Options")
	GameData.current_save = save
	save.equip_array[Equipment.MAIN_HAND_SLOT] = ItemManagerAuto.items_by_id.keys()[0]
	for inert: bool in [false, true]:
		var stage := SubViewport.new()
		stage.size = Vector2i(800, 575)
		add_child_autofree(stage)
		var hub: Control = GameScene.instantiate()
		stage.add_child(hub)
		await wait_process_frames(2)
		hub.get_node("Hotbar").set_inert(inert)
		var button: BaseButton = hub.get_node("Hotbar").get_node("%OptionsButton")
		var item: GameItem = ItemManagerAuto.items_by_id[int(save.equip_array[Equipment.MAIN_HAND_SLOT])]
		button.force_drag({"item": item, "source": "equip", "index": Equipment.MAIN_HAND_SLOT}, Control.new())
		var motion := InputEventMouseMotion.new()
		motion.position = button.get_global_rect().get_center()
		motion.global_position = motion.position
		button.get_viewport().push_input(motion, true)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = motion.position
		release.global_position = motion.position
		button.get_viewport().push_input(release, true)
		assert_false(hub.get_node("OptionsWindow").visible, "inert %s: the Window stays shut" % inert)
		var banner: CombatTextBanner = hub.get_node("CombatTextBanner")
		assert_true(banner.is_up(), "inert %s: the banner shows" % inert)
		assert_eq(banner.label.text, Strings.menu(66), "inert %s" % inert)
		stage.free()
