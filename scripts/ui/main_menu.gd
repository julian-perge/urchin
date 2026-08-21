# main_menu.gd
# The starting screen (scenes/main_menu.tscn): four save slots, then the
# original two-step new-game flow (references/2026_07_18_flashpoint/6-8):
#   1. "Please select a class:" - the original sketch-art class cards, gray at
#      rest and colored on hover, each at the position and size the original
#      places it at. The class name under each card is a Label, because the
#      original fills a separate text field from KrinLang at runtime.
#   2. "Please configure your settings:" - Difficulty, Tutorial Level,
#      Sound, Autosave (Effects/Graphics skipped), then Click here to START!
# All screens sit on the original blue splatter background. The card art, the
# card rects in the scene and the background all come from
# dev/urchin_dev/swf/extract/start_screens.py.
extends Control

# The original's rollOver plays card-sprite frames 2-7 and rollOut plays 8-26,
# at the SWF's 30 fps - see _fade_card().
const CARD_FADE_IN: float = 0.2
const CARD_FADE_OUT: float = 0.633

var _selected_slot: int = 1
var _selected_class: PlayerSave.PlayerClass = PlayerSave.PlayerClass.BIOLOGICAL
var _selected_difficulty: CombatUnit.Difficulty = CombatUnit.Difficulty.EASY
var _tutorial_enabled: bool = true
var _sound_enabled: bool = true
var _autosave_enabled: bool = true
var _card_fades: Dictionary = {}  # card node name -> its running color fade

@onready var slot_buttons: VBoxContainer = $Layout/SlotButtons
@onready var new_game_panel: Control = $NewGamePanel  # class-select screen
@onready var options_panel: Control = $OptionsPanel   # settings screen
@onready var class_picker: Control = $NewGamePanel/ClassPicker
@onready var name_input: LineEdit = $NewGamePanel/NameInput
@onready var difficulty_picker: HBoxContainer = $OptionsPanel/DifficultyPicker


func _ready():
	new_game_panel.hide()
	options_panel.hide()
	_refresh_slot_buttons()
	_setup_class_cards()
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

# Each card gets the shared rich tooltip the abilities and buff icons use, so
# the class name sits in a header bar above its blurb the way the original's
# KrinToolTipper shows it, plus the color fade below. A card node is named
# after its class, which is what pairs it with the right
# CLASS_NAMES/CLASS_DESCRIPTIONS entry.
func _setup_class_cards() -> void:
	for class_id in PlayerSave.CLASS_NAMES.size():
		var card: TextureButton = class_picker.get_node(PlayerSave.CLASS_NAMES[class_id])
		var sections: Array = [
			{"bg_color": TooltipTheme.BG_HEADER, "lines": [{
				"text": PlayerSave.CLASS_NAMES[class_id],
				"color": TooltipTheme.TEXT_TITLE,
			}]},
			{"bg_color": TooltipTheme.BG_BODY, "lines": [{
				"text": PlayerSave.CLASS_DESCRIPTIONS[class_id],
				"color": TooltipTheme.TEXT_BODY,
			}]},
		]
		card.mouse_entered.connect(func():
			GameTooltip.show_sections(sections, card)
			_fade_card(card, 1.0, CARD_FADE_IN))
		card.mouse_exited.connect(func():
			GameTooltip.hide_tooltip()
			_fade_card(card, 0.0, CARD_FADE_OUT))


# Ramps the colored copy of a card over the gray one, which is the whole of the
# original's hover animation: each card sprite is 26 frames of one
# COLORMATRIXFILTER interpolating between a luminance matrix and identity, and
# a matrix lerp applied to fixed pixels is the same thing as crossfading that
# matrix's two endpoint images. Checked against all 26 rendered frames, which
# are each within 1.43/255 of the blend, so no in-between art is needed. The
# two durations are the original's own frame counts at its 30 fps: rollOver
# plays frames 2-7, rollOut plays frames 8-26 and holds a frame before ramping.
func _fade_card(card: TextureButton, to_alpha: float, duration: float) -> void:
	var running: Tween = _card_fades.get(card.name)
	if running != null and running.is_valid():
		running.kill()
	var tween: Tween = create_tween()
	tween.tween_property(card.get_node("Color"), "modulate:a", to_alpha, duration)
	_card_fades[card.name] = tween


func _on_class_picked(class_id: PlayerSave.PlayerClass) -> void:
	_selected_class = class_id
	new_game_panel.hide()
	options_panel.show()


func _on_cancel_new_game() -> void:
	new_game_panel.hide()
	options_panel.hide()
	$Layout.show()


# --- screen 2: settings -------------------------------------------------------

func _on_difficulty_selected(index: CombatUnit.Difficulty) -> void:
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
