# Integration test for the full zone-driven battle loop: story battle picked
# from progression -> battle .tres loaded -> roster built (player + deployed
# companion + enemies) -> fight runs to completion -> BattleSettlement settles
# the win, which advances quest progress and pays out rewards including
# companion XP.
extends GutTest

const MAX_HALF_TURNS = 300
# A settled win unlocks into a file of its own, so a run that does not use
# `uv run gut` (and so shares the real user://) never touches the real
# achievements.
const ACHIEVEMENTS_FILE: String = "user://test_zone_battle_flow_achievements.cfg"

var unit_templates: Dictionary = {}


func before_all():
	unit_templates = UnitManagerAuto.units_by_id


func test_battle_resources_load_by_id():
	var battle = BattleSetup.load_battle(100)
	assert_not_null(battle, "story battle 100 resource")
	assert_eq(battle.id, 100)
	assert_eq(battle.players.size(), 5)
	var training = BattleSetup.load_battle(1000)
	assert_not_null(training, "training battle 1000 resource")


func test_roster_build_places_player_companion_and_enemies():
	var save = PlayerSave.new_game("Flow", 0)
	var battle = BattleSetup.load_battle(100)  # players [5, -2, 0, -1, 0]
	var units = BattleSetup.build_units(battle, save, unit_templates, CombatUnit.Difficulty.HARD)
	assert_true(units.has(1), "player in slot 1")
	assert_false(units[1].ai_enabled, "player is human-controlled")
	assert_true(units.has(2), "Prison Guard enemy in slot 2")
	assert_eq(units[2].player_name, "Prison Guard")
	assert_true(units.has(3), "Veradux (deployed companion) in slot 3")
	assert_eq(units[3].player_name, "Veradux")
	assert_true(units[3].ai_enabled)
	assert_eq(units[3].life_boundary_1, 75.0, "companions use the Tactical AI preset")
	assert_false(units.has(5), "Roald deployed but not joined - slot stays empty")


func test_roster_records_where_each_unit_came_from():
	var save = PlayerSave.new_game("Flow", 0)
	var units = BattleSetup.build_units(BattleSetup.load_battle(100), save, unit_templates, CombatUnit.Difficulty.HARD)
	assert_eq(units[1].origin, CombatUnit.Origin.PLAYER, "slot 1 is the player")
	assert_eq(units[1].party_id, -1, "the player isn't a companion")
	assert_eq(units[2].origin, CombatUnit.Origin.ENEMY, "Prison Guard is an enemy")
	assert_eq(units[2].party_id, -1, "and has no party id")
	assert_eq(units[3].origin, CombatUnit.Origin.COMPANION, "Veradux is a companion")
	assert_eq(units[3].party_id, 1, "with party id 1")


# Battle 508 places unit template 71 on the player's team and battle 504 places
# the same template on the enemy's, so only the slot tells a guest from an enemy.
func test_roster_tells_a_guest_from_an_enemy_with_the_same_template():
	var save = PlayerSave.new_game("Flow", 0)
	var guest: CombatUnit = BattleSetup.build_units(BattleSetup.load_battle(508), save, unit_templates, CombatUnit.Difficulty.HARD)[3]
	var enemy: CombatUnit = BattleSetup.build_units(BattleSetup.load_battle(504), save, unit_templates, CombatUnit.Difficulty.HARD)[2]
	assert_eq(guest.player_name, "Felicity", "508's slot 3")
	assert_eq(enemy.player_name, "Felicity", "504's slot 2")
	assert_eq(guest.origin, CombatUnit.Origin.GUEST, "on the player's team the template is a guest")
	assert_eq(enemy.origin, CombatUnit.Origin.ENEMY, "on the other team the template is an enemy")
	assert_eq(guest.party_id, -1, "the guest isn't the party's Felicity")
	assert_eq(enemy.party_id, -1, "and neither is the enemy")


