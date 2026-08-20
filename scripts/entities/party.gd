# party.gd
# The story companion system, ported from the full SWF script export
# (2026-07-18): roster seeds and per-member stats from frame_42/DoAction_17
# (ClassStats/LevelStats/StatSets1-5/PerSets/DefSets/friendArray/friendArrayX),
# the companion battle-unit stat model from krinAddNewUnit's companion branch
# (frame42/sonny2_createNewBattle.txt), roster joins from the post-battle
# frame_219, and companion XP from the victory-screen bars (DefineSprite_3142
# frame_9).
#
# Terms: a PARTY ID (1-5) identifies a companion (0 is the player).
# save.party_roster (AS3 friendArray) lists joined member ids by roster slot,
# -1 = empty. save.party_deployed (AS3 friendArrayX) holds the two party ids
# taken into battle - battle definitions reference them via the -2/-1 slot
# markers (players[] entries).
#
# No autoload references - unit templates come in as a parameter.
class_name Party
extends RefCounted

const PLAYER_PARTY_ID: int = 0

enum AggressionStance { PHALANX, DEFENSIVE, TACTICAL, AGGRESSIVE, RELENTLESS }

# agModeAr (sonny2_agression.txt): stance columns 0-4 = Phalanx / Defensive /
# Tactical / Aggressive / Relentless. Rows: [Aggression, LifeBoundary1,
# LifeBoundary2, FocusAggression, FocusRegenLimit]. The battle stance
# buttons pick the column; PlayerSave.ag_mode persists it (default
# AggressionStance.TACTICAL).
const AGGRESSION_PRESETS: Array = [
	[0.0, 95.0, 0.0, 0.0, 30.0],     # Phalanx
	[30.0, 90.0, 65.0, 30.0, 30.0],  # Defensive
	[50.0, 75.0, 35.0, 70.0, 30.0],  # Tactical
	[70.0, 40.0, 15.0, 15.0, 5.0],   # Aggressive
	[90.0, 2.0, 1.0, 100.0, 5.0],    # Relentless
]
const AGGRESSION_NAMES: Array[String] = ["Phalanx", "Defensive", "Tactical", "Aggressive", "Relentless"]
# agModeAr column 2 ("Tactical") - the default companion tuning.
const COMPANION_AI_TUNING: Array[float] = [50.0, 75.0, 35.0, 70.0, 30.0]

# Static companion definitions (frame_42/DoAction_17). stat_allocated is the
# StatSets seed [life, strength, magic, speed, focus]; per/def_allocated are
# elemental point seeds in ELEMENT_ORDER; equipment is cosmetic until the
# equip system lands. Companion allocations never change - only level/exp do.
const COMPANIONS: Dictionary = {
	1: {
		"name": "Veradux",
		"unit_id": 4,
		"starting_level": 1,
		"stat_allocated": [9, 12, 11, 9, 0],
		"per_allocated": [0, 0, 0, 0, 82, 0, 0, 0],
		"def_allocated": [0, 0, 0, 0, 0, 0, 0, 0],
		"equipment": [38, 34, 36, 35, 37, 39, 0],
		"model": ["MODEL1", "TWO", "TWO", "M"],
	},
	2: {
		"name": "Roald",
		"unit_id": 32,
		"starting_level": 11,
		"stat_allocated": [22, 42, 13, 37, 0],
		"per_allocated": [0, 0, 0, 89, 0, 0, 0, 89],
		"def_allocated": [0, 0, 0, 0, 0, 0, 0, 0],
		"equipment": [382, 328, 327, 329, 326, 523, 0],
		"model": ["MODEL1", "MANTAT", "THURMAN", "M"],
	},
	3: {
		"name": "Felicity",
		"unit_id": 71,
		"starting_level": 22,
		"stat_allocated": [0, 84, 0, 105, 25],
		"per_allocated": [397, 0, 0, 0, 0, 0, 0, 0],
		"def_allocated": [0, 0, 0, 0, 0, 0, 0, 0],
		"equipment": [627, 628, 629, 630, 631, 651, 652],
		"model": ["MODEL4", "FEL", "", "F"],  # hair is baked into F_SHEAD_FEL
	},
	4: {
		"name": "Teco",
		"unit_id": 2,
		"starting_level": 12,
		"stat_allocated": [0, 0, 0, 0, 0],
		"per_allocated": [0, 0, 0, 0, 0, 0, 0, 0],
		"def_allocated": [0, 0, 0, 0, 0, 0, 0, 0],
		"equipment": [0, 0, 0, 0, 0, 0, 0],
		"model": ["MODEL1", "MANTAT", "THURMAN", "M"],
	},
	5: {
		"name": "Catelin",
		"unit_id": 4,
		"starting_level": 12,
		"stat_allocated": [0, 0, 0, 0, 0],
		"per_allocated": [0, 0, 0, 0, 0, 0, 0, 0],
		"def_allocated": [0, 0, 0, 0, 0, 0, 0, 0],
		"equipment": [0, 0, 0, 0, 0, 0, 0],
		"model": ["MODEL4", "SIX", "THURMAN", "F"],
	},
}


