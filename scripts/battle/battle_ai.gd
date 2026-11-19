# battle_ai.gd
# Enemy/ally move selection, ported from AImoveAdder()
# (frame_42/DoAction_9.as). BattleRunner calls choose_move() once per AI unit
# per half-turn, after ticking that unit's pool cooldowns down (LowerCD).
# The values that the original keeps in _root globals between calls live in
# BattleAI.scratch (see Scratch).
#
# The original's quirks are ported deliberately, not cleaned up:
# - The uniform pick `ceil(roll / (100 / n)) - 1` with roll 0..99 slightly
#   favors index 0 (roll 0 and roll 1..bits both land there).
# - The heal-candidate scan's second slot compares its HP ratio against the
#   FIRST friend slot's ratio, not the current candidate's (AS3 line 215).
# - focusMove selection indexes the cooldown-filtered attack list (A0), not
#   the fully filtered one (A2).
# - AS2 for..in walks an array from its newest key to its oldest
#   (DECODED_ALGORITHMS.md "for..in order over arrays"). The original builds
#   each filter with push while it walks the one before, so each step flips
#   the order. The absolute list and the heal-filtered defense list end in
#   descending pool order, the focus scan walks from the last move down, and
#   the attack list (A2) and the plain defense list end ascending.
#
# No autoload references (same rule as CombatUnit) - the move lookup comes in
# as a parameter.
class_name BattleAI
extends RefCounted

# The original reads an unset global as undefined. A slot that holds this value
# stands for undefined, and choose_move returns it as target 0.
const UNDEFINED_SLOT: int = -1


# AImoveAdder keeps these values in _root globals and resets only some of
# them, so each call starts from what the calls before it left, also the calls
# of the other side and of an earlier battle. Nothing else writes them, and they
# last until the SWF reloads. DECODED_ALGORITHMS.md, "Left-behind globals in
# AImoveAdder", has the lines and the Trace logs.
class Scratch:
	# focusCheck. NaN stands for undefined, because every comparison with
	# undefined is false in AS2, as it is with NaN here.
	var focus_check: float = NAN
	var player_focus_check: int = UNDEFINED_SLOT
	var number_lock_krin: int = UNDEFINED_SLOT
	var focus_move: bool = false
	var focus_select_num: int = -1
	# Whether D_Array_S, D_Array_F and D_Array_E hold a move. An undefined list
	# counts as empty, as its undefined length fails the heal scan's "> 0" test.
	var defense_has_self: bool = false
	var defense_has_ally: bool = false
	var defense_has_enemy: bool = false
	# aliveEnemies, or null while it is undefined.
	var alive_enemies: Variant = null
	var counter_filter_1: int = -1


static var scratch: Scratch = Scratch.new()


# Starts the left-behind values over, as a fresh load of the SWF does.
static func reset_scratch() -> void:
	scratch = Scratch.new()


