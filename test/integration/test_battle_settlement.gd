# Every test here settles a battle from resources/battles through a real
# runner on the real roster, with the outcome set before any half-turn is
# played. Achievements go to a file of this test's own. A run that does not use
# `uv run gut` shares the real user://, and this file keeps it off the real ones.
extends GutTest

const ACHIEVEMENTS_FILE: String = "user://test_battle_settlement_achievements.cfg"


func before_each():
	_remove_achievements_file()


func after_each():
	_remove_achievements_file()


func _remove_achievements_file() -> void:
	if FileAccess.file_exists(ACHIEVEMENTS_FILE):
		DirAccess.remove_absolute(ACHIEVEMENTS_FILE)


# A runner set up on the roster the battle scene would build for this save.
func _runner(battle_id: int, save: PlayerSave, pick: Dictionary) -> BattleRunner:
	var battle: BattleFight = BattleSetup.load_battle(battle_id)
	var train_cap: int = int(pick.get("train_cap", BattleSetup.DEFAULT_TRAIN_CAP))
	var units: Dictionary = BattleSetup.build_units(battle, save, UnitManagerAuto.units_by_id, save.difficulty, train_cap)
	var runner := BattleRunner.new()
	runner.setup(
		units, battle, MoveManagerAuto.moves_by_id, BuffManagerAuto.buffs_by_id,
		BuffManagerAuto.buffs_by_internal_name, TalentTree.get_passive_buff_names(save)
	)
	return runner


func _settle(battle_id: int, save: PlayerSave, outcome: BattleRunner.Outcome, pick: Dictionary) -> BattleSettlement:
	var runner := _runner(battle_id, save, pick)
	runner.win_condition = outcome
	return BattleSettlement.settle(runner, save, pick, ACHIEVEMENTS_FILE)


# Presses the zone's story orb the way the hub does and returns the pick
# ZoneManager hands the battle scene.
func _story_pick(save: PlayerSave, zone: int) -> Dictionary:
	var previous_zone: int = ZoneManager.current_zone
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.current_zone = zone
	var pick: Dictionary = ZoneManager.request_story_fight()
	ZoneManager.pending_battle = {}
	ZoneManager.current_zone = previous_zone
	ZoneManager.auto_start_battles = true
	GameData.current_save = null
	return pick


# The first win of 109, zone 1's boss, queues CS_CUT2 and sends the player to
# the zone map once it ends (frame_219/DoAction.as:32-40).
func test_a_story_win_of_109_moves_zone_1_on_and_queues_cs_cut2():
	var save := PlayerSave.new_game("Settle109")
	save.quest_progress[1] = 9
	var settlement := _settle(109, save, BattleRunner.Outcome.WIN, {"is_story_progress": true})
	assert_eq(settlement.outcome, BattleRunner.Outcome.WIN)
	assert_false(settlement.game_over, "a win goes on")
	assert_eq(ZoneProgression.quest_progress(save, 1), 10, "zone 1 is past its boss")
	assert_eq(settlement.cutscene, "CS_CUT2")
	assert_eq(settlement.goto_scene, "overMap")


# Battle 100 has no chance table and one guaranteed pull from its rare pool of
# Guard's Leggings and Guard's Grip (frame_201/DoAction.as:247-254).
func test_a_win_rolls_the_battles_drops():
	var settlement := _settle(100, PlayerSave.new_game("SettleDrops"), BattleRunner.Outcome.WIN, {})
	assert_eq(settlement.drops.size(), 1, "one pull")
	assert_true(settlement.drops.all(func(item_id): return item_id in [300, 301]), "from the rare pool")


