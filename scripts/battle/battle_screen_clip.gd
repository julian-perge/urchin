# battle_screen_clip.gd
# The hall and the fighters, the original's BATTLESCREEN (DefineSprite 3435).
# GridZoomer zooms it toward a move's target and GridShaker shakes it. Both are
# empty clips whose frame scripts move BATTLESCREEN, so this runs their scripts
# on the frames the SWF runs them on, with each clip's frame count, labels and
# starting variables from battle_screen_motion.json, which
# extract_battle_screen_motion reads out of the SWF. Nothing waits for either.
#
# Flash keeps a clip's _x and _y in whole twips, so this does too, and drops the
# fraction of a twip that a script sets them to. That Flash drops the fraction
# rather than rounding it is inferred, not read in a player: GridShaker's last
# frame adds back 0.9 px, and a simulation of its frames from where BATTLESCREEN
# rests ends exactly there only when the fractions are dropped. It ends 0.1 px
# low when they are rounded or kept.
class_name BattleScreenClip
extends Control

const MOTION_PATH: String = "res://assets/ui/battle/battle_screen_motion.json"
const TWIPS: float = 20.0
# Flash counts a clip placed at its own size as this _xscale and _yscale.
const FULL_SCALE: float = 100.0

static var _motion: Dictionary = {}

# rest is where the battle frame places BATTLESCREEN, which its
# onClipEvent(load) saves as saverX and saverY.
var rest: Vector2 = Vector2.ZERO
# These are BATTLESCREEN's _xscale and _yscale, and its _x and _y.
var clip_xscale: float = FULL_SCALE
var clip_yscale: float = FULL_SCALE
var clip_x: float:
	get:
		return _x_twips / TWIPS
	set(value):
		_x_twips = int(value * TWIPS)
var clip_y: float:
	get:
		return _y_twips / TWIPS
	set(value):
		_y_twips = int(value * TWIPS)

var _x_twips: int = 0
var _y_twips: int = 0
var _zoomer: GridZoomer
var _shaker: GridShaker
var _frames_due: float = 0.0


func _ready() -> void:
	var data: Dictionary = motion()
	rest = Vector2(float(data["rest"]["x"]), float(data["rest"]["y"]))
	clip_x = rest.x
	clip_y = rest.y
	_zoomer = GridZoomer.new(self, data["zoomer"])
	_shaker = GridShaker.new(self, data["shaker"])
	_show()


# Returns what battle_screen_motion.json holds. It reads the file once, the
# first time anything asks.
static func motion() -> Dictionary:
	if _motion.is_empty():
		_motion = JSON.parse_string(FileAccess.get_file_as_string(MOTION_PATH))
	return _motion


# Returns the SWF's frame rate, which the extractor reads from the SWF's header.
# Every clip in the original plays at it, so the port counts the battle's
# frames at it.
static func fps() -> float:
	return float(motion()["fps"])


# Does what the conductor does to zoom: it sets _root.zoomPointX and zoomPointY
# to `point`, plays GridZoomer from KrinZoomGo, and sets _root.zoomPause to
# `hold`.
func zoom(point: Vector2, hold: int) -> void:
	_zoomer.zoom(point, hold)


# Does what the conductor's _root.GridShaker.play() does. A shake that is
# already playing carries on.
func shake() -> void:
	_shaker.play()


# Plays both clips on by `seconds` at the SWF's frame rate.
func advance(seconds: float) -> void:
	_frames_due += seconds * fps()
	while _frames_due >= 1.0:
		_frames_due -= 1.0
		advance_frame()


func advance_frame() -> void:
	_zoomer.advance()
	_shaker.advance()
	_show()


func _show() -> void:
	pivot_offset = rest
	scale = Vector2(clip_xscale, clip_yscale) / FULL_SCALE
	position = Vector2(clip_x, clip_y) - rest


# Clip is a clip's playhead. Flash runs the script of each frame the playhead
# lands on, whether it plays onto it or jumps there, and a jump to a label stops
# the clip.
class Clip:
	var _frames: int
	var _labels: Dictionary
	var _scripts: Dictionary = {}
	var _frame: int = 1
	var _playing: bool = false

	# scripts maps the role names the JSON gives each scripted frame to the
	# function that ports that frame's script.
	func _init(timeline: Dictionary, scripts: Dictionary) -> void:
		_frames = int(timeline["frames"])
		_labels = timeline["labels"]
		for role in scripts:
			_scripts[int(timeline["scripts"][role])] = scripts[role]

	func goto_and_stop(label: String) -> void:
		_playing = false
		_frame = int(_labels[label])
		_run()

	func play() -> void:
		_playing = true

	func stop() -> void:
		_playing = false

	func advance() -> void:
		if _playing:
			_frame = _frame % _frames + 1
			_run()

	func _run() -> void:
		if _scripts.has(_frame):
			_scripts[_frame].call()


