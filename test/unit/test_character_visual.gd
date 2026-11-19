# Unit tests for the CharacterVisual paper doll - part assembly from the
# extracted rest pose of each model, the pieces each model places with no name,
# the dressChar() texture layering, equip-looks resolution, and the code-driven
# animation states.
extends GutTest

const CharacterVisualScene = preload("res://scenes/character_visual.tscn")
const GameItemScript = preload("res://scripts/entities/game_item.gd")
const SWF_FRAME_SECONDS: float = 1.0 / 30.0

var visual: CharacterVisual


func before_each():
	visual = add_child_autofree(CharacterVisualScene.instantiate())


func _animations(model: String = "MODEL1") -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CharacterVisual.animations_file(model)))


func _cues_of(model: String = "MODEL1") -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CharacterVisual.sound_cues_file(model)))


# Returns the frame of `model` that the doll's parts show, numbered from 1 like
# the SWF's, or 0 when the pose matches no frame.
func _shown_frame(model: String = "MODEL1") -> int:
	var frames: Array = _animations(model)["frames"]
	for index in frames.size():
		if _shows_pose(frames[index]):
			return index + 1
	return 0


func _shows_pose(pose: Dictionary) -> bool:
	for part in visual._parts.values():
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


# Returns a doll with no art standing at `spot`. It has no width, so a swing it
# makes stops short of its target by the target's half-width alone.
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
	assert_almost_eq(strike_spot, Vector2(180, 100), Vector2(0.1, 0.0), "sanity: Impact comes at the target")
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


func test_a_swing_plays_its_attack_label_and_an_unknown_label_plays_none():
	watch_signals(visual)
	# Attack_Upper is a 30-frame swing (1s) - the overhead Destroy strike.
	visual.play_melee(func(): return Vector2(80, 0), 0.0, "Attack_Upper")
	assert_eq(visual._attack_label, "Attack_Upper")
	for i in 60:
		visual._process(0.05)
	assert_signal_emitted(visual, "attack_connected")
	assert_eq(visual._state, CharacterVisual.State.IDLE)
	# Flash ignores a goto to a label the clip does not have.
	visual.play_melee(func(): return Vector2(80, 0), 0.0, "Krin.Firebolt")
	assert_eq(visual._attack_label, "")


# Runs one swing through its Runback a frame at a time and returns the MODEL1
# frame (numbered from 1, like the SWF's) on which each cue played, as
# [frame, cue] pairs.
func _swing_cues(label: String) -> Array:
	var cues: Array = []
	visual.sound_cue.connect(func(cue): cues.append([int(visual._playhead) + 1, cue]))
	visual.play_melee(func(): return Vector2(80, 0), 0.0, label)
	for frame in 120:
		visual._process(SWF_FRAME_SECONDS)
	return cues


# Returns the one MODEL1 frame inside `label` that model1_sound_cues.json lists,
# read from the same file and labels the game reads.
func _cue_frame_in(label: String) -> int:
	var segment: Dictionary = _animations()["labels"][label]
	var cues: Dictionary = _cues_of()
	var inside: Array = []
	for frame in cues:
		if int(frame) >= segment["start"] and int(frame) <= segment["end"]:
			inside.append(int(frame))
	assert_eq(inside.size(), 1, "%s holds one cue frame" % label)
	return inside[0] if not inside.is_empty() else -1


# DefineSprite_166_MODEL1 frames 88, 118 and 146 each call
# addSound("Effects", "sfx_swing"), one inside each of the three swing labels.
func test_each_swing_plays_sfx_swing_once_on_its_cue_frame():
	for label in ["Attack_Upper", "Attack_Stab", "Attack"]:
		assert_eq(_swing_cues(label), [[_cue_frame_in(label), "sfx_swing"]], label)


# The original clip's frame scripts only run while its playhead goes through the
# frame, so a doll that stops swinging before the cue frame stays quiet.
func test_a_caster_hit_before_the_cue_frame_plays_no_swing_sound():
	var cues: Array = []
	visual.sound_cue.connect(func(cue): cues.append(cue))
	visual.play_melee(func(): return Vector2(80, 0), 0.0, "Attack_Upper")
	for frame in 14:
		visual._process(SWF_FRAME_SECONDS)
	visual.set_state(CharacterVisual.State.HIT)
	for frame in 120:
		visual._process(SWF_FRAME_SECONDS)
	assert_eq(cues, [])


# A cue outside the strike would never play, because only the strike steps the
# playhead through frames that can hold one.
func test_every_sound_cue_frame_lies_inside_a_swing_label():
	var labels: Dictionary = _animations()["labels"]
	var swings: Array = ["Attack_Upper", "Attack_Stab", "Attack", "attack2"]
	var cues: Dictionary = _cues_of()
	assert_false(cues.is_empty(), "the file lists cues")
	for frame in cues:
		var inside := false
		for swing in swings:
			inside = inside or (int(frame) >= labels[swing]["start"] and int(frame) <= labels[swing]["end"])
		assert_true(inside, "frame %s lies inside a swing label" % frame)


func test_a_doll_that_does_not_swing_plays_no_sound():
	var cues: Array = []
	visual.sound_cue.connect(func(cue): cues.append(cue))
	visual.set_state(CharacterVisual.State.CAST)
	for frame in 60:
		visual._process(SWF_FRAME_SECONDS)
	visual.set_state(CharacterVisual.State.HIT)
	for frame in 60:
		visual._process(SWF_FRAME_SECONDS)
	assert_eq(cues, [])


func test_cast_and_hit_recover_to_idle():
	visual.set_state(CharacterVisual.State.CAST)
	for i in 40:
		visual._process(0.05)
	assert_eq(visual._state, CharacterVisual.State.IDLE)
	visual.set_state(CharacterVisual.State.HIT)
	for i in 20:
		visual._process(0.05)
	assert_eq(visual._state, CharacterVisual.State.IDLE)


# Returns how many steps of `step_seconds` the doll takes to leave `state` for
# idle, which it does on the step that ends the state's label.
func _steps_until_idle(state: CharacterVisual.State, step_seconds: float) -> int:
	visual.set_state(state)
	for step in range(1, 1000):
		visual._process(step_seconds)
		if visual._state == CharacterVisual.State.IDLE:
			return step
	return 0


