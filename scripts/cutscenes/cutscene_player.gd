# cutscene_player.gd
# Reusable full-screen cutscene player: plays an .ogv clip with audio under a
# fade in from black, fades back to black on completion, then frees itself.
#
# It has the original's SKIP button. Button 3468, a hit area at the bottom
# right, and the "SKIP" text 3469 sit on every cutscene frame. Releasing the
# button stops all sounds and sets cutSceneEnd
# (DefineButton2_3468/BUTTONCONDACTION on(release).as), and the original's fade
# clip then fades out and jumps to gotoSceneKrin
# (frame_263/PlaceObject2_3466_80/CLIPACTIONRECORD onClipEvent(enterFrame).as).
# Here a press stops the clip and its audio. Then the same fade out, finished
# signal and queue_free run as when the clip plays to its end. The button works
# from the first frame, while the cutscene still fades in. extract_cutscene_skip
# writes assets/cutscenes/skip_button.json, which says where the button and its
# text go and how the text is drawn.
#
# CS_INTRO is the one id that is not a clip. The original draws it as text over a
# gradient, so play() fades in scenes/cutscenes/cs_intro.tscn for it and holds it
# for as long as the original does, or until the player presses SKIP. Then it
# fades out and finishes as it does for a clip.
#
# Two things in cutscene_player.tscn exist to keep the rest of the game out
# of the way while the clip runs, and both matter:
#   - The root Control is MOUSE_FILTER_STOP, so clicks land here instead of
#     falling through to whatever put the cutscene up. Without it the battle
#     victory screen's Proceed button stays live underneath for as long as the
#     clip plays.
#   - The video, the SKIP button and the fade sit under a CanvasLayer at layer
#     100, above battle_scene.tscn's "UI" layer (the default, 1). Added to an
#     ordinary Control the way battle_scene.gd adds this, they would otherwise
#     draw *under* the battle HUD.
# The fade rect sits above the SKIP button and ignores the mouse. So the button
# fades with the clip, as in the original, and still takes clicks.
class_name CutscenePlayer
extends Control

signal finished

# Emitted when playback ends: the video reported it finished, the failsafe
# timeout ran out, CS_INTRO's hold ran out, or the player pressed SKIP.
signal _playback_settled

# Where the SKIP button's hit area and its text go, and how the text is drawn.
# extract_cutscene_skip writes this file.
const SKIP_LAYOUT_PATH: String = "res://assets/cutscenes/skip_button.json"

# The fade clip takes a step off its _alpha each frame while cutSceneEnd is
# false and the alpha is above 0, and adds the same step each frame once
# cutSceneEnd is true (frame_263/PlaceObject2_3466_80 enterFrame, lines 2-11).
# extract_fade_steps writes the step to this file. The alpha is in Flash's 1/256
# steps (FlashAlpha).
const FADE_PATH: String = "res://assets/cutscenes/cutscene_fade.json"
static var _fade_steps: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FADE_PATH))
# Render deltas that add up to a whole SWF frame can fall short of it by a float
# rounding error, so a frame counts as passed within this margin.
const FRAME_EPSILON: float = 0.000001

# How much longer than the clip's own reported length play() will wait for
# the video to report it finished before giving up on it.
const PLAYBACK_TIMEOUT_MARGIN_SECONDS: float = 5.0

# Budget used when the stream will not report a length at all
# (get_stream_length() returns 0). Longer than any of the 4 clips.
const PLAYBACK_TIMEOUT_FALLBACK_SECONDS: float = 120.0

const INTRO_ID: String = "CS_INTRO"
const CsIntroScene: PackedScene = preload("res://scenes/cutscenes/cs_intro.tscn")

# 1.0 = normal pacing; 0.0 or less = instant (tests). Mirrors
# battle_scene.gd's animation_speed / _pause convention.
var animation_speed: float = 1.0

# Overrides the failsafe timeout budget when set above 0. Only the failsafe's
# own regression test sets it - the derived budget is a real clip's length
# plus a margin, far too long to wait out in a test.
var playback_timeout_seconds: float = 0.0

# Set once play() starts, so a second call can't stack another coroutine
# driving the same fade_rect/queue_free.
var _started: bool = false

# Set when the player presses SKIP. A press before play() reaches its wait for
# the clip or for CS_INTRO's hold emits _playback_settled with nothing listening,
# so play() and _hold() check this.
var _skipped: bool = false

# The fade clip's _alpha in Flash's 1/256 steps. The clip starts opaque.
var _fade_alpha: int = FlashAlpha.STEPS
var _fade_frames_due: float = 0.0

@onready var overlay: CanvasLayer = $Overlay
@onready var video: VideoStreamPlayer = $Overlay/Video
@onready var skip_text: Label = $Overlay/SkipText
@onready var skip_button: Button = $Overlay/SkipButton
@onready var fade_rect: ColorRect = $Overlay/FadeRect


func _ready() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SKIP_LAYOUT_PATH))
	var hit: Dictionary = layout["button"]
	skip_button.position = Vector2(hit["x"], hit["y"])
	skip_button.size = Vector2(hit["w"], hit["h"])
	var text: Dictionary = layout["text"]
	var rect: Dictionary = text["rect"]
	skip_text.text = text["string"]
	skip_text.horizontal_alignment = LabelLayout.ALIGNMENTS[text["align"]]
	skip_text.add_theme_font_size_override("font_size", int(text["size"]))
	skip_text.add_theme_color_override("font_color", Color(text["color"]))
	# The size goes on last. A Control never shrinks back from a size that its
	# minimum forced up, and the minimum of a 16 px Label is taller than this one.
	skip_text.position = Vector2(rect["x"], rect["y"])
	skip_text.size = Vector2(rect["w"], rect["h"])
	skip_button.pressed.connect(_on_skip_pressed)


