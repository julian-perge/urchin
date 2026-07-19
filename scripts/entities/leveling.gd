# leveling.gd
# Player leveling, stat-point allocation, and respec - ported from the full
# SWF script export (2026-07-18):
# - givePoints()/assignPointsStart(): frame42 (sonny2_extra_stat_calcs.txt)
# - level-up on the victory screen: DefineSprite_3142/frame_9 player XP bar
#   clip - exp is a 0-100 percentage bar; each fill grants +1 skill point and
#   givePoints(level) stat points; level cap 30
# - respec button: DefineButton2_3179 on(release) - cost
#   round(0.7 * respecValue(level)), full talent/bar/stat reset, equipment
#   stat bonuses re-applied, 5 respecs per day
# - player stat model: menu screens compute stat = allocated points
#   (StatSets0) + ceil(getStat(class_base_ratio, level, true)); piercing and
#   defense = allocation (PerSets0/DefSets0) + 100 + 15 * level
#
# No autoload references (same rule as TalentTree) - operates on PlayerSave.
class_name Leveling
extends RefCounted

const MAX_LEVEL: int = 30
const EXP_PER_LEVEL: float = 100.0  # exp is a 0-100 percentage bar
const RESPECS_PER_DAY: int = 5
const STAT_POINT_RATIO: float = 40.0  # givePoints feeds getStat(40, ...)

# stat_allocated indices (AS3 StatSets0 order).
enum Stat { LIFE = 0, STRENGTH = 1, MAGIC = 2, SPEED = 3, FOCUS = 4 }

# Class base-stat ratios = the class's own unit template (KNU 1/2/3:
# Bio/Psycho/Hydro) [vitality, strength, magic, speed, focus]. Focus is a
# flat value, not a getStat ratio.
const CLASS_BASE_RATIOS: Dictionary = {
	0: [7.0, 14.0, 4.0, 15.0, 100.0],
	1: [7.0, 3.0, 20.0, 10.0, 100.0],
	2: [15.0, 10.0, 8.0, 7.0, 100.0],
}


# respecValue(lvl) = 10 * lvl^1.5 (frame42/sonny2_createNewItemKrin.txt).
# Doubles as the base of the victory money formula.
static func respec_value(level: float) -> float:
	return 10.0 * pow(level, 1.5)


static func respec_cost(level: int) -> int:
	return int(round(0.7000000000000001 * respec_value(level)))


# givePoints(level, false): stat points granted by reaching `new_level`.
# Fractional points accumulate in save.point_residue and carry over (the
# original's i_e handling).
static func points_for_level_up(save: PlayerSave, new_level: int) -> int:
	var delta = (
		CombatUnit.get_stat(STAT_POINT_RATIO, new_level, true)
		- CombatUnit.get_stat(STAT_POINT_RATIO, new_level - 1, true)
	)
	var points = int(floor(delta))
	save.point_residue += delta - points
	if save.point_residue >= 1:
		save.point_residue -= 1
		points += 1
	return points


# givePoints(level, true): the full stat-point grant for a level, used by
# respec and the new-game auto-spread. Resets the residue first.
static func points_for_respec(save: PlayerSave, level: int) -> int:
	var total = CombatUnit.get_stat(STAT_POINT_RATIO, level, true)
	var points = int(floor(total))
	save.point_residue = total - points
	if save.point_residue >= 1:
		save.point_residue -= 1
		points += 1
	return points


# Recompute the cached base stats (saveArray1's STRENGTH/MAGIC/SPEED/LIFE/
# FOCUS) from allocation + class curve. Call after anything that changes
# level or stat_allocated.
static func compute_stats(save: PlayerSave) -> void:
	var ratios: Array = CLASS_BASE_RATIOS.get(save.player_class, CLASS_BASE_RATIOS[0])
	save.life = save.stat_allocated[Stat.LIFE] + ceil(CombatUnit.get_stat(ratios[Stat.LIFE], save.level, true))
	save.strength = save.stat_allocated[Stat.STRENGTH] + ceil(CombatUnit.get_stat(ratios[Stat.STRENGTH], save.level, true))
	save.magic = save.stat_allocated[Stat.MAGIC] + ceil(CombatUnit.get_stat(ratios[Stat.MAGIC], save.level, true))
	save.speed = save.stat_allocated[Stat.SPEED] + ceil(CombatUnit.get_stat(ratios[Stat.SPEED], save.level, true))
	save.focus = save.stat_allocated[Stat.FOCUS] + ceil(ratios[Stat.FOCUS])