func _label_length(label: String) -> int:
	var segment: Dictionary = _animations()["labels"][label]
	return int(segment["end"]) - int(segment["start"]) + 1


func test_hit_ends_on_the_frame_its_label_length_gives():
	assert_eq(_steps_until_idle(CharacterVisual.State.HIT, SWF_FRAME_SECONDS), _label_length("hit"))


func test_cast_ends_on_the_frame_its_label_length_gives():
	assert_eq(_steps_until_idle(CharacterVisual.State.CAST, SWF_FRAME_SECONDS), _label_length("cast"))


func test_hit_and_cast_end_on_the_same_frame_at_two_steps_a_frame():
	var half_frame: float = SWF_FRAME_SECONDS / 2.0
	assert_eq(_steps_until_idle(CharacterVisual.State.HIT, half_frame), 2 * _label_length("hit"), "hit")
	assert_eq(_steps_until_idle(CharacterVisual.State.CAST, half_frame), 2 * _label_length("cast"), "cast")


func test_the_idle_label_shows_the_same_frame_one_loop_later():
	visual.set_state(CharacterVisual.State.IDLE)
	var stand: Dictionary = _animations()["labels"]["stand"]
	for step in 10:
		visual._process(SWF_FRAME_SECONDS)
	var frame_before_the_loop: int = _shown_frame()
	# The first and last frames of stand hold the same pose, so only a frame
	# between them can tell a loop from a label that stopped at its end.
	assert_ne(frame_before_the_loop, int(stand["start"]), "sanity: a pose the label's ends do not hold")
	for step in _label_length("stand"):
		visual._process(SWF_FRAME_SECONDS)
	assert_eq(_shown_frame(), frame_before_the_loop)


# Returns the alpha each part is drawn at, which is its own modulate times every
# ancestor's, up to the doll.
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


func test_stun_flows_into_its_loop_and_the_wake_up_ends_in_idle():
	visual.set_state(CharacterVisual.State.STUN)
	for step in _label_length("stun") - 1:
		visual._process(SWF_FRAME_SECONDS)
	assert_eq(visual._label, "stun", "on the last frame of stun")
	visual._process(SWF_FRAME_SECONDS)
	assert_eq(visual._label, "stun2", "one step later")
	visual.exit_stun()
	for step in _label_length("outofstun") - 1:
		visual._process(SWF_FRAME_SECONDS)
	assert_eq(visual._state, CharacterVisual.State.STUN, "on the last frame of outofstun")
	visual._process(SWF_FRAME_SECONDS)
	assert_eq(visual._state, CharacterVisual.State.IDLE, "one step later")


func test_matrixless_placement_keeps_its_depths_matrix():
	# Frame 123 of MODEL1 (sprite 166) moves foot2 at depth 9 with a blur filter
	# and no matrix, so foot2 keeps frame 122's matrix: scale 0.8 at (216, 654)
	# twips. The extractor once took weapon2's matrix from the next placement.
	var file: FileAccess = FileAccess.open(CharacterVisual.animations_file("MODEL1"), FileAccess.READ)
	assert_not_null(file, CharacterVisual.animations_file("MODEL1"))
	if file == null:
		return
	var frames: Array = JSON.parse_string(file.get_as_text())["frames"]
	assert_eq(frames[121]["foot2"], [0.8, 0.0, 0.0, 0.8, 10.8, 32.7], "frame 122")
	assert_eq(frames[122]["foot2"], [0.8, 0.0, 0.0, 0.8, 10.8, 32.7], "frame 123")


# --- the Ground shadow (extract_doll_shadow) ----------------------------------

func _shadow_layout() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://resources/sprites/doll_shadow.json"))


# Where the original places its clip: the model's matrix applied to the clip's
# rect, in the doll's own space.
func _expected_shadow_rect(model: String) -> Rect2:
	var layout: Dictionary = _shadow_layout()
	var m: Array = layout["models"][model]
	var rect: Dictionary = layout["rect"]
	var placed := Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5]))
	return placed * Rect2(rect["x"], rect["y"], rect["w"], rect["h"])


func _shadow_rect(shadow: Sprite2D) -> Rect2:
	return shadow.transform * shadow.get_rect()


func test_a_doll_has_no_shadow_until_it_is_asked_for_one():
	assert_null(visual.get_node_or_null("Body/Shadow"), "a menu mannequin draws none")


func test_the_shadow_lands_where_the_models_matrix_puts_it():
	for model in _shadow_layout()["models"]:
		visual.show_shadow(model)
		var shadow: Sprite2D = visual.get_node("Body/Shadow")
		var got: Rect2 = _shadow_rect(shadow)
		var want: Rect2 = _expected_shadow_rect(model)
		assert_true(got.position.is_equal_approx(want.position), "%s position %s, want %s" % [model, got.position, want.position])
		assert_true(got.size.is_equal_approx(want.size), "%s size %s, want %s" % [model, got.size, want.size])


func test_the_shadow_draws_under_every_part():
	visual.show_shadow("MODEL1")
	var body: Node = visual.get_node("Body")
	assert_eq(body.get_child(0).name, &"Shadow", "depth 1 of the model, below its parts")
	assert_eq(body.get_child_count(), 16, "the 15 parts and the shadow")


func test_a_model_with_no_placement_gets_no_shadow():
	visual.show_shadow("MODEL3")
	assert_null(visual.get_node_or_null("Body/Shadow"))


# The shadow follows the clip's own matrix on every frame, so this test starts
# each model's clip, as dressChar does.
func test_asking_again_replaces_the_shadow():
	visual.start_clip("MODEL1")
	visual.start_clip("MODEL2")
	await get_tree().process_frame
	var shadows: int = 0
	for child in visual.get_node("Body").get_children():
		if str(child.name).begins_with("Shadow"):
			shadows += 1
	assert_eq(shadows, 1)
	var got: Rect2 = _shadow_rect(visual.get_node("Body/Shadow"))
	assert_true(got.size.is_equal_approx(_expected_shadow_rect("MODEL2").size))