# A defeat and a draw both end the game. The original sends a draw on to
# loseCombat (frame_241/DoAction.as:1-2), which throws the game in memory away
# (frame_41/DoAction_2.as:7), so the lost fight pays nothing and moves nothing.
func test_a_loss_or_a_draw_ends_the_game_and_pays_nothing():
	for outcome in [BattleRunner.Outcome.LOSS, BattleRunner.Outcome.DRAW]:
		var save := PlayerSave.new_game("SettleLoss")
		save.quest_progress[1] = 9
		var settlement := _settle(109, save, outcome, {"is_story_progress": true})
		assert_eq(settlement.outcome, outcome)
		assert_true(settlement.game_over, "outcome %d ends the game" % outcome)
		assert_eq(save.euro, 0.0, "it pays nothing")
		assert_eq(save.experience, 0.0, "and gives no XP")
		assert_eq(save.party_exp[1], 0.0, "to Veradux either")
		assert_eq(ZoneProgression.quest_progress(save, 1), 9, "zone 1 stays at its boss")
		assert_eq(settlement.cutscene, "", "no cutscene is queued")
		assert_false(Achievements.load_unlocked(ACHIEVEMENTS_FILE)[0], "and The Tape stays locked")


# The battle scene settles only once the runner is over, so settling a battle
# still in progress is a caller's mistake, which is reported and changes
# nothing.
func test_settling_a_battle_still_in_progress_changes_nothing():
	var save := PlayerSave.new_game("SettleOngoing")
	save.quest_progress[1] = 9
	var settlement := _settle(109, save, BattleRunner.Outcome.ONGOING, {"is_story_progress": true})
	assert_push_error("isn't over")
	assert_eq(settlement.outcome, BattleRunner.Outcome.ONGOING)
	assert_false(settlement.game_over, "the game goes on")
	assert_eq(ZoneProgression.quest_progress(save, 1), 9, "zone 1 stays at its boss")
	assert_eq(save.euro, 0.0, "and nothing is paid")


# The first win of 109 earns The Tape (DefineSprite_3142/frame_9/DoAction_2.as,
# lines 1-5). awardAch only shows its banner for an achievement the player
# doesn't hold yet (frame_46/DoAction_2.as:3-9), so a second save's first win
# of 109 reports nothing new.
func test_a_win_reports_only_the_achievements_it_newly_unlocked():
	var first := PlayerSave.new_game("SettleTape")
	first.quest_progress[1] = 9
	var settlement := _settle(109, first, BattleRunner.Outcome.WIN, {"is_story_progress": true})
	assert_eq(Array(settlement.achievements_unlocked), [Achievements.NAMES.find("The Tape")], "The Tape")
	assert_true(Achievements.load_unlocked(ACHIEVEMENTS_FILE)[0], "kept in the test's own file")
	var second := PlayerSave.new_game("SettleTapeAgain")
	second.quest_progress[1] = 9
	settlement = _settle(109, second, BattleRunner.Outcome.WIN, {"is_story_progress": true})
	assert_eq(Array(settlement.achievements_unlocked), [], "the second save's win unlocks nothing new")


# Replaying a beaten boss from a zones 1 to 5 story orb counts as training
# (DefineButton2_3188 on(press), line 9), and Predator, for the first Heroic
# win of 212, needs a save that never trained
# (DefineSprite_3142/frame_9/DoAction_2.as:24-31).
func test_a_boss_replay_counts_as_training_and_forfeits_predator():
	var save := PlayerSave.new_game("SettleReplay")
	save.difficulty = CombatUnit.Difficulty.HARD
	save.quest_progress[1] = 10
	var replay: Dictionary = _story_pick(save, 1)
	assert_eq(replay.get("battle_id"), 109, "the beaten zone 1 orb replays Felicity")
	var settlement := _settle(109, save, BattleRunner.Outcome.WIN, replay)
	assert_eq(ZoneProgression.quest_progress(save, 1), 10, "the replay moves nothing")
	assert_eq(settlement.cutscene, "", "queues no cutscene")
	assert_eq(Array(settlement.achievements_unlocked), [], "earns nothing")
	assert_true(save.used_training, "and counts as training")

	save.quest_progress[2] = 12
	settlement = _settle(212, save, BattleRunner.Outcome.WIN, _story_pick(save, 2))
	assert_eq(Array(settlement.achievements_unlocked), [], "so the first win of 212 earns no Predator")

	var untrained := PlayerSave.new_game("SettleNoReplay")
	untrained.difficulty = CombatUnit.Difficulty.HARD
	untrained.quest_progress[1] = 10
	untrained.quest_progress[2] = 12
	settlement = _settle(212, untrained, BattleRunner.Outcome.WIN, _story_pick(untrained, 2))
	assert_eq(Array(settlement.achievements_unlocked), [Achievements.NAMES.find("Predator")], "while a save that never replayed earns it")


