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


func test_melee_runs_strikes_and_returns_home():
	watch_signals(visual)
	visual.position = Vector2(100, 100)
	visual.play_melee(Vector2(80, 0))
	# krinMelee: eased dash arrives ~0.47s in; Impact 15 frames after arrival;
	# the Runback starts 14 frames after Impact and eases home.
	for i in 6:
		visual._process(0.05)
	assert_gt(visual.position.x, 130.0, "mid-dash: moved toward the target")
	for i in 8:
		visual._process(0.05)
	assert_almost_eq(visual.position.x, 180.0, 1.0, "arrived at the target")
	for i in 46:
		visual._process(0.05)
	assert_signal_emitted(visual, "attack_connected")
	assert_signal_emitted(visual, "melee_finished")
	assert_eq(visual._state, CharacterVisual.State.IDLE, "sequence recovers to idle")
	assert_almost_eq(visual.position.x, 100.0, 0.1, "back home after runback")


# krinMelee's end counter counts the frame that raised the impact flag, so the
# Runback starts 14 frames after Impact, not 15 (frame_42/DoAction_4.as:73-95).
# krinMelee moves the fighter's clip whatever the doll plays (67-135), so a hit
# during the Runback plays over a doll that keeps sliding home.
func test_a_caster_hit_in_its_runback_keeps_sliding_home_while_it_plays_hit():
	watch_signals(visual)
	visual.position = Vector2(100, 100)
	visual.play_melee(Vector2(80, 0))
	for frame in 120:
		if get_signal_emit_count(visual, "attack_connected") > 0:
			break
		visual._process(SWF_FRAME_SECONDS)
	var strike_spot: Vector2 = visual.position
	assert_eq(strike_spot, Vector2(180, 100), "sanity: the blow lands at the target")
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
	visual.play_melee(Vector2(80, 0))
	for frame in 120:
		visual._process(SWF_FRAME_SECONDS)
		if get_signal_emit_count(visual, "attack_connected") > 0 and visual.position.x < 160.0:
			break
	var partway: Vector2 = visual.position
	assert_between(partway.x, 100.5, 160.0, "sanity: the doll is partway home")

	visual.play_melee(Vector2(80, 0))
	visual._process(SWF_FRAME_SECONDS)
	assert_gte(visual.position.x, partway.x, "the new swing runs on from where the doll stands")
	for frame in 240:
		visual._process(SWF_FRAME_SECONDS)
	assert_eq(visual.position, Vector2(100, 100), "and its Runback ends at the doll's own home")


func test_attack_variants_and_in_place_strike():
	watch_signals(visual)
	# Attack_Upper is a 30-frame swing (1s) - the overhead Destroy strike.
	visual.play_melee(Vector2(80, 0), "Attack_Upper")
	assert_eq(visual._attack_label, "Attack_Upper")
	for i in 60:
		visual._process(0.05)
	assert_signal_emitted(visual, "attack_connected")
	assert_eq(visual._state, CharacterVisual.State.IDLE)
	# Unknown labels fall back to the base swing.
	visual.play_melee(Vector2.ZERO, "Krin.Firebolt")
	assert_eq(visual._attack_label, "Attack")
	visual.set_state(CharacterVisual.State.IDLE)
	# In-place strike (Shock moves): strike + follow-through play where the
	# unit stands (the original Shock casters do the same), never moving.
	visual.position = Vector2(50, 50)
	visual.play_strike("Attack_Stab")
	for i in 45:
		visual._process(0.05)
	assert_signal_emitted(visual, "melee_finished")
	assert_eq(visual.position, Vector2(50, 50), "in-place strike never moves")
	assert_eq(visual._state, CharacterVisual.State.IDLE)


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
