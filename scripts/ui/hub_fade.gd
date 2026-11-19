# hub_fade.gd
# The Hub's fade-in, the original's clip 2837, which the Navigation frame places
# above every Window and the Info card. It shows the clip's black at the clip's
# load alpha when the Hub opens, and takes the clip's step off that alpha once
# for each SWF frame until it is clear, as the clip's enterFrame handler does
# (frame_181/PlaceObject2_2837_1660). The clip fades back to black only when a
# script sets its frameGo, and no script in the original does, so the port has
# no fade-out. extract_hub_fade writes the numbers, the colour and the rect to
# assets/ui/hub_fade.json.
class_name HubFade
extends ColorRect

const LAYOUT_FILE := "res://assets/ui/hub_fade.json"

# The clip's _alpha, on Flash's 0 to 100 scale. It goes below 0 on its last
# step, as in the original, and Flash draws that as clear.
var _alpha: int = 0
var _step: int = 0
var _frame_seconds: float = 0.0
var _elapsed: float = 0.0


func _ready() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_FILE))
	var rect: Dictionary = layout["rect"]
	position = Vector2(rect["x"], rect["y"])
	size = Vector2(rect["w"], rect["h"])
	color = Color(layout["color"])
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alpha = int(layout["start_alpha"])
	_step = int(layout["alpha_step"])
	_frame_seconds = 1.0 / float(layout["fps"])
	_show_alpha()


# Flash plays a slow frame late and drops none, so a long delta still steps
# only once.
func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < _frame_seconds:
		return
	_elapsed = 0.0
	step_frame()
	if _alpha <= 0:
		set_process(false)


# One run of the clip's enterFrame handler.
func step_frame() -> void:
	if _alpha > 0:
		_alpha -= _step
	_show_alpha()


func _show_alpha() -> void:
	color.a = maxf(_alpha, 0) / 100.0
