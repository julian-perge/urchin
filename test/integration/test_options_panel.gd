# The new-game settings Screen (spec/433-new-game-settings.md), root frame 93.
# test_screen_rects.gd checks where each piece lands. This file checks the
# texts, the frame's defaults and the rows. test_ui_scenes.gd checks how the
# menu opens it and what START does with the rows.
extends GutTest

const PanelScene: PackedScene = preload("res://scenes/ui/menu/options_panel.tscn")

var _menu: Array


func before_each() -> void:
	_menu = JSON.parse_string(FileAccess.get_file_as_string(Strings.STRINGS_FILE))["MENU"]


func after_each() -> void:
	AudioManagerAuto.sound_enabled = true


func _panel() -> OptionsPanel:
	return add_child_autofree(PanelScene.instantiate())


func _text(panel: Control, node: String) -> String:
	return (panel.get_node(node) as Label).text


func _press(panel: Control, node: String) -> void:
	(panel.get_node(node) as BaseButton).pressed.emit()


# frame_93/DoAction_2.as fills every caption from MENU.
func test_every_caption_reads_its_menu_entry() -> void:
	var panel: OptionsPanel = _panel()
	assert_eq(_text(panel, "Heading"), _menu[33])
	assert_eq(_text(panel, "DifficultyLabel"), _menu[78])
	assert_eq(_text(panel, "TutorialLabel"), _menu[82])
	assert_eq(_text(panel, "SoundLabel"), _menu[27])
	assert_eq(_text(panel, "AutosaveLabel"), _menu[35])
	assert_eq(_text(panel, "HelpText"), _menu[34])
	assert_eq(_text(panel, "StartCaption"), _menu[36])


# frame_93/DoAction.as sets Krin.difficulty to 0, and Krin.tutorOn,
# Krin.sound and Krin.autoSaver to true, and DoAction_2.as shows them.
func test_the_rows_start_at_the_frame_defaults() -> void:
	var panel: OptionsPanel = _panel()
	assert_eq(panel.difficulty, CombatUnit.Difficulty.EASY)
	assert_true(panel.tutorial)
	assert_true(panel.sound)
	assert_true(panel.autosave)
	assert_eq(_text(panel, "DifficultyValue"), _menu[79])
	assert_eq(_text(panel, "TutorialValue"), _menu[84])
	assert_eq(_text(panel, "SoundValue"), _menu[29])
	assert_eq(_text(panel, "AutosaveValue"), _menu[29])


# The frame's scripts run each time the frame plays, so open() puts every row
# back, and Krin.sound = true turns the sound back on.
func test_open_puts_every_row_back_to_the_frame_defaults() -> void:
	var panel: OptionsPanel = _panel()
	for node: String in ["DifficultyButton", "TutorialButton", "SoundButton", "AutosaveButton"]:
		_press(panel, node)
	assert_false(AudioManagerAuto.sound_enabled, "the Sound row turned the sound off")

	panel.open()
	assert_eq(panel.difficulty, CombatUnit.Difficulty.EASY)
	assert_true(panel.tutorial)
	assert_true(panel.sound)
	assert_true(panel.autosave)
	assert_eq(_text(panel, "DifficultyValue"), _menu[79])
	assert_eq(_text(panel, "TutorialValue"), _menu[84])
	assert_eq(_text(panel, "SoundValue"), _menu[29])
	assert_eq(_text(panel, "AutosaveValue"), _menu[29])
	assert_true(AudioManagerAuto.sound_enabled, "and open() turns it back on")


# DefineButton2_2775 on(release) steps Easy, Challenging, Heroic, then Easy.
func test_the_difficulty_row_cycles_through_the_three_difficulties() -> void:
	var panel: OptionsPanel = _panel()
	var expected: Array = [
		[CombatUnit.Difficulty.NORMAL, 80],
		[CombatUnit.Difficulty.HARD, 81],
		[CombatUnit.Difficulty.EASY, 79],
	]
	for step: Array in expected:
		_press(panel, "DifficultyButton")
		assert_eq(panel.difficulty, step[0])
		assert_eq(_text(panel, "DifficultyValue"), _menu[step[1]])


# DefineButton2_2769 on(release) shows MENU[83] when it turns the Tutorial
# off and MENU[84] when it turns it on.
func test_the_tutorial_row_flips() -> void:
	var panel: OptionsPanel = _panel()
	_press(panel, "TutorialButton")
	assert_false(panel.tutorial)
	assert_eq(_text(panel, "TutorialValue"), _menu[83])
	_press(panel, "TutorialButton")
	assert_true(panel.tutorial)
	assert_eq(_text(panel, "TutorialValue"), _menu[84])


# DefineButton2_2774 on(release) flips Krin.sound, which the port keeps in
# AudioManager.sound_enabled while no game is loaded.
func test_the_sound_row_flips_the_sound() -> void:
	var panel: OptionsPanel = _panel()
	_press(panel, "SoundButton")
	assert_false(panel.sound)
	assert_false(AudioManagerAuto.sound_enabled)
	assert_eq(_text(panel, "SoundValue"), _menu[30])
	_press(panel, "SoundButton")
	assert_true(panel.sound)
	assert_true(AudioManagerAuto.sound_enabled)
	assert_eq(_text(panel, "SoundValue"), _menu[29])


# DefineButton2_2772 on(release) flips Krin.autoSaver.
func test_the_autosave_row_flips() -> void:
	var panel: OptionsPanel = _panel()
	_press(panel, "AutosaveButton")
	assert_false(panel.autosave)
	assert_eq(_text(panel, "AutosaveValue"), _menu[30])
	_press(panel, "AutosaveButton")
	assert_true(panel.autosave)
	assert_eq(_text(panel, "AutosaveValue"), _menu[29])


func test_start_emits_start_pressed() -> void:
	var panel: OptionsPanel = _panel()
	watch_signals(panel)
	_press(panel, "StartButton")
	assert_signal_emitted(panel, "start_pressed")


# ADR 0011 leaves out the Effects and Graphics rows, so the Screen has one
# button for each of the four rows and one for START.
func test_the_screen_has_no_effects_or_graphics_button() -> void:
	var panel: OptionsPanel = _panel()
	var buttons: Array[String] = []
	for child: Node in panel.find_children("*", "BaseButton", true, false):
		buttons.append(String(child.name))
	buttons.sort()
	assert_eq(buttons, ["AutosaveButton", "DifficultyButton", "SoundButton", "StartButton", "TutorialButton"])
