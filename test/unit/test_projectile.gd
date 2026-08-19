# Projectile's bolt/trail rendering - real per-clip art instead of a
# tinted circle+line. docs/superpowers/specs/2026-08-18-missile-projectile-art-design.md.
extends GutTest

const ProjectileScene = preload("res://scenes/battle/projectile.tscn")


func test_start_loads_the_named_bolt_clip_untinted():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color(1.0, 0.2, 0.4)
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	var bolt_sprite: AnimatedSprite2D = bolt.get_node("Bolt")
	assert_not_null(bolt_sprite.sprite_frames, "loaded a real spritesheet for this clip")
	assert_eq(bolt_sprite.modulate.r, 1.0, "bolt art itself is never color-tinted")
	assert_eq(bolt_sprite.modulate.g, 1.0)
	assert_eq(bolt_sprite.modulate.b, 1.0)


func test_start_with_unknown_clip_falls_back_to_the_tinted_circle():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "NOT_A_REAL_BOLT_CLIP"
	bolt.trail_color = Color.WHITE
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	var bolt_sprite: AnimatedSprite2D = bolt.get_node("Bolt")
	assert_null(bolt_sprite.sprite_frames, "no matching asset - falls back to the _draw() circle guard")


func test_start_loads_the_trail_as_a_non_looping_tinted_pulse():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color(1.0, 0.2, 0.4)
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	var trail_sprite: AnimatedSprite2D = bolt.get_node("Trail")
	assert_not_null(trail_sprite.sprite_frames, "loaded the real 33-frame KrinTrail spritesheet")
	assert_eq(trail_sprite.sprite_frames.get_frame_count("pulse"), 33, "the real animated content, not sprite 3's 1-frame wrapper")
	assert_false(trail_sprite.sprite_frames.get_animation_loop("pulse"), "plays once - its own frames already carry the fade in/out")
	assert_almost_eq(trail_sprite.modulate.r, 1.0, 0.01, "RGB tint only")
	assert_almost_eq(trail_sprite.modulate.g, 0.2, 0.01)
	assert_almost_eq(trail_sprite.modulate.b, 0.4, 0.01)