# A win of battle 109 pays 36, because the original averages Felicity's level 7
# with the level 1 of both companion markers, Roald's included though he hasn't
# joined yet. Paying for Felicity alone would give 130.
func test_victory_money_counts_the_companion_markers():
	var save := PlayerSave.new_game("SettleMoney")
	var settlement := _settle(109, save, BattleRunner.Outcome.WIN, {"is_story_progress": false, "train_cap": 9})
	assert_eq(settlement.money_gained, 36, "round(0.7 * respecValue((7 + 1 + 1) / 3))")
	assert_eq(save.euro, 36.0, "and the save holds it")


# A training fight's "X" levels are the player's level - 2 clamped to the
# zone's trainFightCap (frame_42/DoAction_14.as:56-67), and the money averages
# the clamped levels (lines 86-92). At level 20 in zone 1, whose cap is 9,
# training fight 1000 pays over 9, 1 and 9 instead of 18, 1 and 18.
func test_a_training_win_pays_over_levels_clamped_to_the_zones_cap():
	var save := PlayerSave.new_game("SettleCap")
	save.level = 20
	Leveling.compute_stats(save)
	var settlement := _settle(1000, save, BattleRunner.Outcome.WIN, {"is_story_progress": false, "train_cap": 9})
	assert_eq(settlement.money_gained, 112, "round(0.7 * respecValue((9 + 1 + 9) / 3)), where the uncapped levels pay 303")


# Black Magic goes to the first win of 308 on Challenging or Heroic when no
# companion spawned (DefineSprite_3142/frame_9/DoAction_2.as:7-15), which
# krinAddNewUnit records in AchVal2 (frame_42/DoAction_14.as:190). The win
# with Veradux comes first, because the second would find Black Magic already
# unlocked either way.
func test_black_magic_goes_to_a_first_308_win_no_companion_fought():
	var with_veradux := _zone_3_boss_save("SettleWithVeradux")
	var settlement := _settle(308, with_veradux, BattleRunner.Outcome.WIN, {"is_story_progress": true})
	assert_eq(Array(settlement.achievements_unlocked), [], "no Black Magic for a win Veradux fought")
	var alone := _zone_3_boss_save("SettleAlone")
	alone.party_deployed = [0, 0]
	settlement = _settle(308, alone, BattleRunner.Outcome.WIN, {"is_story_progress": true})
	assert_eq(Array(settlement.achievements_unlocked), [Achievements.NAMES.find("Black Magic")], "but one for a win with nobody deployed")


func _zone_3_boss_save(save_name: String) -> PlayerSave:
	var save := PlayerSave.new_game(save_name)
	save.difficulty = CombatUnit.Difficulty.NORMAL
	save.section_in = 3
	save.quest_progress[3] = 8
	return save


