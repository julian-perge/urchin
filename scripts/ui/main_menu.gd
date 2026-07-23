# main_menu.gd
# The starting screen (scenes/main_menu.tscn): four save slots, then the
# original two-step new-game flow (references/2026_07_18_flashpoint/6-8):
#   1. "Please select a class:" - the original sketch-art class cards
#      (gray at rest, colored on hover - cropped from root frames 85/90)
#   2. "Please configure your settings:" - Difficulty, Tutorial Level,
#      Sound, Autosave (Effects/Graphics skipped), then Click here to START!
# All screens sit on the original blue splatter background (root frame 65).
extends Control

const CLASS_NAMES: Array[String] = ["Biological", "Psychological", "Hydraulic"]
# Card order matches the original screen: Psychological, Biological, Hydraulic.
const CLASS_CARD_ORDER: Array[int] = [1, 0, 2]
const CLASS_CARD_ART: Dictionary[int, String] = {
	1: "class_cards/psychological",
	0: "class_cards/biological",
	2: "class_cards/hydraulic",
}
const DIFFICULTY_NAMES: Array[String] = ["Easy", "Challenging", "Heroic"]

var _selected_slot: int = 1
var _selected_class: int = 0
var _selected_difficulty: int = 0
var _tutorial_enabled: bool = true
var _sound_enabled: bool = true
var _autosave_enabled: bool = true

@onready var slot_buttons: VBoxContainer = $Layout/SlotButtons
var new_game_panel: Control  # class-select screen
var options_panel: Control   # settings screen
var name_input: LineEdit
var class_picker: HBoxContainer
var difficulty_picker: HBoxContainer
var start_button: Button
var cancel_button: Button


func _ready():
	_build_class_screen()
	_build_options_screen()
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

func _build_class_screen() -> void:
	new_game_panel = _make_screen("NewGamePanel")
	MenuTheme.add_label(
		new_game_panel, "Please select a class:", Rect2(0, 60, 800, 40), 26,
		Color(0.85, 0.5, 0.55), HORIZONTAL_ALIGNMENT_CENTER
	)
	var name_row: Label = MenuTheme.add_label(
		new_game_panel, "Name:", Rect2(250, 116, 80, 30), 15,
		Color(0.8, 0.8, 0.8), HORIZONTAL_ALIGNMENT_RIGHT
	)
	name_row.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_input = LineEdit.new()
	name_input.name = "NameInput"
	name_input.text = "Sonny"
	name_input.max_length = 12
	name_input.position = Vector2(340, 116)
	name_input.size = Vector2(210, 30)
	new_game_panel.add_child(name_input)
	class_picker = HBoxContainer.new()
	class_picker.name = "ClassPicker"
	class_picker.position = Vector2(85, 170)
	class_picker.size = Vector2(630, 330)
	class_picker.add_theme_constant_override("separation", 45)
	new_game_panel.add_child(class_picker)
	for class_id in CLASS_CARD_ORDER:
		class_picker.add_child(_make_class_card(class_id))
	cancel_button = Button.new()
	cancel_button.name = "CancelButton"
	cancel_button.text = "Back"
	cancel_button.position = Vector2(700, 545)
	cancel_button.size = Vector2(80, 36)
	cancel_button.add_theme_font_size_override("font_size", 18)
	cancel_button.pressed.connect(_on_cancel_new_game)
	new_game_panel.add_child(cancel_button)


# The original card art: gray sketch at rest, colored on hover/press.
func _make_class_card(class_id: int) -> TextureButton:
	var card: TextureButton = TextureButton.new()
	card.texture_normal = MenuTheme.texture(CLASS_CARD_ART[class_id] + "_gray.png")
	card.texture_hover = MenuTheme.texture(CLASS_CARD_ART[class_id] + ".png")
	card.texture_pressed = card.texture_hover
	card.ignore_texture_size = true
	card.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	card.custom_minimum_size = Vector2(180, 320)
	card.tooltip_text = CLASS_NAMES[class_id]
	card.pressed.connect(_on_class_picked.bind(class_id))
	return card


