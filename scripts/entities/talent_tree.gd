# talent_tree.gd
# Skill/talent tree data + point-spending rules, ported from loadTalents()
# (frame41/sonny2_setting_class_abilities_extra_globals.txt). One tree per
# playable class: 0 = Biological, 1 = Psychological, 2 = Hydraulic. 28 nodes
# each (the persisted arrays are 38 slots in the original; the extra slots were
# never used).
#
# Node semantics (verified against resources/example_save_file*.json, real
# captured save dumps from the same engine):
# - talent_main_array[i] = rank invested in node i (0..max_rank).
# - Active node (buff_family == ""): each rank grants move id
#   move_id + rank - 1. Move families are consecutive ids sharing one display
#   name (e.g. 100..103 all "Vicious Strike"). On rank-up the previous rank's
#   move id is REPLACED everywhere - the known-move pool (move_matrix2), the
#   equipped bar (move_matrix), and skill_adder_matrix[i] which tracks the
#   currently granted id.
# - Passive node (buff_family != ""): each rank sets buff_adder_matrix[i] to
#   buff_family + str(rank) (e.g. "SAVAGERY3"), a Buff internal_name. At battle
#   load the original pushes every nonzero buff_adder_matrix entry onto the
#   player unit's passive-buff list (updateStat_Player,
#   frame201_LOAD_BATTLE_SCENE) - use get_passive_buff_names() for that.
# - Next rank requires level >= level_min + level_scale * current_rank
#   ("Next Tier (Lvl. N)" tooltip) and every prerequisite node at rank >= 1.
#   ALL prerequisites required and each rank costs exactly 1 skill point -
#   both CONFIRMED from the actual learn-button code (DefineButton2_3096 in
#   the full SWF script export, 2026-07-18), which this learn() mirrors.
#
# No autoload references on purpose - keeps the class compilable from
# EditorScripts (same lesson as CombatUnit.tick_buffs).
class_name TalentTree
extends RefCounted

# Persisted array size in the original saveArray2 format.
const NODE_ARRAY_SIZE: int = 38
const NODES_PER_CLASS: int = 28
const SKILL_POINT_COST_PER_RANK: int = 1
# Krin.skillPoints starting value (preStartSkill, frame41).
const STARTING_SKILL_POINTS: int = 5

enum LearnResult {
	OK,
	NOT_ENOUGH_POINTS,  # TALENTERROR1
	MAX_RANK,           # TALENTERROR2
	LEVEL_TOO_LOW,      # TALENTERROR3
	MISSING_PREREQUISITE,  # TALENTERROR4
	INVALID_NODE,
}

# Original English error strings (frame1/sonny2_skills_english.txt).
const LEARN_RESULT_MESSAGES: Dictionary = {
	LearnResult.OK: "",
	LearnResult.NOT_ENOUGH_POINTS: "You do not have enough Ability Points.",
	LearnResult.MAX_RANK: "This Ability cannot be developed further.",
	LearnResult.LEVEL_TOO_LOW: "Your Level is not high enough.",
	LearnResult.MISSING_PREREQUISITE: "You don't have the required abilites to access this one.",
	LearnResult.INVALID_NODE: "Invalid talent node.",
}

# Krin.startSkill1/startSkill2 - the two moves every new character knows
# before spending any points.
const STARTING_MOVES: Dictionary[PlayerSave.PlayerClass, Array] = {
	PlayerSave.PlayerClass.BIOLOGICAL: [1, 6],        # Leading Strike, Destroy
	PlayerSave.PlayerClass.PSYCHOLOGICAL: [478, 479],  # Dark Infusion, Corruption
	PlayerSave.PlayerClass.HYDRAULIC: [276, 277],      # Vapour Cannon, Slam
}

