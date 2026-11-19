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
# What the original calls the player in battle and on every menu, whatever the
# save is named: the battle unit's name (frame_201/DoAction.as:201) and
# Krin.NameSets[0] (frame_42/DoAction_17.as:45), which no save carries. The
# typed name, PlayerSave.name_user, only shows on the main menu's slot list.
const PLAYER_NAME: String = "Sonny"

enum AggressionStance { PHALANX, DEFENSIVE, TACTICAL, AGGRESSIVE, RELENTLESS }

# agModeAr (sonny2_agression.txt): stance columns 0-4 = Phalanx / Defensive /
# Tactical / Aggressive / Relentless. Rows: [Aggression, LifeBoundary1,
# LifeBoundary2, FocusAggression, FocusRegenLimit]. Every companion starts
# each battle on Tactical, and a battle stance button applies its column to
# that battle's unit only, so a pick never carries into the next battle. The
# original does the same (frame_42/DoAction_14.as:208-213 and
# DefineButton2_3289 on(press), lines 9-14).
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

# Static companion definitions (frame_42/DoAction_17). unit_id is the
# Companion's ClassStats entry, which the original uses both as the unit
# template (KNU) and as the class that an item's class requirement checks.
# stat_allocated is the StatSets seed [life, strength, magic, speed, focus];
# per/def_allocated are the PerSets/DefSets seeds in ELEMENT_ORDER. equipment
# is the seed gear (equipArray1-5), the gear a save without party_equip starts
# from. The original adds and removes each item's bonuses on top of the seeds
# as the player equips the Companion (DefineButton2_2981 on(press)), and
# companion_wearer gives the same result from the saved gear. The seeds are
# not always the seed gear's sum: Felicity's StatSets3 Speed is 105 while her
# gear gives 126, so the original shows Speed 171 with her gear and 45 without
# it at level 22, 21 below the gear alone (#195).
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
	save.party_equip = []
	ensure_party_equip(save)


# Gives every Companion the seed gear from COMPANIONS when the save has no
# party_equip, which is the case for a save written before #195. Entry 0
# stays empty, because the player's gear is in equip_array.
static func ensure_party_equip(save: PlayerSave) -> void:
	if not save.party_equip.is_empty():
		return
	save.party_equip = [[]]
	for party_id in COMPANIONS:
		while save.party_equip.size() <= party_id:
			save.party_equip.append([])
		save.party_equip[party_id] = COMPANIONS[party_id]["equipment"].duplicate()


# The Companion's 7-slot equip array in the save, equipArray1-5 in the
# original. A change to it is a change to the save.
static func companion_equip(save: PlayerSave, party_id: int) -> Array:
	ensure_party_equip(save)
	return save.party_equip[party_id]


# The Companion as an Equipment.Wearer: their saved gear, level and class.
# The bonus pools are the original's StatSets, PerSets and DefSets after the
# player swapped the seed gear for the saved gear: the seeds, less the seed
# gear's bonuses, plus the saved gear's bonuses.
static func companion_wearer(save: PlayerSave, party_id: int, items_by_id: Dictionary) -> Equipment.Wearer:
	var definition: Dictionary = COMPANIONS[party_id]
	var wearer := Equipment.Wearer.new(companion_equip(save, party_id), int(save.party_levels[party_id]), definition["unit_id"])
	wearer.stat_allocated = definition["stat_allocated"].duplicate()
	for element in CombatUnit.ELEMENT_ORDER.size():
		wearer.per[element] = float(definition["per_allocated"][element])
		wearer.def[element] = float(definition["def_allocated"][element])
	for item_id in definition["equipment"]:
		Equipment.apply_item_stats(wearer, items_by_id.get(int(item_id)), -1)
	for item_id in wearer.equip:
		Equipment.apply_item_stats(wearer, items_by_id.get(int(item_id)), 1)
	return wearer


# The five stats [life, strength, magic, speed, focus] that the Inventory
# shows for a Companion: gear bonuses plus the template's level curve
# (updateStatus, DefineSprite_3142/frame_1/DoAction.as:93-97). Life is the
# Vitality value, before the battle unit multiplies it.
static func companion_stats(wearer: Equipment.Wearer, template: Character) -> Array:
	var allocated: Array = wearer.stat_allocated
	return [
		allocated[0] + ceil(CombatUnit.get_stat(template.vitality, wearer.level, true)),
		allocated[1] + ceil(CombatUnit.get_stat(template.strength, wearer.level, true)),
		allocated[2] + ceil(CombatUnit.get_stat(template.magic, wearer.level, true)),
		allocated[3] + ceil(CombatUnit.get_stat(template.speed, wearer.level, true)),
		allocated[4] + ceil(template.focus),
	]


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


# The slot of the Deployed pair that the next added Companion takes, when the
# Inventory opens. The original starts at 0, then moves to 1 when slot 1 holds a
# 0, and to 1 again when both do (DefineSprite_3142/frame_1/DoAction.as:210-219).
static func initial_deploy_picker(deployed: Array) -> int:
	if int(deployed[1]) == 0:
		return 1
	return 0


# The shift-click on a party face, DefineButton2_2895 on(press) lines 2-29. A
# Companion who is in the Deployed pair leaves a 0 in their slot, and the picker
# moves to that slot. Any other Companion takes the picker's slot, which holds a
# member or a 0, and the picker moves to the other slot. The player's face
# ignores the click. Returns the new picker.
static func toggle_deployed(save: PlayerSave, party_id: int, picker: int) -> int:
	if party_id == PLAYER_PARTY_ID:
		return picker
	var slot: int = save.party_deployed.find(party_id)
	if slot >= 0:
		save.party_deployed[slot] = 0
		return slot
	save.party_deployed[picker] = party_id
	return 1 - picker


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
# 15 (original's line does `LevelStats * 5` for that one element). The
# allocations come from the Companion's saved gear (companion_wearer).
static func build_companion_unit(save: PlayerSave, party_id: int, unit_templates: Dictionary, items_by_id: Dictionary, slot: int) -> CombatUnit:
	var definition: Dictionary = COMPANIONS.get(party_id, {})
	if definition.is_empty():
		return null
	var template: Character = unit_templates.get(definition["unit_id"])
	if template == null:
		push_warning("build_companion_unit: no unit template %d" % definition["unit_id"])
		return null
	var wearer: Equipment.Wearer = companion_wearer(save, party_id, items_by_id)
	var level: int = wearer.level
	var stats: Array = companion_stats(wearer, template)

	var unit: CombatUnit = CombatUnit.new()
	unit.player_id = slot
	unit.player_name = definition["name"]
	unit.plevel = level
	unit.base_life = round(stats[0]) * CombatUnit.VIT_LIFE_FACTOR
	unit.base_strength = round(stats[1])
	unit.base_magic = round(stats[2])
	unit.base_speed = round(stats[3])
	unit.base_focus = round(stats[4])

	for i in CombatUnit.ELEMENT_ORDER.size():
		unit.base_per[i] = 100.0 + level * 15.0 + wearer.per[i]
		var defense_per_level: float = 5.0 if i == CombatUnit.Element.LIGHTNING else 15.0
		unit.base_def[i] = 100.0 + level * defense_per_level + wearer.def[i]

	var voice = template.visuals.get("voice", {})
	unit.voice_hit = voice.get("hit", [])
	unit.voice_die = voice.get("die", "")
	unit.model = definition["model"].duplicate()
	unit.equipment_ids = wearer.equip.duplicate()

	unit.ai_enabled = true
	apply_aggression_mode(unit, AggressionStance.TACTICAL)
	unit.load_moves_from(template)
	unit.start_at_full()
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