# The shadow goes with the doll. The script on MODEL1's frame 360 hides
# `_parent.shadower`, which the rig does not have, so the shadow lasts until
# frame 371 removes the whole doll (extract_doll_shadow's header).
func test_the_shadow_stays_through_the_fade_and_goes_with_the_doll_on_frame_371():
	visual.show_shadow("MODEL1")
	visual.set_state(CharacterVisual.State.DEAD)
	for frame in 47:
		visual._process(SWF_FRAME_SECONDS)
	assert_true(visual.get_node("Body/Shadow").is_visible_in_tree(), "frame 360, where the original's script runs")
	for frame in 10:
		visual._process(SWF_FRAME_SECONDS)
	assert_true(visual.get_node("Body/Shadow").is_visible_in_tree(), "frame 370")
	visual._process(SWF_FRAME_SECONDS)
	assert_false(visual.get_node("Body/Shadow").is_visible_in_tree(), "frame 371")


# --- the buff look (convert_buff_looks) ---------------------------------------

func _body_shader() -> ShaderMaterial:
	return visual.get_node("Body").material


func _frost() -> Array:
	var looks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://dev/converted_json/buff_looks.json"))
	return looks["filters"]["Frost"]


func test_a_doll_has_no_buff_look_until_it_is_given_one():
	assert_eq(_body_shader().get_shader_parameter("buff_glows"), 0)
	assert_eq(_body_shader().get_shader_parameter("buff_offset"), Vector3.ZERO)


func test_the_color_offsets_reach_the_shader_in_0_to_1():
	visual.show_buff_look([-50, 0, -225], [])
	assert_eq(_body_shader().get_shader_parameter("buff_offset"), Vector3(-50.0, 0.0, -225.0) / 255.0)


func test_each_glow_reaches_the_shader_with_its_blur_strength_and_kind():
	var frost: Array = _frost()
	visual.show_buff_look([0, 0, 0], frost)
	var shader: ShaderMaterial = _body_shader()
	assert_eq(shader.get_shader_parameter("buff_glows"), 2)
	assert_eq(shader.get_shader_parameter("buff_color_a"), Color.html(frost[0]["color"]))
	assert_eq(shader.get_shader_parameter("buff_params_a"), Vector4(frost[0]["blur_x"], frost[0]["strength"], 1.0, 1.0), "an inner glow with a knockout")
	assert_eq(shader.get_shader_parameter("buff_color_b"), Color.html(frost[1]["color"]))
	assert_eq(shader.get_shader_parameter("buff_params_b"), Vector4(frost[1]["blur_x"], frost[1]["strength"], 0.0, 0.0), "an outer glow")


func test_the_body_is_sized_for_the_outer_glows_reach_and_the_widest_blur():
	var frost: Array = _frost()
	visual.show_buff_look([0, 0, 0], frost)
	var body: CanvasGroup = visual.get_node("Body")
	var stage_scale: float = visual.get_viewport().get_final_transform().get_scale().x
	assert_almost_eq(body.fit_margin, (frost[1]["blur_x"] / 2.0 + 1.0) * stage_scale, 0.0001, "half the outer glow's blur and 1 px")
	assert_almost_eq(body.clear_margin, frost[1]["blur_x"] / 2.0 * stage_scale, 0.0001, "half the widest blur")


func test_empty_arguments_give_the_doll_its_plain_look_back():
	visual.show_buff_look([-50, 0, -225], _frost())
	visual.show_buff_look([], [])
	assert_eq(_body_shader().get_shader_parameter("buff_glows"), 0)
	assert_eq(_body_shader().get_shader_parameter("buff_offset"), Vector3.ZERO)
	assert_eq(visual.get_node("Body").fit_margin, 0.0)


func test_a_result_flash_keeps_the_buff_look_for_when_it_ends():
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/battle/result_flash.json"))
	visual.show_buff_look([-50, 0, -225], _frost())
	visual.show_result_flash(Color.WHITE, layout["white_glow"], layout["color_glow"])
	assert_eq(_body_shader().get_shader_parameter("buff_glows"), 2, "the shader still holds it, and skips it while the flash is on")
	visual.hide_result_flash()
	var frost: Array = _frost()
	var stage_scale: float = visual.get_viewport().get_final_transform().get_scale().x
	assert_almost_eq(visual.get_node("Body").clear_margin, frost[1]["blur_x"] / 2.0 * stage_scale, 0.0001, "the body is sized for the buff look again")


# --- changeForm (convert_buff_looks) ------------------------------------------

func _forms() -> Dictionary:
	var looks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://dev/converted_json/buff_looks.json"))
	return looks["forms"]


# The file names of the layers a part draws, such as "M_SCHEST_ZOMBIE2.png".
func _layer_files(part_name: String) -> Array:
	var files: Array = []
	for child in visual._parts[part_name].get_children():
		if child is Sprite2D and not child.is_queued_for_deletion():
			files.append(child.texture.resource_path.get_file())
	return files


# dressChar passes "" as the armor set of every form, so the parts ask for clips
# such as `M_CHEST_` that neither SWF has, and the doll wears its skin set alone.
func test_a_form_wears_its_skin_set_and_no_armor():
	visual.dress("M", "ONE", "ONE", ["ARCTIC", "ARCTIC", "ARCTIC", "ARCTIC", "ARCTIC", "AK", "AK"])
	visual.wear_form(_forms()["BARON"], ["ARCTIC", "ARCTIC", "ARCTIC", "ARCTIC", "ARCTIC", "AK", "AK"], false)
	assert_eq(_layer_files("chest"), ["M_SCHEST_ZOMBIE2.png"], "the form's skin, and none of the unit's armor")
	assert_eq(_layer_files("head"), ["M_SHEAD_ZOMBIE2.png"], "and no hair")


func test_a_form_takes_its_weapon_and_a_weapon_of_empty_takes_the_units_own():
	var equip: Array = ["", "", "", "", "", "AK", "BATON"]
	visual.wear_form(_forms()["BARON"], equip, false)
	assert_eq(_layer_files("weapon1"), ["M_WEAPON_XADER2.png"], "BARON's own first weapon")
	assert_eq(_layer_files("weapon2"), ["M_WEAPON_BATON.png"], "its second is empty, so the unit's slot 6")


func test_a_form_with_the_weapon_none_wields_nothing():
	visual.wear_form(_forms()["PREDATOR"], ["", "", "", "", "", "AK", "AK"], false)
	assert_eq(_layer_files("weapon1"), [])
	assert_eq(_layer_files("weapon2"), [])


