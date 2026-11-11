# main_menu.gd
# The starting screen (scenes/main_menu.tscn), the original's menu from its
# subMenu frame on. references/2026_07_18_flashpoint/4-8 show screens 3 to 5.
#   1. New Game or Load Game (root frame 56). The original's third choice,
#      PvP Arena, is left out with the rest of the arena.
#   2. New Game asks for the player's name (root frame 64).
#   3. The four save slots (root frame 74). New Game goes on to class select
#      from any slot, used or empty, and Load Game loads a used one.
#   4. "Please select a class:" - the original sketch-art class cards, gray at
#      rest and colored on hover, each at the position and size the original
#      places it at. The class name under each card is a Label, because the
#      original fills a separate text field from KrinLang at runtime.
#   5. "Please configure your settings:" - Difficulty, Tutorial Level,
#      Sound, Autosave (Effects/Graphics skipped), then Click here to START!
# All screens sit on the original blue splatter background. The card art, the
# card rects in the scene and the background all come from
# dev/urchin_dev/swf/extract/start_screens.py.
extends Control

# New Game and Load Game open the same slot list, and the original tells the
# two apart by Krin.dataMode, which DefineButton2_2707 sets to "save" and
# DefineButton2_2706 to "load".
enum SlotMode { NEW_GAME, LOAD_GAME }

# The original's rollOver plays card-sprite frames 2-7 and rollOut plays 8-26,
# at the SWF's 30 fps - see _fade_card().
const CARD_FADE_IN: float = 0.2
const CARD_FADE_OUT: float = 0.633

# What a slot shows on hover in New Game mode, MENU[21] over MENU[25]
# (frame_1/DoAction.as:229 and 233). The original never asks again when the
# slot is clicked, so this is its only warning that a used slot's save will be
# replaced.
const NEW_GAME_WARNING_TITLE: String = "New Game"
const NEW_GAME_WARNING_TEXT: String = "Warning! Starting a new game in a saved slot will remove your old data! Saved games are stored relative to where you play this game."

# SYSTEM[34] (frame_1/DoAction.as:101), which the original puts in the name
# field each time the name screen opens (frame_64/DoAction.as:1).
const NAME_PROMPT: String = "< Enter Name Here >"

var _slot_mode: SlotMode = SlotMode.LOAD_GAME
var _selected_slot: int = 1
var _selected_class: PlayerSave.PlayerClass = PlayerSave.PlayerClass.BIOLOGICAL
var _selected_difficulty: CombatUnit.Difficulty = CombatUnit.Difficulty.EASY
var _tutorial_enabled: bool = true
var _sound_enabled: bool = true
var _autosave_enabled: bool = true
var _card_fades: Dictionary = {}  # card node name -> its running color fade

@onready var mode_panel: Control = $ModePanel  # New Game or Load Game
@onready var name_panel: Control = $NamePanel
@onready var slot_panel: Control = $SlotPanel
@onready var slot_buttons: VBoxContainer = $SlotPanel/Layout/SlotButtons
@onready var new_game_panel: Control = $NewGamePanel  # class-select screen
@onready var options_panel: Control = $OptionsPanel   # settings screen
@onready var class_picker: Control = $NewGamePanel/ClassPicker
@onready var name_input: LineEdit = $NamePanel/NameInput
@onready var difficulty_picker: HBoxContainer = $OptionsPanel/DifficultyPicker


func _ready():
	# TeX Gyre Heros is 38 px tall at this field's 26 px, so the default 4 px of
	# padding above and below would make the box taller than the 45.25 px of
	# edit text 2712. Half a pixel less on each side keeps the original's rect,
	# and LineEdit takes its minimum height from the tallest of these styles.
	for style_name in ["normal", "focus", "read_only"]:
		var style: StyleBox = name_input.get_theme_stylebox(style_name).duplicate()
		style.set_content_margin(SIDE_TOP, 3.5)
		style.set_content_margin(SIDE_BOTTOM, 3.5)
		name_input.add_theme_stylebox_override(style_name, style)
	_show_screen(mode_panel)
	_refresh_slot_buttons()
	_setup_class_cards()
	AudioManagerAuto.play_menu_music()


func _show_screen(screen: Control) -> void:
	for panel in [mode_panel, name_panel, slot_panel, new_game_panel, options_panel]:
		panel.visible = panel == screen