# The account in DECODED_ALGORITHMS.md of why no guest ever shows a stance row
# rests on these being the only guests in the game.
func test_only_battles_2_and_508_put_a_guest_on_the_field():
	var save = PlayerSave.new_game("Flow", 0)
	var battle_ids: Array = []
	for file in DirAccess.get_files_at("res://resources/battles"):
		if file.ends_with(".tres"):
			battle_ids.append(int(file.get_slice("_", 0)))
	battle_ids.sort()
	var guests: Array = []
	for battle_id in battle_ids:
		var units = BattleSetup.build_units(BattleSetup.load_battle(battle_id), save, unit_templates, CombatUnit.Difficulty.HARD)
		for slot in units:
			if units[slot].origin == CombatUnit.Origin.GUEST:
				guests.append([battle_id, slot])
	assert_eq(guests, [[2, 5], [508, 3]])


# A marker names a deployment position rather than a companion, so swapping the
# deployed pair has to swap the party ids too.
func test_roster_takes_a_companions_party_id_from_the_deployment():
	var save = PlayerSave.new_game("Flow", 0)
	save.party_roster = [0, 1, 2, -1, -1, -1]
	save.party_deployed = [2, 1]
	var units = BattleSetup.build_units(BattleSetup.load_battle(100), save, unit_templates, CombatUnit.Difficulty.HARD)
	assert_eq([units[3].player_name, units[3].party_id], ["Roald", 2], "the first marker fields Roald")
	assert_eq([units[5].player_name, units[5].party_id], ["Veradux", 1], "and the second fields Veradux")


func test_companion_stat_model():
	var save = PlayerSave.new_game("Flow", 0)
	var veradux = Party.build_companion_unit(save, 1, unit_templates, 3)
	# Level 1 Veradux (template ratios all 20): allocation + ceil(curve).
	var curve = ceil(CombatUnit.get_stat(20, 1, true))
	assert_eq(veradux.base_life, round(9 + curve) * 33)
	assert_eq(veradux.base_strength, round(12 + curve))
	assert_eq(veradux.base_per[CombatUnit.Element.LIGHTNING], 100.0 + 15.0 + 82.0, "PerSets seed applies")
	assert_eq(veradux.base_def[CombatUnit.Element.LIGHTNING], 100.0 + 5.0, "faithful Lightning-defense 5/level quirk")
	assert_eq(veradux.base_def[CombatUnit.Element.PHYSICAL], 100.0 + 15.0)


func test_full_zone_battle_loop():
	var save = PlayerSave.new_game("Flow", 0)
	save.skill_points = 8
	TalentTree.learn(save, 0)
	TalentTree.learn(save, 1)

	var pick = ZoneProgression.pick_story_battle(save)
	assert_eq(pick["battle_id"], 100)
	var battle = BattleSetup.load_battle(pick["battle_id"])
	var units = BattleSetup.build_units(battle, save, unit_templates, CombatUnit.Difficulty.HARD)

	# Headless autonomy: let the AI drive the player unit with their talent
	# moves (the battle UI will feed real input later).
	var player: CombatUnit = units[1]
	player.ai_enabled = true
	player.move_pool_attack = TalentTree.get_known_move_ids(save)
	player.cooldowns_attack = []
	for i in player.move_pool_attack.size():
		player.cooldowns_attack.append(0)

	var runner = BattleRunner.new()
	runner.setup(
		units, battle, MoveManagerAuto.moves_by_id, BuffManagerAuto.buffs_by_id,
		BuffManagerAuto.buffs_by_internal_name, TalentTree.get_passive_buff_names(save)
	)
	var half_turns = 0
	while not runner.is_over() and half_turns < MAX_HALF_TURNS:
		runner.advance_half_turn()
		half_turns += 1
	assert_true(runner.is_over(), "zone-driven battle terminates")
	gut.p("battle 100 outcome=%d turns=%d" % [runner.win_condition, runner.turn_count])

	var settlement := BattleSettlement.settle(runner, save, pick, ACHIEVEMENTS_FILE)
	if FileAccess.file_exists(ACHIEVEMENTS_FILE):
		DirAccess.remove_absolute(ACHIEVEMENTS_FILE)
	if runner.win_condition == BattleRunner.Outcome.WIN:
		assert_eq(ZoneProgression.quest_progress(save, 1), 1, "story win advanced progress")
		assert_eq(settlement.money_gained, 7, "round(0.7 * respecValue(1)) over the Prison Guard and both markers")
		assert_eq(Array(settlement.fighting_party), [1], "Veradux fought")
		assert_true(save.party_exp[1] > 0.0 or save.party_levels[1] > 1, "and earned XP")
