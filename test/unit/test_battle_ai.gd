# BattleAI walks some of its filtered move lists in the original's for..in
# order. AS2 for..in walks an array's keys from the newest key to the oldest
# (DECODED_ALGORITHMS.md "for..in order over arrays"), so every filter that
# AImoveAdder (frame_42/DoAction_9.as) builds once with push and then walks
# once comes out in descending pool order. Each test uses a pool of three
# moves, where ascending and descending order pick different moves.
extends GutTest

const CASTER_SLOT: int = 1
const TEAMMATE_SLOT: int = 3
const ENEMY_SLOT: int = 2


func before_each():
	BattleAI.reset_scratch()


func after_each():
	randomize()


func _unit(team: CombatUnit.Team) -> CombatUnit:
	var unit := CombatUnit.new()
	unit.team_side = team
	unit.life_u = 1000.0
	unit.life_n = 1000.0
	unit.focus_u = 100.0
	unit.focus_n = 100.0
	return unit


func _move(id: int, category: String, flags: Array[String]) -> Ability:
	var move := Ability.new()
	move.id = id
	move.effect_category = category
	for flag in flags:
		move.set(flag, true)
	return move


func _moves_by_id(moves: Array[Ability]) -> Dictionary:
	var by_id: Dictionary = {}
	for move in moves:
		by_id[move.id] = move
	return by_id


func _ids(moves: Array[Ability]) -> Array:
	return moves.map(func(move: Ability): return move.id)


# The uniform pick reads one roll of 0..99 and maps it with
# ceil(roll / (100 / n)) - 1. This finds a seed whose first roll is in
# [low, high], so the next choose_move call makes that roll.
func _seed_first_roll(low: int, high: int) -> void:
	_seed_rolls([[low, high]])


# Finds a seed whose rolls of 0..99, in order, each fall in their [low, high].
func _seed_rolls(ranges: Array) -> void:
	for candidate in 10000:
		seed(candidate)
		var all_match: bool = true
		for range_pair in ranges:
			var roll: int = randi_range(0, 99)
			if roll < range_pair[0] or roll > range_pair[1]:
				all_match = false
				break
		if all_match:
			seed(candidate)
			return
	fail_test("no seed gives the rolls %s" % [ranges])


# moveFilterABS1 is pushed while walking moveFilterABS0 (line 50), so it is in
# descending pool order and pick 0 is the last eligible absolute move.
func test_the_absolute_pick_walks_the_pool_from_the_last_move():
	var moves: Array[Ability] = [
		_move(11, "Damage", ["can_target_others"]),
		_move(12, "Damage", ["can_target_others"]),
		_move(13, "Damage", ["can_target_others"]),
	]
	for row in [
		{"name": "pick 0", "low": 0, "high": 33, "move_id": 13, "pool_index": 2},
		{"name": "pick 2", "low": 67, "high": 99, "move_id": 11, "pool_index": 0},
	]:
		var caster := _unit(CombatUnit.Team.ONE)
		caster.move_pool_absolute = _ids(moves).map(func(id): return {"id": id, "phase": 0})
		caster.cooldowns_absolute = [0, 0, 0]
		var units: Dictionary = {CASTER_SLOT: caster, ENEMY_SLOT: _unit(CombatUnit.Team.TWO)}
		_seed_first_roll(row["low"], row["high"])
		var chosen: Dictionary = BattleAI.choose_move(CASTER_SLOT, units, 1, {}, _moves_by_id(moves))
		assert_eq(chosen.get("move_id"), row["move_id"], row["name"])
		assert_eq(chosen.get("pool"), CombatUnit.MovePool.ABSOLUTE, row["name"])
		assert_eq(chosen.get("pool_index"), row["pool_index"], row["name"])


# With a heal candidate, moveFilterD2 is rebuilt by pushing while walking
# moveD_final (line 305), so it is in descending pool order.
func test_the_heal_filtered_defense_pick_walks_the_pool_from_the_last_move():
	var moves: Array[Ability] = [
		_move(21, "Heal", ["can_target_self"]),
		_move(22, "Heal", ["can_target_self"]),
		_move(23, "Heal", ["can_target_self"]),
	]
	for row in [
		{"name": "pick 0", "low": 0, "high": 33, "move_id": 23, "pool_index": 2},
		{"name": "pick 2", "low": 67, "high": 99, "move_id": 21, "pool_index": 0},
	]:
		var caster := _unit(CombatUnit.Team.ONE)
		caster.move_pool_defense = _ids(moves)
		caster.cooldowns_defense = [0, 0, 0]
		var units: Dictionary = {CASTER_SLOT: caster, ENEMY_SLOT: _unit(CombatUnit.Team.TWO)}
		_seed_first_roll(row["low"], row["high"])
		var chosen: Dictionary = BattleAI.choose_move(CASTER_SLOT, units, 1, {}, _moves_by_id(moves))
		assert_eq(chosen.get("move_id"), row["move_id"], row["name"])
		assert_eq(chosen.get("pool"), CombatUnit.MovePool.DEFENSE, row["name"])
		assert_eq(chosen.get("pool_index"), row["pool_index"], row["name"])
		assert_eq(chosen.get("target_slot"), CASTER_SLOT, row["name"])


