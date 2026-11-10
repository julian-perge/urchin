# battle_manager.gd
class_name BattleManager
extends RefCounted

# Ported from frame42/sonny2_executeMove.txt, with buff application from
# frame42/sonny2_addNewBuffKrin.txt's applyBuffKrin() wired in afterward. The
# original applies a move's status effect in one place, after executeMove()
# returns, whatever the move's category (the conductor,
# frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(enterFrame).as
# lines 70-102), so _apply_status_effect() runs after the match below for
# every category. The conductor then recomputes the target's stats with
# applyChangesKrin (line 103), which redraws its bars, its buff icons and its
# stun pose (frame_42/DoAction_10.as:342-379 and 468-481), so execute_move()
# ends with that recompute and takes the snapshot the result ends on after it.
# Visual/audio side effects (BATTLEFLASH, BATTLESCREEN, addSound, ...) are left
# out entirely. This returns a MoveResult and the battle screen reacts to it.
#
# _crit_roll() calls randi_range(0, 99) where the original's perScript() reads
# KRS, a table of 100 random(100) values that it refills every time a battle
# loads, and docs/adr/0003-keep-fresh-battle-rolls.md says why the port rolls
# fresh. The status effect proc in _apply_status_effect() calls randf(), as the
# original calls Math.random() there (the conductor, line 72).
#
# executeMove() computes nothing for a category other than "Full Damage",
# "Heal" and "Focus", so a move with any other category gives a STATUS_ONLY
# result with no amount. Shatter Bolt is the one move whose category is
# "Attack": it deals no damage and stuns its target through its status effect
# alone. Dispel runs before this, in BattleRunner._resolve_dispels(), the same
# order as the conductor.
#
# `buffs_by_name` (Buff.internal_name -> Buff, e.g.
# BuffManagerAuto.buffs_by_internal_name) is a parameter for the same reason
# CombatUnit.tick_buffs() takes one - referencing an autoload singleton
# directly from this script would break its compilation anywhere it's loaded
# outside an actually-running game (EditorScript smoke tests included).
static func execute_move(ability: Ability, caster: CombatUnit, target: CombatUnit, buffs_by_name: Dictionary = {}) -> MoveResult:
	var result := MoveResult.new()
	result.life_before = target.life_n
	result.target_stunned = target.stun != 0
	var was_active: bool = target.active

	var avg_num_c: int = 100 + 15 * caster.plevel
	var speed_crit_calc: float = caster.speed_u / CombatUnit.get_stat(10, caster.plevel) - 1

	var element: CombatUnit.Element = ability.damage_element_type
	var per_calc = caster.per_u.get(element, 0.0) / avg_num_c
	var def_calc = target.def_u.get(element, 0.0) / avg_num_c
	if def_calc <= 0:
		def_calc = 0.1
	if per_calc <= 0:
		per_calc = 0.1

	var crit_calc_x = min(per_calc / def_calc, 10.0)
	var focus_coef: float = ability.focus_cost_multiplier + caster.focus_n / 100.0 * ability.focus_scaling_modifier

	match ability.effect_category:
		"Full Damage":
			_execute_full_damage(result, ability, caster, target, per_calc, def_calc, crit_calc_x, focus_coef, speed_crit_calc)
		"Heal":
			_execute_heal(result, ability, caster, target, per_calc, focus_coef, speed_crit_calc)
		"Focus":
			_execute_focus(result, ability, target)
		"Attack":
			result.kind = MoveResult.Kind.STATUS_ONLY
		_:
			# The original also lands only the status here, but no move in the
			# data has another category, so one showing up means a converter bug.
			push_warning("execute_move: unknown effect_category '%s' on move %s" % [ability.effect_category, ability.display_name])
			result.kind = MoveResult.Kind.STATUS_ONLY

	result.buff_applied = _apply_status_effect(ability, caster, target, buffs_by_name)
	target.apply_changes()
	result.target_after = UnitSnapshot.of(target)
	result.killed = was_active and not target.active
	return result


# BattleRunner's hit roll failed, so the result only states the target as it
# was, which nothing changed.
static func miss(target: CombatUnit) -> MoveResult:
	var result := MoveResult.new()
	result.kind = MoveResult.Kind.MISS
	result.life_before = target.life_n
	result.target_stunned = target.stun != 0
	result.target_after = UnitSnapshot.of(target)
	return result


static func _apply_status_effect(ability: Ability, caster: CombatUnit, target: CombatUnit, buffs_by_name: Dictionary) -> String:
	if ability.status_effect_id.is_empty():
		return ""
	if randf() > ability.effect_proc_chance:
		return ""
	var buff = buffs_by_name.get(ability.status_effect_id)
	if buff == null:
		push_warning("execute_move: no buff def for status_effect_id '%s'" % ability.status_effect_id)
		return ""
	var buff_target: CombatUnit = caster if ability.effect_target_is_self else target
	# Unique ("cannot stack") buffs refresh the existing instance's duration
	# instead of applying a second copy - ported from the buffUniqueCheck block
	# in frame217_KRIN_BATTLE_SCENE/onClipEvent_enterFrame.txt.
	if buff.is_unique:
		var refreshed: bool = false
		for slot in buff_target.buff_slots:
			if slot["buff_id"] == buff.id and slot["cd"] != 0:
				slot["cd"] = buff.duration_turns
				refreshed = true
		if refreshed:
			return buff.internal_name
	# This deliberately leaves apply_changes() out. The conductor's status block
	# never runs applyChangesKrin, and the one after the hit (line 103) is on the
	# target only, which execute_move() matches. A buff that lands on the caster
	# waits for the caster's tick_buffs(), like the original's buffTicker
	# (frame_42/DoAction_10.as:135).
	buff_target.apply_buff(buff, 1, caster)
	return buff.internal_name