# Node fields: move_id (base move id, 0 for passives), level_min, level_scale,
# max_rank (AS3 TIER), prerequisites (node indices, AS3 PRESKILL, [-1] -> []),
# buff_family (AS3 BUFFNAME, "" for actives).
const TREES: Dictionary[PlayerSave.PlayerClass, Array] = {
	PlayerSave.PlayerClass.BIOLOGICAL: [
		{"move_id": 100, "level_min": 1, "level_scale": 0, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 0, "level_min": 1, "level_scale": 0, "max_rank": 4, "prerequisites": [], "buff_family": "INTEGRITY"},
		{"move_id": 126, "level_min": 1, "level_scale": 0, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 133, "level_min": 1, "level_scale": 0, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 104, "level_min": 1, "level_scale": 1, "max_rank": 2, "prerequisites": [0], "buff_family": ""},
		{"move_id": 120, "level_min": 1, "level_scale": 1, "max_rank": 3, "prerequisites": [1], "buff_family": ""},
		{"move_id": 130, "level_min": 1, "level_scale": 1, "max_rank": 3, "prerequisites": [2], "buff_family": ""},
		{"move_id": 138, "level_min": 1, "level_scale": 1, "max_rank": 4, "prerequisites": [3], "buff_family": ""},
		{"move_id": 110, "level_min": 1, "level_scale": 1, "max_rank": 2, "prerequisites": [4], "buff_family": ""},
		{"move_id": 106, "level_min": 1, "level_scale": 1, "max_rank": 2, "prerequisites": [4], "buff_family": ""},
		{"move_id": 123, "level_min": 1, "level_scale": 1, "max_rank": 3, "prerequisites": [5], "buff_family": ""},
		{"move_id": 142, "level_min": 1, "level_scale": 1, "max_rank": 4, "prerequisites": [7], "buff_family": ""},
		{"move_id": 0, "level_min": 4, "level_scale": 1, "max_rank": 4, "prerequisites": [], "buff_family": "SAVAGERY"},
		{"move_id": 112, "level_min": 4, "level_scale": 1, "max_rank": 4, "prerequisites": [9], "buff_family": ""},
		{"move_id": 146, "level_min": 4, "level_scale": 1, "max_rank": 4, "prerequisites": [11], "buff_family": ""},
		{"move_id": 154, "level_min": 4, "level_scale": 1, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 116, "level_min": 6, "level_scale": 1, "max_rank": 1, "prerequisites": [12], "buff_family": ""},
		{"move_id": 167, "level_min": 6, "level_scale": 1, "max_rank": 3, "prerequisites": [], "buff_family": ""},
		{"move_id": 150, "level_min": 6, "level_scale": 1, "max_rank": 4, "prerequisites": [14], "buff_family": ""},
		{"move_id": 158, "level_min": 6, "level_scale": 1, "max_rank": 1, "prerequisites": [15], "buff_family": ""},
		{"move_id": 117, "level_min": 8, "level_scale": 1, "max_rank": 3, "prerequisites": [16], "buff_family": ""},
		{"move_id": 159, "level_min": 8, "level_scale": 1, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 0, "level_min": 8, "level_scale": 1, "max_rank": 4, "prerequisites": [], "buff_family": "MARATHON"},
		{"move_id": 0, "level_min": 8, "level_scale": 1, "max_rank": 4, "prerequisites": [19], "buff_family": "ACIDIC"},
		{"move_id": 163, "level_min": 10, "level_scale": 1, "max_rank": 4, "prerequisites": [21], "buff_family": ""},
		{"move_id": 0, "level_min": 10, "level_scale": 1, "max_rank": 3, "prerequisites": [], "buff_family": "EVOLUTION"},
		{"move_id": 173, "level_min": 10, "level_scale": 1, "max_rank": 1, "prerequisites": [], "buff_family": ""},
		{"move_id": 170, "level_min": 10, "level_scale": 1, "max_rank": 3, "prerequisites": [22], "buff_family": ""},
	],
	PlayerSave.PlayerClass.PSYCHOLOGICAL: [
		{"move_id": 400, "level_min": 1, "level_scale": 0, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 404, "level_min": 1, "level_scale": 0, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 408, "level_min": 1, "level_scale": 0, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 412, "level_min": 1, "level_scale": 0, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 416, "level_min": 1, "level_scale": 1, "max_rank": 4, "prerequisites": [0], "buff_family": ""},
		{"move_id": 420, "level_min": 1, "level_scale": 1, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 424, "level_min": 1, "level_scale": 1, "max_rank": 2, "prerequisites": [], "buff_family": ""},
		{"move_id": 426, "level_min": 1, "level_scale": 1, "max_rank": 4, "prerequisites": [3], "buff_family": ""},
		{"move_id": 430, "level_min": 1, "level_scale": 1, "max_rank": 4, "prerequisites": [4], "buff_family": ""},
		{"move_id": 434, "level_min": 1, "level_scale": 1, "max_rank": 3, "prerequisites": [], "buff_family": ""},
		{"move_id": 475, "level_min": 1, "level_scale": 9, "max_rank": 2, "prerequisites": [5, 7], "buff_family": ""},
		{"move_id": 463, "level_min": 1, "level_scale": 1, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 0, "level_min": 4, "level_scale": 1, "max_rank": 5, "prerequisites": [8], "buff_family": "TENACITY"},
		{"move_id": 437, "level_min": 4, "level_scale": 1, "max_rank": 4, "prerequisites": [9], "buff_family": ""},
		{"move_id": 0, "level_min": 4, "level_scale": 1, "max_rank": 1, "prerequisites": [10], "buff_family": "OVERDRIVE"},
		{"move_id": 441, "level_min": 4, "level_scale": 1, "max_rank": 3, "prerequisites": [], "buff_family": ""},
		{"move_id": 448, "level_min": 6, "level_scale": 1, "max_rank": 4, "prerequisites": [13], "buff_family": ""},
		{"move_id": 0, "level_min": 6, "level_scale": 1, "max_rank": 5, "prerequisites": [], "buff_family": "CHARGEDBLOOD"},
		{"move_id": 444, "level_min": 6, "level_scale": 1, "max_rank": 4, "prerequisites": [13], "buff_family": ""},
		{"move_id": 452, "level_min": 6, "level_scale": 1, "max_rank": 4, "prerequisites": [14], "buff_family": ""},
		{"move_id": 477, "level_min": 8, "level_scale": 1, "max_rank": 1, "prerequisites": [16], "buff_family": ""},
		{"move_id": 456, "level_min": 8, "level_scale": 1, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 460, "level_min": 8, "level_scale": 1, "max_rank": 2, "prerequisites": [], "buff_family": ""},
		{"move_id": 462, "level_min": 8, "level_scale": 1, "max_rank": 1, "prerequisites": [19], "buff_family": ""},
		{"move_id": 470, "level_min": 10, "level_scale": 1, "max_rank": 3, "prerequisites": [], "buff_family": ""},
		{"move_id": 467, "level_min": 10, "level_scale": 1, "max_rank": 1, "prerequisites": [21], "buff_family": ""},
		{"move_id": 468, "level_min": 10, "level_scale": 1, "max_rank": 2, "prerequisites": [22], "buff_family": ""},
		{"move_id": 473, "level_min": 10, "level_scale": 1, "max_rank": 2, "prerequisites": [], "buff_family": ""},
	],
	PlayerSave.PlayerClass.HYDRAULIC: [
		{"move_id": 200, "level_min": 1, "level_scale": 0, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 204, "level_min": 1, "level_scale": 0, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 253, "level_min": 1, "level_scale": 0, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 257, "level_min": 1, "level_scale": 0, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 208, "level_min": 1, "level_scale": 1, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 228, "level_min": 1, "level_scale": 1, "max_rank": 3, "prerequisites": [], "buff_family": ""},
		{"move_id": 0, "level_min": 1, "level_scale": 1, "max_rank": 1, "prerequisites": [2], "buff_family": "HOTBLOOD"},
		{"move_id": 261, "level_min": 1, "level_scale": 1, "max_rank": 3, "prerequisites": [], "buff_family": ""},
		{"move_id": 212, "level_min": 1, "level_scale": 1, "max_rank": 4, "prerequisites": [4], "buff_family": ""},
		{"move_id": 231, "level_min": 1, "level_scale": 1, "max_rank": 4, "prerequisites": [5], "buff_family": ""},
		{"move_id": 235, "level_min": 1, "level_scale": 1, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 264, "level_min": 1, "level_scale": 1, "max_rank": 4, "prerequisites": [6, 7], "buff_family": ""},
		{"move_id": 216, "level_min": 4, "level_scale": 1, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 239, "level_min": 4, "level_scale": 1, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 243, "level_min": 4, "level_scale": 1, "max_rank": 4, "prerequisites": [9, 10], "buff_family": ""},
		{"move_id": 268, "level_min": 4, "level_scale": 1, "max_rank": 4, "prerequisites": [11], "buff_family": ""},
		{"move_id": 220, "level_min": 6, "level_scale": 1, "max_rank": 4, "prerequisites": [13], "buff_family": ""},
		{"move_id": 247, "level_min": 6, "level_scale": 1, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 0, "level_min": 6, "level_scale": 1, "max_rank": 5, "prerequisites": [14], "buff_family": "STIFFUPPER"},
		{"move_id": 272, "level_min": 6, "level_scale": 1, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 0, "level_min": 8, "level_scale": 1, "max_rank": 5, "prerequisites": [16], "buff_family": "CRYSTALICE"},
		{"move_id": 0, "level_min": 8, "level_scale": 1, "max_rank": 4, "prerequisites": [], "buff_family": "COLDNEU"},
		{"move_id": 0, "level_min": 8, "level_scale": 1, "max_rank": 4, "prerequisites": [], "buff_family": "WARMNEU"},
		{"move_id": 0, "level_min": 8, "level_scale": 1, "max_rank": 4, "prerequisites": [19], "buff_family": "LASTINGPAIN"},
		{"move_id": 224, "level_min": 10, "level_scale": 1, "max_rank": 4, "prerequisites": [], "buff_family": ""},
		{"move_id": 251, "level_min": 10, "level_scale": 1, "max_rank": 1, "prerequisites": [21], "buff_family": ""},
		{"move_id": 252, "level_min": 10, "level_scale": 1, "max_rank": 1, "prerequisites": [22], "buff_family": ""},
		{"move_id": 173, "level_min": 10, "level_scale": 1, "max_rank": 1, "prerequisites": [], "buff_family": ""},
	],
}


