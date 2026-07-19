# Unit tests for Leveling (level-up point grants, stat allocation, respec) -
# expected values hand-verified against the AS3 formulas (givePoints/
# assignPointsStart/respec button, see leveling.gd header).
extends GutTest

var save: PlayerSave


func before_each():
	save = PlayerSave.new_game("Test", 0)


func test_new_game_auto_spread_class_0():
	# free points at level 1 = floor(getStat(40, 1, true)) = 19, spread by
	# Bio ratios [7,14,4,15]/40 -> floors [3,6,1,7]. givePoints leaves the
	# 0.158 grant fraction in point_residue, the split fractions add 1.9999..
	# more, so TWO leftover points distribute (speed then strength, largest
	# splits first) and 0.158 stays - all 19 points spent.
	assert_eq(save.stat_allocated, [3, 7, 1, 8, 0], "life/strength/magic/speed/focus allocation")
	assert_almost_eq(save.point_residue, 0.158, 0.001)
	assert_eq(save.life, 7.0, "3 allocated + ceil(3.35) class base")
	assert_eq(save.strength, 14.0, "7 + ceil(6.71)")
	assert_eq(save.magic, 3.0, "1 + ceil(1.92)")
	assert_eq(save.speed, 16.0, "8 + ceil(7.19)")
	assert_eq(save.focus, 100.0)
	assert_eq(save.stat_points, 0, "starting grant is auto-spent")


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


func test_respec_daily_limit_and_cost_gate():
	save.level = 1
	save.euro = 1000.0
	for i in 5:
		assert_true(Leveling.respec(save, [0, 0, 0, 0, 0], "2026-07-18"), "respec %d of 5" % (i + 1))
	assert_false(Leveling.respec(save, [0, 0, 0, 0, 0], "2026-07-18"), "6th same-day respec blocked")
	assert_true(Leveling.respec(save, [0, 0, 0, 0, 0], "2026-07-19"), "new day resets the limit")
	save.euro = 0.0
	assert_false(Leveling.respec(save, [0, 0, 0, 0, 0], "2026-07-19"), "cannot afford")
