# Unit tests for the CharacterVisual paper doll - part assembly from the
# extracted MODEL1 rest pose, the dressChar() texture layering, equip-looks
# resolution, and the code-driven animation states.
extends GutTest

const CharacterVisualScene = preload("res://scenes/character_visual.tscn")
const GameItemScript = preload("res://scripts/entities/game_item.gd")
const SWF_FRAME_SECONDS: float = 1.0 / 30.0

var visual: CharacterVisual


func before_each():
	visual = add_child_autofree(CharacterVisualScene.instantiate())


func _animations() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CharacterVisual.ANIMATIONS_FILE))


# The MODEL1 frame the doll's parts show, numbered from 1 like the SWF's, or 0
# when the pose matches no frame.
func _shown_frame() -> int:
	var frames: Array = _animations()["frames"]
	for index in frames.size():
		if _shows_pose(frames[index]):
			return index + 1
	return 0


func _shows_pose(pose: Dictionary) -> bool:
	for part in visual.get_node("Body").get_children():
		var matrix = pose.get(str(part.name))
		if matrix == null:
			if part.visible:
				return false
			continue
		var transform := Transform2D(Vector2(matrix[0], matrix[1]), Vector2(matrix[2], matrix[3]), Vector2(matrix[4], matrix[5]))
		if not part.visible or not part.transform.is_equal_approx(transform):
			return false
	return true


func _sprite_count(part_name: String) -> int:
	var count = 0
	for child in visual._parts[part_name].get_children():
		if child is Sprite2D and not child.is_queued_for_deletion():
			count += 1
	return count


func test_all_15_parts_built_on_stand_frame():
	assert_eq(visual._parts.size(), 15)
	# Animated dolls start on the stand label's first frame (the timeline's
	# own rest pose - chest at 0.45/-16.85 px).
	var chest: Node2D = visual._parts["chest"]
	assert_almost_eq(chest.position.x, 0.45, 0.05, "MODEL1 stand frame 1, twips converted")
	assert_almost_eq(chest.position.y, -16.85, 0.05)
	var hand2: Node2D = visual._parts["hand2"]
	assert_lt(hand2.transform.x.x, 0.0, "mirrored back hand preserved")
	# z-order: weapon2 (depth 7) draws behind chest (depth 21).
	assert_lt(visual._parts["weapon2"].get_index(), visual._parts["chest"].get_index())


func test_dress_layers_skin_equipment_and_hair():
	visual.dress("M", "ONE", "ONE", ["", "ARCTIC", "", "", "", "AK", ""])
	assert_eq(_sprite_count("head"), 2, "skin + hair")
	assert_eq(_sprite_count("chest"), 2, "skin + ARCTIC chest armor")
	assert_eq(_sprite_count("arm1"), 2, "arms take the chest slot's armor")
	assert_eq(_sprite_count("weapon1"), 1, "weapon has no skin layer")
	assert_eq(_sprite_count("weapon2"), 0, "no secondary equipped")
	assert_eq(_sprite_count("foot1"), 1, "bare foot = skin only")


func test_dress_bare_and_female():
	visual.dress("M", "ONE", "", ["", "", "", "", "", "", ""])
	assert_eq(_sprite_count("head"), 1, "no hair key, skin only")
	assert_eq(_sprite_count("weapon1"), 0)
	visual.dress("F", "FEL", "FEL", ["", "", "", "", "", "", ""])
	# Frame-delay: queue_free from the redress hasn't run yet, so count only
	# live sprites (helper already filters queued ones).
	assert_eq(_sprite_count("chest"), 1, "female base skin resolves (F_SCHEST_FEL)")
	# Felicity's hair is baked into her head skin - there is no HAIR_FEL
	# sprite in the extracted assets, so the missing layer is skipped.
	assert_eq(_sprite_count("head"), 1, "FEL hair baked into F_SHEAD_FEL")
	visual.dress("F", "FEL", "TWO", ["", "", "", "", "", "", ""])
	assert_eq(_sprite_count("head"), 2, "separate hair sprite layers when one exists")


