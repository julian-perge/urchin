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


func test_trail_stays_anchored_at_its_spawn_point_as_the_bolt_flies_on():
	# Confirmed empirically (a real running scene): a normal Node2D child
	# keeps inheriting its parent's transform every frame - without
	# top_level=true on Trail, it would be dragged along as Projectile's
	# own position keeps advancing, instead of staying anchored at the
	# point it was given on the first tick, defeating the whole point of
	# a streak that bridges a growing gap as the bolt flies away.
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	var trail_sprite: AnimatedSprite2D = bolt.get_node("Trail")
	bolt._process(1.0 / 30.0)  # first tick - spawns the trail at the bolt's current position
	var spawn_pos: Vector2 = trail_sprite.global_position
	for i in 10:
		bolt._process(1.0 / 30.0)  # the bolt keeps advancing
	assert_eq(trail_sprite.global_position, spawn_pos, "trail stays put while the bolt flies on")
	assert_gt(bolt.global_position.x, spawn_pos.x, "the bolt itself really did move away from that point")


func test_hit_frees_immediately_on_reaching_target():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.did_hit = true
	bolt.start(Vector2(100, 100), Vector2(103, 100))  # short hop - reaches fast
	# A Dictionary is used (not a bare local) because GDScript lambdas
	# capture plain locals by value, not by reference - see
	# test_cutscene_player.gd's identical note.
	var result := {"reached": false}
	bolt.reached_target.connect(func(): result.reached = true)

	for i in 200:
		bolt._process(1.0 / 30.0)
		if bolt.is_queued_for_deletion():
			break

	assert_true(result.reached, "reached_target fired")
	assert_true(bolt.is_queued_for_deletion(), "hit - frees right at the coordinate-cross tick")


func test_miss_keeps_flying_past_the_target_until_off_screen():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.did_hit = false
	bolt.start(Vector2(100, 100), Vector2(103, 100))
	# A Dictionary is used (not a bare local) because GDScript lambdas
	# capture plain locals by value, not by reference - see
	# test_cutscene_player.gd's identical note.
	var result := {"reached": false}
	bolt.reached_target.connect(func(): result.reached = true)

	# Advance a handful of ticks - reached_target should have already fired
	# (same coordinate-cross tick a hit would use), but the bolt must still
	# be alive, still past the target, not yet off-screen.
	for i in 30:
		bolt._process(1.0 / 30.0)
	assert_true(result.reached, "reached_target fires on a miss too, at the same tick a hit would")
	assert_false(bolt.is_queued_for_deletion(), "miss - doesn't free at the coordinate-cross tick")
	assert_true(bolt.position.x > 103.0, "kept moving past the target")

	# Let it keep flying until it exits this port's own screen bounds.
	for i in 2000:
		bolt._process(1.0 / 30.0)
		if bolt.is_queued_for_deletion():
			break
	assert_true(bolt.is_queued_for_deletion(), "eventually frees once off-screen")
