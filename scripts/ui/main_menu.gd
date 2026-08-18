# main_menu.gd
# The starting screen (scenes/main_menu.tscn): four save slots, then the
# original two-step new-game flow (references/2026_07_18_flashpoint/6-8):
#   1. "Please select a class:" - the original sketch-art class cards
#      (gray at rest, colored on hover - cropped from root frames 85/90)
#   2. "Please configure your settings:" - Difficulty, Tutorial Level,
#      Sound, Autosave (Effects/Graphics skipped), then Click here to START!
# All screens sit on the original blue splatter background (root frame 65).
extends Control

var _selected_slot: int = 1
var _selected_class: PlayerSave.PlayerClass = PlayerSave.PlayerClass.BIOLOGICAL
var _selected_difficulty: int = 0
var _tutorial_enabled: bool = true
var _sound_enabled: bool = true
var _autosave_enabled: bool = true

@onready var slot_buttons: VBoxContainer = $Layout/SlotButtons
@onready var new_game_panel: Control = $NewGamePanel  # class-select screen
@onready var options_panel: Control = $OptionsPanel   # settings screen
@onready var name_input: LineEdit = $NewGamePanel/NameInput
@onready var class_picker: HBoxContainer = $NewGamePanel/ClassPicker
@onready var difficulty_picker: HBoxContainer = $OptionsPanel/DifficultyPicker


func _ready():
	new_game_panel.hide()
	options_panel.hide()
	_refresh_slot_buttons()
	AudioManagerAuto.play_menu_music()


# --- screen 0: save slots ----------------------------------------------------

func _refresh_slot_buttons() -> void:
	for child in slot_buttons.get_children():
		child.queue_free()
	for slot in range(1, GameData.NUM_SLOTS + 1):
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(320, 44)
		button.text = _slot_label(slot)
		button.pressed.connect(_on_slot_pressed.bind(slot))
		slot_buttons.add_child(button)


func _slot_label(slot: int) -> String:
	if not GameData.has_save(slot):
		return "Slot %d - New Game" % slot
	var save: Resource = ResourceLoader.load(GameData._slot_path(slot))
	if save is PlayerSave:
		return "Slot %d - %s  Lv %d  (Zone %d)" % [slot, save.name_user, save.level, save.section_in]
	return "Slot %d - (corrupted)" % slot


func _on_slot_pressed(slot: int) -> void:
	_selected_slot = slot
	if GameData.has_save(slot):
		if GameData.load_game(slot):
			_enter_game()
	else:
		name_input.text = "Sonny"
		$Layout.hide()
		new_game_panel.show()


# --- screen 1: class select ---------------------------------------------------

func _on_class_picked(class_id: PlayerSave.PlayerClass) -> void:
	_selected_class = class_id
	new_game_panel.hide()
	options_panel.show()


func _on_cancel_new_game() -> void:
	new_game_panel.hide()
	options_panel.hide()
	$Layout.show()


# --- screen 2: settings -------------------------------------------------------

func _on_difficulty_selected(index: int) -> void:
	_selected_difficulty = index


func _on_tutorial_toggled(pressed: bool) -> void:
	$OptionsPanel/TutorialToggle.text = "Yeah, sure!" if pressed else "No thanks"
	_tutorial_enabled = pressed


func _on_sound_toggled(pressed: bool) -> void:
	$OptionsPanel/SoundToggle.text = "On" if pressed else "Off"
	_sound_enabled = pressed
	AudioServer.set_bus_mute(0, not pressed)


func _on_autosave_toggled(pressed: bool) -> void:
	$OptionsPanel/AutosaveToggle.text = "On" if pressed else "Off"
	_autosave_enabled = pressed


func _on_options_back_pressed() -> void:
	options_panel.hide()
	new_game_panel.show()


func _on_start_new_game() -> void:
	var player_name: String = name_input.text.strip_edges()
	if player_name == "":
		player_name = "Sonny"
	GameData.new_game(_selected_slot, player_name, _selected_class)
	GameData.current_save.difficulty = _selected_difficulty
	GameData.current_save.autosave = _autosave_enabled
	GameData.save_game()
	_enter_game()


func _enter_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
