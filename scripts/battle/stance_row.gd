# stance_row.gd
# One companion's stance-mode row in the battle bottom bar: a name and the
# five aggression-preset buttons. battle_scene.gd instances one per deployed
# companion, positions it, wires each button's press to that companion's party
# id and mode, and calls set_selected() when the stance changes.
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

@onready var name_label: Label = $NameLabel
@onready var panel: TextureRect = $Panel
@onready var buttons: Array[TextureButton] = [$Mode0, $Mode1, $Mode2, $Mode3, $Mode4]

static var _layout: Dictionary = {}


# -> the stance_row section of battle_layout.json. _layout is a static var, so
# this file is read once per process, not once per battle: the parsed result
# is cached and reused by every battle scene and every test script that runs
# in the same invocation.
static func layout() -> Dictionary:
	if _layout.is_empty():
		var file := FileAccess.open(BATTLE_LAYOUT_PATH, FileAccess.READ)
		if file == null:
			push_error("missing %s" % BATTLE_LAYOUT_PATH)
			return {}
		var parsed: Dictionary = JSON.parse_string(file.get_as_text())
		_layout = parsed.get("stance_row", {})
	return _layout


# -> how far apart two rows sit, so battle_scene.gd does not carry its own copy.
static func row_pitch() -> float:
	return float(layout().get("row_pitch", 37.5))


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


func setup(unit_name: String) -> void:
	name_label.text = unit_name


# The original marks the picked stance by putting the WHITE cover on that one
# button and the BLACK cover on the other four (setAG, in DefineSprite 3312's
# own onClipEvent(load)).
func set_selected(mode: int) -> void:
	var zoom: float = float(layout().get("art_zoom", 4.0))
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