func _on_class_picked(class_id: int) -> void:
	_selected_class = class_id
	new_game_panel.hide()
	options_panel.show()


func _on_cancel_new_game() -> void:
	new_game_panel.hide()
	options_panel.hide()
	$Layout.show()


# --- screen 2: settings -------------------------------------------------------

func _build_options_screen() -> void:
	options_panel = _make_screen("OptionsPanel")
	MenuTheme.add_label(
		options_panel, "Please configure your settings:", Rect2(0, 50, 800, 34), 22,
		Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER
	)
	MenuTheme.add_label(
		options_panel, "Difficulty:", Rect2(140, 120, 250, 30), 22,
		Color(0.95, 0.6, 0.15), HORIZONTAL_ALIGNMENT_RIGHT
	)
	difficulty_picker = HBoxContainer.new()
	difficulty_picker.name = "DifficultyPicker"
	difficulty_picker.position = Vector2(410, 120)
	difficulty_picker.add_theme_constant_override("separation", 8)
	options_panel.add_child(difficulty_picker)
	var group: ButtonGroup = ButtonGroup.new()
	for i in DIFFICULTY_NAMES.size():
		var button: Button = Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.text = DIFFICULTY_NAMES[i]
		button.button_pressed = i == 0
		button.pressed.connect(func(): _selected_difficulty = i)
		difficulty_picker.add_child(button)
	_add_toggle_row("Tutorial Level:", 170, "Yeah, sure!", "No thanks", func(on): _tutorial_enabled = on)
	_add_toggle_row("Sound:", 220, "On", "Off", func(on):
		_sound_enabled = on
		AudioServer.set_bus_mute(0, not on))
	_add_toggle_row("Autosave:", 270, "On", "Off", func(on): _autosave_enabled = on)
	var note: Label = MenuTheme.add_label(
		options_panel, "If you turn Autosave on, your game will be saved when you press "
		+ "'Proceed' after winning a battle. The difficulty level cannot be changed - "
		+ "you must start a new game if you wish to play on a different mode.",
		Rect2(120, 330, 560, 80), 13, Color(0.9, 0.9, 0.9), HORIZONTAL_ALIGNMENT_LEFT, true
	)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_button = Button.new()
	start_button.name = "StartButton"
	start_button.text = "Click here to START!"
	start_button.position = Vector2(250, 460)
	start_button.size = Vector2(300, 50)
	start_button.add_theme_font_size_override("font_size", 24)
	start_button.add_theme_color_override("font_color", Color(0.35, 0.95, 0.25))
	start_button.add_theme_color_override("font_hover_color", Color(0.6, 1.0, 0.5))
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	start_button.add_theme_stylebox_override("normal", style)
	start_button.add_theme_stylebox_override("hover", style)
	start_button.add_theme_stylebox_override("pressed", style)
	start_button.pressed.connect(_on_start_new_game)
	options_panel.add_child(start_button)
	var back: Button = Button.new()
	back.text = "Back"
	back.position = Vector2(700, 545)
	back.size = Vector2(80, 36)
	back.pressed.connect(func():
		options_panel.hide()
		new_game_panel.show())
	options_panel.add_child(back)


func _add_toggle_row(label_text: String, y: float, on_text: String, off_text: String, on_change: Callable) -> void:
	MenuTheme.add_label(
		options_panel, label_text, Rect2(140, y, 250, 26), 17,
		Color(0.55, 0.85, 0.4), HORIZONTAL_ALIGNMENT_RIGHT
	)
	var button: Button = Button.new()
	button.toggle_mode = true
	button.button_pressed = true
	button.text = on_text
	button.position = Vector2(410, y)
	button.size = Vector2(140, 28)
	button.toggled.connect(func(pressed):
		button.text = on_text if pressed else off_text
		on_change.call(pressed))
	options_panel.add_child(button)


func _make_screen(screen_name: String) -> Control:
	var screen: Control = Control.new()
	screen.name = screen_name
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var bg: TextureRect = TextureRect.new()
	bg.texture = MenuTheme.texture("start_background.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(bg)
	screen.move_child(bg, 0)
	return screen


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
