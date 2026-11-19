# options_panel.gd
# The new-game settings Screen (scenes/ui/menu/options_panel.tscn), the
# original's optionsMenu, root frame 93 (spec/433-new-game-settings.md). Class
# select opens it, START begins the game, and Back is menu_back.tscn, which
# main_menu.gd connects. ADR 0011 leaves out the original's Effects and
# Graphics rows, so the Screen shows two empty bands where they were.
class_name OptionsPanel
extends Control

signal start_pressed

# frame_93/DoAction_2.as fills the captions from these MENU entries.
const HEADING: int = 33
const DIFFICULTY_CAPTION: int = 78
const TUTORIAL_CAPTION: int = 82
const SOUND_CAPTION: int = 27
const AUTOSAVE_CAPTION: int = 35
const HELP_TEXT: int = 34
const START_CAPTION: int = 36
# MENU[79] is Easy, MENU[80] Challenging and MENU[81] Heroic.
const FIRST_DIFFICULTY: int = 79
const ON: int = 29
const OFF: int = 30
const TUTORIAL_ON: int = 84
const TUTORIAL_OFF: int = 83

# The rows' values, which START copies into the new game. open() puts them
# back to the frame's defaults.
var difficulty: CombatUnit.Difficulty = CombatUnit.Difficulty.EASY
var tutorial: bool = true
var sound: bool = true
var autosave: bool = true


func _ready() -> void:
	$Heading.text = Strings.menu(HEADING)
	$DifficultyLabel.text = Strings.menu(DIFFICULTY_CAPTION)
	$TutorialLabel.text = Strings.menu(TUTORIAL_CAPTION)
	$SoundLabel.text = Strings.menu(SOUND_CAPTION)
	$AutosaveLabel.text = Strings.menu(AUTOSAVE_CAPTION)
	$HelpText.text = Strings.menu(HELP_TEXT)
	$StartCaption.text = Strings.menu(START_CAPTION)
	_reset_rows()


# frame_93/DoAction.as runs each time the frame plays, so every visit starts
# from the same rows, whatever the player chose on an earlier visit. Its
# Krin.sound = true also turns the sound back on.
func open() -> void:
	_reset_rows()
	AudioManagerAuto.sound_enabled = true


func _reset_rows() -> void:
	difficulty = CombatUnit.Difficulty.EASY
	tutorial = true
	sound = true
	autosave = true
	_refresh()


func _refresh() -> void:
	$DifficultyValue.text = Strings.menu(FIRST_DIFFICULTY + difficulty)
	$TutorialValue.text = Strings.menu(TUTORIAL_ON if tutorial else TUTORIAL_OFF)
	$SoundValue.text = _on_off(sound)
	$AutosaveValue.text = _on_off(autosave)


func _on_off(on: bool) -> String:
	return Strings.menu(ON if on else OFF)


# DefineButton2_2775 on(release) steps Krin.difficulty from Easy to Heroic and
# then back to Easy.
func _on_difficulty_pressed() -> void:
	difficulty = (difficulty + 1) % CombatUnit.Difficulty.size() as CombatUnit.Difficulty
	_refresh()


# DefineButton2_2769 on(release) flips Krin.tutorOn.
func _on_tutorial_pressed() -> void:
	tutorial = not tutorial
	_refresh()


# DefineButton2_2774 on(release) only flips Krin.sound, so the music that
# plays now goes on, and nothing starts while it is off.
func _on_sound_pressed() -> void:
	sound = not sound
	AudioManagerAuto.sound_enabled = sound
	_refresh()


# DefineButton2_2772 on(release) flips Krin.autoSaver, which the port keeps
# in PlayerSave.autosave for Proceed to read.
func _on_autosave_pressed() -> void:
	autosave = not autosave
	_refresh()


func _on_start_pressed() -> void:
	start_pressed.emit()
