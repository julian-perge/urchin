# Unit tests for the CharacterVisual paper doll - part assembly from the
# extracted MODEL1 rest pose, the dressChar() texture layering, equip-looks
# resolution, and the code-driven animation states.
extends GutTest

const CharacterVisualScene = preload("res://scenes/character_visual.tscn")
const GameItemScript = preload("res://scripts/entities/game_item.gd")

var visual: CharacterVisual


func before_each():
	visual = add_child_autofree(CharacterVisualScene.instantiate())


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
	# krinMelee: eased dash arrives ~0.47s in; impact 0.5s after arrival;
	# runback starts 1.0s after arrival and eases home (~2.2s total).
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


func test_cast_and_hit_recover_death_holds():
	visual.set_state(CharacterVisual.State.CAST)
	for i in 40:
		visual._process(0.05)
	assert_eq(visual._state, CharacterVisual.State.IDLE)
	visual.set_state(CharacterVisual.State.HIT)
	for i in 20:
		visual._process(0.05)
	assert_eq(visual._state, CharacterVisual.State.IDLE)
	visual.set_state(CharacterVisual.State.DEAD)
	for i in 40:
		visual._process(0.05)
	assert_eq(visual._state, CharacterVisual.State.DEAD, "death holds")
	assert_lt(visual.modulate.a, 1.0, "faded")


func test_stun_holds_until_cleared():
	visual.set_state(CharacterVisual.State.STUN)
	for i in 60:
		visual._process(0.05)
	assert_eq(visual._state, CharacterVisual.State.STUN)
	visual.set_state(CharacterVisual.State.IDLE)
	assert_true(visual.is_idle())