func test_the_standard_form_comes_back_from_the_unit():
	var equip: Array = ["", "ARCTIC", "", "", "", "AK", ""]
	visual.wear_form(_forms()["BARON"], equip, false)
	visual.wear_own_form(["MODEL1", "ONE", "ONE", "M"], equip, false)
	assert_eq(_layer_files("chest"), ["M_SCHEST_ONE.png", "M_CHEST_ARCTIC.png"])
	assert_eq(_layer_files("head").size(), 2, "skin and hair")


# changeForm puts a new clip of the model in the rig, which starts on its first
# frame, and a stunned unit's doll goes straight to the stun loop
# (frame_42/DoAction_10.as:533-536).
func test_a_form_change_starts_the_new_clip_on_stand():
	visual.set_state(CharacterVisual.State.HIT)
	visual.wear_form(_forms()["BARON"], ["", "", "", "", "", "", ""], false)
	assert_eq(visual._state, CharacterVisual.State.IDLE)
	assert_eq(visual._label, "stand")


func test_a_stunned_doll_is_in_the_stun_loop_after_a_form_change():
	visual.set_state(CharacterVisual.State.STUN)
	visual.wear_form(_forms()["BARON"], ["", "", "", "", "", "", ""], true)
	assert_eq(visual._state, CharacterVisual.State.STUN)
	assert_eq(visual._label, "stun2", "the loop, not the entry")
	visual._process(SWF_FRAME_SECONDS)
	assert_eq(visual._label, "stun2", "and it stays there")


func test_a_form_of_another_model_gets_that_models_shadow():
	visual.show_shadow("MODEL1")
	visual.wear_form(_forms()["HOUND"], ["", "", "", "", "", "", ""], false)
	var got: Rect2 = _shadow_rect(visual.get_node("Body/Shadow"))
	assert_true(got.size.is_equal_approx(_expected_shadow_rect("MODEL5").size))


# --- MODEL4, the female clip (extract_model_animations) -----------------------

# Returns the 1-based frame of each label of MODEL4, as model4_animations.json
# gives it, for the label's first frame or, with `last` true, its last.
func _model4_frame(label: String, last: bool = false) -> int:
	return int(_animations("MODEL4")["labels"][label]["end" if last else "start"])


# dressChar attaches the unit's model[0] clip (frame_217/DoAction_2.as:17), and
# a new clip starts on its first frame, MODEL4's rest pose.
func test_a_model4_doll_stands_on_model4s_frame_1_matrices():
	visual.dress_from_model(["MODEL4", "FEL", "", "F"], ["", "", "", "", "", "", ""])
	visual.start_clip("MODEL4")
	var pose: Dictionary = _animations("MODEL4")["frames"][0]
	assert_eq(pose.size(), 15, "sanity: frame 1 places every part")
	for part_name in pose:
		var m: Array = pose[part_name]
		var want := Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5]))
		assert_true(visual._parts[part_name].transform.is_equal_approx(want), part_name)
	assert_false(_shows_pose(_animations("MODEL1")["frames"][0]), "and not MODEL1's")


func test_a_static_model4_doll_holds_model4s_frame_1():
	var doll: CharacterVisual = CharacterVisualScene.instantiate()
	doll.animate = false
	add_child_autofree(doll)
	doll.start_clip("MODEL4")
	var m: Array = _animations("MODEL4")["frames"][0]["chest"]
	assert_true(doll._parts["chest"].transform.is_equal_approx(Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5]))))


# MODEL4 places head at depth 25 over arm1 at 23, and MODEL1 places arm1 at 25
# over head at 23.
func test_each_model_draws_its_parts_in_its_own_depth_order():
	assert_lt(visual._parts["head"].get_index(), visual._parts["arm1"].get_index(), "MODEL1: arm1 in front")
	visual.show_shadow("MODEL4")
	visual.start_clip("MODEL4")
	assert_lt(visual._parts["arm1"].get_index(), visual._parts["head"].get_index(), "MODEL4: head in front")
	assert_eq(visual.get_node("Body").get_child(0).name, &"Shadow", "the shadow stays under every part")
	var depths: Dictionary = _animations("MODEL4")["depths"].duplicate()
	for frame in _pieces_of("MODEL4")["frames"]:
		for depth in frame:
			depths["Piece%s" % depth] = int(depth)
	var order: Array = depths.keys()
	order.sort_custom(func(a, b): return depths[a] < depths[b])
	var drawn: Array = []
	for child in visual.get_node("Body").get_children():
		if child.name != &"Shadow":
			drawn.append(str(child.name))
	assert_eq(drawn, order)


func test_a_model4_doll_plays_each_state_label_on_model4s_frames():
	visual.start_clip("MODEL4")
	assert_eq(_shown_frame("MODEL4"), _model4_frame("stand"), "stand")
	var one_shots: Dictionary = {"cast": CharacterVisual.State.CAST, "hit": CharacterVisual.State.HIT, "stun": CharacterVisual.State.STUN}
	for label in one_shots:
		visual.set_state(one_shots[label])
		assert_true(_shows_pose(_animations("MODEL4")["frames"][_model4_frame(label) - 1]), "%s starts on frame %d" % [label, _model4_frame(label)])
		for step in _model4_frame(label, true) - _model4_frame(label):
			visual._process(SWF_FRAME_SECONDS)
		assert_true(_shows_pose(_animations("MODEL4")["frames"][_model4_frame(label, true) - 1]), "%s ends on frame %d" % [label, _model4_frame(label, true)])
	visual._process(SWF_FRAME_SECONDS)
	assert_eq(visual._label, "stun2", "stun flows into stun2")
	assert_true(_shows_pose(_animations("MODEL4")["frames"][_model4_frame("stun2") - 1]), "stun2 starts on its own frame")
	visual.exit_stun()
	assert_true(_shows_pose(_animations("MODEL4")["frames"][_model4_frame("outofstun") - 1]), "outofstun starts on its own frame")