func test_resolve_equip_looks():
	var save = PlayerSave.new_game("Test", 0)
	var unit = CombatUnit.from_player_save(save)
	var item = Resource.new()
	item.set_script(GameItemScript)
	item.id = 42
	item.looks = "ARCTIC"
	var items_by_id = {42: item}
	unit.equipment_ids = [42, 0, 0, 0, 0, 0, 0]
	assert_eq(
		CharacterVisual.resolve_equip_looks(unit, items_by_id),
		["ARCTIC", "", "", "", "", "", ""]
	)
	unit.skin_setter = "ZPCI"
	unit.equipment_ids = [0, 0, 0, 0, 0, 42, 0]
	assert_eq(
		CharacterVisual.resolve_equip_looks(unit, items_by_id),
		["ZPCI", "ZPCI", "ZPCI", "ZPCI", "ZPCI", "ARCTIC", ""],
		"skinSetter uniforms slots 0-4, weapon still from items"
	)


# A doll with no art standing at `spot`. It has no width, so a swing it makes
# stops short of its target by the target's half-width alone.
func _bare_doll(spot: Vector2) -> CharacterVisual:
	var doll: CharacterVisual = add_child_autofree(CharacterVisualScene.instantiate())
	doll.position = spot
	return doll


# Each frame krinMelee moves the caster a sixth of the way from its home to the
# target's center, times min(1, 1.5 - 1.45 * relX / slowPoint), and the dash
# ends on the first frame that has covered slowPoint, the distance less both
# half-widths (frame_42/DoAction_4.as:46-56 and 97-133). So the dash takes 13
# frames with no half-widths at any distance, and fewer the more of the
# distance the half-widths take up (DECODED_ALGORITHMS.md, "krinMelee").
func test_the_dash_reaches_its_end_point_in_the_original_number_of_frames():
	var cases: Array = [
		{"distance": 300.0, "half_widths": 0.0, "frames": 13},
		{"distance": 477.0, "half_widths": 0.0, "frames": 13},
		{"distance": 300.0, "half_widths": 60.0, "frames": 11},
		{"distance": 150.0, "half_widths": 100.0, "frames": 4},
	]
	for case in cases:
		var caster: CharacterVisual = _bare_doll(Vector2(100, 100))
		assert_eq(caster.get_bounds().size.x, 0.0, "sanity: a doll with no art has no width")
		var target: Vector2 = Vector2(100.0 + case["distance"], 100.0)
		caster.play_melee(func(): return target, case["half_widths"])
		var reached: int = 0
		for frame in range(1, 31):
			caster._process(SWF_FRAME_SECONDS)
			if caster.position.x >= target.x - case["half_widths"]:
				reached = frame
				break
		assert_eq(reached, case["frames"], "%d px with %d px of half-widths" % [case["distance"], case["half_widths"]])


# krinMelee reads the target's x and both widths once, when the swing starts,
# and ends the dash on the first frame that gets the caster to that end point
# (frame_42/DoAction_4.as:46-56 and 124-133). The next action can dispatch
# while its target is still running home, so the caster stops at the edge of
# where the target stood when the swing started, wherever it has run since.
func test_a_dash_at_a_target_still_in_its_runback_ends_at_its_edge_where_it_stood_then():
	var caster: CharacterVisual = _bare_doll(Vector2(160, 100))
	var target: CharacterVisual = _bare_doll(Vector2(640, 100))
	watch_signals(target)
	target.play_melee(func(): return caster.position, 0.0)
	var runback_frames: int = 0
	for frame in 120:
		var before: float = target.position.x
		target._process(SWF_FRAME_SECONDS)
		if get_signal_emit_count(target, "attack_connected") > 0 and target.position.x > before:
			runback_frames += 1
			if runback_frames == 2:
				break
	assert_between(target.position.x, 200.0, 600.0, "sanity: the target is partway home")

	var edge: float = target.position.x - 30.0
	caster.play_melee(func(): return target.position, 30.0)
	var dash: Array = [caster.position.x]
	for frame in 60:
		target._process(SWF_FRAME_SECONDS)
		caster._process(SWF_FRAME_SECONDS)
		if caster.position.x == dash[-1]:
			break
		dash.append(caster.position.x)
	assert_gt(target.position.x - 30.0, dash[-1] + 100.0, "sanity: the target has run on since")
	assert_gte(dash[-1], edge, "the dash reaches the target's edge where it stood when the swing started")
	assert_lt(dash[-2], edge, "and ends on the frame it gets there")


