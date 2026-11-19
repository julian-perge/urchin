# hint_steps.gd
# The tutorial steps of the Abilities window's hint box, the clip `reader`
# (DefineSprite 3059) on frame 25 of the original's menu clip.
#
# The clip rests on its label `stable`, where the window's HintLabel shows a
# random tip. When the window opens and the player has upgrade points, the
# clip's onClipEvent(load) sends it to `level` instead
# (DefineSprite_3142/frame_25/PlaceObject2_3059_675). Each later label shows
# one step, and a click on the box goes to the next label, until the click on
# the last step goes back to `stable` and its frame script picks a new tip.
#
# extract_hint_steps writes hint_steps.json: each label's MENU indices, where
# its text fields and its click area sit, and its strips of glow art. A box
# strip holds the 40 frames of the glowing box. It plays on from one label to
# the next, as the box does in the original, because every step label keeps
# the same box clip. A pointer strip holds one label's loop of the bar and the
# arrow, which starts again each time the label is entered.
#
# Each playhead is one number that advance() steps at the SWF's frame rate, as
# in ShieldClip, so a test can step it frame by frame.
class_name HintSteps
extends Control

const LAYOUT_PATH: String = "res://assets/ui/menu/hint_steps/hint_steps.json"
const ART_DIR: String = "res://assets/ui/menu/hint_steps/"
const ALIGNMENTS: Dictionary = {
	"left": HORIZONTAL_ALIGNMENT_LEFT,
	"center": HORIZONTAL_ALIGNMENT_CENTER,
	"right": HORIZONTAL_ALIGNMENT_RIGHT,
}

# The Label that shows the tip on the resting label.
@export var tip_label: Label

# The label the clip shows.
var state: String = ""
# The frame each strip shows, counted from 1 as in the SWF.
var box_frame: int = 1
var pointer_frame: int = 1

var _layout: Dictionary = {}
var _strips: Dictionary = {}
var _frames_due: float = 0.0
var _step_label: Label
var _click_label: Label
var _click_button: Button
var _box_art: TextureRect
var _pointer_art: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	for strip_name: String in _layout["strips"]:
		var frames: Array[Texture2D] = []
		for png: String in _layout["strips"][strip_name]["frames"]:
			frames.append(load(ART_DIR + png))
		_strips[strip_name] = frames
	# Flash draws the fields at depths 1 and 2, the button at depth 3 and the
	# glow art at depths 5 to 9 of the clip, so the art goes over the text.
	_step_label = _new_label("StepLabel")
	_click_label = _new_label("ClickLabel")
	_click_button = Button.new()
	_click_button.name = "ClickButton"
	_click_button.flat = true
	_click_button.focus_mode = Control.FOCUS_NONE
	_click_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for style: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		_click_button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	_click_button.pressed.connect(click)
	add_child(_click_button)
	_box_art = _new_art("BoxArt")
	_pointer_art = _new_art("PointerArt")
	_show(_layout["rest"])


func _process(delta: float) -> void:
	if is_visible_in_tree():
		advance(delta)


# The clip's onClipEvent(load), which runs each time the window opens. It goes
# to the first step when the player has ability or attribute points to spend,
# and rests on the tip otherwise. The clip is placed new on each opening, so
# the box starts again from its first frame even when the window closed on a
# step.
func open(save: PlayerSave) -> void:
	var points: int = 0 if save == null else save.skill_points + save.stat_points
	state = ""
	_show(_layout["start"] if points > 0 else _layout["rest"])


# The release handler of the label's button, which goes to the next label.
func click() -> void:
	if _layout["steps"].has(state):
		_show(_layout["steps"][state]["next"])


# Steps the playheads on by `delta` seconds at the SWF's frame rate. _process()
# passes the real time, and a test calls this directly after set_process(false).
func advance(delta: float) -> void:
	if not _layout["steps"].has(state):
		return
	_frames_due += delta * float(_layout["fps"])
	while _frames_due >= 1.0:
		_frames_due -= 1.0
		box_frame = box_frame % _box_frames().size() + 1
		var pointer: Array = _pointer_frames()
		if not pointer.is_empty():
			pointer_frame = pointer_frame % pointer.size() + 1
	_draw_art()


func _show(next: String) -> void:
	var was_step: bool = _layout["steps"].has(state)
	state = next
	var is_step: bool = _layout["steps"].has(state)
	tip_label.visible = not is_step
	for node: CanvasItem in [_step_label, _click_label, _click_button, _box_art, _pointer_art]:
		node.visible = is_step
	if not is_step:
		# DefineSprite_3059/frame_1/DoAction.as picks MENU[first + random(count)].
		var tips: Dictionary = _layout["tips"]
		tip_label.text = Strings.menu(int(tips["first"]) + randi() % int(tips["count"]))
		return
	var step: Dictionary = _layout["steps"][state]
	_place_label(_step_label, step["reader_field"], Strings.menu(int(step["reader"])))
	_place_label(_click_label, step["clicker_field"], Strings.menu(int(step["clicker"])))
	var hit: Array = step["button"]
	_click_button.position = Vector2(hit[0], hit[1])
	_click_button.size = Vector2(hit[2], hit[3])
	# The box clip is placed new when the clip enters its first step, and plays
	# on through the later steps.
	if not was_step:
		box_frame = 1
		_frames_due = 0.0
	pointer_frame = 1
	_place_art(_box_art, step["box"])
	_place_art(_pointer_art, step["pointer"])
	_draw_art()


func _box_frames() -> Array:
	return _strips[_layout["steps"][state]["box"]]


func _pointer_frames() -> Array:
	var pointer: Variant = _layout["steps"][state]["pointer"]
	return [] if pointer == null else _strips[pointer]


func _draw_art() -> void:
	_box_art.texture = _box_frames()[box_frame - 1]
	var pointer: Array = _pointer_frames()
	_pointer_art.texture = null if pointer.is_empty() else pointer[pointer_frame - 1]


func _new_label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _new_art(node_name: String) -> TextureRect:
	var art := TextureRect.new()
	art.name = node_name
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(art)
	return art


func _place_art(art: TextureRect, strip_name: Variant) -> void:
	if strip_name == null:
		return
	var rect: Dictionary = _layout["strips"][strip_name]["rect"]
	art.position = Vector2(rect["x"], rect["y"])
	art.size = Vector2(rect["w"], rect["h"])


# Draws a field as test_screen_rects.gd checks a text piece: font 65 in the
# theme's bold face and font 295 through RegularLabel, and the line pitch as
# the font's height plus the line spacing.
func _place_label(label: Label, field: Dictionary, text: String) -> void:
	label.theme_type_variation = &"" if field["bold"] else &"RegularLabel"
	var font_size: int = roundi(float(field["font_size"]))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.html(field["color"]))
	label.horizontal_alignment = ALIGNMENTS[field["align"]]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if field["wrap"] else TextServer.AUTOWRAP_OFF
	if field.has("line_pitch"):
		var height: float = label.get_theme_font("font").get_height(font_size)
		label.add_theme_constant_override("line_spacing", roundi(float(field["line_pitch"]) - height))
	var rect: Array = field["rect"]
	label.position = Vector2(rect[0], rect[1])
	label.size = Vector2(rect[2], rect[3])
	label.text = text