# MODEL4's dead label is frames 248 to 306, and the script on frame 306 removes
# the doll (DefineSprite_2668_MODEL4/frame_306/DoAction.as).
func test_a_model4_doll_dies_on_model4s_dead_label():
	visual.start_clip("MODEL4")
	visual.set_state(CharacterVisual.State.DEAD)
	assert_true(_shows_pose(_animations("MODEL4")["frames"][_model4_frame("dead") - 1]), "frame 248")
	var length: int = _model4_frame("dead", true) - _model4_frame("dead")
	for frame in length - 1:
		visual._process(SWF_FRAME_SECONDS)
	assert_true(visual.is_visible_in_tree(), "frame 305 is drawn")
	visual._process(SWF_FRAME_SECONDS)
	assert_false(visual.is_visible_in_tree(), "frame 306 is not")


# Returns the 1-based MODEL4 frames that a swing shows, one per SWF frame, until
# the doll is idle again.
func _model4_swing_frames(label: String) -> Array:
	visual.start_clip("MODEL4")
	visual.play_melee(func(): return Vector2(80, 0), 0.0, label)
	var shown: Array = [int(visual._playhead) + 1]
	for frame in 120:
		visual._process(SWF_FRAME_SECONDS)
		if visual.is_idle():
			break
		shown.append(int(visual._playhead) + 1)
	return shown


# MODEL4 starts Attack, Attack_Upper and Attack_Stab all on frame 78, so every
# swing runs on frames from 46, strikes from 78 through attack2 as soon as the
# dash ends, and runs back on 108 to 123, whose script falls into stand
# (DefineSprite_2668_MODEL4/frame_123).
func test_a_model4_doll_swings_on_model4s_run_strike_and_runback_frames():
	for label in ["Attack", "Attack_Upper", "Attack_Stab"]:
		var shown: Array = _model4_swing_frames(label)
		assert_eq(shown[0], _model4_frame("run"), "%s: the run starts on frame 46" % label)
		var strike: int = shown.find(_model4_frame(label))
		assert_gt(strike, 0, "%s: the strike starts on frame 78" % label)
		assert_between(shown[strike - 1], _model4_frame("run"), _model4_frame("run", true), "%s: straight after a run frame" % label)
		assert_true(shown.has(_model4_frame("runback")), "%s: the runback starts on frame 108" % label)
		assert_eq(shown[-1], _model4_frame("runback", true), "%s: and ends on frame 123" % label)


# DefineSprite_2668_MODEL4/frame_86 is MODEL4's one addSound("Effects",
# "sfx_swing"), inside the swing that all three attack labels share.
func test_a_model4_swing_plays_sfx_swing_on_model4s_cue_frame():
	var want: Array = []
	for frame in _cues_of("MODEL4"):
		for cue in _cues_of("MODEL4")[frame]:
			want.append([int(frame), cue])
	assert_eq(want.size(), 1, "MODEL4's clip has one cue")
	for label in ["Attack", "Attack_Upper", "Attack_Stab"]:
		visual.start_clip("MODEL4")
		var cues: Array = _swing_cues(label)
		assert_eq(cues, want, label)
		for connection in visual.sound_cue.get_connections():
			visual.sound_cue.disconnect(connection["callable"])


# The SWF exports no MODEL3, so a model of that name plays MODEL1's clip.
func test_a_model_with_no_timeline_of_its_own_plays_model1s():
	visual.start_clip("MODEL3")
	assert_eq(visual._model, "MODEL1")
	assert_eq(_shown_frame(), 1)


func test_every_model_with_its_own_clip_has_its_timeline_and_cues():
	for model in CharacterVisual.CLIP_MODELS:
		assert_true(FileAccess.file_exists(CharacterVisual.animations_file(model)), model)
		assert_true(FileAccess.file_exists(CharacterVisual.sound_cues_file(model)), model)


# --- MODEL2 and MODEL5 to MODEL9 (extract_model_animations, extract_model_pieces)

# Returns the 1-based frame of `model`'s `label`, as its animations file gives
# it, for the label's first frame or, with `last` true, its last.
func _frame_of(model: String, label: String, last: bool = false) -> int:
	return int(_animations(model)["labels"][label]["end" if last else "start"])


func _pieces_of(model: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CharacterVisual.pieces_file(model)))


# MODEL5 names 11 of the doll's parts and has no foot2, shoulder, weapon1 or
# weapon2. dressChar still dresses all 15 names, and a name the clip does not
# place draws nothing.
func test_a_model5_doll_stands_on_model5s_frame_1_and_hides_the_parts_it_does_not_place():
	visual.dress_from_model(["MODEL5", "WOLF", "", "M"], ["", "", "", "", "", "", ""])
	visual.start_clip("MODEL5")
	var pose: Dictionary = _animations("MODEL5")["frames"][0]
	assert_eq(pose.size(), 11, "sanity: MODEL5 places 11 parts")
	for part_name in visual._parts:
		var part: Node2D = visual._parts[part_name]
		if not pose.has(part_name):
			assert_false(part.visible, "%s is hidden" % part_name)
			continue
		var m: Array = pose[part_name]
		var want := Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5]))
		assert_true(part.visible and part.transform.is_equal_approx(want), part_name)
	for part_name in ["foot2", "shoulder", "weapon1", "weapon2"]:
		assert_false(visual._parts[part_name].visible, part_name)


# Each model starts every label on its own frame: MODEL5 casts on 124 and dies
# on 144, where MODEL1 casts on 189 and dies on 313.
func test_each_of_model5_to_model8_plays_its_labels_on_its_own_frames():
	for model in ["MODEL5", "MODEL6", "MODEL7", "MODEL8"]:
		visual.start_clip(model)
		assert_eq(visual._frame_index + 1, _frame_of(model, "stand"), "%s stand" % model)
		var one_shots: Dictionary = {"cast": CharacterVisual.State.CAST, "hit": CharacterVisual.State.HIT, "stun": CharacterVisual.State.STUN}
		for label in one_shots:
			visual.set_state(one_shots[label])
			assert_eq(visual._frame_index + 1, _frame_of(model, label), "%s %s starts on its own frame" % [model, label])
			for step in _frame_of(model, label, true) - _frame_of(model, label):
				visual._process(SWF_FRAME_SECONDS)
			assert_true(_shows_pose(_animations(model)["frames"][_frame_of(model, label, true) - 1]), "%s %s ends on its own frame" % [model, label])
		visual._process(SWF_FRAME_SECONDS)
		assert_eq(visual._label, "stun2", "%s stun flows into stun2" % model)
		assert_true(_shows_pose(_animations(model)["frames"][_frame_of(model, "stun2") - 1]), "%s stun2" % model)
		visual.exit_stun()
		assert_true(_shows_pose(_animations(model)["frames"][_frame_of(model, "outofstun") - 1]), "%s outofstun" % model)
		visual.set_state(CharacterVisual.State.DEAD)
		assert_true(_shows_pose(_animations(model)["frames"][_frame_of(model, "dead") - 1]), "%s dead" % model)


