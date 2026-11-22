# Projectile's bolt/trail rendering - each clip's own generated scene
# (dev/urchin_dev/swf/extract/vfx_scenes.py) instead of a tinted circle+
# line or a dynamically-scanned PNG folder.
# spec/old/2026-08-19-vfx-registration-scenes-design.md.
extends GutTest

const AlphaSteps = preload("res://test/alpha_steps.gd")
const ProjectileScene = preload("res://scenes/battle/projectile.tscn")

var _krin: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Projectile.KRIN_SETTINGS_PATH))
# The width of KrinTrail's inner shape at an _xscale of 100, from the extracted
# registration offsets.
var _trail_art_width: float = float(
	JSON.parse_string(FileAccess.get_file_as_string("res://assets/vfx/vfx_offsets.json"))["krintrail"]["w"]
)


# Each frame krinBoltMake moves the bolt by the distance it measured at the
# start over krinBoltTime, times SpeedConst, and then multiplies SpeedConst by
# krinBoltIncrease. SpeedConst starts at krinBoltSpeed
# (frame_42/DoAction_4.as:146 and 165-171).
func test_the_bolt_speeds_up_by_krin_bolt_increase_each_frame():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.start(Vector2(-400, 100), Vector2(400, 100))
	bolt.set_process(false)
	var step: float = 800.0 / float(_krin["krinBoltTime"])
	var speed: float = float(_krin["krinBoltSpeed"])
	var expected_x: float = -400.0
	for frame: int in 10:
		bolt._process(1.0 / BattleScreenClip.fps())
		expected_x += step * speed
		speed *= float(_krin["krinBoltIncrease"])
		assert_almost_eq(bolt.position.x, expected_x, 0.001, "frame %d" % (frame + 1))
	bolt._trail_root.queue_free()


# The Traced run replayed the bolt's onEnterFrame fade from its attach at 0
# (FADE case "bolt" of alpha_steps_probe.as). The bolt shows the alpha that each
# frame logged, and stops adding once it is at 100 or above.
func test_the_bolt_fades_in_on_the_frames_the_traced_run_measured():
	var measured: Array[float] = AlphaSteps.values("FADE", "bolt")
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.start(Vector2(-400, 100), Vector2(400, 100))
	bolt.set_process(false)
	var ported: Array[float] = [FlashAlpha.to_percent(bolt._alpha)]
	var shown: Array[float] = [0.0]
	for _frame: int in 14:
		bolt._process(1.0 / BattleScreenClip.fps())
		ported.append(FlashAlpha.to_percent(bolt._alpha))
		shown.append(bolt._bolt_sprite.modulate.a)
	assert_eq(ported, measured.slice(0, 15), "every frame's _alpha")
	var drawn: Array[float] = []
	for percent: float in measured.slice(0, 15):
		drawn.append(percent / 100.0)
	assert_eq(shown, drawn, "drawn as the alpha over 100")


func test_start_loads_the_named_bolt_clip_untinted():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color(1.0, 0.2, 0.4)
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	assert_not_null(bolt._bolt_sprite, "loaded the real generated scene for this clip")
	assert_eq(bolt._bolt_sprite.modulate.r, 1.0, "bolt art itself is never color-tinted")
	assert_eq(bolt._bolt_sprite.modulate.g, 1.0)
	assert_eq(bolt._bolt_sprite.modulate.b, 1.0)


func test_bolt_art_is_halved_to_undo_the_extractors_2x_zoom():
	# Every generated scene's baked scale collapses to exactly 1/ZOOM -
	# see extract_vfx_scenes.py's own note on why - so this stays a flat
	# assertion even though the value now comes from the clip's own scene,
	# not a shared VFX_SCALE constant.
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	assert_eq(bolt._bolt_sprite.scale, Vector2(0.5, 0.5), "bolt renders at its design size")


