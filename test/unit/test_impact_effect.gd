# ImpactEffect - a one-shot animation that frees itself when done.
# docs/superpowers/specs/2026-08-18-missile-projectile-art-design.md.
extends GutTest

const ImpactEffectScene = preload("res://scenes/battle/impact_effect.tscn")


func test_play_empty_name_is_a_noop_that_frees_the_node():
	var effect: ImpactEffect = add_child_autofree(ImpactEffectScene.instantiate())
	effect.play("")
	assert_true(effect.is_queued_for_deletion(), "no clip name - nothing to play, frees immediately")


func test_play_unknown_clip_is_a_noop_that_frees_the_node():
	var effect: ImpactEffect = add_child_autofree(ImpactEffectScene.instantiate())
	effect.play("NOT_A_REAL_IMPACT_CLIP")
	assert_true(effect.is_queued_for_deletion(), "no matching folder on disk - frees immediately")


func test_play_real_clip_plays_and_frees_on_finish():
	var effect: ImpactEffect = add_child_autofree(ImpactEffectScene.instantiate())
	effect.play("BOOM_SPARK")
	assert_false(effect.is_queued_for_deletion(), "a real clip starts playing, not immediately freed")
	var anim_sprite: AnimatedSprite2D = effect.get_node("Anim")
	assert_true(anim_sprite.is_playing(), "the one-shot animation is running")
	anim_sprite.animation_finished.emit()
	assert_true(effect.is_queued_for_deletion(), "frees once the one-shot animation finishes")