# Chooses a move for the unit in caster_slot. Returns {} to pass the turn
# (queue move 0), else:
#   {move_id, target_slot, pool: CombatUnit.MovePool, pool_index}
# A target_slot of 0 is the original's undefined target, which the conductor
# treats as a dead target (line 350), so BattleRunner passes the turn.
# pool/pool_index tell BattleRunner which cooldown counter to set when the
# move actually starts (AI_CD_ARR/AI_CD_PUT).
static func choose_move(caster_slot: int, units: Dictionary, phase: int, healed_this_turn: Dictionary, moves_by_id: Dictionary) -> Dictionary:
	var caster: CombatUnit = units.get(caster_slot)
	if caster == null or not caster.active:
		return {}

	var s: Scratch = scratch
	var team: int = caster.team_side
	var friend_slots: Array[Variant] = [team, team + 2, team + 4]
	var enemy_slots: Array[Variant] = [7 - team, 5 - team, 3 - team]

	# The teammate scan (lines 6-34) writes the scratch values only for a
	# living teammate, and the first slot sets focusCheck with no comparison.
	var has_friends: bool = false
	for slot in friend_slots:
		var friend: CombatUnit = units.get(slot)
		if friend != null and friend.active and slot != caster_slot:
			has_friends = true
			s.number_lock_krin = slot
			if slot == team or friend.focus_n < s.focus_check:
				s.focus_check = friend.focus_n
				s.player_focus_check = slot

	# --- Absolute (boss-priority) pool: if anything is available, it is used
	# unconditionally and the attack/defense pools are ignored.
	var absolute_ids: Array[Variant] = []
	var absolute_indices: Array[Variant] = []
	for i in range(caster.move_pool_absolute.size() - 1, -1, -1):
		if caster.cooldowns_absolute[i] != 0:
			continue
		var entry = caster.move_pool_absolute[i]
		if entry["phase"] != 0 and entry["phase"] != phase:
			continue
		var move: Ability = moves_by_id.get(entry["id"])
		if move == null or not MoveLegality.can_afford(caster, move):
			continue
		if move.can_target_self or move.can_target_others or has_friends:
			absolute_ids.append(entry["id"])
			absolute_indices.append(i)

	var use_absolute: bool = not absolute_ids.is_empty()

	# --- Attack pool (A0 -> A1 -> A2) + focus-move priority.
	var attack_ids_cd: Array[Variant] = []  # A0: off cooldown
	var attack_indices_cd: Array[Variant] = []
	var attack_ids: Array[Variant] = []  # A2: fully filtered
	var attack_indices: Array[Variant] = []
	# --- Defense pool (D0 -> D1 -> D2) + ally/self/enemy splits.
	var defense_ids: Array[Variant] = []  # D2
	var defense_indices: Array[Variant] = []

	if not use_absolute:
		for i in caster.move_pool_attack.size():
			if caster.cooldowns_attack[i] == 0:
				attack_ids_cd.append(caster.move_pool_attack[i])
				attack_indices_cd.append(i)
		s.focus_move = false
		# A self focus move sets playerFocusCheck to the caster (line 105), so
		# the teammate focus moves that the scan walks after it no longer
		# count (line 95). focusSelectNum indexes A0, not A2.
		for i in range(attack_ids_cd.size() - 1, -1, -1):
			var move: Ability = moves_by_id.get(attack_ids_cd[i])
			if move == null or not MoveLegality.can_afford(caster, move):
				continue
			var restores_ally_focus: bool = move.targets_allies and s.focus_check < caster.focus_regen_limit
			var restores_own_focus: bool = move.can_target_self and caster.focus_n < caster.focus_regen_limit
			if move.effect_category != "Focus" or restores_ally_focus or restores_own_focus:
				if restores_ally_focus and s.player_focus_check != caster_slot:
					s.focus_move = true
					s.focus_select_num = i
				if restores_own_focus:
					s.focus_move = true
					s.focus_select_num = i
					s.player_focus_check = caster_slot
				if move.can_target_self or move.can_target_others or has_friends:
					attack_ids.push_front(attack_ids_cd[i])
					attack_indices.push_front(attack_indices_cd[i])

		s.defense_has_self = false
		s.defense_has_ally = false
		s.defense_has_enemy = false
		for i in caster.move_pool_defense.size():
			if caster.cooldowns_defense[i] != 0:
				continue
			var move: Ability = moves_by_id.get(caster.move_pool_defense[i])
			if move == null or not MoveLegality.can_afford(caster, move):
				continue
			if move.can_target_self or move.can_target_others or has_friends:
				defense_ids.append(caster.move_pool_defense[i])
				defense_indices.append(i)
				if move.targets_allies:
					s.defense_has_ally = true
				if move.can_target_self:
					s.defense_has_self = true
				if move.can_target_others:
					s.defense_has_enemy = true

	# --- Heal-candidate scan (krinAITargetCheckedHEALTEST): the friendly unit
	# (self included) lowest on predicted HP that the defense lists can target.
	# On the absolute path it reads the lists that the last non-absolute call
	# left.
	var heal_candidate_slot: int = 0
	var first_friend: CombatUnit = units.get(friend_slots[0])
	for slot_index in friend_slots.size():
		var slot = friend_slots[slot_index]
		var candidate: CombatUnit = units.get(slot)
		if candidate == null or not candidate.active:
			continue
		var should_consider: bool = true
		if slot_index > 0 and heal_candidate_slot != 0:
			var current: CombatUnit = units[heal_candidate_slot]
			var current_full: bool = current.life_n == current.life_u
			var candidate_ratio = (candidate.life_n + healed_this_turn.get(slot, 0.0)) / candidate.life_u
			# AS3 quirk: the second slot compares against the FIRST friend
			# slot's ratio, the third against the current candidate's.
			var compare_unit: CombatUnit = first_friend if slot_index == 1 else current
			var compare_slot = friend_slots[0] if slot_index == 1 else heal_candidate_slot
			var compare_ratio = INF
			if compare_unit != null:
				compare_ratio = (compare_unit.life_n + healed_this_turn.get(compare_slot, 0.0)) / compare_unit.life_u
			should_consider = current_full or candidate_ratio <= compare_ratio
		if should_consider:
			if slot == caster_slot:
				if s.defense_has_self or s.defense_has_enemy:
					heal_candidate_slot = slot
			elif s.defense_has_ally or s.defense_has_enemy:
				heal_candidate_slot = slot

	# --- Attack vs defense mode (LifeBoundary1/2 + Aggression roll). Skipped
	# (ScriptEnderKAIA) when either pool came up empty.
	var attack_mode: bool = not attack_ids.is_empty()
	var boundary_check_applies: bool = not attack_ids.is_empty() and not defense_ids.is_empty()
	if boundary_check_applies and heal_candidate_slot != 0:
		var candidate: CombatUnit = units[heal_candidate_slot]
		var hp_percent: float = candidate.life_n / candidate.life_u * 100.0
		if hp_percent <= caster.life_boundary_1:
			if hp_percent <= caster.life_boundary_2:
				attack_mode = false
			else:
				attack_mode = caster.aggression >= randi_range(0, 99)

	# --- Pick the move.
	var move_id: int = 0
	# Never read unless a move is actually chosen below - move_id == 0
	# returns {} first in every other path.
	var pool: CombatUnit.MovePool = CombatUnit.MovePool.ATTACK
	var pool_index: int = -1
	if use_absolute:
		var pick: int = _uniform_pick(absolute_ids.size())
		move_id = absolute_ids[pick]
		pool = CombatUnit.MovePool.ABSOLUTE
		pool_index = absolute_indices[pick]
	elif attack_mode:
		if s.focus_move:
			move_id = attack_ids_cd[s.focus_select_num]
			pool = CombatUnit.MovePool.ATTACK
			pool_index = attack_indices_cd[s.focus_select_num]
		elif not attack_ids.is_empty():
			var pick: int = _uniform_pick(attack_ids.size())
			move_id = attack_ids[pick]
			pool = CombatUnit.MovePool.ATTACK
			pool_index = attack_indices[pick]
	else:
		s.focus_move = false
		var final_ids: Array[Variant] = defense_ids
		var final_indices: Array[Variant] = defense_indices
		if heal_candidate_slot != 0:
			final_ids = []
			final_indices = []
			for i in range(defense_ids.size() - 1, -1, -1):
				var move: Ability = moves_by_id.get(defense_ids[i])
				if move == null:
					continue
				var targets_candidate: bool
				if caster_slot == heal_candidate_slot:
					targets_candidate = move.can_target_self or move.can_target_others
				else:
					targets_candidate = move.targets_allies or move.can_target_others
				if targets_candidate:
					final_ids.append(defense_ids[i])
					final_indices.append(defense_indices[i])
		if not final_ids.is_empty():
			var pick: int = _uniform_pick(final_ids.size())
			move_id = final_ids[pick]
			pool = CombatUnit.MovePool.DEFENSE
			pool_index = final_indices[pick]

	if move_id == 0:
		return {}
	var chosen: Ability = moves_by_id.get(move_id)

	# --- Pick the target (lines 345-440).
	var target_slot: int = 0
	if chosen.can_target_self:
		target_slot = caster_slot
	if chosen.can_target_others:
		var alive_enemies: Array[Variant] = []
		var weakest_slot: int = 0
		for slot in enemy_slots:
			var enemy: CombatUnit = units.get(slot)
			if enemy == null or not enemy.active:
				continue
			alive_enemies.append(slot)
			if weakest_slot == 0:
				weakest_slot = slot
			else:
				var weakest: CombatUnit = units[weakest_slot]
				if enemy.life_n + enemy.shield < weakest.life_n + weakest.shield:
					weakest_slot = slot
		s.alive_enemies = alive_enemies
		if randi_range(0, 99) < caster.focus_aggression:
			target_slot = weakest_slot
		else:
			s.counter_filter_1 = _uniform_pick(alive_enemies.size())
			target_slot = _slot_at(alive_enemies, s.counter_filter_1)

	# Line 399 adds the heal guess even when the heal scan found no one, and
	# before line 413 can pass the turn.
	if chosen.targets_allies and (target_slot == 0 or target_slot == caster_slot):
		target_slot = heal_candidate_slot
		healed_this_turn[target_slot] = healed_this_turn.get(target_slot, 0.0) + heal_guess(caster, chosen)
	if chosen.targets_allies and not chosen.can_target_self:
		target_slot = s.number_lock_krin
	if s.focus_move:
		target_slot = s.player_focus_check
	# An undefined aliveEnemies has no length of 0, so only a list that a call
	# built empty passes the turn.
	if s.alive_enemies != null and s.alive_enemies.is_empty():
		return {}
	# An undefined target is not 0, so it skips this fallback.
	if target_slot == 0:
		target_slot = _slot_at(s.alive_enemies, s.counter_filter_1)
	if target_slot == UNDEFINED_SLOT:
		target_slot = 0

	return {
		"move_id": move_id,
		"target_slot": target_slot,
		"pool": pool,
		"pool_index": pool_index,
	}


