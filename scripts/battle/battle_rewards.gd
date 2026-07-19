# battle_rewards.gd
# Post-battle rewards - drops, money, experience. Ported from the full SWF
# script export (2026-07-18):
# - drop rolls: frame201 LOAD_BATTLE_SCENE (dropArray pre-rolled at battle
#   load: itemDrops are per-item % chances, itemRare/2/3 are guaranteed
#   uniform pulls, 15 drop slots total)
# - money: victory screen (DefineSprite_3142/frame_9) -
#   round(0.7 * respecValue(average spawned-unit level))
# - experience: expWorkOut(averageEnemyLevel, yourLevel)
#   (frame42/sonny2_expWorkOut.txt), fed into the 0-100 XP bar
#   (Leveling.grant_experience)
#
# The original accumulates the money input (moneyConstGain/totalEnemyGain)
# over EVERY unit spawned from a positive template id - including allied
# guest units like tutorial Louis - while the XP input (EnemyXP/EnemyXP3)
# only counts enemy-team units. Both helpers take level arrays so the caller
# controls that distinction; unit_levels_from_slots() extracts them from a
# BattleRunner-style units dictionary.
#
# No autoload references - keeping/kept drops go through the inventory layer
# (GameData) at the UI level, not here.
class_name BattleRewards
extends RefCounted

const DROP_SLOTS: int = 15


# Pre-rolls the battle's drop table (the original does this at battle LOAD,
# before the fight). Returns item ids, at most DROP_SLOTS. Converted data
# shapes: item_drops entries are {chance, item: {id, name}}; the rare pools
# hold {id, name} entries.
static func roll_drops(battle: BattleFight) -> Array:
	var drops = []
	if battle == null:
		return drops
	for entry in battle.item_drops:
		if int(_num(entry.get("chance"))) > randi_range(0, 99):
			drops.append(int(_num(entry.get("item", {}).get("id"))))
	for pool_index in 3:
		var pool: Array = [battle.item_rare, battle.item_rare2, battle.item_rare3][pool_index]
		var pulls: int = [battle.item_rare_dropper, battle.item_rare_dropper2, battle.item_rare_dropper3][pool_index]
		if pool.is_empty():
			continue
		for pull in pulls:
			var pulled = pool[randi_range(0, pool.size() - 1)]
			drops.append(int(_num(pulled.get("id"))))
	if drops.size() > DROP_SLOTS:
		push_warning("roll_drops: %d drops exceed the %d display slots" % [drops.size(), DROP_SLOTS])
		drops.resize(DROP_SLOTS)
	return drops


# moneyGain = round(0.7 * respecValue(average level of spawned units)).
static func money_gain(spawned_unit_levels: Array) -> int:
	if spawned_unit_levels.is_empty():
		return 0
	var total = 0.0
	for level in spawned_unit_levels:
		total += level
	var average = total / spawned_unit_levels.size()
	return int(round(0.7000000000000001 * Leveling.respec_value(average)))


# expWorkOut(): XP for the 0-100 bar. Bonus/penalty scales with the level
# difference (clamped 0..3x), and the base shrinks as your level grows.
static func experience_gain(average_enemy_level: float, your_level: int) -> float:
	var difference_multiplier = 1.0 + (average_enemy_level - your_level) * 0.1
	difference_multiplier = clamp(difference_multiplier, 0.0, 3.0)
	return 1.8000000000000005 * difference_multiplier * (100.0 / (1.0 + pow(your_level, 0.6)))


static func average_level(levels: Array) -> float:
	if levels.is_empty():
		return 0.0
	var total = 0.0
	for level in levels:
		total += level
	return total / levels.size()


# Extracts plevels from a BattleRunner units dictionary for the given slots
# (e.g. [2, 4, 6] for the enemy team).
static func unit_levels_from_slots(units: Dictionary, slots: Array) -> Array:
	var levels = []
	for slot in slots:
		var unit: CombatUnit = units.get(slot)
		if unit != null:
			levels.append(unit.plevel)
	return levels


# Applies a victory's money + XP to the save, including XP for the deployed
# companions who fought (the victory screen's per-member bars - each gets
# their own expWorkOut against their own level). Kept drops are the caller's
# responsibility (click-to-keep UI -> inventory). Returns the summary:
# {money_gained, xp_gained, levels_gained, new_level, stat_points_granted,
#  companion_levels_gained}.
static func apply_victory(save: PlayerSave, spawned_unit_levels: Array, enemy_levels: Array, fighting_party_ids: Array = []) -> Dictionary:
	var money = money_gain(spawned_unit_levels)
	save.euro += money
	var average_enemy = average_level(enemy_levels)
	var xp = experience_gain(average_enemy, save.level)
	var level_result = Leveling.grant_experience(save, xp)
	var companion_levels_gained = {}
	for party_id in fighting_party_ids:
		var companion_level = int(save.party_levels[party_id])
		var companion_xp = experience_gain(average_enemy, companion_level)
		companion_levels_gained[party_id] = Party.grant_companion_experience(save, party_id, companion_xp)
	return {
		"money_gained": money,
		"xp_gained": xp,
		"levels_gained": level_result["levels_gained"],
		"new_level": level_result["new_level"],
		"stat_points_granted": level_result["stat_points_granted"],
		"companion_levels_gained": companion_levels_gained,
	}


static func _num(value, default: float = 0.0) -> float:
	if value is float or value is int:
		return float(value)
	return default
