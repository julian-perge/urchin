# stance_row.gd
# One member row in the battle bottom bar, the original's sprite 3311. Its
# `active` frame shows a companion's name and the five aggression-preset
# buttons, and its `inactive` frame shows the text of MENU[52] in place of them.
# battle_scene.gd keeps one per slot, wires each button's press to that
# companion's party id and mode, calls show_active() or show_inactive() at each
# Decision, and calls set_selected() when the stance changes.
#
# The art is the original's own, extracted by dev/urchin_dev/swf/extract/
# battle_screen.py. Every position comes from battle_layout.json's stance_row
# section rather than being typed in here, because the script that measured
# those numbers off the SWF is the only thing that should own them. The
# textures are rendered at art_zoom, so a size in design px is the texture's
# pixel size over that.
extends Control
class_name StanceRow

const BATTLE_LAYOUT_PATH: String = "res://assets/backgrounds/battle/battle_layout.json"
const COVER_UNSELECTED: String = "res://assets/ui/battle/stance/cover_BLACK.png"
const COVER_SELECTED: String = "res://assets/ui/battle/stance/cover_WHITE.png"
# Where the inactive frame draws its text, which extract_member_rows reads out of
# the SWF, and MENU's index for the text.
const MEMBER_ROWS_PATH: String = "res://assets/ui/battle/member_rows.json"
const INACTIVE_MENU_INDEX: int = 52

@onready var name_label: Label = $NameLabel
@onready var panel: TextureRect = $Panel
@onready var inactive_label: Label = $InactiveLabel
@onready var buttons: Array[TextureButton] = [$Mode0, $Mode1, $Mode2, $Mode3, $Mode4]

static var _layout: Dictionary = {}
static var _member_rows: Dictionary = {}


# -> the stance_row section of battle_layout.json. _layout is a static var, so
# this file is read once per process, not once per battle: the parsed result
# is cached and reused by every battle scene and every test script that runs
# in the same invocation. The returned Dictionary is the cache itself, not a
# copy, so callers must treat it as read-only; mutating it would corrupt the
# layout for every other row and battle in the process.
static func layout() -> Dictionary:
	if _layout.is_empty():
		var file := FileAccess.open(BATTLE_LAYOUT_PATH, FileAccess.READ)
		if file == null:
			push_error("missing %s" % BATTLE_LAYOUT_PATH)
			return {}
		var parsed: Dictionary = JSON.parse_string(file.get_as_text())
		_layout = parsed.get("stance_row", {})
	return _layout


# -> the record that extract_member_rows writes. It is read once per process.
static func member_rows() -> Dictionary:
	if _member_rows.is_empty():
		_member_rows = JSON.parse_string(FileAccess.get_file_as_string(MEMBER_ROWS_PATH))
	return _member_rows


# -> how far apart two rows sit, so battle_scene.gd does not carry its own copy.
static func row_pitch() -> float:
	return float(layout()["row_pitch"])


func _ready() -> void:
	var rect: Dictionary = layout()
	if rect.is_empty():
		return
	var zoom: float = float(rect["art_zoom"])
	var bar := Vector2(float(rect["bar_size"]["w"]), float(rect["bar_size"]["h"]))
	custom_minimum_size = bar
	size = bar
	panel.size = bar

	name_label.position = Vector2(
		float(rect["name_offset"]["x"]), float(rect["name_offset"]["y"])
	)
	var button_size := Vector2(
		float(rect["button_size"]["w"]), float(rect["button_size"]["h"])
	)
	var first := Vector2(
		float(rect["first_button"]["x"]), float(rect["first_button"]["y"])
	)
	var pitch: float = float(rect["button_pitch"])
	for mode in buttons.size():
		var button: TextureButton = buttons[mode]
		button.position = Vector2(first.x + pitch * mode, first.y)
		button.size = button_size
		_place_cover(button, load(COVER_UNSELECTED), zoom)

	var inactive: Dictionary = member_rows()["inactive"]
	inactive_label.position = Vector2(float(inactive["rect"][0]), float(inactive["rect"][1]))
	inactive_label.size = Vector2(float(inactive["rect"][2]), float(inactive["rect"][3]))
	inactive_label.horizontal_alignment = {
		"left": HORIZONTAL_ALIGNMENT_LEFT,
		"center": HORIZONTAL_ALIGNMENT_CENTER,
		"right": HORIZONTAL_ALIGNMENT_RIGHT,
	}[inactive["align"]]
	inactive_label.add_theme_font_size_override("font_size", roundi(float(inactive["font_size"])))
	inactive_label.add_theme_color_override("font_color", Color.html(inactive["color"]))
	inactive_label.text = Strings.menu(INACTIVE_MENU_INDEX)


func setup(unit_name: String) -> void:
	name_label.text = unit_name


# Shows the `active` frame: the name and the five buttons. This is the row's state
# until show_inactive() is called.
func show_active() -> void:
	_show_frame(true)


# Shows the `inactive` frame, which the original shows for a slot whose unit is
# not active (frame_217/PlaceObject2_3389_480 enterFrame, lines 696 to 746).
func show_inactive() -> void:
	_show_frame(false)


func _show_frame(active: bool) -> void:
	name_label.visible = active
	for button in buttons:
		button.visible = active
	inactive_label.visible = not active


# The original marks the picked stance by putting the WHITE cover on that one
# button and the BLACK cover on the other four (setAG, in DefineSprite 3312's
# own onClipEvent(load)).
func set_selected(mode: int) -> void:
	var zoom: float = float(layout()["art_zoom"])
	for index in buttons.size():
		var path: String = COVER_SELECTED if index == mode else COVER_UNSELECTED
		_place_cover(buttons[index], load(path), zoom)


# The WHITE cover is a glow that spills outside the button and the BLACK one
# sits just inside it, so each is centred on the button at its own size rather
# than stretched to fit.
func _place_cover(button: TextureButton, cover: Texture2D, zoom: float) -> void:
	var rect: TextureRect = button.get_node("Cover")
	rect.texture = cover
	rect.size = Vector2(cover.get_width(), cover.get_height()) / zoom
	rect.position = (button.size - rect.size) / 2.0
