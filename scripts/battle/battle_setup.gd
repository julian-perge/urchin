# battle_setup.gd
# Builds a BattleRunner-ready roster from a battle definition + the player's
# save - the port of the unit-placement half of LOAD_BATTLE_SCENE +
# krinAddNewUnit (frame42/sonny2_createNewBattle.txt).
#
# Slot layout: battle.players[i] fills slot i + 2. Positive values are enemy
# unit template ids, 0 is an empty slot, and the -2/-1 markers are the two
# deployed companions (see Party.deployed_party_id). Slot 1 is always the
# player. players_levels entries can be "X" (player level - 2) or "Z"
# (player level + 5), both clamped to [1, train_cap] (finalTrainCap).
#
# No autoload references - unit templates and the battle resource come in as
# parameters. load_battle() is the one filesystem touch (the generated
# resources/battles/*.tres files).
class_name BattleSetup
extends RefCounted

const DEFAULT_TRAIN_CAP: int = 30
const BATTLE_RESOURCE_PATH: String = "res://resources/battles/%d_KBR%d.tres"


static func load_battle(battle_id: int) -> BattleFight:
	var path: String = BATTLE_RESOURCE_PATH % [battle_id, battle_id]
	if not ResourceLoader.exists(path):
		push_warning("load_battle: no battle resource at " + path)
		return null
	return load(path)


# Builds {slot: CombatUnit} for BattleRunner.setup(). The player unit is
# human-controlled (ai_enabled false); pass everything to the runner along
# with TalentTree.get_passive_buff_names(save).
static func build_units(battle: BattleFight, save: PlayerSave, unit_templates: Dictionary, difficulty: int, train_cap: int = DEFAULT_TRAIN_CAP) -> Dictionary:
	var units: Dictionary[Variant, Variant] = {}
	for i in battle.players.size():
		var entry = battle.players[i]
		var template_id: int = int(entry.get("id", 0)) if entry is Dictionary else int(entry)
		var slot: int = i + 2
		if template_id > 0:
			var template: Character = unit_templates.get(template_id)
			if template == null:
				push_warning("build_units: no unit template %d (battle %d)" % [template_id, battle.id])
				continue
			var level: int = resolve_level(_level_entry(battle.players_levels, i), save.level, train_cap)
			units[slot] = CombatUnit.from_character(template, level, difficulty, slot)
		elif template_id < 0:
			var party_id: int = Party.deployed_party_id(save, template_id)
			if party_id > 0:
				var companion: CombatUnit = Party.build_companion_unit(save, party_id, unit_templates, slot)
				if companion != null:
					units[slot] = companion
	units[BattleRunner.PLAYER_SLOT] = CombatUnit.from_player_save(save, BattleRunner.PLAYER_SLOT)
	return units


# "X" -> player level - 2, "Z" -> player level + 5, both clamped to
# [1, train_cap]; numeric levels pass through (minimum 1).
static func resolve_level(raw_level, player_level: int, train_cap: int) -> int:
	if raw_level is String:
		var level: int
		if raw_level == "X":
			level = player_level - 2
		elif raw_level == "Z":
			level = player_level + 5
		else:
			return 1
		return clamp(level, 1, train_cap)
	return max(int(raw_level), 1)


static func _level_entry(levels: Array, index: int):
	return levels[index] if index < levels.size() else 1
