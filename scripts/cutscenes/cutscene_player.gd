# cutscene_player.gd
# Reusable full-screen cutscene player: fades in from black, plays an .ogv
# clip with audio, fades back to black on completion, then frees itself.
# None of the 4 in-scope cutscenes (CS_CUT2-5) have a skip mechanism in the
# original, so this deliberately has no input handling.
class_name CutscenePlayer
extends Control

signal finished

# The original's fade steps _alpha by 5 per frame at 30fps, so a full
# 0-100 sweep is 20 frames = 0.667s. Matched here for both fade directions.
const FADE_SECONDS: float = 20.0 / 30.0

# 1.0 = normal pacing; 0.0 or less = instant (tests). Mirrors
# battle_scene.gd's animation_speed / _pause convention.
var animation_speed: float = 1.0

@onready var video: VideoStreamPlayer = $Video
@onready var fade_rect: ColorRect = $FadeRect


func play(cutscene_id: String) -> void:
	video.stream = load("res://assets/cutscenes/%s.ogv" % cutscene_id)
	fade_rect.color.a = 1.0
	await _fade(0.0)
	video.play()
	await video.finished
	await _fade(1.0)
	finished.emit()
	queue_free()


# Tweens the fade overlay's alpha to target_alpha over FADE_SECONDS (scaled
# by animation_speed), skipping straight there if animation_speed <= 0.
func _fade(target_alpha: float) -> void:
	if animation_speed <= 0.0:
		fade_rect.color.a = target_alpha
		return
	var tween: Tween = create_tween()
	tween.tween_property(fade_rect, "color:a", target_alpha, FADE_SECONDS / animation_speed)
	await tween.finished
