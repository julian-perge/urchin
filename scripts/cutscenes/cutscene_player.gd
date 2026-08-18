# cutscene_player.gd
# Reusable full-screen cutscene player: fades in from black, plays an .ogv
# clip with audio, fades back to black on completion, then frees itself.
# None of the 4 in-scope cutscenes (CS_CUT2-5) have a skip mechanism in the
# original, so this deliberately has no input handling.
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

@onready var video: VideoStreamPlayer = $Overlay/Video
@onready var fade_rect: ColorRect = $Overlay/FadeRect


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
	video.play()
	await _await_playback_end()
	await _fade(1.0)
	finished.emit()
	queue_free()


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
