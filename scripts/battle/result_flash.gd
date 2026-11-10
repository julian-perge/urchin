# result_flash.gd
# The Result flash, the original's BATTLEFLASH (DefineSprite 3416). It puts a
# filter on a doll that turns it white with a rim and a halo in the label's
# color, and doll_body.gdshader draws that filter. Each Fighter presenter has
# its own, so every unit a move hits flashes. The original has one for the whole
# battle, which flashes only the last of them, an Original bug that ADR 0005 has
# the port fix.
#
# PULSE_FRAMES, FRAMES_ON and LENGTH are the timeline of BATTLEFLASH's labels,
# which DECODED_ALGORITHMS.md records under "The Result flash".
#
# The playhead is one number that advance() steps at the SWF's frame rate,
# rather than a Timer or a Tween, so nothing can outlive the doll.
class_name ResultFlash
extends Node

enum Kind { HIT, HEAL, FOCUS }

# The color of each label's two colored glows, KFHit, KFHeal and KFFocus in
# frame_42/DoAction_3.as:117-130 and 162-168.
const COLORS: Dictionary[Kind, Color] = {
	Kind.HIT: Color("#ffcc00"),
	Kind.HEAL: Color("#99ff00"),
	Kind.FOCUS: Color("#33ffff"),
}
const PULSE_FRAMES: int = 4
const FRAMES_ON: int = 2
const LENGTH: int = 14

@export var doll: CharacterVisual

var _kind: Kind = Kind.HIT
# Frames since the label started, which is LENGTH while no flash plays.
var _frame: int = LENGTH
# The time since the playhead last stepped, counted in frames of the SWF.
var _frames_due: float = 0.0


func _process(delta: float) -> void:
	advance(delta)


# Starts the label over from its first frame, the way executeMove's
# gotoAndPlay() does, even while a flash is already playing.
func play(kind: Kind) -> void:
	_kind = kind
	_frame = 0
	_frames_due = 0.0
	_show_frame()


# Steps the playhead on by `delta` seconds at the SWF's frame rate. _process()
# passes the real time, and a test calls this directly after set_process(false).
func advance(delta: float) -> void:
	if _frame >= LENGTH:
		return
	_frames_due += delta * BattleScreenClip.fps()
	while _frames_due >= 1.0 and _frame < LENGTH:
		_frames_due -= 1.0
		_frame += 1
	_show_frame()


func _show_frame() -> void:
	if _frame < LENGTH and _frame % PULSE_FRAMES < FRAMES_ON:
		doll.show_result_flash(COLORS[_kind])
	else:
		doll.hide_result_flash()
