# Projectile's bolt/trail rendering - the real per-clip folders of
# individually-sized frame files instead of a tinted circle+line.
# docs/superpowers/specs/2026-08-18-missile-projectile-art-design.md.
extends GutTest

const ProjectileScene = preload("res://scenes/battle/projectile.tscn")


func test_start_loads_the_named_bolt_clip_untinted():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color(1.0, 0.2, 0.4)
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	var bolt_sprite: AnimatedSprite2D = bolt.get_node("Bolt")
	assert_not_null(bolt_sprite.sprite_frames, "loaded the real frame folder for this clip")
	assert_eq(bolt_sprite.modulate.r, 1.0, "bolt art itself is never color-tinted")
	assert_eq(bolt_sprite.modulate.g, 1.0)
	assert_eq(bolt_sprite.modulate.b, 1.0)


func test_bolt_art_is_halved_to_undo_the_extractors_2x_zoom():
	# vfx.py renders every clip at ZOOM = 2.0 for a crisp 1600x1200 window,
	# so drawn at scale 1.0 the art would cover twice the design-space area
	# the source clip did - character_visual.gd applies the same 0.5 to
	# doll_art.py's own 2x output.
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	assert_eq(bolt.get_node("Bolt").scale, Vector2(0.5, 0.5), "bolt renders at its design size")


func test_trail_art_is_halved_and_grows_from_that_baseline():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	var trail_sprite: AnimatedSprite2D = bolt.get_node("Trail")
	bolt._process(1.0 / 30.0)  # first tick - spawns the trail and grows it once
	assert_eq(trail_sprite.scale.y, 0.5, "the trail's thickness stays at its design size")
	# One tick of growth is 0.083 * step length * speed_const on top of a
	# 1.0 baseline, then the whole thing is halved.
	var step_length: float = (Vector2(300, 100) - Vector2(100, 100)).length() / Projectile.BOLT_TIME
	assert_almost_eq(trail_sprite.scale.x, 0.5 * (1.0 + 0.083 * step_length), 0.001,
		"growth is a multiple of the halved baseline, not an unscaled increment")


func test_bolt_is_rotated_to_the_flight_direction():
	# krinBoltMake rotates the bolt clip itself and copies that rotation
	# onto the trail. The direction is fixed at spawn, so start() can set it.
	var rightward: Projectile = add_child_autofree(ProjectileScene.instantiate())
	rightward.clip_name = "Krin.Firebolt"
	rightward.start(Vector2(100, 100), Vector2(300, 100))
	assert_almost_eq(rightward.get_node("Bolt").rotation, 0.0, 0.001, "flying right - no rotation")

	var leftward: Projectile = add_child_autofree(ProjectileScene.instantiate())
	leftward.clip_name = "Krin.Firebolt"
	leftward.start(Vector2(300, 100), Vector2(100, 100))
	assert_almost_eq(absf(leftward.get_node("Bolt").rotation), PI, 0.001, "flying left - turned around")

	var diagonal: Projectile = add_child_autofree(ProjectileScene.instantiate())
	diagonal.clip_name = "Krin.Firebolt"
	diagonal.start(Vector2(100, 100), Vector2(200, 200))
	assert_almost_eq(diagonal.get_node("Bolt").rotation, PI / 4.0, 0.001, "flying down-right")


func test_trail_is_anchored_at_its_left_edge_not_its_center():
	# KrinTrail's real inner sprite (id 2) places its shape at x 0..10,
	# y -3.5..3.5 design units, so the clip's origin sits at the streak's
	# LEFT edge, vertically centered. Godot centers a sprite by default,
	# which would send half of the growing streak backwards past the
	# caster. The extracted frames are 20x14 px (vfx.py's ZOOM = 2.0), so
	# the origin lands 7 px down from the texture's top-left corner.
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	var trail_sprite: AnimatedSprite2D = bolt.get_node("Trail")
	assert_false(trail_sprite.centered, "grows forward from its anchor, not out of its own middle")
	assert_eq(trail_sprite.offset, Vector2(0, -7), "left edge on the anchor, vertically centered on it")
	var frame: Texture2D = trail_sprite.sprite_frames.get_frame_texture("pulse", 0)
	assert_eq(frame.get_size(), Vector2(20, 14), "the offset above is half this texture's height")


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
	assert_not_null(trail_sprite.sprite_frames, "loaded the real 33-frame KrinTrail folder")
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


func test_trail_outlives_the_bolt_so_its_own_fade_can_finish():
	# The flight to a real target takes ~17 ticks; KrinTrail's own fade
	# runs 33 frames. As the bolt's child the trail would be torn down
	# mid-fade the moment a hit freed the bolt, so it moves up to be the
	# bolt's sibling as soon as it is placed.
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.did_hit = true
	bolt.start(Vector2(100, 100), Vector2(103, 100))

	var trail_sprite: AnimatedSprite2D = bolt.get_node("Trail")
	for i in 200:
		bolt._process(1.0 / 30.0)
		if bolt.is_queued_for_deletion():
			break
	assert_true(bolt.is_queued_for_deletion(), "the hit really did free the bolt")
	assert_eq(trail_sprite.get_parent(), self, "trail moved up to the bolt's own parent")

	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(bolt), "the bolt's deferred free has actually run by now")
	assert_true(is_instance_valid(trail_sprite), "the trail was not taken down with it")
	assert_true(trail_sprite.is_playing(), "it is still running its own fade")
	trail_sprite.queue_free()


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


func test_a_miss_with_no_horizontal_travel_still_ends():
	# A caster and target sharing an x coordinate would give the bolt a
	# zero x-step, so it could never cross the off-screen bound and the
	# fly-past would run forever. No battle slot pairing does that today -
	# this is the guard against future data that would.
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.did_hit = false
	bolt.start(Vector2(400, 100), Vector2(400, 300))

	for i in Projectile.MAX_FLIGHT_TICKS + 10:
		bolt._process(1.0 / 30.0)
		if bolt.is_queued_for_deletion():
			break
	assert_true(bolt.is_queued_for_deletion(), "the tick cap ends a flight that can never exit sideways")