# Battle 508 places the Mayor, Felicity as a guest and the ZPCI Ambassador
# ([69, 71, 72, 0, 0]) and no companion marker, so no companion spawns, and the
# original's victory screen hides both companion bars
# (DefineSprite_3142/frame_9/PlaceObject3_3002_1111 and _1154,
# onClipEvent(load), lines 2-6).
func test_a_win_of_508_pays_no_companion_xp():
	var save := PlayerSave.new_game("Settle508")
	var settlement := _settle(508, save, BattleRunner.Outcome.WIN, {"is_story_progress": false})
	assert_almost_eq(settlement.xp_gained, 270.0, 0.001, "Sonny earns expWorkOut(22, 1), the level gap capped at 3x")
	assert_eq(settlement.levels_gained, 2, "which fills his bar twice")
	assert_eq(Array(settlement.fighting_party), [], "no companion fought")
	assert_eq(save.party_exp, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "so none earned XP")
	assert_eq(save.party_levels, [0, 1, 11, 22, 12, 12], "or a level")


# Training fight 1000 has only the first marker ([5, -2, 5, 0, 0]), so Veradux,
# deployed first, fights, and Roald, deployed second, stays home although he
# has joined. Roald is level 1 here because at his starting level 11 the level
# gap leaves him no XP from level 1 enemies anyway.
func test_a_win_of_1000_pays_only_the_companion_deployed_first():
	var save := PlayerSave.new_game("Settle1000")
	save.party_roster = [0, 1, 2, -1, -1, -1]
	save.party_levels[2] = 1
	var settlement := _settle(1000, save, BattleRunner.Outcome.WIN, {"is_story_progress": false, "train_cap": 9})
	assert_eq(Array(settlement.fighting_party), [1], "only Veradux fought")
	assert_almost_eq(save.party_exp[1], 90.0, 0.001, "and earned expWorkOut(1, 1) against two level 1 Prison Guards")
	assert_eq(save.party_exp[2], 0.0, "Roald earned nothing")


# Nothing takes a companion back out of friendlySlotsFFTT when it dies, so the
# original pays a fallen companion's bar like a standing one's.
func test_a_companion_who_died_still_earns_xp():
	var save := PlayerSave.new_game("SettleFallen")
	var runner := _runner(100, save, {})
	var veradux: CombatUnit = runner.units[3]
	veradux.life_n = 0.0
	veradux.active = false
	runner.win_condition = BattleRunner.Outcome.WIN
	var settlement := BattleSettlement.settle(runner, save, {}, ACHIEVEMENTS_FILE)
	assert_eq(Array(settlement.fighting_party), [1], "Veradux fought")
	assert_almost_eq(save.party_exp[1], 90.0, 0.001, "and earned expWorkOut(1, 1) though he fell")


func _heroic_clear(player_class: int) -> PlayerSave:
	var clear := PlayerSave.new_game("AllStar%d" % player_class, player_class)
	clear.difficulty = CombatUnit.Difficulty.HARD
	clear.quest_progress[5] = 14
	return clear


# The victory screen runs checkIfAllStar after every win
# (DefineSprite_3142/frame_9/DoAction_2.as:64-67). It scans the four slots and
# the live game. The original's live branch reads Krin.data.Class, which nothing
# assigns (frame_42/DoAction_20.as:34-44), so the port counts the live game
# whatever it has saved (docs/adr/0005-fix-original-bugs-keep-quirks.md).
func test_all_star_goes_to_a_win_that_completes_the_three_classes_with_the_live_game():
	var live := _heroic_clear(2)
	var others: Array = [_heroic_clear(0), _heroic_clear(1)]
	var runner := _runner(1000, live, {})
	runner.win_condition = BattleRunner.Outcome.WIN
	var settlement := BattleSettlement.settle(runner, live, {}, ACHIEVEMENTS_FILE, others)
	assert_has(settlement.achievements_unlocked, Achievements.NAMES.find("All Star"), "any win awards it, a training fight included")
	var short_runner := _runner(1000, live, {})
	short_runner.win_condition = BattleRunner.Outcome.WIN
	DirAccess.remove_absolute(ACHIEVEMENTS_FILE)
	settlement = BattleSettlement.settle(short_runner, live, {}, ACHIEVEMENTS_FILE, [_heroic_clear(0)])
	assert_does_not_have(settlement.achievements_unlocked, Achievements.NAMES.find("All Star"), "two classes are not enough")
