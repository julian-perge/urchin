# combat_text_banner.gd
# The Combat text banner, the original's KrinCombatText (DefineSprite 2852): a
# line of text over a pink band near the top of the Battle screen. It tells the
# player the Refusal of a pick they cannot make, or why their own move failed as
# it dispatched. extract_combat_text writes where the banner sits, where its band
# and text go and how it slides and fades into combat_text.json, and this plays
# it from there.
#
# The clip waits on its empty frame 1. Its GO frame, frame 2, copies the message
# into the text field, and from there the clip slides up and fades in, holds,
# empties the text on frame 125 and slides down as it fades out until frame 136,
# then loops to frame 1 and stops. show_text() is the original's
# gotoAndPlay("GO"), which starts the banner over with the new text. It is not
# called show() because every Control already has one. show_if_idle() is the
# original's bare play(), which leaves a banner that is already up alone
# (frame_217/DoAction.as:19-26).
#
# The playhead is one number that advance() steps at the SWF's frame rate,
# rather than a Timer and a Tween, so nothing can outlive the banner. A Tween
# that outlived the Radial menu once closed the next menu to open (08dc6a7).
extends Control
class_name CombatTextBanner

const LAYOUT_PATH: String = "res://assets/ui/battle/combat_text.json"
# The frame that runs stop() and shows nothing, which the clip loops back to.
const IDLE_FRAME: int = 1
const ALIGNMENTS: Dictionary = {
	"left": HORIZONTAL_ALIGNMENT_LEFT,
	"center": HORIZONTAL_ALIGNMENT_CENTER,
	"right": HORIZONTAL_ALIGNMENT_RIGHT,
	"justify": HORIZONTAL_ALIGNMENT_FILL,
}

var _layout: Dictionary = {}
var _origin: Vector2 = Vector2.ZERO
var _frame: int = IDLE_FRAME
# The time since the playhead last stepped, counted in frames of the SWF.
var _frames_due: float = 0.0

@onready var label: Label = $Label
@onready var _backdrop: TextureRect = $Backdrop


func _ready() -> void:
	_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	_origin = Vector2(_layout["position"]["x"], _layout["position"]["y"])
	var band: Dictionary = _layout["backdrop"]
	_backdrop.position = Vector2(band["x"], band["y"])
	_backdrop.size = Vector2(band["w"], band["h"])
	# The Label keeps the font the project theme gives every Label, which is the
	# Stand-in font for the bold _sans the field names. It draws no glow, because a
	# Label cannot blur one, and the outline other screens use in its place reads
	# far heavier than the faint red halo the original leaves around 12 px text.
	# The band's share of the glow is baked into its art.
	var text: Dictionary = _layout["text"]
	var rect: Dictionary = text["rect"]
	label.position = Vector2(rect["x"], rect["y"])
	label.size = Vector2(rect["w"], rect["h"])
	label.horizontal_alignment = ALIGNMENTS[text["align"]]
	label.add_theme_font_size_override("font_size", int(text["size"]))
	label.add_theme_color_override("font_color", Color(text["color"]))
	_show_frame()


func _process(delta: float) -> void:
	advance(delta)


func show_text(text: String) -> void:
	label.text = text
	_frame = int(_layout["go_frame"])
	_frames_due = 0.0
	_show_frame()


func show_if_idle(text: String) -> void:
	if not is_up():
		show_text(text)


func is_up() -> bool:
	return _frame != IDLE_FRAME


# Steps the playhead on by `delta` seconds at the SWF's frame rate. _process()
# passes the real time, and a test calls this directly after set_process(false).
func advance(delta: float) -> void:
	if not is_up():
		return
	_frames_due += delta * float(_layout["fps"])
	while _frames_due >= 1.0 and is_up():
		_frames_due -= 1.0
		_frame += 1
		if _frame > _layout["alphas"].size():
			_frame = IDLE_FRAME
			_frames_due = 0.0
		elif _frame == int(_layout["clear_frame"]):
			label.text = ""
	_show_frame()


func _show_frame() -> void:
	visible = is_up()
	position = _origin + Vector2(0.0, float(_layout["offsets"][_frame - 1]))
	modulate.a = float(_layout["alphas"][_frame - 1])