func test_trail_art_is_halved_and_grows_from_that_baseline():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	bolt._process(1.0 / 30.0)  # first tick - spawns the trail and grows it once
	assert_eq(bolt._trail_sprite.scale.y, 0.5, "the trail's thickness stays at its design size")
	# One tick of growth is krinBoltTrailGrowth percent of the step length
	# times SpeedConst after its first krinBoltIncrease, on top of a 1.0
	# baseline, then the whole thing is halved (the trail scene's own baked
	# scale).
	var step_length: float = (Vector2(300, 100) - Vector2(100, 100)).length() / float(_krin["krinBoltTime"])
	var speed: float = float(_krin["krinBoltSpeed"]) * float(_krin["krinBoltIncrease"])
	assert_almost_eq(bolt._trail_sprite.scale.x, 0.5 * (1.0 + float(_krin["krinBoltTrailGrowth"]) / 100.0 * step_length * speed), 0.001,
		"growth is a multiple of the halved baseline, not an unscaled increment")


func test_bolt_is_rotated_to_the_flight_direction():
	# krinBoltMake rotates the bolt clip itself and copies that rotation
	# onto the trail. The direction is fixed at spawn, so start() can set
	# it - on the wrapper node, so the sprite's own baked registration
	# offset rotates around the wrapper's origin (the clip's true pivot),
	# not the texture's own center.
	var rightward: Projectile = add_child_autofree(ProjectileScene.instantiate())
	rightward.clip_name = "Krin.Firebolt"
	rightward.start(Vector2(100, 100), Vector2(300, 100))
	assert_almost_eq(rightward._bolt_root.rotation, 0.0, 0.001, "flying right - no rotation")

	var leftward: Projectile = add_child_autofree(ProjectileScene.instantiate())
	leftward.clip_name = "Krin.Firebolt"
	leftward.start(Vector2(300, 100), Vector2(100, 100))
	assert_almost_eq(absf(leftward._bolt_root.rotation), PI, 0.001, "flying left - turned around")

	var diagonal: Projectile = add_child_autofree(ProjectileScene.instantiate())
	diagonal.clip_name = "Krin.Firebolt"
	diagonal.start(Vector2(100, 100), Vector2(200, 200))
	assert_almost_eq(diagonal._bolt_root.rotation, PI / 4.0, 0.001, "flying down-right")


func test_trail_is_not_centered_on_its_own_bounding_box():
	# KrinTrail's real inner sprite (id 2) places its shape at x 0..10,
	# y -3.5..3.5 design units - the clip's origin sits at the streak's
	# LEFT edge, vertically centered, not its texture's own center. The
	# generated scene bakes this as a plain .position on its
	# AnimatedSprite2D (natural, unzoomed units - the same convention
	# resources/sprites/doll_offsets.json uses).
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	assert_false(bolt._trail_sprite.centered, "grows forward from its anchor, not out of its own middle")
	assert_eq(bolt._trail_sprite.position, Vector2(0, -3.5), "left edge on the anchor, vertically centered on it")
	var frame: Texture2D = bolt._trail_sprite.sprite_frames.get_frame_texture("pulse", 0)
	assert_eq(frame.get_size(), Vector2(20, 14), "the position above is in natural units - half this texture's height, unzoomed")


func test_start_with_unknown_clip_falls_back_to_the_tinted_circle():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "NOT_A_REAL_BOLT_CLIP"
	bolt.trail_color = Color.WHITE
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	assert_null(bolt._bolt_sprite, "no matching generated scene - falls back to the _draw() circle guard")


func test_start_loads_the_trail_as_a_non_looping_tinted_pulse():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color(1.0, 0.2, 0.4)
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	assert_not_null(bolt._trail_sprite.sprite_frames, "loaded the real 33-frame KrinTrail generated scene")
	assert_eq(bolt._trail_sprite.sprite_frames.get_frame_count("pulse"), 33, "the real animated content, not sprite 3's 1-frame wrapper")
	assert_false(bolt._trail_sprite.sprite_frames.get_animation_loop("pulse"), "plays once - its own frames already carry the fade in/out")
	assert_almost_eq(bolt._trail_sprite.modulate.r, 1.0, 0.01, "RGB tint only")
	assert_almost_eq(bolt._trail_sprite.modulate.g, 0.2, 0.01)
	assert_almost_eq(bolt._trail_sprite.modulate.b, 0.4, 0.01)


