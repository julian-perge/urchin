# player_save.gd
# Single-player save data. Field set is scoped down from the original AS3
# saveArray1/saveArray2 (frame42/sonny2_savingdata_pvpcode.txt, cross-checked
# against resources/example_save_file.json) - dropped everything that only
# exists for the arena/friend-battle system (friendArray, friendArrayX,
# ClassStats, LevelStats, equipArray1-5, PerSets0-5, DefSets0-5, StatSets0-5,
# ExpSets, skillAdderMatrixOld), since PvP/arena is out of scope for this
# project. agMode (companion aggression stance, 0-4, default 2 Tactical)
# came back with the battle stance buttons - see ag_mode below.
# (buffAdderMatrix was originally on the dropped list by mistake - it's the
# passive-talent store, required in single player. Re-added 2026-07-18 with
# the talent system, see talent_tree.gd.)
class_name PlayerSave
extends Resource

@export var name_user: String = "Sonny"
@export var euro: float = 0.0
@export var player_class: int = 0
@export var level: int = 1  # cap 30
@export var experience: float = 0.0  # 0-100 percentage bar; 100 -> level up (see Leveling)
@export var skill_points: int = 0
@export var stat_points: int = 0
@export var point_residue: float = 0.0  # fractional leftover from stat-point rounding, see Leveling.points_for_level_up()

# Allocated stat points (AS3 StatSets0): [life, strength, magic, speed,
# focus] - see Leveling.Stat. Base stats below are CACHED derived values
# (allocation + class level curve), recomputed by Leveling.compute_stats();
# the original persists both the same way (StatSets0 + STRENGTH/... in the
# save arrays).
@export var stat_allocated: Array = []
@export var strength: float = 0.0
@export var magic: float = 0.0
@export var speed: float = 0.0
@export var focus: float = 0.0
@export var life: float = 0.0
# Element name -> allocated piercing/defense points (AS3 PerSets0/DefSets0).
# Derived battle values are allocation + 100 + 15 * level
# (CombatUnit.from_player_save). Raised by gear, not level-up points.
@export var per: Dictionary = {}
@export var def: Dictionary = {}

# Respec daily limit (AS3 respecSet/lastDay2): 5 per day.
@export var respec_set: int = 5
@export var last_respec_day: String = ""

# Current zone (Krin.sectionIn, 1-based) and story progress per zone
# (Krin.questProgress; slot 0 holds the original's "EMPTY" placeholder).
# Managed by ZoneProgression. progress_level_on is persisted for save
# compatibility (frame41 seeds it to 2); its consumer hasn't been located.
@export var section_in: int = 1
@export var progress_level_on: int = 2
@export var quest_progress: Array = []

# Story companion state - managed by Party (scripts/entities/party.gd):
# roster slots (AS3 friendArray, value = party id or -1), the two deployed
# party ids (friendArrayX), and per-member level/XP-bar (LevelStats/ExpSets;
# index 0 is the player's slot, unused - the player's own fields above are
# authoritative).
@export var party_roster: Array = []
@export var party_deployed: Array = []
@export var party_levels: Array = []
@export var party_exp: Array = []
# Companion aggression stance (AS3 agMode), indexed by party id 1-5:
# 0 Phalanx / 1 Defensive / 2 Tactical (default) / 3 Aggressive /
# 4 Relentless. Index 0 (the player) is unused.
@export var ag_mode: Array = [2, 2, 2, 2, 2, 2]

@export var item_array: Array = []  # 37-slot inventory, item ids
@export var equip_array: Array = []  # 7-slot equipped item ids

# Talent state - all managed by TalentTree (scripts/entities/talent_tree.gd):
# rank per node / granted move id per active node / granted passive buff
# internal_name per passive node / 8-slot equipped action bar / known-move
# pool / per-move equip limits (unused - recompute from Ability
# hotbar_slot_limit instead; the original persisted it but real save dumps
# show it empty).
@export var talent_main_array: Array = []
@export var skill_adder_matrix: Array = []
@export var buff_adder_matrix: Array = []
@export var move_matrix: Array = []
@export var move_matrix2: Array = []
@export var move_matrix2_limit: Array = []

@export var used_training: bool = false
@export var difficulty: int = 1  # CombatUnit.Difficulty
@export var sound: bool = true
@export var graphics: bool = true
@export var auto_saver: bool = true
@export var qual: String = "HIGH"
# New-game options screen: autosave on Proceed after victories.
@export var autosave: bool = true

static func new_game(player_name: String, new_player_class: int = 0) -> PlayerSave:
	var save = PlayerSave.new()
	save.name_user = player_name
	save.player_class = new_player_class
	save.skill_points = TalentTree.STARTING_SKILL_POINTS
	save.item_array = []
	for i in 37:
		save.item_array.append(0)
	save.equip_array = [0, 0, 0, 0, 0, 0, 0]
	for element in CombatUnit.ELEMENT_ORDER:
		save.per[element] = 0.0
		save.def[element] = 0.0
	save.section_in = 1
	save.quest_progress = ["EMPTY"]
	for i in 13:
		save.quest_progress.append(0)
	TalentTree.initialize_save(save)
	# The class-select buttons (DefineButton2_2735 and siblings) also put the
	# two starting moves ON the action bar - a fresh character must be able
	# to fight, not just Pass.
	var starting_moves: Array = TalentTree.STARTING_MOVES.get(save.player_class, [])
	for i in starting_moves.size():
		save.move_matrix[i] = starting_moves[i]
	Party.initialize_save(save)
	# Level-1 stat grant auto-spread across the class's ratio profile
	# (assignPointsStart), which also fills the cached base stats.
	save.stat_allocated = [0, 0, 0, 0, 0]
	Leveling.assign_points_start(save)
	return save
