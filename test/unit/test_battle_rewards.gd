# Unit tests for BattleRewards (drops, money, experience) - expected values
# hand-verified against the AS3 formulas (victory screen money, expWorkOut,
# LOAD_BATTLE_SCENE drop rolls - see battle_rewards.gd header).
extends GutTest

const BattleFightScript = preload("res://scripts/battle/battle_fight.gd")


func test_money_gain():
	assert_eq(BattleRewards.money_gain([1]), 7, "round(0.7 * 10 * 1^1.5)")
	assert_eq(BattleRewards.money_gain([3, 3]), 36, "average level 3")
	assert_eq(BattleRewards.money_gain([5]), 78)
	assert_eq(BattleRewards.money_gain([]), 0, "no spawned units, no money")


func test_experience_gain():
	assert_almost_eq(BattleRewards.experience_gain(1.0, 1), 90.0, 0.001, "equal levels at 1")
	assert_almost_eq(BattleRewards.experience_gain(5.0, 1), 126.0, 0.001, "higher enemies boost xp")
	assert_almost_eq(BattleRewards.experience_gain(1.0, 10), 3.614, 0.001, "outleveled enemies give little")
	assert_almost_eq(
		BattleRewards.experience_gain(50.0, 1), 270.0, 0.001,
		"difference multiplier clamps at 3x"
	)
	assert_almost_eq(
		BattleRewards.experience_gain(1.0, 30), 0.0, 0.001,
		"difference multiplier clamps at 0 when far above the enemies"
	)


func test_roll_drops_chances_and_pools():
	var battle = _make_battle()
	battle.item_drops = [
		{"chance": 100, "item": {"id": 307, "name": "Always"}},
		{"chance": 0, "item": {"id": 999, "name": "Never"}},
	]
	# item_rare pools are typed Array[Dictionary] exports - append, don't
	# assign untyped literals.
	for id in [301, 302, 303]:
		battle.item_rare.append({"id": id})
	battle.item_rare_dropper = 2
	battle.item_rare2.append({"id": 500})
	battle.item_rare_dropper2 = 1
	for run in 20:
		var drops = BattleRewards.roll_drops(battle)
		assert_eq(drops.size(), 4, "1 guaranteed chance drop + 2 rare pulls + 1 rare2 pull")
		assert_eq(drops[0], 307, "100% chance always drops")
		assert_does_not_have(drops, 999, "0% chance never drops")
		assert_has([301, 302, 303], drops[1], "rare pull from pool 1")
		assert_has([301, 302, 303], drops[2], "rare pull from pool 1")
		assert_eq(drops[3], 500, "rare2 pull")


func test_roll_drops_caps_at_display_slots():
	var battle = _make_battle()
	battle.item_rare.append({"id": 1})
	battle.item_rare_dropper = 20
	var drops = BattleRewards.roll_drops(battle)
	assert_eq(drops.size(), BattleRewards.DROP_SLOTS)


func test_unit_levels_from_slots():
	var save = PlayerSave.new_game("Test", 0)
	var player = CombatUnit.from_player_save(save)
	var units = {1: player}
	assert_eq(BattleRewards.unit_levels_from_slots(units, [2, 4, 6]), [], "empty enemy slots")
	assert_eq(BattleRewards.unit_levels_from_slots(units, [1]), [1])


func test_apply_victory():
	var save = PlayerSave.new_game("Test", 0)
	save.point_residue = 0.0
	var result = BattleRewards.apply_victory(save, [5, 5], [5, 5])
	assert_eq(result["money_gained"], 78, "average spawned level 5")
	assert_eq(save.euro, 78.0)
	assert_almost_eq(result["xp_gained"], 126.0, 0.001)
	assert_eq(result["levels_gained"], 1, "126 xp fills the bar once")
	assert_eq(save.level, 2)
	assert_almost_eq(save.experience, 26.0, 0.001)


# The typed Array[Dictionary] exports (item_rare/2/3) default to empty typed
# arrays - do not assign untyped [] literals to them, append entries instead.
func _make_battle() -> BattleFight:
	var battle = Resource.new()
	battle.set_script(BattleFightScript)
	battle.item_drops = []
	return battle