# Every screen's Back returns to the first screen. The original's Back,
# DefineButton2_2702, goes to mainMenu from all of them (on(release), line 2),
# the title screen in front of New Game and Load Game, which the port doesn't
# have.
func _on_back_pressed() -> void:
	GameTooltip.hide_tooltip()
	_show_screen(mode_panel)


# --- screen 1: New Game or Load Game -----------------------------------------

func _on_new_game_pressed() -> void:
	_slot_mode = SlotMode.NEW_GAME
	name_input.text = NAME_PROMPT
	_show_screen(name_panel)


func _on_load_game_pressed() -> void:
	_slot_mode = SlotMode.LOAD_GAME
	_show_screen(slot_panel)


# --- screen 2: name ----------------------------------------------------------

func _on_name_confirmed() -> void:
	_show_screen(slot_panel)


# --- screen 3: save slots ----------------------------------------------------

func _refresh_slot_buttons() -> void:
	for child in slot_buttons.get_children():
		child.queue_free()
	for slot in range(1, GameData.NUM_SLOTS + 1):
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(320, 44)
		button.text = _slot_label(slot)
		button.pressed.connect(_on_slot_pressed.bind(slot))
		button.mouse_entered.connect(_on_slot_hovered.bind(button))
		button.mouse_exited.connect(GameTooltip.hide_tooltip)
		slot_buttons.add_child(button)


func _slot_label(slot: int) -> String:
	if not GameData.has_save(slot):
		return "Slot %d - < Empty Slot >" % slot
	var save: Resource = ResourceLoader.load(GameData._slot_path(slot))
	if save is PlayerSave:
		return "Slot %d - %s  Lv %d  (Zone %d)" % [slot, save.name_user, save.level, save.section_in]
	return "Slot %d - (corrupted)" % slot


func _on_slot_hovered(button: Button) -> void:
	if _slot_mode != SlotMode.NEW_GAME:
		return
	GameTooltip.show_sections([
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{
			"text": NEW_GAME_WARNING_TITLE,
			"color": TooltipTheme.TEXT_TITLE,
		}]},
		{"bg_color": TooltipTheme.BG_BODY, "lines": [{
			"text": NEW_GAME_WARNING_TEXT,
			"color": TooltipTheme.TEXT_BODY,
		}]},
	], button)


# New Game goes on to class select from any slot without reading it, and Load
# Game loads a slot only when it holds a save (DefineButton2_2719 to
# DefineButton2_2722 on(release)), so an empty slot does nothing there.
func _on_slot_pressed(slot: int) -> void:
	if _slot_mode == SlotMode.NEW_GAME:
		_selected_slot = slot
		GameTooltip.hide_tooltip()
		_show_screen(new_game_panel)
	elif GameData.load_game(slot):
		_enter_game()


# --- screen 4: class select ---------------------------------------------------

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


# --- screen 5: settings -------------------------------------------------------

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


# The new game is not saved here. In the original only the Save button
# (DefineButton2_3183) and the autosave on a victory's Proceed
# (DefineButton2_3004) write a slot, through krinHandleData
# (frame_42/DoAction_20.as:58-126), so a used slot keeps its old save until the
# new game is first saved. The name goes in exactly as typed, the untouched
# prompt and an empty field included, because OK! never reads it
# (DefineButton2_2710 on(release)) and the slot button copies it unchanged
# (DefineButton2_2722 on(release), line 5).
#
# START goes on to the first fight and not to the hub. The original's START
# plays CS_INTRO when the Tutorial is on, which leads into battle 2 (see
# ZoneProgression.TUTORIAL_FIGHT). It plays CS_INTRO2 when the Tutorial is off
# (DefineButton2_2770 on(release)), which leads into battle 100 (see
# ZoneProgression.FIRST_STORY_FIGHT).
func _on_start_new_game() -> void:
	GameData.new_game(_selected_slot, name_input.text, _selected_class)
	GameData.current_save.difficulty = _selected_difficulty
	GameData.current_save.autosave = _autosave_enabled
	if _tutorial_enabled:
		ZoneManager.request_tutorial_fight()
	else:
		ZoneManager.request_new_game_fight()


func _enter_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