func test_trail_stays_anchored_at_its_spawn_point_as_the_bolt_flies_on():
	# The first tick moves the trail from the bolt to the bolt's parent. As
	# the bolt's child it would be dragged along as the bolt flies, instead
	# of staying at the point it was given on the first tick.
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.start(Vector2(100, 100), Vector2(300, 100))

	bolt._process(1.0 / 30.0)  # first tick - spawns the trail at the bolt's current position
	var spawn_pos: Vector2 = bolt._trail_sprite.global_position
	for i in 10:
		bolt._process(1.0 / 30.0)  # the bolt keeps advancing
	assert_eq(bolt._trail_sprite.global_position, spawn_pos, "trail stays put while the bolt flies on")
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
	var result := {"reached": false, "ended": false}
	bolt.reached_target.connect(func(): result.reached = true)
	bolt.flight_ended.connect(func(): result.ended = result.reached)

	for i in 200:
		bolt._process(1.0 / 30.0)
		if bolt.is_queued_for_deletion():
			break

	assert_true(result.reached, "reached_target fired")
	assert_true(bolt.is_queued_for_deletion(), "hit - frees right at the coordinate-cross tick")
	assert_true(result.ended, "and its flight ends then, after reached_target")


func test_trail_outlives_the_bolt_so_its_own_fade_can_finish():
	# The flight to a real target takes ~17 ticks; KrinTrail's own fade
	# runs 33 frames. As the bolt's child the trail would be torn down
	# mid-fade the moment a hit freed the bolt, so its wrapper moves up to
	# be the bolt's sibling as soon as it is placed.
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.did_hit = true
	bolt.start(Vector2(100, 100), Vector2(103, 100))

	var trail_root: Node2D = bolt._trail_root
	var trail_sprite: AnimatedSprite2D = bolt._trail_sprite
	for i in 200:
		bolt._process(1.0 / 30.0)
		if bolt.is_queued_for_deletion():
			break
	assert_true(bolt.is_queued_for_deletion(), "the hit really did free the bolt")
	assert_eq(trail_root.get_parent(), self, "trail's wrapper moved up to the bolt's own parent")

	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(bolt), "the bolt's deferred free has actually run by now")
	assert_true(is_instance_valid(trail_root), "the trail was not taken down with it")
	assert_true(trail_sprite.is_playing(), "it is still running its own fade")
	trail_root.queue_free()


func test_miss_keeps_flying_past_the_target_until_off_screen():
	var bolt: Projectile = add_child_autofree(ProjectileScene.instantiate())
	bolt.clip_name = "Krin.Firebolt"
	bolt.trail_color = Color.WHITE
	bolt.did_hit = false
	var rest_x: float = float(BattleScreenClip.motion()["rest"]["x"])
	bolt.battle_screen_x = rest_x
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

	# krinBoltMake removes a missed bolt once it is more than krinBoltMissX px
	# from the origin of BATTLESCREEN (frame_42/DoAction_4.as:201), which sits
	# where the battle frame places BATTLESCREEN.
	var ended: Array = []
	bolt.flight_ended.connect(func(): ended.append(bolt.position.x))
	var last_x: float = bolt.position.x
	for i in 2000:
		last_x = bolt.position.x
		bolt._process(1.0 / 30.0)
		if bolt.is_queued_for_deletion():
			break
	assert_true(bolt.is_queued_for_deletion(), "eventually frees")
	var miss_x: float = float(_krin["krinBoltMissX"])
	assert_lte(last_x, rest_x + miss_x, "not while it was within %d px of BATTLESCREEN's origin" % miss_x)
	assert_gt(bolt.position.x, rest_x + miss_x, "but on the tick it got further")
	assert_eq(ended.size(), 1, "and its flight ends then")


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