# This is GridZoomer, DefineSprite 3419, with its frame scripts ported.
class GridZoomer extends Clip:
	var _screen: BattleScreenClip
	# Its onClipEvent(load) sets these (frame_217/PlaceObject2_3419_332).
	var _zoom_time: float
	var _scale_change: float
	var _zoom_factor: float
	var _zoom_point: float
	# Its KrinZoomGo frame works these out, and the last one counts the frames
	# it has held.
	var _zoom_point_x: float = 0.0
	var _zoom_point_y: float = 0.0
	var _zoom_scale_x: float = 0.0
	var _zoom_scale_y: float = 0.0
	var _zoom_reverse: float = 0.0
	var _zoom_pause_counter: int = 0
	# These stand for _root.zoomPointX and zoomPointY, and _root.zoomPause.
	var _point: Vector2 = Vector2.ZERO
	var _hold_frames: int = 0

	func _init(screen: BattleScreenClip, timeline: Dictionary) -> void:
		super(timeline, {"stop": stop, "go": _go, "step": _step, "hold": _hold})
		_screen = screen
		var variables: Dictionary = timeline["variables"]
		_zoom_time = float(variables["zoomTime"])
		_scale_change = float(variables["scaleChange"])
		_zoom_factor = float(variables["zoomFactor"])
		_zoom_point = float(variables["zoomPoint"])

	func zoom(point: Vector2, hold: int) -> void:
		_point = point
		goto_and_stop("KrinZoomGo")
		play()
		_hold_frames = hold

	# This ports DefineSprite_3419/frame_2. The blur and the drop in quality it
	# can start never run, because frame_201/DoAction.as:87-100 sets SFX2 false
	# and SFX3 true for both Graphics settings.
	func _go() -> void:
		_zoom_point_x = (_point.x - _screen.rest.x) / _zoom_factor
		_zoom_point_y = (_point.y - _screen.rest.y) / _zoom_factor
		_zoom_scale_x = _scale_change / _zoom_factor
		_zoom_scale_y = _scale_change / _zoom_factor
		_zoom_point = _zoom_time
		_zoom_reverse = 1

	# This ports DefineSprite_3419/frame_4. The original's last step puts _x
	# and _y back where BATTLESCREEN rests and leaves the scale to come back by
	# itself. It does unless a second zoom starts before the first ends, and
	# then the screen stays zoomed for the rest of the battle. The port puts the
	# scale back too, which ADR 0005 lists. It leaves out the original's reset
	# of zoomPoint to 0 when zoomPoint is zoomTime + 1, which a count down from
	# zoomTime never reaches.
	func _step() -> void:
		var x_go: float = _zoom_point_x * _zoom_point
		var y_go: float = _zoom_point_y * _zoom_point
		var x_scale_go: float = _zoom_scale_x * _zoom_point
		var y_scale_go: float = _zoom_scale_y * _zoom_point
		_screen.clip_x += x_go * _zoom_reverse
		_screen.clip_y += y_go * _zoom_reverse
		_screen.clip_xscale += x_scale_go * _zoom_reverse
		_screen.clip_yscale += y_scale_go * _zoom_reverse
		_zoom_point -= 1
		if _zoom_point > 0:
			goto_and_stop("KrinZoomPlay")
			play()
		elif _zoom_reverse == 1:
			_zoom_reverse = -1
			_zoom_point = _zoom_time
			_zoom_pause_counter = 0
			goto_and_stop("KrinZoomPause")
			play()
		else:
			_screen.clip_x = _screen.rest.x
			_screen.clip_y = _screen.rest.y
			_screen.clip_xscale = FULL_SCALE
			_screen.clip_yscale = FULL_SCALE
			goto_and_stop("KrinZoomStop")

	# This ports DefineSprite_3419/frame_6.
	func _hold() -> void:
		_zoom_pause_counter += 1
		if _zoom_pause_counter == _hold_frames:
			goto_and_stop("KrinZoomPlay")
		else:
			goto_and_stop("KrinZoomPause")
		play()


# This is GridShaker, DefineSprite 3420, with its frame scripts ported.
class GridShaker extends Clip:
	var _screen: BattleScreenClip
	# Its onClipEvent(load) sets these (frame_217/PlaceObject2_3420_330).
	var _shake_original: float
	var _shake_value: float
	var _shake_minus: float
	# Its last frame adds this to _y when it stops.
	var _settle: float

	func _init(screen: BattleScreenClip, timeline: Dictionary) -> void:
		super(timeline, {"stop": stop, "open": _open, "up": _up, "down": _down})
		_screen = screen
		var variables: Dictionary = timeline["variables"]
		_shake_original = float(variables["shakeOriginal"])
		_shake_value = float(variables["shakeValue"])
		_shake_minus = float(variables["shakeMinus"])
		_settle = float(timeline["settle"])

	# This ports DefineSprite_3420/frame_2.
	func _open() -> void:
		_screen.clip_y += _shake_value / 2

	# This ports DefineSprite_3420/frame_4.
	func _up() -> void:
		_screen.clip_y -= _shake_value
		_shake_value -= _shake_minus

	# This ports DefineSprite_3420/frame_5.
	func _down() -> void:
		_screen.clip_y += _shake_value
		_shake_value -= _shake_minus
		if _shake_value > 0:
			goto_and_stop("KrinShakeplayHere")
			play()
		else:
			_shake_value = _shake_original
			_screen.clip_y += _settle
			goto_and_stop("KrinShakestopHere")