static func get_nodes(player_class: PlayerSave.PlayerClass) -> Array:
	return TREES.get(player_class, [])


static func get_talent_node(player_class: PlayerSave.PlayerClass, node_index: int) -> Dictionary:
	var nodes: Array = get_nodes(player_class)
	if node_index < 0 or node_index >= nodes.size():
		return {}
	return nodes[node_index]


static func is_passive(node: Dictionary) -> bool:
	return node.get("buff_family", "") != ""


# Level required to buy the NEXT rank when current_rank ranks are already
# invested ("Next Tier (Lvl. N)").
static func required_level(node: Dictionary, current_rank: int) -> int:
	return node["level_min"] + node["level_scale"] * current_rank


# Move id granted at a given rank of an active node.
static func granted_move_id(node: Dictionary, rank: int) -> int:
	return node["move_id"] + rank - 1


# Buff internal_name granted at a given rank of a passive node
# (resolve via BuffManager.get_buff_by_name).
static func granted_buff_name(node: Dictionary, rank: int) -> String:
	return node["buff_family"] + str(rank)


static func get_rank(save: PlayerSave, node_index: int) -> int:
	if node_index < 0 or node_index >= save.talent_main_array.size():
		return 0
	return int(save.talent_main_array[node_index])


# Whether a specific prerequisite node has been learned at all (rank >= 1) -
# used to color the tree's connector lines (gold = learned, gray = not).
static func is_prerequisite_learned(save: PlayerSave, prereq_index: int) -> bool:
	return get_rank(save, prereq_index) >= 1


