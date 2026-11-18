# speech_box.gd
# The Speech box, the original's combatScript (DefineSprite 3367): the frame
# that shows a battle line with its speaker's face and name, and a pulsing
# "Press SPACEBAR to Skip" hint above it. extract_speech_box writes where each
# piece goes into speech_box.json and renders the frame, and extract_faces
# renders the faces.
#
# The box fades at 5 alpha a frame on the original's 0 to 100 scale, so it takes
# 20 frames to fade in and 20 to fade out. show_line() is what the conductor does
# to start a line (frame_217/PlaceObject2_3389_480 enterFrame, lines 819-831): it
# moves the box, fills the two fields and sends the face clip to the frame named
# after the speaker. The box then fades in until hide_line() is called, which
# is the original's nextSpeechKKK, and fades out from there. A line that
# starts while the box is still fading out fades back in from where it is
# (frame_217/PlaceObject2_3367_634 enterFrame, lines 2-22).
#
# The playhead is one number that advance() steps in frames of the SWF, rather
# than a Tween, so a test can step it frame by frame and nothing outlives the
# battle. The battle scene calls advance() with the frames its own clock passed,
# so the fade keeps pace with animation_speed.
class_name SpeechBox
extends Control

# Emitted whenever the box's alpha changes, on the original's 0 to 100 scale. The
# battle scene sets the music's level from it (see battle_scene.gd).
signal alpha_changed(alpha: float)

const LAYOUT_PATH: String = "res://assets/ui/battle/speech_box.json"
const PORTRAIT_DIR: String = "res://assets/ui/menu/portraits/"
const PIXEL_FONT_PATH: String = "res://assets/fonts/3307_copy 10_65.ttf"
# The original's x for a speaker on side 2 and for everyone else, and its y for
# both (conductor lines 819-828).
const X_SIDE_TWO: float = 473.3
const X_OTHERS: float = 21.8
const Y: float = 460.7
# How much _alpha moves each frame, on the 0 to 100 scale.
const ALPHA_STEP: float = 5.0
# The skip hint's MENU entry (DefineSprite_3358/frame_1/DoAction.as:1).
const HINT_MENU_INDEX: int = 53

# What the box shows: the face clip's frame label ("" for an empty face well),
# and whether a line is up. A line that has gone down leaves its text
# in the fields, as the original's box does.
var face_name: String = ""
var showing: bool = false
var alpha: float = 0.0

@onready var speaker_label: Label = $Inner/SpeakerLabel
@onready var line_label: Label = $Inner/LineLabel
@onready var face: TextureRect = $Inner/Face
@onready var hint_label: Label = $Hint

var _hint_base: Color
var _hint_colors: Array = []
var _hint_frame: int = 0
var _hint_frames_due: float = 0.0


func _ready() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	var frame: Dictionary = layout["frame"]
	var art: TextureRect = $Frame
	art.position = Vector2(frame["x"], frame["y"])
	art.size = Vector2(frame["w"], frame["h"])
	var face_rect: Dictionary = layout["face"]
	face.position = Vector2(face_rect["x"], face_rect["y"])
	face.size = Vector2(face_rect["w"], face_rect["h"])
	_place_text(speaker_label, layout["name"])
	_place_text(line_label, layout["line"])
	var hint: Dictionary = layout["hint"]
	_place_text(hint_label, hint["text"])
	_hint_base = Color(hint["text"]["color"])
	_hint_colors = hint["colors"]
	hint_label.text = Strings.menu(HINT_MENU_INDEX)
	var spaced := FontVariation.new()
	spaced.base_font = load(PIXEL_FONT_PATH)
	spaced.spacing_glyph = int(hint["letter_spacing"])
	hint_label.add_theme_font_override("font", spaced)
	speaker_label.text = ""
	line_label.text = ""
	_show_frame()


# Sets the box on a line: where it sits, what it says and whose face it shows,
# and starts it fading in. `side_two` is the speaker's teamSide == 2.
func show_line(speaker_name: String, say: String, side_two: bool) -> void:
	position = Vector2(X_SIDE_TWO if side_two else X_OTHERS, Y)
	speaker_label.text = speaker_name
	line_label.text = say
	_show_face(speaker_name)
	showing = true


# The original's nextSpeechKKK = true: the box fades out from here.
func hide_line() -> void:
	showing = false


# Steps the playhead on by `frames` frames of the SWF. The battle scene's
# _process() passes the frames its clock advanced, and a test calls this
# directly after set_process(false).
func advance(frames: float) -> void:
	_hint_frames_due += frames
	while _hint_frames_due >= 1.0:
		_hint_frames_due -= 1.0
		_hint_frame = (_hint_frame + 1) % _hint_colors.size()
	var before: float = alpha
	if showing:
		alpha = minf(alpha + ALPHA_STEP * frames, 100.0)
	else:
		alpha = maxf(alpha - ALPHA_STEP * frames, 0.0)
	_show_frame()
	if alpha != before:
		alpha_changed.emit(alpha)


func _show_frame() -> void:
	modulate.a = alpha / 100.0
	var step: Dictionary = _hint_colors[_hint_frame]
	var mult: Array = step["mult"]
	var add: Array = step["add"]
	hint_label.add_theme_color_override("font_color", Color(
		_hint_base.r * mult[0] + add[0],
		_hint_base.g * mult[1] + add[1],
		_hint_base.b * mult[2] + add[2],
		step["alpha"],
	))


# The original sends the face clip to the frame named after the speaker. The
# clip has no frame for some speakers, and the original then leaves the last
# face up. The port shows the empty face well instead, which the user chose
# (spec-less decision on #156), so a face never belongs to the wrong person.
func _show_face(speaker_name: String) -> void:
	var path: String = PORTRAIT_DIR + SpeechBox.portrait_file(speaker_name)
	if ResourceLoader.exists(path):
		face_name = speaker_name
		face.texture = load(path)
	else:
		face_name = ""
		face.texture = null


# Returns the file extract_faces writes for the face clip's frame label `label`.
static func portrait_file(label: String) -> String:
	var regex := RegEx.create_from_string("[^A-Za-z0-9]+")
	return regex.sub(label, "_", true).trim_prefix("_").trim_suffix("_").to_lower() + ".png"


func _place_text(label: Label, text_layout: Dictionary) -> void:
	var rect: Dictionary = text_layout["rect"]
	label.position = Vector2(rect["x"], rect["y"])
	label.size = Vector2(rect["w"], rect["h"])
	label.horizontal_alignment = LabelLayout.ALIGNMENTS[text_layout["align"]]
	label.add_theme_font_size_override("font_size", int(round(text_layout["size"])))
	label.add_theme_color_override("font_color", Color(text_layout["color"]))
