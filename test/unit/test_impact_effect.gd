# ImpactEffect - a one-shot animation that frees itself when done. Art
# comes from a per-clip generated scene under scenes/battle/vfx/impacts/.
# docs/superpowers/specs/2026-08-19-vfx-registration-scenes-design.md.
extends GutTest

const ImpactEffectScene = preload("res://scenes/battle/impact_effect.tscn")


func test_play_empty_name_is_a_noop_that_frees_the_node():
	var effect: ImpactEffect = add_child_autofree(ImpactEffectScene.instantiate())
	effect.play("")
	assert_true(effect.is_queued_for_deletion(), "no clip name - nothing to play, frees immediately")


func test_play_unknown_clip_is_a_noop_that_frees_the_node():
	var effect: ImpactEffect = add_child_autofree(ImpactEffectScene.instantiate())
	effect.play("NOT_A_REAL_IMPACT_CLIP")
	assert_true(effect.is_queued_for_deletion(), "no matching generated scene - frees immediately")


func test_play_real_clip_plays_and_frees_on_finish():
	var effect: ImpactEffect = add_child_autofree(ImpactEffectScene.instantiate())
	effect.play("BOOM_SPARK")
	assert_false(effect.is_queued_for_deletion(), "a real clip starts playing, not immediately freed")
	assert_true(effect._anim_sprite.is_playing(), "the one-shot animation is running")
	effect._anim_sprite.animation_finished.emit()
	assert_true(effect.is_queued_for_deletion(), "frees once the one-shot animation finishes")


func test_impact_art_is_halved_to_undo_the_extractors_2x_zoom():
	# Every generated scene's baked scale collapses to exactly 1/ZOOM -
	# see extract_vfx_scenes.py's own note on why.
	var effect: ImpactEffect = add_child_autofree(ImpactEffectScene.instantiate())
	effect.play("BOOM_SPARK")
	assert_eq(effect._anim_sprite.scale, Vector2(0.5, 0.5), "impact renders at its design size")


func test_impact_is_not_centered_on_its_own_bounding_box():
	# Real registration point from the generated scene, not Godot's
	# centered=true default - the whole reason this rework exists.
	var effect: ImpactEffect = add_child_autofree(ImpactEffectScene.instantiate())
	effect.play("BOOM_SPARK")
	assert_false(effect._anim_sprite.centered, "positioned at its real registration point, not centered on its texture")
