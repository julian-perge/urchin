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
	for candidate in 10000:
		seed(candidate)
		var roll: int = randi_range(0, 99)
		if roll >= low and roll <= high:
			seed(candidate)
			return
	fail_test("no seed gives a first roll in [%d, %d]" % [low, high])


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
# focus move at playerFocusCheck.
func test_a_self_focus_move_stops_the_ally_focus_moves_walked_after_it():
	for row in [
		{
			"name": "self focus move below the teammate one",
			"moves": [
				_move(41, "Focus", ["can_target_self"]),
				_move(42, "Damage", ["can_target_others"]),
				_move(43, "Focus", ["targets_allies"]),
			],
			"move_id": 41, "pool_index": 0, "target_slot": CASTER_SLOT,
		},
		{
			"name": "self focus move above the teammate one",
			"moves": [
				_move(51, "Focus", ["targets_allies"]),
				_move(52, "Damage", ["can_target_others"]),
				_move(53, "Focus", ["can_target_self"]),
			],
			"move_id": 53, "pool_index": 2, "target_slot": CASTER_SLOT,
		},
		{
			"name": "only teammate focus moves",
			"moves": [
				_move(61, "Focus", ["targets_allies"]),
				_move(62, "Damage", ["can_target_others"]),
				_move(63, "Focus", ["targets_allies"]),
			],
			"move_id": 61, "pool_index": 0, "target_slot": TEAMMATE_SLOT,
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
		var units: Dictionary = {CASTER_SLOT: caster, TEAMMATE_SLOT: teammate, ENEMY_SLOT: _unit(CombatUnit.Team.TWO)}
		var chosen: Dictionary = BattleAI.choose_move(CASTER_SLOT, units, 1, {}, _moves_by_id(moves))
		assert_eq(chosen.get("move_id"), row["move_id"], row["name"])
		assert_eq(chosen.get("pool_index"), row["pool_index"], row["name"])
		assert_eq(chosen.get("target_slot"), row["target_slot"], row["name"])