# Validation only - mirrors TALENTERROR1-4 in original check order
# (points, max tier, level, prerequisites).
static func can_learn(save: PlayerSave, node_index: int) -> LearnResult:
	var node: Dictionary = get_talent_node(save.player_class, node_index)
	if node.is_empty():
		return LearnResult.INVALID_NODE
	if save.skill_points < SKILL_POINT_COST_PER_RANK:
		return LearnResult.NOT_ENOUGH_POINTS
	var rank: int = get_rank(save, node_index)
	if rank >= node["max_rank"]:
		return LearnResult.MAX_RANK
	if save.level < required_level(node, rank):
		return LearnResult.LEVEL_TOO_LOW
	for prerequisite_index in node["prerequisites"]:
		if get_rank(save, prerequisite_index) < 1:
			return LearnResult.MISSING_PREREQUISITE
	return LearnResult.OK


# Spend one skill point on node_index. Mutates save. Returns LearnResult.OK on
# success, otherwise the failure reason (save untouched).
static func learn(save: PlayerSave, node_index: int) -> LearnResult:
	var result = can_learn(save, node_index)
	if result != LearnResult.OK:
		return result
	_ensure_talent_arrays(save)
	var node: Dictionary = get_talent_node(save.player_class, node_index)
	var new_rank: int = get_rank(save, node_index) + 1
	save.skill_points -= SKILL_POINT_COST_PER_RANK
	save.talent_main_array[node_index] = new_rank
	if is_passive(node):
		save.buff_adder_matrix[node_index] = granted_buff_name(node, new_rank)
	else:
		# Source-faithful (talent learn button, DefineButton2_3096): upgrade
		# the equipped bar in place, then REBUILD the known pool from
		# skill_adder_matrix in node-index order.
		var new_move_id: int = granted_move_id(node, new_rank)
		var old_move_id: int = int(save.skill_adder_matrix[node_index])
		if old_move_id != 0:
			_replace_move_id(save.move_matrix, old_move_id, new_move_id)
		save.skill_adder_matrix[node_index] = new_move_id
		_rebuild_known_moves(save)
	return LearnResult.OK