# krinMelee works each frame's step out from where the target stands that
# frame (frame_42/DoAction_4.as:112-116), so a caster gains on a target that
# runs on, and gets to the same end point sooner.
func test_the_dash_chases_a_target_that_runs_on():
	var running: Array = [Vector2(400, 100)]
	var chaser: CharacterVisual = _bare_doll(Vector2(100, 100))
	chaser.play_melee(func(): return running[0], 0.0)
	var still: CharacterVisual = _bare_doll(Vector2(100, 100))
	still.play_melee(func(): return Vector2(400, 100), 0.0)
	var reached: Dictionary = {}
	for frame in range(1, 31):
		running[0] += Vector2(20, 0)
		chaser._process(SWF_FRAME_SECONDS)
		still._process(SWF_FRAME_SECONDS)
		if chaser.position.x >= 400.0 and not reached.has("chaser"):
			reached["chaser"] = frame
		if still.position.x >= 400.0 and not reached.has("still"):
			reached["still"] = frame
	assert_eq(reached.get("still"), 13, "sanity: the dash at a target that stands still")
	assert_lt(reached.get("chaser", 99), 13, "the dash after a target that runs on")


# krinMelee moves y by the same share of the way to the target's center as x,
# with no offset of its own (frame_42/DoAction_4.as:112-116), so the caster
# runs along the line from its home to the target's center.
func test_the_dash_runs_along_the_line_to_the_targets_center():
	var caster: CharacterVisual = _bare_doll(Vector2(100, 100))
	caster.play_melee(func(): return Vector2(400, 200), 60.0)
	for frame in 11:
		caster._process(SWF_FRAME_SECONDS)
		var travelled: Vector2 = caster.position - Vector2(100, 100)
		assert_almost_eq(travelled.y * 3.0, travelled.x, 0.001, "frame %d" % (frame + 1))
	assert_gt(caster.position.y, 170.0, "sanity: the caster got most of the way down")


# krinMelee: the dash with no half-widths arrives 13 frames in, Impact comes
# 15 frames after arrival, and the Runback starts 14 frames after Impact and
# eases home.
func test_melee_runs_strikes_and_returns_home():
	watch_signals(visual)
	visual.position = Vector2(100, 100)
	visual.play_melee(func(): return Vector2(180, 100), 0.0)
	for frame in 6:
		visual._process(SWF_FRAME_SECONDS)
	assert_gt(visual.position.x, 130.0, "mid-dash: moved toward the target")
	for frame in 7:
		visual._process(SWF_FRAME_SECONDS)
	assert_almost_eq(visual.position.x, 180.0, 1.0, "arrived at the target")
	for frame in 120:
		visual._process(SWF_FRAME_SECONDS)
	assert_signal_emitted(visual, "attack_connected")
	assert_signal_emitted(visual, "melee_finished")
	assert_eq(visual._state, CharacterVisual.State.IDLE, "sequence recovers to idle")
	assert_eq(visual.position, Vector2(100, 100), "back home after runback")