# The far end of the trail, in the coordinates of the node the bolt flies in.
# KrinTrail's inner shape starts at x 0, and the scene draws it from a texture
# twice its size, so the texture's right edge is the shape's far end.
func _trail_end_in(field: Node2D, bolt: Projectile) -> Vector2:
	var texture: Texture2D = bolt._trail_sprite.sprite_frames.get_frame_texture("pulse", 0)
	var tip: Vector2 = Vector2(texture.get_width(), texture.get_height() / 2.0)
	return field.get_global_transform().affine_inverse() * (bolt._trail_sprite.get_global_transform() * tip)


# A bolt from slot 1 to slot 2 (SLOT_POSITIONS in battle_scene.gd) that hits.
# Each frame, krinBoltMake moves the bolt and multiplies SpeedConst by
# krinBoltIncrease (frame_42/DoAction_4.as:165-171). On the first frame it then
# attaches KrinTrail at the bolt's new _x, with its inner clip at an _xscale of
# 100 (lines 173-177). While the bolt has not crossed the target's x, it grows
# the inner clip's _xscale by krinBoltTrailGrowth times the step times the new
# SpeedConst (line 209). On the frame it crosses on a hit, it removes the bolt
# and does not grow the trail (lines 188-195).
func test_the_trail_ends_where_krin_bolt_make_puts_it_on_every_frame_of_a_hit():
	var from := Vector2(160.9, 297.4)
	var to := Vector2(637.9, 297.4)
	var field: Node2D = add_child_autofree(Node2D.new())
	var bolt: Projectile = ProjectileScene.instantiate()
	bolt.clip_name = "Krin.Iceblade"
	bolt.did_hit = true
	field.add_child(bolt)
	bolt.start(from, to)
	bolt.set_process(false)
	var step: float = (to.x - from.x) / float(_krin["krinBoltTime"])
	var speed: float = float(_krin["krinBoltSpeed"])
	var bolt_x: float = from.x
	var trail_x: float = 0.0
	var xscale: float = 0.0
	var ported: Array[float] = []
	var original: Array[float] = []
	for frame: int in 60:
		bolt._process(1.0 / BattleScreenClip.fps())
		bolt_x += step * speed
		speed *= float(_krin["krinBoltIncrease"])
		if frame == 0:
			trail_x = bolt_x
			xscale = 100.0
		var crossed: bool = to.x - bolt_x <= 0.0
		if not crossed:
			xscale += float(_krin["krinBoltTrailGrowth"]) * step * speed
		ported.append(snappedf(_trail_end_in(field, bolt).x, 0.01))
		original.append(snappedf(trail_x + _trail_art_width * xscale / 100.0, 0.01))
		if crossed:
			break
	assert_true(bolt.is_queued_for_deletion(), "the bolt hit on the frame the original's crossed")
	assert_eq(ported, original, "the trail's far end on each frame")


# The Flash capture of #492 (references/traced_runs/vapour_cannon_web_flash.txt,
# written by vapour_cannon_probe.as in the same folder). Each cast is one
# Vapour Cannon bolt in battle 100: cast 1 flies from slot 3 to slot 2, and cast
# 2 from slot 2 to slot 1. Its "made" line gives where krinBoltMake put the bolt
# and its target, in BATTLESCREEN space. Its BOLT lines give the bolt and its
# KrinTrail after each of the bolt's enterFrames, until the frame that removed
# the bolt.
func _flash_cast(cast: int) -> Dictionary:
	var made: Dictionary = {}
	var frames: Array[Dictionary] = []
	var path := "res://references/traced_runs/vapour_cannon_web_flash.txt"
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var fields: PackedStringArray = line.split("\t")
		var values: Dictionary = {}
		for field: String in fields:
			var pair: PackedStringArray = field.split("=", false, 1)
			if pair.size() == 2:
				values[pair[0]] = pair[1]
		if values.get("cast") != str(cast):
			continue
		if fields[0] == "VAP" and fields[1] == "made":
			made = values
		elif fields[0] == "BOLT":
			frames.append(values)
	return {"made": made, "frames": frames}