# The focus scan walks moveFilterA0 from the last move down (line 85) and
# keeps the last match, so the lowest matching pool index wins.
func test_the_focus_scan_keeps_the_lowest_matching_move():
	var moves: Array[Ability] = [
		_move(31, "Focus", ["can_target_self"]),
		_move(32, "Damage", ["can_target_others"]),
		_move(33, "Focus", ["can_target_self"]),
	]
	var caster := _unit(CombatUnit.Team.ONE)
	caster.focus_n = 5.0
	caster.move_pool_attack = _ids(moves)
	caster.cooldowns_attack = [0, 0, 0]
	var units: Dictionary = {CASTER_SLOT: caster, ENEMY_SLOT: _unit(CombatUnit.Team.TWO)}
	var chosen: Dictionary = BattleAI.choose_move(CASTER_SLOT, units, 1, {}, _moves_by_id(moves))
	assert_eq(chosen.get("move_id"), 31)
	assert_eq(chosen.get("pool"), CombatUnit.MovePool.ATTACK)
	assert_eq(chosen.get("pool_index"), 0)
	assert_eq(chosen.get("target_slot"), CASTER_SLOT)


# moveFilterA2 goes through two push-and-walk steps (lines 85 and 110), so it
# ends in ascending pool order and pick 0 is the first eligible attack move.
func test_the_plain_attack_pick_walks_the_pool_from_the_first_move():
	var moves: Array[Ability] = [
		_move(71, "Damage", ["can_target_others"]),
		_move(72, "Damage", ["can_target_others"]),
		_move(73, "Damage", ["can_target_others"]),
	]
	for row in [
		{"name": "pick 0", "low": 0, "high": 33, "move_id": 71, "pool_index": 0},
		{"name": "pick 2", "low": 67, "high": 99, "move_id": 73, "pool_index": 2},
	]:
		var caster := _unit(CombatUnit.Team.ONE)
		caster.move_pool_attack = _ids(moves)
		caster.cooldowns_attack = [0, 0, 0]
		var units: Dictionary = {CASTER_SLOT: caster, ENEMY_SLOT: _unit(CombatUnit.Team.TWO)}
		_seed_first_roll(row["low"], row["high"])
		var chosen: Dictionary = BattleAI.choose_move(CASTER_SLOT, units, 1, {}, _moves_by_id(moves))
		assert_eq(chosen.get("move_id"), row["move_id"], row["name"])
		assert_eq(chosen.get("pool"), CombatUnit.MovePool.ATTACK, row["name"])
		assert_eq(chosen.get("pool_index"), row["pool_index"], row["name"])


# Lines 93-106: a self focus move sets playerFocusCheck to the caster, which
# stops every teammate focus move walked after it, and line 407 aims the chosen
# focus move at playerFocusCheck. The teammate stands in its side's first slot,
# because only that slot sets focusCheck with no comparison (line 12).
func test_a_self_focus_move_stops_the_ally_focus_moves_walked_after_it():
	const FOCUS_CASTER_SLOT: int = 3
	const FOCUS_TEAMMATE_SLOT: int = 1
	for row in [
		{
			"name": "self focus move below the teammate one",
			"moves": [
				_move(41, "Focus", ["can_target_self"]),
				_move(42, "Damage", ["can_target_others"]),
				_move(43, "Focus", ["targets_allies"]),
			],
			"move_id": 41, "pool_index": 0, "target_slot": FOCUS_CASTER_SLOT,
		},
		{
			"name": "self focus move above the teammate one",
			"moves": [
				_move(51, "Focus", ["targets_allies"]),
				_move(52, "Damage", ["can_target_others"]),
				_move(53, "Focus", ["can_target_self"]),
			],
			"move_id": 53, "pool_index": 2, "target_slot": FOCUS_CASTER_SLOT,
		},
		{
			"name": "only teammate focus moves",
			"moves": [
				_move(61, "Focus", ["targets_allies"]),
				_move(62, "Damage", ["can_target_others"]),
				_move(63, "Focus", ["targets_allies"]),
			],
			"move_id": 61, "pool_index": 0, "target_slot": FOCUS_TEAMMATE_SLOT,
		},
	]:
		var moves: Array[Ability] = []
		moves.assign(row["moves"])
		var caster := _unit(CombatUnit.Team.ONE)
		caster.focus_n = 5.0
		caster.move_pool_attack = _ids(moves)
		caster.cooldowns_attack = [0, 0, 0]
		var teammate := _unit(CombatUnit.Team.ONE)
		teammate.focus_n = 0.0
		var units: Dictionary = {FOCUS_CASTER_SLOT: caster, FOCUS_TEAMMATE_SLOT: teammate, ENEMY_SLOT: _unit(CombatUnit.Team.TWO)}
		var chosen: Dictionary = BattleAI.choose_move(FOCUS_CASTER_SLOT, units, 1, {}, _moves_by_id(moves))
		assert_eq(chosen.get("move_id"), row["move_id"], row["name"])
		assert_eq(chosen.get("pool_index"), row["pool_index"], row["name"])
		assert_eq(chosen.get("target_slot"), row["target_slot"], row["name"])


