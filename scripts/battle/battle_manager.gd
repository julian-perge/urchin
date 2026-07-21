# battle_manager.gd
class_name BattleManager
extends Node

# Ported from frame42/sonny2_executeMove.txt, with buff application from
# frame42/sonny2_addNewBuffKrin.txt's applyBuffKrin() wired in afterward (the
# original interleaves them per move-type branch; this applies uniformly to
# whichever branch ran, which is equivalent since status_effect_id/
# effect_proc_chance/effect_target_is_self aren't branch-specific in the data).
# Visual/audio side effects (BATTLEFLASH, BATTLESCREEN, addSound, ...) are left
# out entirely; this returns a result Dictionary and the UI layer reacts to it.
#
# Original used a pre-rolled deterministic RNG array (KRS/KRSC/KRRR) shared
# with the PvP checksum system, which we're not porting - crit/proc rolls here
# use plain randi_range()/randf() instead.
#
# Not wired up: dispel (ability_two[15]/[16], removing the target's existing
# buffs) and the single move whose effect_category is "Attack" ("Shatter
# Bolt") - the original executeMove() doesn't handle that category either, so
# this matches source behavior, not a gap introduced here.
#
# `buffs_by_name` (Buff.internal_name -> Buff, e.g.
# BuffManagerAuto.buffs_by_internal_name) is a parameter for the same reason
# CombatUnit.tick_buffs() takes one - referencing an autoload singleton
# directly from this script would break its compilation anywhere it's loaded
# outside an actually-running game (EditorScript smoke tests included).
func execute_move(ability: Ability, caster: CombatUnit, target: CombatUnit, buffs_by_name: Dictionary = {}) -> Dictionary:
	var avg_num_c: int = 100 + 15 * caster.plevel
	var speed_crit_calc: float = caster.speed_u / CombatUnit.get_stat(10, caster.plevel) - 1

	var element: String = ability.damage_element_type
	var per_calc = caster.per_u.get(element, 0.0) / avg_num_c
	var def_calc = target.def_u.get(element, 0.0) / avg_num_c
	if def_calc <= 0:
		def_calc = 0.1
	if per_calc <= 0:
		per_calc = 0.1

	var crit_calc_x = min(per_calc / def_calc, 10.0)
	var focus_coef: float = ability.focus_cost_multiplier + caster.focus_n / 100.0 * ability.focus_scaling_modifier

	var result: Dictionary
	match ability.effect_category:
		"Full Damage":
			result = _execute_full_damage(ability, caster, target, per_calc, def_calc, crit_calc_x, focus_coef, speed_crit_calc)
		"Heal":
			result = _execute_heal(ability, caster, target, per_calc, focus_coef, speed_crit_calc)
		"Focus":
			result = _execute_focus(ability, target)
		_:
			push_warning("execute_move: unhandled effect_category '%s' on move %s" % [ability.effect_category, ability.display_name])
			return {}

	result["buff_applied"] = _apply_status_effect(ability, caster, target, buffs_by_name)
	return result

func _apply_status_effect(ability: Ability, caster: CombatUnit, target: CombatUnit, buffs_by_name: Dictionary) -> String:
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
	buff_target.apply_buff(buff, 1, caster)
	buff_target.apply_changes()
	return buff.internal_name

func _crit_roll(per_calc: float, def_calc: float, speed_crit_calc: float, ability: Ability) -> bool:
	# GGG[7]/GGG[8] in the original perScript() - read by raw numeric slot since
	# the JSON converter's field labels ("effect_duration_turns"/
	# "base_damage_multiplier") describe their meaning elsewhere, not their use
	# here; these array slots serve double duty depending on the calling code.
	var crit_chance_bonus = ability.ability_two_raw.get("7_effect_duration_turns", 0.0)
	var crit_chance_scalar = ability.ability_two_raw.get("8_base_damage_multiplier", 0.0)
	var speed_term = max(speed_crit_calc, 0.0)
	var threshold = (per_calc + crit_chance_bonus + speed_term) * crit_chance_scalar / def_calc * 15
	return randi_range(0, 99) < threshold

func _execute_full_damage(ability: Ability, caster: CombatUnit, target: CombatUnit, per_calc: float, def_calc: float, crit_calc_x: float, focus_coef: float, speed_crit_calc: float) -> Dictionary:
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

	return _apply_damage(target, damage, did_crit)

func _apply_damage(target: CombatUnit, amount: float, did_crit: bool) -> Dictionary:
	var shielded_amount: float = 0.0
	if target.shield > 0:
		var difference: float = target.shield - amount
		if difference > 0:
			target.shield -= amount
			return {"type": "damage", "amount": 0, "shielded_amount": amount, "did_crit": did_crit, "target_died": false}
		shielded_amount = target.shield
		amount -= target.shield
		target.shield = 0

	if target.sswitch == 0:
		target.life_n -= amount
		if target.life_n <= 0:
			target.life_n = 0
			target.focus_n = 0
			target.active = false
	else:
		target.life_n += amount
		if target.life_n > target.life_u:
			target.life_n = target.life_u

	return {
		"type": "damage",
		"amount": amount,
		"shielded_amount": shielded_amount,
		"did_crit": did_crit,
		"target_died": not target.active,
	}

func _execute_heal(ability: Ability, caster: CombatUnit, target: CombatUnit, per_calc: float, focus_coef: float, speed_crit_calc: float) -> Dictionary:
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
	if amount <= 0:
		return {"type": "heal", "amount": 0, "did_crit": did_crit, "target_died": false}

	if target.sswitch == 0:
		target.life_n += amount
		if target.life_n > target.life_u:
			target.life_n = target.life_u
		return {"type": "heal", "amount": amount, "did_crit": did_crit, "target_died": false}
	else:
		target.life_n -= amount
		if target.life_n <= 0:
			target.life_n = 0
			target.focus_n = 0
			target.active = false
		return {"type": "heal", "amount": amount, "did_crit": did_crit, "target_died": not target.active}

func _execute_focus(ability: Ability, target: CombatUnit) -> Dictionary:
	target.focus_n += ability.focus_amount_change
	target.focus_n = clamp(target.focus_n, 0, target.focus_u)
	return {"type": "focus", "amount": ability.focus_amount_change}