# Fresh-save party state: player + Veradux in the roster, Veradux and the
# (not yet joined) Roald pre-selected for the two battle slots.
static func initialize_save(save: PlayerSave) -> void:
	save.party_roster = [0, 1, -1, -1, -1, -1]
	save.party_deployed = [1, 2]
	save.party_levels = [0, 0, 0, 0, 0, 0]
	save.party_exp = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for party_id in COMPANIONS:
		save.party_levels[party_id] = COMPANIONS[party_id]["starting_level"]


# frame_219 roster rules, checked after every battle: Roald joins once zone 2
# story progress passes 1, Felicity once zone 5 story progress passes 4.
# Returns true when the roster changed.
static func update_roster_after_battle(save: PlayerSave) -> bool:
	var before: Array = save.party_roster.duplicate()
	if _quest_progress(save, 2) > 1:
		save.party_roster = [0, 1, 2, -1, -1, -1]
	if _quest_progress(save, 5) > 4:
		save.party_roster = [0, 1, 2, 3, -1, -1]
	return save.party_roster != before


static func is_in_roster(save: PlayerSave, party_id: int) -> bool:
	return save.party_roster.has(party_id)


# The party id fighting in a battle-definition companion slot. Markers are
# the players[] values -2 (first deployed slot) and -1 (second). Returns -1
# when that deployment points at a companion who hasn't joined yet.
static func deployed_party_id(save: PlayerSave, slot_marker: int) -> int:
	var deploy_index: int = slot_marker + 2  # -2 -> 0, -1 -> 1 (friendArrayX[players + 2])
	if deploy_index < 0 or deploy_index >= save.party_deployed.size():
		return -1
	var party_id: int = int(save.party_deployed[deploy_index])
	if party_id <= 0 or not is_in_roster(save, party_id):
		return -1
	return party_id


static func get_ag_mode(save: PlayerSave, party_id: int) -> AggressionStance:
	if party_id < 0 or party_id >= save.ag_mode.size():
		return AggressionStance.TACTICAL
	return clampi(int(save.ag_mode[party_id]), 0, AGGRESSION_PRESETS.size() - 1) as AggressionStance


static func set_ag_mode(save: PlayerSave, party_id: int, mode: AggressionStance) -> void:
	while save.ag_mode.size() < 6:
		save.ag_mode.append(AggressionStance.TACTICAL)
	if party_id >= 0 and party_id < save.ag_mode.size():
		save.ag_mode[party_id] = clampi(mode, 0, AGGRESSION_PRESETS.size() - 1)


static func apply_aggression_mode(unit: CombatUnit, mode: AggressionStance) -> void:
	var preset: Array = AGGRESSION_PRESETS[clampi(mode, 0, AGGRESSION_PRESETS.size() - 1)]
	unit.aggression = preset[0]
	unit.life_boundary_1 = preset[1]
	unit.life_boundary_2 = preset[2]
	unit.focus_aggression = preset[3]
	unit.focus_regen_limit = preset[4]