# MODEL5 to MODEL8 run on frames 31 to 59, swing from 60 and run back on 92 to
# 111, whose script falls into stand (DefineSprite_2631_MODEL7/frame_111).
func test_each_of_model5_to_model8_swings_on_its_own_run_strike_and_runback_frames():
	for model in ["MODEL5", "MODEL6", "MODEL7", "MODEL8"]:
		visual.start_clip(model)
		visual.play_melee(func(): return Vector2(80, 0), 0.0, "Attack")
		var shown: Array = [int(visual._playhead) + 1]
		for frame in 120:
			visual._process(SWF_FRAME_SECONDS)
			if visual.is_idle():
				break
			shown.append(int(visual._playhead) + 1)
		assert_eq(shown[0], _frame_of(model, "run"), "%s run" % model)
		assert_true(shown.has(_frame_of(model, "Attack")), "%s strike" % model)
		assert_true(shown.has(_frame_of(model, "runback")), "%s runback" % model)
		assert_eq(shown[-1], _frame_of(model, "runback", true), "%s ends the runback" % model)


# MODEL5 plays sfx_swing on its frame 71 and MODEL6 and MODEL7 on their frame
# 69 (DefineSprite_2664_MODEL5/frame_71, DefineSprite_2608_MODEL6/frame_69,
# DefineSprite_2631_MODEL7/frame_69). MODEL8's scripts play no sound.
func test_model5_to_model7_play_sfx_swing_on_their_own_cue_frame_and_model8_plays_none():
	for model in ["MODEL5", "MODEL6", "MODEL7", "MODEL8"]:
		var want: Array = []
		for frame in _cues_of(model):
			for cue in _cues_of(model)[frame]:
				want.append([int(frame), cue])
		assert_eq(want.size(), 0 if model == "MODEL8" else 1, "%s cues" % model)
		visual.start_clip(model)
		assert_eq(_swing_cues("Attack"), want, model)
		for connection in visual.sound_cue.get_connections():
			visual.sound_cue.disconnect(connection["callable"])


# Gregor (MODEL7) swings with Terrify, whose label is Attack_Stab. MODEL7 has no
# such label, so krinMelee's goto does nothing and the doll holds the run's last
# frame, whose script runs stop(), until the Runback. It plays no swing sound.
func test_a_swing_on_a_label_the_model_lacks_holds_the_run_until_the_runback():
	visual.start_clip("MODEL7")
	watch_signals(visual)
	var cues: Array = _swing_cues("Attack_Stab")
	assert_eq(cues, [], "no sfx_swing")
	assert_signal_emitted(visual, "attack_connected", "Impact still lands")
	visual.start_clip("MODEL7")
	visual.play_melee(func(): return Vector2(80, 0), 0.0, "Attack_Stab")
	var held: Array = []
	for frame in 120:
		visual._process(SWF_FRAME_SECONDS)
		if visual._melee_phase == CharacterVisual.MeleePhase.STRIKE:
			held.append(int(visual._playhead) + 1)
		elif not held.is_empty():
			break
	assert_false(held.is_empty(), "sanity: the swing reached its strike")
	assert_eq(held[-1], _frame_of("MODEL7", "run", true), "the strike ends on frame 59")
	for frame in held:
		assert_between(frame, _frame_of("MODEL7", "run"), _frame_of("MODEL7", "run", true), "every strike frame is a run frame")


# MODEL2 has only stand, cast and dead. A hit or a stun sends the orb's clip to
# a label it does not have, so it plays its stand loop on.
func test_a_hit_or_stun_on_a_model_without_that_label_leaves_the_doll_as_it_was():
	visual.start_clip("MODEL2")
	for step in 5:
		visual._process(SWF_FRAME_SECONDS)
	visual.set_state(CharacterVisual.State.HIT)
	assert_eq(visual._state, CharacterVisual.State.IDLE)
	assert_eq(visual._frame_index, 5, "stand plays on")
	visual.enter_stun()
	assert_eq(visual._state, CharacterVisual.State.IDLE)
	visual._process(SWF_FRAME_SECONDS)
	assert_eq(visual._frame_index, 6)


# MODEL8 places two unnamed shapes at depths 9 and 10, between leg3 at 7 and
# chest at 11, and dressChar does not dress them.
func test_model8_draws_its_unnamed_clips_between_its_parts_in_depth_order():
	visual.start_clip("MODEL8")
	var pieces: Dictionary = _pieces_of("MODEL8")
	for depth in ["9", "10"]:
		var sprite: Sprite2D = visual.get_node("Body/Piece%s" % depth)
		assert_true(sprite.visible, depth)
		var rect: Dictionary = pieces["art"][pieces["frames"][0][depth]]
		var got: Rect2 = sprite.transform * sprite.get_rect()
		assert_true(got.is_equal_approx(Rect2(rect["x"], rect["y"], rect["w"], rect["h"])), "depth %s lands on its rect, got %s" % [depth, got])
	var body: Node = visual.get_node("Body")
	assert_lt(visual._parts["leg3"].get_index(), body.get_node("Piece9").get_index())
	assert_lt(body.get_node("Piece9").get_index(), body.get_node("Piece10").get_index())
	assert_lt(body.get_node("Piece10").get_index(), visual._parts["chest"].get_index())


func test_a_new_clip_drops_the_last_models_pieces():
	visual.start_clip("MODEL8")
	visual.start_clip("MODEL1")
	assert_null(visual.get_node_or_null("Body/Piece9"))


