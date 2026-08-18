# battle_ai.gd
# Enemy/ally move selection, ported from AImoveAdder()
# (frame42/sonny2_ai_move_adder.txt). Stateless - BattleRunner calls
# choose_move() once per AI unit per half-turn, after ticking that unit's
# pool cooldowns down (LowerCD).
#
# The original's quirks are ported deliberately, not cleaned up:
# - The uniform pick `ceil(roll / (100 / n)) - 1` with roll 0..99 slightly
#   favors index 0 (roll 0 and roll 1..bits both land there).
# - The heal-candidate scan's second slot compares its HP ratio against the
#   FIRST friend slot's ratio, not the current candidate's (AS3 line 215).
# - focusMove selection indexes the cooldown-filtered attack list (A0), not
#   the fully filtered one (A2).
#
# No autoload references (same rule as CombatUnit) - the move lookup comes in
# as a parameter.
class_name BattleAI
extends RefCounted


# Chooses a move for the unit in caster_slot. Returns {} to pass the turn
# (queue move 0), else:
#   {move_id, target_slot, pool: CombatUnit.MovePool, pool_index}
# pool/pool_index tell BattleRunner which cooldown counter to set when the
# move actually starts (AI_CD_ARR/AI_CD_PUT).
static func choose_move(caster_slot: int, units: Dictionary, phase: int, healed_this_turn: Dictionary, moves_by_id: Dictionary) -> Dictionary:
	var caster: CombatUnit = units.get(caster_slot)
	if caster == null or not caster.active:
		return {}

	var team: int = caster.team_side
	var friend_slots: Array[Variant] = [team, team + 2, team + 4]
	var enemy_slots: Array[Variant] = [7 - team, 5 - team, 3 - team]

	# Living teammates other than the caster; track the one lowest on focus
	# (focusCheck/playerFocusCheck/numberLockKrin).
	var has_friends: bool = false
	var friend_lock_slot: int = 0  # numberLockKrin - last living friend found
	var lowest_focus = INF
	var lowest_focus_slot: int = 0  # playerFocusCheck
	for slot in friend_slots:
		var friend: CombatUnit = units.get(slot)
		if friend != null and friend.active and slot != caster_slot:
			has_friends = true
			friend_lock_slot = slot
			if friend.focus_n < lowest_focus:
				lowest_focus = friend.focus_n
				lowest_focus_slot = slot

	# --- Absolute (boss-priority) pool: if anything is available, it is used
	# unconditionally and the attack/defense pools are ignored.
	var absolute_ids: Array[Variant] = []
	var absolute_indices: Array[Variant] = []
	for i in caster.move_pool_absolute.size():
		if caster.cooldowns_absolute[i] != 0:
			continue
		var entry = caster.move_pool_absolute[i]
		if entry["phase"] != 0 and entry["phase"] != phase:
			continue
		var move: Ability = moves_by_id.get(entry["id"])
		if move == null or not _can_afford(caster, move):
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
	var focus_move: bool = false
	var focus_pick_index: int = -1  # indexes attack_ids_cd (A0), matching the original
	var focus_target_slot: int = 0
	# --- Defense pool (D0 -> D1 -> D2) + ally/self/enemy splits.
	var defense_ids: Array[Variant] = []  # D2
	var defense_indices: Array[Variant] = []
	var defense_has_self: bool = false  # D_Array_S nonempty
	var defense_has_ally: bool = false  # D_Array_F nonempty
	var defense_has_enemy: bool = false  # D_Array_E nonempty

	if not use_absolute:
		for i in caster.move_pool_attack.size():
			if caster.cooldowns_attack[i] == 0:
				attack_ids_cd.append(caster.move_pool_attack[i])
				attack_indices_cd.append(i)
		for i in attack_ids_cd.size():
			var move: Ability = moves_by_id.get(attack_ids_cd[i])
			if move == null or not _can_afford(caster, move):
				continue
			var restores_ally_focus: bool = move.targets_allies and lowest_focus < caster.focus_regen_limit
			var restores_own_focus: bool = move.can_target_self and caster.focus_n < caster.focus_regen_limit
			if move.effect_category != "Focus" or restores_ally_focus or restores_own_focus:
				if restores_ally_focus and lowest_focus_slot != caster_slot and lowest_focus_slot != 0:
					focus_move = true
					focus_pick_index = i
					focus_target_slot = lowest_focus_slot
				if restores_own_focus:
					focus_move = true
					focus_pick_index = i
					focus_target_slot = caster_slot
				if move.can_target_self or move.can_target_others or has_friends:
					attack_ids.append(attack_ids_cd[i])
					attack_indices.append(attack_indices_cd[i])

		for i in caster.move_pool_defense.size():
			if caster.cooldowns_defense[i] != 0:
				continue
			var move: Ability = moves_by_id.get(caster.move_pool_defense[i])
			if move == null or not _can_afford(caster, move):
				continue
			if move.can_target_self or move.can_target_others or has_friends:
				defense_ids.append(caster.move_pool_defense[i])
				defense_indices.append(i)
				if move.targets_allies:
					defense_has_ally = true
				if move.can_target_self:
					defense_has_self = true
				if move.can_target_others:
					defense_has_enemy = true

	# --- Heal-candidate scan (krinAITargetCheckedHEALTEST): the friendly unit
	# (self included) lowest on predicted HP that the defense pool can target.
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
				if defense_has_self or defense_has_enemy:
					heal_candidate_slot = slot
			elif defense_has_ally or defense_has_enemy:
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
		if focus_move:
			move_id = attack_ids_cd[focus_pick_index]
			pool = CombatUnit.MovePool.ATTACK
			pool_index = attack_indices_cd[focus_pick_index]
		elif not attack_ids.is_empty():
			var pick: int = _uniform_pick(attack_ids.size())
			move_id = attack_ids[pick]
			pool = CombatUnit.MovePool.ATTACK
			pool_index = attack_indices[pick]
	else:
		focus_move = false
		var final_ids: Array[Variant] = defense_ids
		var final_indices: Array[Variant] = defense_indices
		if heal_candidate_slot != 0:
			final_ids = []
			final_indices = []
			for i in defense_ids.size():
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

	# --- Pick the target.
	var target_slot: int = 0
	var alive_enemies: Array[Variant] = []
	if chosen.can_target_self:
		target_slot = caster_slot
	if chosen.can_target_others:
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
		if alive_enemies.is_empty():
			return {}
		if randi_range(0, 99) < caster.focus_aggression:
			target_slot = weakest_slot
		else:
			target_slot = alive_enemies[_uniform_pick(alive_enemies.size())]

	if chosen.targets_allies and (target_slot == 0 or target_slot == caster_slot):
		if heal_candidate_slot != 0:
			var heal_guess: float = chosen.focus_effect_multiplier * (
				(caster.strength_u + chosen.base_strength_bonus) * chosen.strength_damage_multiplier
				+ (caster.magic_u + chosen.base_magic_bonus) * chosen.magic_damage_multiplier
				+ (caster.speed_u + chosen.base_speed_bonus) * chosen.speed_damage_multiplier
				+ caster.focus_n * chosen.focus_scaling_modifier
				+ chosen.focus_amount_change
			)
			target_slot = heal_candidate_slot
			healed_this_turn[target_slot] = healed_this_turn.get(target_slot, 0.0) + heal_guess
	if chosen.targets_allies and not chosen.can_target_self and friend_lock_slot != 0:
		target_slot = friend_lock_slot
	if focus_move and focus_target_slot != 0:
		target_slot = focus_target_slot
	if target_slot == 0:
		target_slot = caster_slot

	return {
		"move_id": move_id,
		"target_slot": target_slot,
		"pool": pool,
		"pool_index": pool_index,
	}


# Silence blocks any move with a focus cost (cost * SILENCED == 0 gate in the
# original - this is the confirmed silence rule). Life check: strictly MORE
# life than the total cost, so a move can never kill its own caster.
static func _can_afford(caster: CombatUnit, move: Ability) -> bool:
	if caster.silenced != 0 and move.focus_cost > 0:
		return false
	if caster.focus_n < move.focus_cost:
		return false
	return caster.life_n > move.flat_life_cost + round(caster.life_u * move.health_cost_percentage)


# The original's uniform list pick: KRSO roll 0..99 through
# ceil(roll / (100 / n)) - 1, clamped at 0.
static func _uniform_pick(count: int) -> int:
	if count <= 1:
		return 0
	var bits: float = 100.0 / count
	var pick: int = int(ceil(randi_range(0, 99) / bits)) - 1
	return max(pick, 0)
