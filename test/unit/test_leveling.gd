# Unit tests for Leveling (level-up point grants, stat allocation, respec) -
# expected values hand-verified against the AS3 formulas (givePoints/
# assignPointsStart/respec button, see leveling.gd header).
extends GutTest

var save: PlayerSave


func before_each():
	save = PlayerSave.new_game("Test", 0)


func test_new_game_holds_only_the_starting_gear_bonuses():
	# The class buttons spread the 19 level-1 points, then
	# frame_180/DoAction.as:8 resets StatSets0 to the starting gear's bonuses,
	# so every class starts on [5, 6, 5, 3, 0] and keeps only the split's 0.158
	# residue. Each stat is that allocation plus
	# ceil(getStat(class ratio, 1, true)), the menu formula in
	# DefineButton2_3179 on(release) lines 47-50.
	var expected_stats: Dictionary[PlayerSave.PlayerClass, Array] = {
		PlayerSave.PlayerClass.BIOLOGICAL: [9.0, 13.0, 7.0, 11.0],
		PlayerSave.PlayerClass.PSYCHOLOGICAL: [9.0, 8.0, 15.0, 8.0],
		PlayerSave.PlayerClass.HYDRAULIC: [13.0, 11.0, 9.0, 7.0],
	}
	var previous_slot: int = GameData.current_slot
	var previous_save: PlayerSave = GameData.current_save
	for player_class in expected_stats:
		GameData.new_game(-1, "Test", player_class)
		var new_save: PlayerSave = GameData.current_save
		var label: String = PlayerSave.CLASS_NAMES[player_class]
		assert_eq(new_save.stat_allocated, [5, 6, 5, 3, 0], "%s allocation" % label)
		assert_eq(
			[new_save.life, new_save.strength, new_save.magic, new_save.speed],
			expected_stats[player_class],
			"%s life/strength/magic/speed" % label
		)
		assert_eq(new_save.stat_points, 0, "%s free stat points" % label)
		assert_almost_eq(new_save.point_residue, 0.158, 0.001, "%s point residue" % label)
	GameData.current_slot = previous_slot
	GameData.current_save = previous_save


func test_point_grant_consistency_across_30_levels():
	# Sum of level-up grants (2..30) plus the initial level-1 grant must
	# equal the full respec grant at 30 - the floor+residue-carry design
	# guarantees it.
	var fresh = PlayerSave.new_game("Sum", 0)
	fresh.point_residue = 0.0
	var initial = Leveling.points_for_respec(fresh, 1)
	var total = initial
	for level in range(2, 31):
		total += Leveling.points_for_level_up(fresh, level)
	var respec_save = PlayerSave.new_game("Respec", 0)
	assert_eq(initial, 19)
	assert_eq(total, Leveling.points_for_respec(respec_save, 30), "19 + level-ups == full grant")
	assert_eq(total, 192)


func test_grant_experience_levels_up_with_points():
	save.point_residue = 0.0
	var starting_skill_points = save.skill_points
	var result = Leveling.grant_experience(save, 250.0)
	assert_eq(result["levels_gained"], 2, "250 xp on the 0-100 bar = two levels")
	assert_eq(save.level, 3)
	assert_almost_eq(save.experience, 50.0, 0.001)
	assert_eq(save.skill_points, starting_skill_points + 2, "1 skill point per level")
	assert_eq(result["stat_points_granted"], 5, "grants at levels 2 and 3 (2 + 3)")
	assert_eq(save.stat_points, 5)


func test_no_experience_past_level_cap():
	save.level = Leveling.MAX_LEVEL
	save.experience = 40.0
	var result = Leveling.grant_experience(save, 500.0)
	assert_eq(result["levels_gained"], 0)
	assert_eq(save.level, 30)
	assert_almost_eq(save.experience, 40.0, 0.001, "no xp accumulates at the cap")


func test_spend_stat_point():
	save.stat_points = 2
	var speed_before = save.speed
	assert_true(Leveling.spend_stat_point(save, Leveling.Stat.SPEED))
	assert_eq(save.speed, speed_before + 1)
	assert_eq(save.stat_points, 1)
	assert_true(Leveling.spend_stat_point(save, Leveling.Stat.LIFE))
	assert_false(Leveling.spend_stat_point(save, Leveling.Stat.LIFE), "no points left")
	assert_false(Leveling.spend_stat_point(save, 9), "invalid index")


func test_respec_resets_everything():
	save.level = 5
	save.euro = 100.0
	save.skill_points = 10
	TalentTree.learn(save, 0)
	TalentTree.learn(save, 1)
	save.move_matrix[0] = 100
	assert_true(Leveling.respec(save, [0, 0, 0, 0, 0], "2026-07-18"))
	assert_eq(save.euro, 22.0, "cost round(0.7 * 10 * 5^1.5) = 78")
	assert_eq(save.skill_points, 9, "level - 1 + 5 starting points")
	assert_eq(save.stat_points, 28, "floor(getStat(40, 5, true)) = 28")
	assert_eq(TalentTree.get_rank(save, 0), 0, "talents zeroed")
	assert_eq(save.buff_adder_matrix[1], 0, "passives zeroed")
	assert_eq(save.move_matrix, [1, 6, 0, 0, 0, 0, 0, 0], "starting moves back ON the bar")
	assert_eq(save.move_matrix2, [1, 6], "known pool reset")
	assert_eq(save.stat_allocated, [0, 0, 0, 0, 0])
	assert_eq(save.respec_set, 4)


func test_respec_equipment_bonuses_reapplied():
	save.level = 5
	save.euro = 100.0
	assert_true(Leveling.respec(save, [2, 5, 0, 1, 0], "2026-07-18"))
	assert_eq(save.stat_allocated, [2, 5, 0, 1, 0], "gear statUpdater re-seeds the allocation")
	assert_eq(save.strength, 5 + ceil(CombatUnit.get_stat(14, 5, true)))


func test_respec_cost_gate():
	# The respec button checks that Euro covers
	# round(0.7 * respecValue(Level)), which is 78 at level 5
	# (DefineButton2_3179 on(release) line 6). A refused respec runs none of
	# lines 8-14, so it leaves the money, the day counter and its date alone.
	save.level = 5
	save.euro = 77.0
	save.respec_set = 3
	save.last_respec_day = "2026-07-18"
	assert_false(Leveling.respec(save, [0, 0, 0, 0, 0], "2026-07-19"), "one short of the 78 cost")
	assert_eq(save.euro, 77.0, "a refused respec costs nothing")
	assert_eq(save.respec_set, 3, "a refused respec leaves the counter alone")
	assert_eq(save.last_respec_day, "2026-07-18", "a refused respec leaves the date alone")
	save.euro = 78.0
	assert_true(Leveling.respec(save, [0, 0, 0, 0, 0], "2026-07-19"), "exactly the cost is enough")
	assert_eq(save.euro, 0.0)


func test_respec_has_no_daily_limit():
	# The respec button resets respecSet to 5 on a new day and takes one off
	# per respec, but never checks it (DefineButton2_3179 on(release) lines
	# 9-14), so a sixth respec in one day goes through and leaves it at -1.
	save.level = 1
	save.euro = 1000.0
	for i in 6:
		assert_true(Leveling.respec(save, [0, 0, 0, 0, 0], "2026-07-18"), "respec %d of 6 in one day" % (i + 1))
	assert_eq(save.euro, 958.0, "six respecs at round(0.7 * 10 * 1^1.5) = 7 each")
	assert_eq(save.respec_set, -1)