# MODEL2 places its orb (DefineSprite 1768, 71 frames) on frame 1 and keeps it,
# so the orb plays on its own clock and the stand label's goto back to frame 1
# (DefineSprite_1795_MODEL2/frame_29) does not restart it.
func test_the_orb_plays_on_its_own_clock_through_the_stand_loop():
	visual.start_clip("MODEL2")
	var pieces: Dictionary = _pieces_of("MODEL2")
	var loop: Array = pieces["clips"][pieces["frames"][0]["3"]["clip"]]["frames"]
	var orb: Sprite2D = visual.get_node("Body/Piece3")
	var stand: int = _frame_of("MODEL2", "stand", true)
	for step in stand + 5:
		visual._process(SWF_FRAME_SECONDS)
	assert_eq(visual._frame_index, 5, "sanity: stand looped back to its frame 6")
	assert_eq(orb.texture.resource_path, CharacterVisual.PIECE_ART % loop[stand + 5], "the orb is on its own frame %d" % (stand + 6))


# MODEL2's dead label tints the orb toward red with colour offsets from frame
# 58 and then fades it.
func test_the_orb_takes_its_frames_colour_transform():
	visual.start_clip("MODEL2")
	visual.set_state(CharacterVisual.State.DEAD)
	var frames: Array = _pieces_of("MODEL2")["frames"]
	var tinted: int = -1
	for index in range(_frame_of("MODEL2", "dead") - 1, frames.size()):
		if frames[index]["3"]["color"][4] > 0.0:
			tinted = index
			break
	assert_gt(tinted, 0, "sanity: a dead frame tints the orb")
	for step in tinted - (_frame_of("MODEL2", "dead") - 1):
		visual._process(SWF_FRAME_SECONDS)
	assert_eq(visual._frame_index, tinted, "sanity: on the tinted frame")
	var c: Array = frames[tinted]["3"]["color"]
	var material: ShaderMaterial = visual.get_node("Body/Piece3").material
	assert_eq(material.get_shader_parameter("offset"), Vector4(c[4], c[5], c[6], c[7]))
	assert_eq(material.get_shader_parameter("multiplier"), Vector4(c[0], c[1], c[2], c[3]))


# MODEL8 moves its shadow on later frames, and the shadow follows.
func test_the_shadow_follows_the_models_matrix_on_every_frame():
	visual.start_clip("MODEL8")
	var shadows: Array = _animations("MODEL8")["shadow"]
	var moved: int = -1
	for index in shadows.size():
		if shadows[index] != null and shadows[index] != shadows[0]:
			moved = index
			break
	assert_gt(moved, 0, "sanity: MODEL8 moves its shadow")
	visual._apply_frame_index(moved)
	var shadow: Sprite2D = visual.get_node("Body/Shadow")
	var m: Array = shadows[moved]
	var placed := Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5]))
	assert_true(shadow.transform.is_equal_approx(placed * shadow.get_meta("art")))


# Flash measures a clip's _width over all it draws, so the bomb, which names no
# part, is as wide as its own art.
func test_a_doll_with_no_parts_measures_its_pieces():
	visual.start_clip("MODEL9")
	var bomb: Sprite2D = visual.get_node("Body/Piece3")
	assert_true(bomb.visible)
	var want: Rect2 = visual.transform * bomb.transform * bomb.get_rect()
	assert_true(visual.get_bounds().is_equal_approx(want), "%s, want %s" % [visual.get_bounds(), want])


# MODEL9's dead label is frames 163 to 192, and the script on frame 192 removes
# the bomb (DefineSprite_2469_MODEL9/frame_192). BOOM1 plays from 163.
func test_the_bomb_dies_on_its_dead_label_and_shows_its_blast():
	visual.start_clip("MODEL9")
	visual.set_state(CharacterVisual.State.DEAD)
	assert_eq(visual._frame_index + 1, _frame_of("MODEL9", "dead"))
	assert_true(visual.get_node("Body/Piece6").visible, "BOOM1 at depth 6")
	for step in _frame_of("MODEL9", "dead", true) - _frame_of("MODEL9", "dead"):
		visual._process(SWF_FRAME_SECONDS)
	assert_false(visual.is_visible_in_tree(), "frame 192 removes the doll")


# MODEL1's cast label places the cast glow (DefineSprite 162) on each of its
# frames. Its part 161 runs setRGB(colortobe) as it loads
# (DefineSprite_162/frame_1/PlaceObject2_161_1), so that part takes the doll's
# colortobe, and the frame's colour transform fades the whole glow.
func test_a_model1_cast_shows_the_cast_glow_in_colortobe_on_its_cast_frames():
	visual.start_clip("MODEL1")
	var pieces: Dictionary = _pieces_of("MODEL1")
	var glow_clip: Dictionary = pieces["clips"]["162"]
	var color := Color(0.2, 1.0, 0.0)
	visual.colortobe = color
	visual.set_state(CharacterVisual.State.CAST)
	var glow: Sprite2D = visual.get_node("Body/Piece33")
	var shown: int = 0
	for index in range(_frame_of("MODEL1", "cast") - 1, _frame_of("MODEL1", "cast", true)):
		assert_eq(visual._frame_index, index, "sanity: on cast frame %d" % (index + 1))
		var entry = pieces["frames"][index].get("33")
		if entry is Dictionary and entry["clip"] == "162":
			shown += 1
			var c: Array = entry["color"]
			var tint: Sprite2D = glow.get_node("Tint")
			assert_true(glow.visible and tint.visible, "frame %d shows the glow" % (index + 1))
			assert_eq(glow.texture.resource_path, CharacterVisual.PIECE_ART % glow_clip["frames"][0])
			assert_eq(tint.texture.resource_path, CharacterVisual.PIECE_ART % glow_clip["tints"][0])
			var want := Vector4(c[0] * color.r + c[4], c[1] * color.g + c[5], c[2] * color.b + c[6], c[7])
			assert_true((tint.material.get_shader_parameter("offset") as Vector4).is_equal_approx(want), "frame %d tints 161 in colortobe" % (index + 1))
			assert_eq(tint.material.get_shader_parameter("multiplier"), Vector4(0.0, 0.0, 0.0, c[3]))
		else:
			assert_false(glow.visible, "frame %d shows no glow" % (index + 1))
		visual._process(SWF_FRAME_SECONDS)
	assert_eq(shown, _frame_of("MODEL1", "cast", true) - _frame_of("MODEL1", "cast") + 1, "every cast frame places the glow")