static func _crit_roll(per_calc: float, def_calc: float, speed_crit_calc: float, ability: Ability) -> bool:
	# GGG[7]/GGG[8] in the original perScript() - read by raw numeric slot since
	# the JSON converter's field labels ("effect_duration_turns"/
	# "base_damage_multiplier") describe their meaning elsewhere, not their use
	# here; these array slots serve double duty depending on the calling code.
	var crit_chance_bonus = ability.ability_two_raw.get("7_effect_duration_turns", 0.0)
	var crit_chance_scalar = ability.ability_two_raw.get("8_base_damage_multiplier", 0.0)
	var speed_term = max(speed_crit_calc, 0.0)
	var threshold = (per_calc + crit_chance_bonus + speed_term) * crit_chance_scalar / def_calc * 15
	return randi_range(0, 99) < threshold


static func _execute_full_damage(result: MoveResult, ability: Ability, caster: CombatUnit, target: CombatUnit, per_calc: float, def_calc: float, crit_calc_x: float, focus_coef: float, speed_crit_calc: float) -> void:
	var base_damage: float = (
		(caster.strength_u + ability.base_strength_bonus) * ability.strength_damage_multiplier
		+ (caster.magic_u + ability.base_magic_bonus) * ability.magic_damage_multiplier
		+ (caster.speed_u + ability.base_speed_bonus) * ability.speed_damage_multiplier
		+ ability.focus_amount_change
	)
	var crit_multiplier: float = ability.focus_effect_multiplier

	var element_multiplier: float
	var did_crit: bool = _crit_roll(per_calc, def_calc, speed_crit_calc, ability)
	if did_crit:
		var x: float = crit_calc_x + 1
		element_multiplier = max(0.016666667 * pow(x, 4) - 0.25 * pow(x, 3) + 1.233333 * pow(x, 2) - 1.9000000000000001 * x + 1.9000000000000001, 0.0)
	else:
		if crit_calc_x <= 1:
			element_multiplier = crit_calc_x
		else:
			element_multiplier = 1 + 0.07 * (per_calc - def_calc)
		if element_multiplier <= 0:
			element_multiplier = 0.01

	var damage = ceil(
		caster.dmg + target.idmg
		+ base_damage * focus_coef * crit_multiplier * element_multiplier
		* (1 + caster.dmg2) * (1 + target.idmg2) * target.idmgp2
	)
	if damage <= 0 or is_nan(damage):
		damage = 1

	result.kind = MoveResult.Kind.DAMAGE
	result.critical = did_crit
	_apply_damage(result, target, damage)


static func _apply_damage(result: MoveResult, target: CombatUnit, amount: float) -> void:
	result.direction = MoveResult.Direction.HARM
	if target.shield > 0:
		var difference: float = target.shield - amount
		if difference > 0:
			target.shield -= amount
			result.amount = 0
			result.shield_took_all = true
			return
		amount -= target.shield
		target.shield = 0

	result.amount = amount
	if target.sswitch == 0:
		target.life_n -= amount
		if target.life_n <= 0:
			target.life_n = 0
			target.focus_n = 0
			target.active = false
	else:
		result.direction = MoveResult.Direction.HEAL
		target.life_n += amount
		if target.life_n > target.life_u:
			target.life_n = target.life_u


static func _execute_heal(result: MoveResult, ability: Ability, caster: CombatUnit, target: CombatUnit, per_calc: float, focus_coef: float, speed_crit_calc: float) -> void:
	var base_amount: float = (
		(caster.strength_u + ability.base_strength_bonus) * ability.strength_damage_multiplier
		+ (caster.magic_u + ability.base_magic_bonus) * ability.magic_damage_multiplier
		+ (caster.speed_u + ability.base_speed_bonus) * ability.speed_damage_multiplier
		+ caster.life_u * ability.heal_percent_max_health
		+ ability.focus_amount_change
	)
	# The original passes a fixed def_calc of 1 here (perScript(PERCALK, 1, IDKM2)).
	var did_crit: bool = _crit_roll(per_calc, 1.0, speed_crit_calc, ability)
	var element_multiplier: float = 1.5 if did_crit else 1.0

	var amount = ceil(base_amount * focus_coef * ability.focus_effect_multiplier * element_multiplier * caster.heal_mod * target.heal_mod_plus * target.heal_mod_minus)
	if amount <= 0:
		amount = 0

	result.kind = MoveResult.Kind.HEAL
	result.direction = MoveResult.Direction.HEAL
	result.critical = did_crit
	result.amount = amount
	if amount <= 0:
		return

	if target.sswitch == 0:
		target.life_n += amount
		if target.life_n > target.life_u:
			target.life_n = target.life_u
	else:
		result.direction = MoveResult.Direction.HARM
		target.life_n -= amount
		if target.life_n <= 0:
			target.life_n = 0
			target.focus_n = 0
			target.active = false


static func _execute_focus(result: MoveResult, ability: Ability, target: CombatUnit) -> void:
	target.focus_n += ability.focus_amount_change
	target.focus_n = clamp(target.focus_n, 0, target.focus_u)
	result.kind = MoveResult.Kind.FOCUS
	result.amount = ability.focus_amount_change