# Battle 212 in phase 2: the ZPCI Medic (slot 4) with Captain Hunt (slot 2) and
# the Sniper (slot 6), against the player's side in slots 1, 3 and 5.
const MEDIC_SLOT: int = 4
const HUNT_SLOT: int = 2
const SNIPER_SLOT: int = 6
const MED_BUFF_ID: int = 550


func _battle_212_units() -> Dictionary:
	var units: Dictionary = {}
	for slot in [1, 3, 5]:
		units[slot] = _unit(CombatUnit.Team.ONE)
	for slot in [HUNT_SLOT, MEDIC_SLOT, SNIPER_SLOT]:
		units[slot] = _unit(CombatUnit.Team.TWO)
	return units


func _med_buff() -> Ability:
	var move := _move(MED_BUFF_ID, "Buff", ["can_target_self", "targets_allies"])
	move.focus_effect_multiplier = 1.0
	move.focus_amount_change = 40.0
	return move


func _give_absolute_med_buff(medic: CombatUnit) -> void:
	medic.move_pool_absolute = [{"id": MED_BUFF_ID, "phase": 0}]
	medic.cooldowns_absolute = [0]


# Call 9 of run 3 in references/traced_runs/aimove_web_ruffle.txt. A call of
# the player's side (slot 3) left one defense move for a teammate and the self
# in D_Array_F and D_Array_S. The absolute path does not rebuild those lists
# (lines 134-139), so the Medic's heal scan reads them, finds the Sniper lowest
# on life, and line 398 sends Med Buff 1 and its heal guess there.
func test_an_absolute_buff_follows_the_defense_lists_an_earlier_call_left():
	var units: Dictionary = _battle_212_units()
	var heal := _move(9, "Heal", ["can_target_self", "targets_allies"])
	var med_buff := _med_buff()
	var moves_by_id: Dictionary = _moves_by_id([heal, med_buff])
	units[3].move_pool_defense = [heal.id]
	units[3].cooldowns_defense = [0]
	BattleAI.choose_move(3, units, 2, {}, moves_by_id)

	var medic: CombatUnit = units[MEDIC_SLOT]
	_give_absolute_med_buff(medic)
	units[HUNT_SLOT].life_n = 800.0
	medic.life_n = 900.0
	units[SNIPER_SLOT].life_n = 400.0
	var healed_this_turn: Dictionary = {}
	var chosen: Dictionary = BattleAI.choose_move(MEDIC_SLOT, units, 2, healed_this_turn, moves_by_id)
	assert_eq(chosen.get("move_id"), MED_BUFF_ID)
	assert_eq(chosen.get("target_slot"), SNIPER_SLOT)
	assert_eq(healed_this_turn.get(SNIPER_SLOT), 40.0)
	assert_false(healed_this_turn.has(MEDIC_SLOT), "nothing is queued on the Medic")