# MODEL1's stun2 label places the stun mark (DefineSprite 165, 30 frames, no
# stop) on each of its 40 frames, and its last frame's script goes back to its
# first (DefineSprite_166_MODEL1/frame_279). Flash keeps the mark through that
# goto, so the mark loops on its own clock.
func test_a_model1_stun_shows_the_stun_mark_on_its_own_clock_through_the_stun2_loop():
	visual.start_clip("MODEL1")
	var pieces: Dictionary = _pieces_of("MODEL1")
	var mark: Array = pieces["clips"]["165"]["frames"]
	var sprite: Sprite2D = visual.get_node("Body/Piece33")
	visual.enter_stun()
	while visual._label != "stun2":
		assert_false(sprite.visible, "the stun label shows no mark")
		visual._process(SWF_FRAME_SECONDS)
	var stun2: int = _frame_of("MODEL1", "stun2", true) - _frame_of("MODEL1", "stun2") + 1
	for age in stun2 * 2:
		assert_eq(pieces["frames"][visual._frame_index]["33"]["clip"], "165", "sanity: stun2 places the mark")
		assert_true(sprite.visible, "the mark shows %d frames into stun2" % age)
		assert_eq(sprite.texture.resource_path, CharacterVisual.PIECE_ART % mark[age % mark.size()], "the mark is on its own frame %d" % (age % mark.size() + 1))
		visual._process(SWF_FRAME_SECONDS)


# Each MODEL1 swing places its trail on its label (149 on Attack_Upper, 153 on
# Attack_Stab, and 158 on attack2, which Attack flows into). A trail plays its
# 12 frames from where the label places it and holds its empty frame 12, and
# its tinted part takes the colortobe that krinMelee set at the strike.
func test_a_model1_swing_shows_its_trail_on_the_frames_its_label_places_it():
	var pieces: Dictionary = _pieces_of("MODEL1")
	var color := Color(1.0, 0.2, 0.4)
	for case in [["Attack_Upper", "149"], ["Attack_Stab", "153"], ["Attack", "158"]]:
		var clip: Dictionary = pieces["clips"][case[1]]
		visual.start_clip("MODEL1")
		visual.play_melee(func(): return Vector2(80, 0), 0.0, case[0], color)
		var trail: Sprite2D = visual.get_node("Body/Piece33")
		var shown: int = 0
		for step in 200:
			visual._process(SWF_FRAME_SECONDS)
			if visual.is_idle():
				break
			var entry = pieces["frames"][visual._frame_index].get("33")
			if not (entry is Dictionary and entry["clip"] == case[1]):
				assert_false(trail.visible, "%s: no trail on frame %d" % [case[0], visual._frame_index + 1])
				continue
			var age: int = visual._frame_index + 1 - int(entry["since"])
			var art: String = clip["frames"][mini(age, int(clip["hold"]) - 1)]
			if not pieces["art"].has(art):
				assert_null(trail.texture, "%s: the trail's frame %d draws nothing" % [case[0], age + 1])
				continue
			shown += 1
			var tint: Sprite2D = trail.get_node("Tint")
			assert_eq(trail.texture.resource_path, CharacterVisual.PIECE_ART % art, "%s: trail frame %d" % [case[0], age + 1])
			assert_true(tint.visible, "%s: with its tinted part" % case[0])
			assert_true((tint.material.get_shader_parameter("offset") as Vector4).is_equal_approx(Vector4(color.r, color.g, color.b, 0.0)), "%s: in colortobe" % case[0])
		assert_eq(shown, clip["frames"].filter(func(name): return pieces["art"].has(name)).size(), "%s shows every frame of %s that draws" % [case[0], case[1]])


# A slow frame can carry the playhead past the frame that places a clip. Flash
# would have placed the clip on that frame and played it on each frame since, so
# the clip shows the frame it has reached by now, not its frame 1.
func test_a_slow_frame_past_a_trails_placement_shows_the_frame_the_trail_has_reached():
	var pieces: Dictionary = _pieces_of("MODEL1")
	var clip: Dictionary = pieces["clips"]["149"]
	visual.start_clip("MODEL1")
	visual.play_melee(func(): return Vector2(80, 0), 0.0, "Attack_Upper")
	var since: int = -1
	for index in pieces["frames"].size():
		var entry = pieces["frames"][index].get("33")
		if entry is Dictionary and entry["clip"] == "149":
			since = int(entry["since"])
			break
	assert_gt(since, 0, "sanity: Attack_Upper places the trail")
	for step in 200:
		if visual._melee_phase == CharacterVisual.MeleePhase.STRIKE and visual._frame_index + 1 == since - 2:
			break
		visual._process(SWF_FRAME_SECONDS)
	assert_eq(visual._frame_index + 1, since - 2, "sanity: two frames before the trail")
	visual._process(SWF_FRAME_SECONDS * 3.0)
	var age: int = visual._frame_index + 1 - since
	assert_eq(age, 1, "sanity: the slow frame lands one frame past the placement")
	assert_eq(visual.get_node("Body/Piece33").texture.resource_path, CharacterVisual.PIECE_ART % clip["frames"][age])


func test_every_model_with_pieces_names_art_that_exists():
	for model in CharacterVisual.CLIP_MODELS:
		if not FileAccess.file_exists(CharacterVisual.pieces_file(model)):
			continue
		var pieces: Dictionary = _pieces_of(model)
		for art in pieces["art"]:
			assert_true(ResourceLoader.exists(CharacterVisual.PIECE_ART % art), art)


# extract_doll_shadow and extract_model_animations each write a model's frame 1
# shadow matrix. show_shadow reads the first and each frame the second, so they
# must agree or the shadow jumps on the clip's first frame.
func test_the_shadow_layout_and_each_timelines_first_shadow_agree():
	var models: Dictionary = _shadow_layout()["models"]
	for model in CharacterVisual.CLIP_MODELS:
		var first: Array = _animations(model)["shadow"][0]
		var want: Array = models[model]
		for index in 6:
			assert_almost_eq(float(first[index]), float(want[index]), 0.01, "%s matrix entry %d" % [model, index])