# moveMatrix2 = [startSkill1, startSkill2] + every nonzero skill_adder_matrix
# entry, in node-index order.
static func _rebuild_known_moves(save: PlayerSave) -> void:
	save.move_matrix2 = TalentTree.STARTING_MOVES.get(save.player_class, []).duplicate()
	for granted in save.skill_adder_matrix:
		if int(granted) > 0:
			save.move_matrix2.append(int(granted))


# Passive buff internal_names to apply to the player's CombatUnit at battle
# load - the updateStat_Player buffAdderMatrix -> passiveBuffs port.
static func get_passive_buff_names(save: PlayerSave) -> Array:
	var names: Array[Variant] = []
	for entry in save.buff_adder_matrix:
		if entry is String and entry != "":
			names.append(entry)
	return names


# Move ids the character currently knows (starting moves + highest learned
# rank per active node) - the move_matrix2 pool.
static func get_known_move_ids(save: PlayerSave) -> Array:
	var ids: Array[Variant] = []
	for entry in save.move_matrix2:
		if int(entry) != 0:
			ids.append(int(entry))
	return ids


# Reset save's talent state to a fresh character of its player_class:
# zeroed 38-slot arrays, empty 8-slot action bar, starting-move pool.
static func initialize_save(save: PlayerSave) -> void:
	save.talent_main_array = _zero_array(NODE_ARRAY_SIZE)
	save.skill_adder_matrix = _zero_array(NODE_ARRAY_SIZE)
	save.buff_adder_matrix = _zero_array(NODE_ARRAY_SIZE)
	save.move_matrix = _zero_array(8)
	save.move_matrix2 = STARTING_MOVES.get(save.player_class, []).duplicate()
	save.move_matrix2_limit = []


# Pad talent arrays on saves created before all fields existed (e.g. saves
# from before buff_adder_matrix was added). Preserves existing entries.
static func _ensure_talent_arrays(save: PlayerSave) -> void:
	for talent_array in [save.talent_main_array, save.skill_adder_matrix, save.buff_adder_matrix]:
		while talent_array.size() < NODE_ARRAY_SIZE:
			talent_array.append(0)
	while save.move_matrix.size() < 8:
		save.move_matrix.append(0)


static func _replace_move_id(move_ids: Array, old_move_id: int, new_move_id: int) -> void:
	for i in move_ids.size():
		if int(move_ids[i]) == old_move_id:
			move_ids[i] = new_move_id


static func _zero_array(size: int) -> Array:
	var result: Array[Variant] = []
	result.resize(size)
	result.fill(0)
	return result
