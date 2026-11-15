# result_flash.gd
# The Result flash, the original's BATTLEFLASH (DefineSprite 3416). It puts a
# filter on a doll that turns it white with a rim and a halo in the label's
# color, and doll_body.gdshader draws that filter. Each Fighter presenter has
# its own, so every unit a move hits flashes. The original has one for the whole
# battle, which flashes only the last of them, an Original bug that ADR 0005 has
# the port fix.
#
# extract_result_flash writes result_flash.json from the clip's frame scripts
# and from the filter lists in frame_42/DoAction_3.as:117-130 and 162-168. It
# holds the color of each label's glows, whether the filter is on for each
# frame the label plays, and the blur and the strength of the glows.
# DECODED_ALGORITHMS.md records the clip under "The Result flash".
#
# The playhead is one number that advance() steps at the SWF's frame rate,
# rather than a Timer or a Tween, so nothing can outlive the doll.
class_name ResultFlash
extends Node

enum Kind { HIT, HEAL, FOCUS }

const LAYOUT_PATH: String = "res://assets/ui/battle/result_flash.json"
# The label of BATTLEFLASH that executeMove plays for each kind.
const LABELS: Dictionary[Kind, String] = {
	Kind.HIT: "hit",
	Kind.HEAL: "heal",
	Kind.FOCUS: "focus",
}

static var _layout: Dictionary = {}

@export var doll: CharacterVisual

var _color: Color = Color.WHITE
# Whether the filter is on for each frame of the label that plays, which is
# empty until the first flash.
var _frames: Array = []
# Frames since the label started, which is the size of _frames while no flash
# plays.
var _frame: int = 0
# The time since the playhead last stepped, counted in frames of the SWF.
var _frames_due: float = 0.0


static func layout() -> Dictionary:
	if _layout.is_empty():
		_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	return _layout


func _process(delta: float) -> void:
	advance(delta)


# Starts the label over from its first frame, the way executeMove's
# gotoAndPlay() does, even while a flash is already playing.
func play(kind: Kind) -> void:
	var label: Dictionary = layout()["labels"][LABELS[kind]]
	_color = Color.html(label["color"])
	_frames = label["frames"]
	_frame = 0
	_frames_due = 0.0
	_show_frame()


# Steps the playhead on by `delta` seconds at the SWF's frame rate. _process()
# passes the real time, and a test calls this directly after set_process(false).
func advance(delta: float) -> void:
	if _frame >= _frames.size():
		return
	_frames_due += delta * BattleScreenClip.fps()
	while _frames_due >= 1.0 and _frame < _frames.size():
		_frames_due -= 1.0
		_frame += 1
	_show_frame()


func _show_frame() -> void:
	if _frame < _frames.size() and _frames[_frame]:
		doll.show_result_flash(_color, layout()["white_glow"], layout()["color_glow"])
	else:
		doll.hide_result_flash()