# assignPointsStart(): new-game auto-spread of the level-1 stat grant across
# life/strength/magic/speed, proportional to the class's base ratios.
# Faithful to the original's float behavior: the fractional residues can sum
# to just under a whole point (doubles), leaving ~1.0 in point_residue and
# one fewer point spent - Flash did the same.
static func assign_points_start(save: PlayerSave) -> void:
	var free_points = points_for_respec(save, 1)
	var ratios: Array = CLASS_BASE_RATIOS.get(save.player_class, CLASS_BASE_RATIOS[0])
	var split = []
	for i in 4:
		split.append({"val": ratios[i] / STAT_POINT_RATIO * free_points, "id": i})
	for entry in split:
		save.point_residue += entry["val"] - floor(entry["val"])
		save.stat_allocated[entry["id"]] += int(floor(entry["val"]))
	split.sort_custom(func(a, b):
		if a["val"] == b["val"]:
			return a["id"] < b["id"]
		return a["val"] > b["val"])
	var cycle = 0
	while save.point_residue >= 1:
		save.stat_allocated[split[cycle]["id"]] += 1
		cycle += 1
		save.point_residue -= 1
	compute_stats(save)


# One stat point -> +1 allocation (the stat-screen plus buttons).
static func spend_stat_point(save: PlayerSave, stat_index: int) -> bool:
	if save.stat_points <= 0 or stat_index < 0 or stat_index >= save.stat_allocated.size():
		return false
	save.stat_points -= 1
	save.stat_allocated[stat_index] += 1
	compute_stats(save)
	return true


# The victory-screen XP bar: exp += xp on a 0-100 bar; each fill levels up
# (+1 skill point, +givePoints stat points). No XP accumulates at the cap.
# Returns {levels_gained, new_level, stat_points_granted}.
static func grant_experience(save: PlayerSave, xp_amount: float) -> Dictionary:
	var levels_gained = 0
	var stat_points_granted = 0
	if save.level < MAX_LEVEL:
		save.experience += xp_amount
		while save.experience >= EXP_PER_LEVEL and save.level < MAX_LEVEL:
			save.experience -= EXP_PER_LEVEL
			save.level += 1
			levels_gained += 1
			save.skill_points += 1
			var granted = points_for_level_up(save, save.level)
			save.stat_points += granted
			stat_points_granted += granted
	if levels_gained > 0:
		compute_stats(save)
	return {
		"levels_gained": levels_gained,
		"new_level": save.level,
		"stat_points_granted": stat_points_granted,
	}


# Full respec (DefineButton2_3179): costs round(0.7 * respecValue(level)),
# limited to 5 per day. Resets talents/action bar/allocation; skill points
# back to level - 1 + the 5 starting points; stat points to the full grant.
# equipment_stat_bonuses = the summed statUpdater values of equipped items
# (StatSets0 re-seed) - pass zeros until the equip system exists. `today`
# is injectable for tests; defaults to the system date.
static func respec(save: PlayerSave, equipment_stat_bonuses: Array = [0, 0, 0, 0, 0], today: String = "") -> bool:
	if today == "":
		today = Time.get_date_string_from_system()
	if save.last_respec_day != today:
		save.respec_set = RESPECS_PER_DAY
	var cost = respec_cost(save.level)
	if save.euro < cost or save.respec_set <= 0:
		return false
	save.euro -= cost
	save.respec_set -= 1
	save.last_respec_day = today

	save.skill_points = save.level - 1 + TalentTree.STARTING_SKILL_POINTS
	save.stat_points = points_for_respec(save, save.level)
	TalentTree.initialize_save(save)
	# Respec puts the two starting moves back ON the action bar (new_game
	# only puts them in the known pool).
	var starting_moves: Array = TalentTree.STARTING_MOVES.get(save.player_class, [])
	for i in starting_moves.size():
		save.move_matrix[i] = starting_moves[i]
	save.stat_allocated = []
	for i in 5:
		save.stat_allocated.append(int(equipment_stat_bonuses[i]) if i < equipment_stat_bonuses.size() else 0)
	compute_stats(save)
	return true
