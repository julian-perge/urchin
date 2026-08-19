# VfxFrames.load_frames() - loads a per-clip folder of numbered frame
# files (dev/urchin_dev/swf/extract/vfx.py's own output) into a
# SpriteFrames animation. Shared by ImpactEffect and Projectile.
# docs/superpowers/specs/2026-08-18-missile-projectile-art-design.md.
extends GutTest


func test_load_frames_returns_null_for_a_missing_folder():
	var result: SpriteFrames = VfxFrames.load_frames("res://assets/vfx/impacts/not_a_real_clip/", "default", false, 30.0)
	assert_null(result, "no such folder - nothing to load")


func test_load_frames_loads_every_numbered_frame_of_a_real_clip():
	var result: SpriteFrames = VfxFrames.load_frames("res://assets/vfx/impacts/boom_sparkblue/", "default", false, 30.0)
	assert_not_null(result, "loaded the real boom_sparkblue clip")
	assert_eq(result.get_frame_count("default"), 25, "boom_sparkblue has 25 real frames")
	assert_false(result.get_animation_loop("default"), "loop flag passed through as given")


func test_load_frames_supports_a_non_default_looping_animation_name():
	# SpriteFrames.new() ships with a "default" animation already
	# registered - add_animation("default") throws "already has
	# animation" if called unconditionally. A non-"default" name like
	# "fly" doesn't collide, exercising the has_animation() guard's
	# other branch.
	var result: SpriteFrames = VfxFrames.load_frames("res://assets/vfx/bolts/krin_firebolt/", "fly", true, 30.0)
	assert_not_null(result)
	assert_true(result.get_animation_loop("fly"))
