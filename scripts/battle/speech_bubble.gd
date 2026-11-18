# speech_bubble.gd
# The Speech bubble (DefineSprite 2674), the "!" bubble that the original's
# fighter rig (DefineSprite 2676) holds over the doll's head. The conductor plays
# it on the speaker as each line starts (frame_217/PlaceObject2_3389_480 enterFrame,
# line 842), and the Fighter presenter plays it from play_speech_bubble().
#
# extract_speech_bubble renders each frame of the clip whole into one box around
# the clip's own origin, and speech_bubble.json lists the frames, that box, and
# where the rig places the clip with its x scale of -1. The clip rests on its
# frame 1, which shows nothing and runs stop(). play() runs it from there to its
# last frame, 57, and then it loops back to frame 1 and stops again, as the
# Shield clip does.
#
# The playhead is one number that advance() steps at the SWF's frame rate, so a
# test can step it frame by frame and nothing outlives the battle.
class_name SpeechBubble
extends Node2D

const LAYOUT_PATH: String = "res://assets/ui/battle/speech_bubble/speech_bubble.json"
const ART_DIR: String = "res://assets/ui/battle/speech_bubble/"

# The frame the clip shows, counted from 1 as in the SWF.
var frame: int = 1
# The Sprite2D that draws the frame.
var sprite: Sprite2D

var _frames: Array[Texture2D] = []
var _playing: bool = false
# The time since the playhead last stepped, counted in frames of the SWF.
var _frames_due: float = 0.0


func _ready() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	for png in layout["frames"]:
		_frames.append(load(ART_DIR + png))
	var place: Dictionary = layout["place"]
	var holder := Node2D.new()
	holder.position = Vector2(place["x"], place["y"])
	if layout["mirrored"]:
		holder.scale.x = -1.0
	add_child(holder)
	var rect: Dictionary = layout["rect"]
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.position = Vector2(rect["x"], rect["y"])
	sprite.scale = Vector2(rect["w"], rect["h"]) / _frames[0].get_size()
	holder.add_child(sprite)
	_show_frame()


func _process(delta: float) -> void:
	advance(delta)


func is_playing() -> bool:
	return _playing


# The original's play(), which leaves the playhead where it is until the SWF's
# next frame. Like Flash's play(), it changes nothing while the clip plays.
func play() -> void:
	_playing = true


# Steps the playhead on by `delta` seconds at the SWF's frame rate. _process()
# passes the real time, and a test calls this directly after set_process(false).
func advance(delta: float) -> void:
	if not _playing:
		return
	_frames_due += delta * BattleScreenClip.fps()
	while _frames_due >= 1.0 and _playing:
		_frames_due -= 1.0
		frame += 1
		if frame > _frames.size():
			frame = 1
			_playing = false
			_frames_due = 0.0
	_show_frame()


func _show_frame() -> void:
	sprite.texture = _frames[frame - 1]