# On every frame of the Flash capture, the port's bolt is where the original's
# was, and its trail ends where the original's did. On the frame that removes
# the bolt, the port's bolt is freed, and only the trail is compared. The
# original's trail ends at its _x and _y plus its length along its _rotation,
# and its length is the width of the art times the inner clip's _xscale. Flash keeps _x and _y in whole
# twips (0.05 px) after each move, so the positions drift from the port's by a
# little each frame.
func test_the_bolt_and_its_trail_match_the_flash_capture_on_every_frame():
	for cast: int in [1, 2]:
		var capture: Dictionary = _flash_cast(cast)
		var made: Dictionary = capture["made"]
		assert_eq(made.get("model"), "Krin.Iceblade", "cast %d is a Vapour Cannon bolt" % cast)
		var field: Node2D = add_child_autofree(Node2D.new())
		var bolt: Projectile = ProjectileScene.instantiate()
		bolt.clip_name = "Krin.Iceblade"
		bolt.did_hit = made["strikeSuccess"] == "true"
		field.add_child(bolt)
		bolt.start(
			Vector2(float(made["boltX"]), float(made["boltY"])),
			Vector2(float(made["hitterX"]), float(made["hitterY"]))
		)
		bolt.set_process(false)
		var frames: Array[Dictionary] = capture["frames"]
		assert_gt(frames.size(), 10, "cast %d has its frames" % cast)
		for frame: Dictionary in frames:
			bolt._process(1.0 / BattleScreenClip.fps())
			var at := "cast %d, frame %s" % [cast, frame["n"]]
			var length: float = _trail_art_width * float(frame["innerXscale"]) / 100.0
			var flash_end := (
				Vector2(float(frame["trailX"]), float(frame["trailY"]))
				+ Vector2.from_angle(deg_to_rad(float(frame["trailRot"]))) * length
			)
			assert_almost_eq(_trail_end_in(field, bolt), flash_end, Vector2(0.5, 0.5), "%s: the trail's far end" % at)
			if frame["removed"] == "true":
				assert_true(bolt.is_queued_for_deletion(), "%s: the bolt hit" % at)
			else:
				var flash_bolt := Vector2(float(frame["boltX"]), float(frame["boltY"]))
				assert_almost_eq(bolt.position, flash_bolt, Vector2(0.5, 0.5), "%s: the bolt" % at)


# GridZoomer zooms and pans BATTLESCREEN while a Missile flies. krinBoltMake
# attaches both the bolt and KrinTrail to BATTLESCREEN (frame_42/DoAction_4.as:140
# and 174), so the zoom moves and scales the trail the same as the bolt. The
# same flight with and without the zoom leaves the trail's far end at the same
# point of the field.
func test_the_trail_zooms_and_pans_with_the_battle_screen():
	var from := Vector2(160.9, 297.4)
	var to := Vector2(637.9, 297.4)
	var flights: Array[Dictionary] = []
	for zoomed: bool in [false, true]:
		var screen := BattleScreenClip.new()
		add_child_autofree(screen)
		var field := Node2D.new()
		screen.add_child(field)
		var bolt: Projectile = ProjectileScene.instantiate()
		bolt.clip_name = "Krin.Iceblade"
		field.add_child(bolt)
		bolt.start(from, to)
		bolt.set_process(false)
		if zoomed:
			var missile: Dictionary = BattleScreenClip.motion()["zooms"]["Missile"]
			var center := Vector2(float(missile["center"]["x"]), float(missile["center"]["y"]))
			screen.zoom((to - screen.rest) * float(missile["factor"]) + center, int(missile["hold"]))
		flights.append({"screen": screen, "field": field, "bolt": bolt, "ends": [] as Array[float]})
	for _frame: int in 10:
		for flight: Dictionary in flights:
			flight["screen"].advance_frame()
			flight["bolt"]._process(1.0 / BattleScreenClip.fps())
			flight["ends"].append(snappedf(_trail_end_in(flight["field"], flight["bolt"]).x, 0.01))
	assert_ne(flights[1]["screen"].scale, Vector2.ONE, "the zoomed screen really is zoomed")
	assert_eq(flights[1]["ends"], flights[0]["ends"], "the trail's far end in the field, zoomed and not")