# krinMelee's end counter counts the frame that raised the impact flag, so the
# Runback starts 14 frames after Impact, not 15 (frame_42/DoAction_4.as:73-95).
# krinMelee moves the fighter's clip whatever the doll plays (67-135), so a hit
# during the Runback plays over a doll that keeps sliding home.
func test_a_caster_hit_in_its_runback_keeps_sliding_home_while_it_plays_hit():
	watch_signals(visual)
	visual.position = Vector2(100, 100)
	visual.play_melee(func(): return Vector2(180, 100), 0.0)
	for frame in 120:
		if get_signal_emit_count(visual, "attack_connected") > 0:
			break
		visual._process(SWF_FRAME_SECONDS)
	var strike_spot: Vector2 = visual.position
	assert_almost_eq(strike_spot, Vector2(180, 100), Vector2(0.1, 0.0), "sanity: the blow lands at the target")
	for frame in 13:
		visual._process(SWF_FRAME_SECONDS)
	assert_eq(visual.position, strike_spot, "13 frames after Impact the caster still stands where it struck")
	visual._process(SWF_FRAME_SECONDS)
	assert_lt(visual.position.x, strike_spot.x, "and the 14th frame starts its Runback")

	visual.set_state(CharacterVisual.State.HIT)
	var hit: Dictionary = _animations()["labels"]["hit"]
	for frame in 4:
		var before: Vector2 = visual.position
		visual._process(SWF_FRAME_SECONDS)
		assert_lt(visual.position.x, before.x, "a hit doesn't stop the slide home")
		assert_between(_shown_frame(), int(hit["start"]), int(hit["end"]), "while the doll plays hit")
	for frame in 120:
		visual._process(SWF_FRAME_SECONDS)
	assert_eq(visual.position, Vector2(100, 100), "and the doll gets home")


# The next action can dispatch before a Runback ends, so a fighter can swing
# again on its way home. The original takes the clip's position then as the
# fighter's new home (frame_42/DoAction_4.as:38-39), and ADR 0005 counts that
# as an Original bug.
func test_a_swing_that_starts_during_the_runback_still_ends_at_home():
	watch_signals(visual)
	visual.position = Vector2(100, 100)
	visual.play_melee(func(): return Vector2(180, 100), 0.0)
	for frame in 120:
		visual._process(SWF_FRAME_SECONDS)
		if get_signal_emit_count(visual, "attack_connected") > 0 and visual.position.x < 160.0:
			break
	var partway: Vector2 = visual.position
	assert_between(partway.x, 100.5, 160.0, "sanity: the doll is partway home")

	visual.play_melee(func(): return Vector2(180, 100), 0.0)
	visual._process(SWF_FRAME_SECONDS)
	assert_gte(visual.position.x, partway.x, "the new swing runs on from where the doll stands")
	for frame in 240:
		visual._process(SWF_FRAME_SECONDS)
	assert_eq(visual.position, Vector2(100, 100), "and its Runback ends at the doll's own home")


# krinMelee starts every swing with relX at 0 and works its dash out from where
# the fighter stands (frame_42/DoAction_4.as:38-57 and 97-133). So a swing that
# starts during the Runback dashes frame for frame the way a swing from that
# spot does, and only its Runback differs, because it ends at the doll's home.
func test_a_swing_that_starts_during_the_runback_dashes_as_one_from_that_spot():
	var target: Vector2 = Vector2(400, 100)
	var doll: CharacterVisual = _bare_doll(Vector2(100, 100))
	watch_signals(doll)
	doll.play_melee(func(): return target, 0.0)
	for frame in 120:
		doll._process(SWF_FRAME_SECONDS)
		if get_signal_emit_count(doll, "attack_connected") > 0 and doll.position.x < 200.0:
			break
	var spot: Vector2 = doll.position
	assert_between(spot.x, 100.5, 200.0, "sanity: the doll is partway home")

	var fresh: CharacterVisual = _bare_doll(spot)
	doll.play_melee(func(): return target, 0.0)
	fresh.play_melee(func(): return target, 0.0)
	var dashes: Array = [[], []]
	for frame in 20:
		doll._process(SWF_FRAME_SECONDS)
		fresh._process(SWF_FRAME_SECONDS)
		dashes[0].append(doll.position)
		dashes[1].append(fresh.position)
	assert_eq(dashes[0], dashes[1], "the dash and its arrival match a swing from that spot")