# The healing a move is expected to do. The original adds it to the target's
# healedThisTurn entry when an AI unit picks a move that targets allies
# (frame_42/DoAction_9.as:393-400) and when the player picks a Heal
# (frame_42/DoAction_11.as:92-95), so a unit that decides later in the
# half-turn sees what is already queued.
static func heal_guess(caster: CombatUnit, move: Ability) -> float:
	return move.focus_effect_multiplier * (
		(caster.strength_u + move.base_strength_bonus) * move.strength_damage_multiplier
		+ (caster.magic_u + move.base_magic_bonus) * move.magic_damage_multiplier
		+ (caster.speed_u + move.base_speed_bonus) * move.speed_damage_multiplier
		+ caster.focus_n * move.focus_scaling_modifier
		+ move.focus_amount_change
	)


# The slot at index in the original's aliveEnemies list. An undefined list or
# an index past its end reads as undefined.
static func _slot_at(list: Variant, index: int) -> int:
	if list == null or index < 0 or index >= list.size():
		return UNDEFINED_SLOT
	return list[index]


# The original's uniform list pick: KRSO roll 0..99 through
# ceil(roll / (100 / n)) - 1, clamped at 0.
static func _uniform_pick(count: int) -> int:
	if count <= 1:
		return 0
	var bits: float = 100.0 / count
	var pick: int = int(ceil(randi_range(0, 99) / bits)) - 1
	return max(pick, 0)