func play(cutscene_id: String) -> void:
	if _started:
		push_warning("CutscenePlayer.play() called again on an instance already playing %s - ignored." % cutscene_id)
		return
	_started = true

	if cutscene_id == INTRO_ID:
		await _play_intro()
		return

	var stream: VideoStream = load("res://assets/cutscenes/%s.ogv" % cutscene_id)
	if stream == null:
		# Missing/misspelled cutscene id: a caller awaiting our finished
		# signal (the battle-victory flow) must not hang forever waiting on
		# a video that will never start.
		push_warning("CutscenePlayer.play(): no video stream for '%s' - skipping playback." % cutscene_id)
		finished.emit()
		queue_free()
		return

	# The original places the clip on the same root frame as the fade clip, and
	# nothing stops the clip on its first frame, so it plays under the fade-in
	# (frame_263/PlaceObject2_3466_80 enterFrame, lines 2-8). A SKIP press
	# during the fade-in stops it.
	video.stream = stream
	_show_fade()
	video.play()
	await _fade(false)
	if not _skipped:
		await _await_playback_end()
	await _fade(true)
	finished.emit()
	queue_free()


# The scene takes the video's place in the overlay's order, so SKIP and the fade stay
# above it.
func _play_intro() -> void:
	var intro: CsIntro = CsIntroScene.instantiate()
	overlay.add_child(intro)
	overlay.move_child(intro, video.get_index() + 1)
	_show_fade()
	await _fade(false)
	await _hold(intro.hold_seconds)
	await _fade(true)
	finished.emit()
	queue_free()


# Waits `seconds` of the original's time. animation_speed scales the wait as it scales
# the fades. It ends early when the player presses SKIP, and a speed of 0 or less, or a
# press before it starts, skips it.
func _hold(seconds: float) -> void:
	if animation_speed <= 0.0 or _skipped:
		return
	var timer: SceneTreeTimer = get_tree().create_timer(seconds / animation_speed)
	var settle: Callable = func(): _playback_settled.emit()
	timer.timeout.connect(settle, CONNECT_ONE_SHOT)
	await _playback_settled
	# Drop the timer's call if SKIP ended the wait first, so it can't reach a freed node.
	if timer.timeout.is_connected(settle):
		timer.timeout.disconnect(settle)


func _on_skip_pressed() -> void:
	_skipped = true
	video.stop()
	_playback_settled.emit()


# Waits for whichever comes first: the video reporting it finished, a timeout
# sized from the clip's own length, or the player pressing SKIP. A Theora
# stream that stalls or fails to decode partway never emits "finished". The
# player could press SKIP, but waiting on the video and SKIP alone would leave
# the game stuck until they did. Timing out is treated exactly like a normal
# end - fade out, signal, free - so the player still lands back in the game.
func _await_playback_end() -> void:
	var budget: float = playback_timeout_seconds
	if budget <= 0.0:
		var length: float = video.get_stream_length()
		if length <= 0.0:
			length = PLAYBACK_TIMEOUT_FALLBACK_SECONDS
		budget = length + PLAYBACK_TIMEOUT_MARGIN_SECONDS

	var settled: Dictionary = {"done": false}
	var settle: Callable = func():
		if settled.done:
			return
		settled.done = true
		_playback_settled.emit()

	var timer: SceneTreeTimer = get_tree().create_timer(budget)
	video.finished.connect(settle, CONNECT_ONE_SHOT)
	timer.timeout.connect(settle, CONNECT_ONE_SHOT)
	await _playback_settled
	# Drop whichever one did not fire, so it can't reach a freed node later.
	if video.finished.is_connected(settle):
		video.finished.disconnect(settle)
	if timer.timeout.is_connected(settle):
		timer.timeout.disconnect(settle)


# Runs the fade clip's enterFrame once for each SWF frame of display time, scaled
# by animation_speed, until the fade ends. With cut_scene_end false it ends when
# the clip is clear or the player presses SKIP, which turns the fade around at
# once, as the original's SKIP does by setting cutSceneEnd. With cut_scene_end
# true it ends when the clip is black, where the original jumps to
# gotoSceneKrin. At an animation_speed of 0 or below it shows the end at once.
# A player that leaves the tree mid-fade stops the fade where it is.
func _fade(cut_scene_end: bool) -> void:
	if animation_speed <= 0.0:
		_fade_alpha = FlashAlpha.STEPS if cut_scene_end else 0
		_show_fade()
		return
	_fade_frames_due = 0.0
	while not _fade_ended(cut_scene_end):
		await get_tree().process_frame
		if not is_inside_tree():
			return
		_fade_frames_due += get_process_delta_time() * BattleScreenClip.fps() * animation_speed
		while _fade_frames_due >= 1.0 - FRAME_EPSILON and not _fade_ended(cut_scene_end):
			_fade_frames_due -= 1.0
			step_fade(cut_scene_end)


func _fade_ended(cut_scene_end: bool) -> bool:
	if cut_scene_end:
		return is_black()
	return _skipped or _fade_alpha <= 0


# One run of the fade clip's enterFrame.
func step_fade(cut_scene_end: bool) -> void:
	if cut_scene_end:
		_fade_alpha = FlashAlpha.add(_fade_alpha, float(_fade_steps["fade_step"]))
	elif _fade_alpha > 0:
		_fade_alpha = FlashAlpha.add(_fade_alpha, -float(_fade_steps["fade_step"]))
	_show_fade()


# Whether the fade clip has reached the "_alpha >= 100" that sends the original
# to gotoSceneKrin.
func is_black() -> bool:
	return FlashAlpha.to_percent(_fade_alpha) >= 100.0


func _show_fade() -> void:
	fade_rect.color.a = FlashAlpha.multiplier(_fade_alpha)