func test_a_swing_plays_its_attack_label_and_an_unknown_label_plays_attack():
	watch_signals(visual)
	# Attack_Upper is a 30-frame swing (1s) - the overhead Destroy strike.
	visual.play_melee(func(): return Vector2(80, 0), 0.0, "Attack_Upper")
	assert_eq(visual._attack_label, "Attack_Upper")
	for i in 60:
		visual._process(0.05)
	assert_signal_emitted(visual, "attack_connected")
	assert_eq(visual._state, CharacterVisual.State.IDLE)
	# Unknown labels fall back to the base swing.
	visual.play_melee(func(): return Vector2(80, 0), 0.0, "Krin.Firebolt")
	assert_eq(visual._attack_label, "Attack")


func test_cast_and_hit_recover_to_idle():
	visual.set_state(CharacterVisual.State.CAST)
	for i in 40:
		visual._process(0.05)
	assert_eq(visual._state, CharacterVisual.State.IDLE)
	visual.set_state(CharacterVisual.State.HIT)
	for i in 20:
		visual._process(0.05)
	assert_eq(visual._state, CharacterVisual.State.IDLE)


# The alpha each part is drawn at: its own modulate times every ancestor's, up
# to the doll.
func _drawn_alphas() -> Array:
	var alphas: Array = []
	for part in visual._parts.values():
		var alpha: float = 1.0
		var node: Node = part
		while node != visual.get_parent():
			alpha *= (node as CanvasItem).modulate.a
			node = node.get_parent()
		alphas.append(alpha)
	return alphas


# MODEL1's dead label is frames 313 to 371. The fall plays at full alpha, and
# the label's own colour transforms then fade every part, from 233/256 on frame
# 361 to 23/256 on frame 370 (DefineSprite 166).
func test_the_death_falls_at_full_alpha_then_fades_on_its_own_timeline():
	var expected: Array = []
	expected.resize(48)
	expected.fill(256)
	expected.append_array([233, 209, 186, 163, 140, 116, 93, 70, 47, 23])
	var mismatches: Array = []
	visual.set_state(CharacterVisual.State.DEAD)
	for frame in expected.size():
		if frame > 0:
			visual._process(1.0 / 30.0)
		for alpha in _drawn_alphas():
			if absf(alpha - expected[frame] / 256.0) > 0.0001:
				mismatches.append("frame %d drew alpha %.4f" % [313 + frame, alpha])
				break
	assert_eq(mismatches, [], "every part on every frame of the fall and the fade")


# The script on frame 371 removes the doll before Flash draws that frame
# (DefineSprite_166_MODEL1/frame_371/DoAction.as).
func test_the_doll_is_not_drawn_once_dead_reaches_its_last_frame():
	visual.set_state(CharacterVisual.State.DEAD)
	for frame in 57:
		visual._process(1.0 / 30.0)
	assert_true(visual.is_visible_in_tree(), "frame 370 is drawn")
	visual._process(1.0 / 30.0)
	assert_false(visual.is_visible_in_tree(), "frame 371 is not")


func test_stun_holds_until_cleared():
	visual.set_state(CharacterVisual.State.STUN)
	for i in 60:
		visual._process(0.05)
	assert_eq(visual._state, CharacterVisual.State.STUN)
	visual.set_state(CharacterVisual.State.IDLE)
	assert_true(visual.is_idle())


func test_matrixless_placement_keeps_its_depths_matrix():
	# Frame 123 of MODEL1 (sprite 166) moves foot2 at depth 9 with a blur filter
	# and no matrix, so foot2 keeps frame 122's matrix: scale 0.8 at (216, 654)
	# twips. The extractor once took weapon2's matrix from the next placement.
	var file: FileAccess = FileAccess.open(CharacterVisual.ANIMATIONS_FILE, FileAccess.READ)
	assert_not_null(file, CharacterVisual.ANIMATIONS_FILE)
	if file == null:
		return
	var frames: Array = JSON.parse_string(file.get_as_text())["frames"]
	assert_eq(frames[121]["foot2"], [0.8, 0.0, 0.0, 0.8, 10.8, 32.7], "frame 122")
	assert_eq(frames[122]["foot2"], [0.8, 0.0, 0.0, 0.8, 10.8, 32.7], "frame 123")