# Companion battle unit - krinAddNewUnit's companion branch. Same stat model
# as the player (allocation + class curve; PER/DEF = allocation + 100 +
# 15/level) with one faithful quirk: Lightning DEFENSE uses 5 per level, not
# 15 (original's line does `LevelStats * 5` for that one element).
static func build_companion_unit(save: PlayerSave, party_id: int, unit_templates: Dictionary, slot: int) -> CombatUnit:
	var definition: Dictionary = COMPANIONS.get(party_id, {})
	if definition.is_empty():
		return null
	var template: Character = unit_templates.get(definition["unit_id"])
	if template == null:
		push_warning("build_companion_unit: no unit template %d" % definition["unit_id"])
		return null
	var level: int = int(save.party_levels[party_id])
	var allocated: Array = definition["stat_allocated"]

	var unit: CombatUnit = CombatUnit.new()
	unit.player_id = slot
	unit.player_name = definition["name"]
	unit.plevel = level
	unit.base_life = round(allocated[0] + ceil(CombatUnit.get_stat(template.vitality, level, true))) * CombatUnit.VIT_LIFE_FACTOR
	unit.base_strength = round(allocated[1] + ceil(CombatUnit.get_stat(template.strength, level, true)))
	unit.base_magic = round(allocated[2] + ceil(CombatUnit.get_stat(template.magic, level, true)))
	unit.base_speed = round(allocated[3] + ceil(CombatUnit.get_stat(template.speed, level, true)))
	unit.base_focus = round(allocated[4] + ceil(template.focus))

	for i in CombatUnit.ELEMENT_ORDER.size():
		unit.base_per[i] = 100.0 + level * 15.0 + definition["per_allocated"][i]
		var defense_per_level: float = 5.0 if i == CombatUnit.Element.LIGHTNING else 15.0
		unit.base_def[i] = 100.0 + level * defense_per_level + definition["def_allocated"][i]

	var voice = template.visuals.get("voice", {})
	unit.voice_hit = voice.get("hit", [])
	unit.voice_die = voice.get("die", "")
	unit.model = definition["model"].duplicate()
	unit.equipment_ids = definition["equipment"].duplicate()

	unit.ai_enabled = true
	apply_aggression_mode(unit, get_ag_mode(save, party_id))
	unit.move_pool_attack = template.moves.get("attack", []).duplicate()
	unit.move_pool_defense = template.moves.get("defense", []).duplicate()
	unit.move_pool_absolute = []
	for absolute_entry in template.moves.get("absolute", []):
		if absolute_entry is Dictionary:
			unit.move_pool_absolute.append({"id": int(absolute_entry["id"]), "phase": int(absolute_entry["phase"])})
		else:
			unit.move_pool_absolute.append({"id": int(absolute_entry), "phase": 0})
	unit.cooldowns_attack = CombatUnit._zero_array(unit.move_pool_attack.size())
	unit.cooldowns_defense = CombatUnit._zero_array(unit.move_pool_defense.size())
	unit.cooldowns_absolute = CombatUnit._zero_array(unit.move_pool_absolute.size())

	unit.change_array = CombatUnit._zero_array(12)
	unit.change_array_ep = CombatUnit._zero_array(8)
	unit.change_array_ep2 = CombatUnit._zero_array(8)
	unit.change_array_ed = CombatUnit._zero_array(8)
	unit.change_array_ed2 = CombatUnit._zero_array(8)
	unit.dot_ticker_array = CombatUnit._zero_array(10)
	unit.buff_slots = []
	for i in CombatUnit.MAX_BUFF_LIMIT:
		unit.buff_slots.append({"cd": 0, "buff_id": -1, "buff_value": 0.0, "shield_buff_value": 0.0})

	unit.life_u = unit.base_life
	unit.life_n = unit.base_life
	unit.focus_u = unit.base_focus
	unit.focus_n = unit.base_focus
	unit.apply_changes()
	return unit


# Companion XP: same 0-100 bar and level-30 cap as the player, but no skill
# or stat point grants (victory-screen companion bars). Returns levels gained.
static func grant_companion_experience(save: PlayerSave, party_id: int, xp_amount: float) -> int:
	if party_id <= 0 or party_id >= save.party_levels.size():
		return 0
	var levels_gained: int = 0
	if save.party_levels[party_id] < Leveling.MAX_LEVEL:
		save.party_exp[party_id] += xp_amount
		while save.party_exp[party_id] >= Leveling.EXP_PER_LEVEL and save.party_levels[party_id] < Leveling.MAX_LEVEL:
			save.party_exp[party_id] -= Leveling.EXP_PER_LEVEL
			save.party_levels[party_id] += 1
			levels_gained += 1
	return levels_gained


static func _quest_progress(save: PlayerSave, zone: int) -> int:
	if zone < 0 or zone >= save.quest_progress.size():
		return 0
	var value = save.quest_progress[zone]
	return int(value) if value is int or value is float else 0
