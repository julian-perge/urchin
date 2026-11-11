# cutscene_player.gd
# Reusable full-screen cutscene player: fades in from black, plays an .ogv
# clip with audio, fades back to black on completion, then frees itself.
# The original does have a skip: button 3468, labelled by the "SKIP" text
# 3469, sits on every cutscene frame and stops all sounds and sets
# cutSceneEnd when released (DefineButton2_3468/BUTTONCONDACTION
# on(release).as). This player has no input handling, so it has no skip yet.
#
# Two things in cutscene_player.tscn exist to keep the rest of the game out
# of the way while the clip runs, and both matter:
#   - The root Control is MOUSE_FILTER_STOP, so clicks land here instead of
#     falling through to whatever put the cutscene up. Without it the battle
#     victory screen's Proceed button stays live underneath for the clip's
#     whole unskippable runtime.
#   - The video and the fade sit under a CanvasLayer at layer 100, above
#     battle_scene.tscn's "UI" layer (the default, 1). Added to an ordinary
#     Control the way battle_scene.gd adds this, they would otherwise draw
#     *under* the battle HUD.
class_name CutscenePlayer
extends Control

signal finished

# Emitted once playback has ended, whether the video reported it or the
# failsafe timeout did. Private to _await_playback_end().
signal _playback_settled

# Where the SKIP button's hit area and its text go, and how the text is drawn.
# extract_cutscene_skip writes this file.
const SKIP_LAYOUT_PATH: String = "res://assets/cutscenes/skip_button.json"

# The original's fade steps _alpha by 5 per frame at 30fps, so a full
# 0-100 sweep is 20 frames = 0.667s. Matched here for both fade directions.
const FADE_SECONDS: float = 20.0 / 30.0

# How much longer than the clip's own reported length play() will wait for
# the video to report it finished before giving up on it.
const PLAYBACK_TIMEOUT_MARGIN_SECONDS: float = 5.0

# Budget used when the stream will not report a length at all
# (get_stream_length() returns 0). Longer than any of the 4 clips.
const PLAYBACK_TIMEOUT_FALLBACK_SECONDS: float = 120.0

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
# the clip emits _playback_settled with nothing listening, so play() checks this.
var _skipped: bool = false

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

	var stream: VideoStream = load("res://assets/cutscenes/%s.ogv" % cutscene_id)
	if stream == null:
		# Missing/misspelled cutscene id: a caller awaiting our finished
		# signal (the battle-victory flow) must not hang forever waiting on
		# a video that will never start.
		push_warning("CutscenePlayer.play(): no video stream for '%s' - skipping playback." % cutscene_id)
		finished.emit()
		queue_free()
		return

	video.stream = stream
	fade_rect.color.a = 1.0
	await _fade(0.0)
	if not _skipped:
		video.play()
		await _await_playback_end()
	await _fade(1.0)
	finished.emit()
	queue_free()


func _on_skip_pressed() -> void:
	_skipped = true
	video.stop()
	_playback_settled.emit()


# Waits for whichever comes first: the video reporting it finished, or a
# timeout sized from the clip's own length. A Theora stream that stalls or
# fails to decode partway never emits "finished", and there is no skip input
# and no other way out of a cutscene, so waiting on the video alone would
# soft-lock the game outright. Timing out is treated exactly like a normal
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


# Tweens the fade overlay's alpha to target_alpha over FADE_SECONDS (scaled
# by animation_speed), skipping straight there if animation_speed <= 0.
func _fade(target_alpha: float) -> void:
	if animation_speed <= 0.0:
		fade_rect.color.a = target_alpha
		return
	var tween: Tween = create_tween()
	tween.tween_property(fade_rect, "color:a", target_alpha, FADE_SECONDS / animation_speed)
	await tween.finished
