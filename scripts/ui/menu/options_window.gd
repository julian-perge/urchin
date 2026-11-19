# options_window.gd
# The in-game Options Window, the options label (frame 39) of the original
# menu clip (spec/379-options-window.md). options_window.tscn holds every
# piece, and test_screen_rects.gd checks each against the SWF. The rows are
# Sound, Autosave and the difficulty, which has no button because a game
# cannot change it. ADR 0011 leaves out the original's Effects and Graphics
# rows.
class_name OptionsWindow
extends Control

@onready var _sound_value: Label = $SoundValue
@onready var _autosave_value: Label = $AutosaveValue
@onready var _difficulty_value: Label = $DifficultyValue


func _ready() -> void:
	$Heading.text = Strings.menu(33)
	$SoundLabel.text = Strings.menu(27)
	$AutosaveLabel.text = Strings.menu(35)
	$DifficultyLabel.text = Strings.menu(78)
	$HelpText.text = Strings.menu(34)
	visibility_changed.connect(func():
		if visible:
			refresh())
	refresh()


# Fills the values from the save, as the frame's script does each time the
# menu clip goes to the options label (DefineSprite_3142/frame_39/DoAction.as).
# The difficulty is MENU[79] for Easy, MENU[80] for Challenging and MENU[81]
# for Heroic, which the frame's last else branch shows for any value above 1.
func refresh() -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	_sound_value.text = _on_off(save.sound)
	_autosave_value.text = _on_off(save.autosave)
	_difficulty_value.text = Strings.menu(79 + mini(save.difficulty, 2))


func _on_off(on: bool) -> String:
	return Strings.menu(29 if on else 30)


# DefineButton2_3131 on(release) flips Krin.sound. Off stops every sound. On
# starts the menu music from the first track of its rotation.
func _on_sound_pressed() -> void:
	var save: PlayerSave = GameData.current_save
	save.sound = not save.sound
	AudioManagerAuto.sound_enabled = save.sound
	if save.sound:
		AudioManagerAuto.reset_music_rotation()
		AudioManagerAuto.play_menu_music()
	else:
		AudioManagerAuto.stop_all_sounds()
	refresh()


# DefineButton2_2772 on(release) flips Krin.autoSaver, which the port keeps in
# PlayerSave.autosave for Proceed to read.
func _on_autosave_pressed() -> void:
	GameData.current_save.autosave = not GameData.current_save.autosave
	refresh()