# Call 64 of references/traced_runs/aimove_web_flash.txt. The lists are empty,
# so the heal scan finds no one and the target stays 0, and lines 437-439 take
# aliveEnemies[counterFilter1] from the [6 4 2] list that a caster of the
# player's side built. The heal guess goes to the scan's 0.
func test_an_absolute_buff_with_no_heal_target_falls_back_to_the_left_enemy_list():
	var units: Dictionary = _battle_212_units()
	var strike := _move(19, "Damage", ["can_target_others"])
	var med_buff := _med_buff()
	var moves_by_id: Dictionary = _moves_by_id([strike, med_buff])
	units[3].move_pool_attack = [strike.id]
	units[3].cooldowns_attack = [0]
	units[3].focus_aggression = 0.0
	# The focus aggression roll, then a uniform pick of index 0 from [6 4 2].
	_seed_rolls([[0, 99], [0, 33]])
	var strike_choice: Dictionary = BattleAI.choose_move(3, units, 2, {}, moves_by_id)
	assert_eq(strike_choice.get("target_slot"), SNIPER_SLOT, "the strike set counterFilter1 to 0")

	_give_absolute_med_buff(units[MEDIC_SLOT])
	var healed_this_turn: Dictionary = {}
	var chosen: Dictionary = BattleAI.choose_move(MEDIC_SLOT, units, 2, healed_this_turn, moves_by_id)
	assert_eq(chosen.get("move_id"), MED_BUFF_ID)
	assert_eq(chosen.get("target_slot"), SNIPER_SLOT)
	assert_eq(healed_this_turn.get(0), 40.0)
	assert_false(healed_this_turn.has(SNIPER_SLOT))


# Only the non-absolute path resets focusMove (lines 84 and 296), so an absolute
# move after a call that left it true goes to playerFocusCheck (line 407),
# which this call's teammate scan sets to the teammate lowest on focus.
func test_an_absolute_move_after_a_left_focus_move_goes_to_player_focus_check():
	var focus_gift := _move(31, "Focus", ["targets_allies"])
	var strike := _move(32, "Damage", ["can_target_others"])
	var moves_by_id: Dictionary = _moves_by_id([focus_gift, strike])
	var low_focus_teammate := _unit(CombatUnit.Team.ONE)
	low_focus_teammate.focus_n = 0.0
	var units: Dictionary = {
		1: low_focus_teammate,
		3: _unit(CombatUnit.Team.ONE),
		5: _unit(CombatUnit.Team.ONE),
		ENEMY_SLOT: _unit(CombatUnit.Team.TWO),
	}
	units[3].move_pool_attack = [focus_gift.id]
	units[3].cooldowns_attack = [0]
	var focus_choice: Dictionary = BattleAI.choose_move(3, units, 1, {}, moves_by_id)
	assert_eq(focus_choice.get("target_slot"), 1, "the focus move went to slot 1")
	assert_true(BattleAI.scratch.focus_move)

	units[5].move_pool_absolute = [{"id": strike.id, "phase": 0}]
	units[5].cooldowns_absolute = [0]
	units[5].focus_aggression = 100.0
	var chosen: Dictionary = BattleAI.choose_move(5, units, 1, {}, moves_by_id)
	assert_eq(chosen.get("move_id"), strike.id)
	assert_eq(chosen.get("target_slot"), 1)


# Calls 305 and 308 of run 2 in aimove_web_ruffle.txt. counterFilter1 is 1 from
# a call that had two enemies, and aliveEnemies is [2] from a later call that
# took the weakest enemy. aliveEnemies[1] is undefined, and the conductor runs
# no move at an undefined target (line 350), so choose_move returns target 0.
func test_a_fallback_past_the_end_of_the_left_enemy_list_has_no_target():
	BattleAI.scratch.alive_enemies = [2]
	BattleAI.scratch.counter_filter_1 = 1
	var units: Dictionary = _battle_212_units()
	_give_absolute_med_buff(units[MEDIC_SLOT])
	var chosen: Dictionary = BattleAI.choose_move(MEDIC_SLOT, units, 2, {}, _moves_by_id([_med_buff()]))
	assert_eq(chosen.get("move_id"), MED_BUFF_ID)
	assert_eq(chosen.get("target_slot"), 0)


# Line 413 passes the turn when aliveEnemies is empty, also for a move that
# does not hit enemies and so reads the list an earlier call left. Line 399 has
# already added the heal guess by then.
func test_an_empty_left_enemy_list_passes_the_turn_after_the_heal_guess():
	BattleAI.scratch.alive_enemies = []
	BattleAI.scratch.defense_has_self = true
	var units: Dictionary = _battle_212_units()
	_give_absolute_med_buff(units[MEDIC_SLOT])
	var healed_this_turn: Dictionary = {}
	var chosen: Dictionary = BattleAI.choose_move(MEDIC_SLOT, units, 2, healed_this_turn, _moves_by_id([_med_buff()]))
	assert_eq(chosen, {})
	assert_eq(healed_this_turn.get(MEDIC_SLOT), 40.0)
