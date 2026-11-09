# Checks the QA save presets in dev/save_presets/ against the game's own
# progression data, so a preset that drifts from the story fails here instead
# of in the middle of a QA run.
extends GutTest

const PRESET_DIR: String = "res://dev/save_presets/"
const ZONE_BOSS_PRESETS: Array[String] = [
	"zone1_boss", "zone2_boss", "zone3_boss", "zone4_boss", "zone5_boss", "zone6_boss", "zone7_boss",
]
const POSTGAME_PRESETS: Array[String] = ["postgame_easy", "postgame_heroic", "postgame_normal"]
const NO_TRAINING_PRESETS: Array[String] = ["no_training_legend", "no_training_predator"]
const ACHIEVEMENT_VARIANTS: Array[String] = [
	"heroic_legend", "no_training_legend", "no_training_predator", "postgame_heroic", "zone7_boss",
]
const STRONG_LEVEL: int = 99
const STRONG_EURO: float = 999999.0
# The generator's strong stats won every boss in at most five moves over twenty
# seeds, and the weak preset lost battle 513 in at most eleven half-turns.
const MAX_STRONG_MOVES: int = 8
const MAX_WEAK_HALF_TURNS: int = 20
const MAX_HALF_TURNS: int = 400


func after_each():
	randomize()


func _all_presets() -> Array[String]:
	var presets: Array[String] = ["fresh_normal", "heroic_legend", "rich", "weak"]
	presets.append_array(ZONE_BOSS_PRESETS)
	presets.append_array(POSTGAME_PRESETS)
	presets.append_array(NO_TRAINING_PRESETS)
	presets.sort()
	return presets


func _strong_presets() -> Array[String]:
	var presets: Array[String] = ["heroic_legend"]
	presets.append_array(ZONE_BOSS_PRESETS)
	presets.append_array(POSTGAME_PRESETS)
	presets.append_array(NO_TRAINING_PRESETS)
	return presets


func _load_preset(preset_name: String) -> PlayerSave:
	return ResourceLoader.load(PRESET_DIR + preset_name + ".tres", "", ResourceLoader.CACHE_MODE_IGNORE)


func _unlocked_achievements(preset_name: String) -> Array:
	return Achievements.load_unlocked(PRESET_DIR + preset_name + ".achievements.cfg")


func _preset_files_ending_with(suffix: String) -> Array:
	var names: Array = []
	for file_name in DirAccess.get_files_at(PRESET_DIR):
		if file_name.ends_with(suffix):
			names.append(file_name.trim_suffix(suffix))
	names.sort()
	return names


func _progress_max(zone: int) -> int:
	return int(ZoneProgression.QUEST_HUB[zone]["progress_max"])


func _assert_progress(save: PlayerSave, preset_name: String, expected_by_zone: Dictionary) -> void:
	for zone: int in ZoneProgression.QUEST_HUB:
		assert_eq(ZoneProgression.quest_progress(save, zone), expected_by_zone.get(zone, 0), "%s zone %d progress" % [preset_name, zone])


func _past_zones(last_zone: int) -> Dictionary:
	var expected: Dictionary = {}
	for zone in range(1, last_zone + 1):
		expected[zone] = _progress_max(zone) + 1
	return expected


# Runs the story fight the save has next, with the player using the first move
# on the bar against the first living enemy when attack is true, and passing
# every turn when it is false. Returns the battle's outcome and its length.
func _fight_next_story_battle(save: PlayerSave, attack: bool) -> Dictionary:
	var pick: Dictionary = ZoneProgression.pick_story_battle(save)
	var battle: BattleFight = BattleSetup.load_battle(pick["battle_id"])
	var units: Dictionary = BattleSetup.build_units(battle, save, UnitManagerAuto.units_by_id, save.difficulty)
	var manager: BattleManager = BattleManager.new()
	add_child_autofree(manager)
	var runner: BattleRunner = BattleRunner.new()
	runner.setup(
		units, battle, MoveManagerAuto.moves_by_id, BuffManagerAuto.buffs_by_id,
		BuffManagerAuto.buffs_by_internal_name, manager, TalentTree.get_passive_buff_names(save)
	)
	var half_turns: int = 0
	var moves: int = 0
	while not runner.is_over() and half_turns < MAX_HALF_TURNS:
		var action: Dictionary = {}
		if attack and runner.is_player_turn():
			for slot in [2, 4, 6]:
				if units.get(slot) != null and units[slot].active:
					action = {"target_slot": slot, "move_id": int(save.move_matrix[0]), "bar_index": 0}
					moves += 1
					break
		runner.advance_half_turn(action)
		half_turns += 1
	return {"outcome": runner.win_condition, "moves": moves, "half_turns": half_turns}


func test_the_folder_holds_exactly_the_expected_files():
	assert_eq(_preset_files_ending_with(".tres"), Array(_all_presets()))
	assert_eq(_preset_files_ending_with(".achievements.cfg"), Array(ACHIEVEMENT_VARIANTS))


func test_every_preset_is_a_real_new_game_with_story_progress():
	for preset_name in _all_presets():
		var save: PlayerSave = _load_preset(preset_name)
		assert_true(save is PlayerSave, "%s loads as a PlayerSave" % preset_name)
		assert_eq(save.name_user, preset_name, "the slot button shows the preset name")
		assert_eq(save.player_class, PlayerSave.PlayerClass.BIOLOGICAL, preset_name)
		assert_true(save.autosave, "%s autosaves like a default new game" % preset_name)
		assert_eq(save.quest_progress.size(), PlayerSave.new_game("x").quest_progress.size(), preset_name)
		for equip_slot in GameData.STARTING_EQUIPMENT:
			assert_eq(int(save.equip_array[equip_slot]), GameData.STARTING_EQUIPMENT[equip_slot], "%s starting outfit" % preset_name)
		var starting_moves: Array = TalentTree.STARTING_MOVES[save.player_class]
		for i in starting_moves.size():
			assert_eq(int(save.move_matrix[i]), starting_moves[i], "%s starting moves" % preset_name)
		assert_false(Party.update_roster_after_battle(save), "%s roster matches its story progress" % preset_name)


func test_strong_presets_carry_usable_stats_above_the_level_cap():
	for preset_name in _strong_presets():
		var save: PlayerSave = _load_preset(preset_name)
		assert_eq(save.level, STRONG_LEVEL, preset_name)
		assert_gt(save.level, Leveling.MAX_LEVEL, preset_name)
		assert_eq(save.euro, STRONG_EURO, preset_name)
		assert_eq(save.stat_points, 0, "%s has no point that would recompute its stats" % preset_name)
		for stat in [save.life, save.strength, save.magic, save.speed]:
			assert_gt(stat, 0.0, "%s keeps positive stats" % preset_name)


func test_presets_at_or_below_the_level_cap_store_their_computed_stats():
	for preset_name in ["fresh_normal", "rich", "weak"]:
		var save: PlayerSave = _load_preset(preset_name)
		var stored: Array = [save.life, save.strength, save.magic, save.speed, save.focus]
		Leveling.compute_stats(save)
		assert_eq([save.life, save.strength, save.magic, save.speed, save.focus], stored, preset_name)


func test_fresh_normal_is_a_new_game_on_normal():
	var save: PlayerSave = _load_preset("fresh_normal")
	assert_eq(save.difficulty, CombatUnit.Difficulty.NORMAL)
	assert_eq(save.level, 1)
	assert_eq(save.euro, 0.0)
	assert_eq(save.section_in, 1)
	assert_false(save.used_training)
	_assert_progress(save, "fresh_normal", {})
	assert_eq(ZoneProgression.pick_story_battle(save)["battle_id"], 100)


# The boss each preset stops at is the fight at its zone's progress_max. The
# original flags that fight as a boss fight in every zone but zone 4, whose
# story orb compares against an undefined progressMax1 (DefineButton2_3239
# on(press), line 14).
func test_each_zone_boss_preset_has_that_boss_next():
	for zone: int in ZoneProgression.QUEST_HUB:
		var preset_name: String = "zone%d_boss" % zone
		var save: PlayerSave = _load_preset(preset_name)
		var expected: Dictionary = _past_zones(zone - 1)
		expected[zone] = _progress_max(zone)
		_assert_progress(save, preset_name, expected)
		assert_eq(save.section_in, zone, preset_name)
		assert_false(save.used_training, preset_name)
		var pick: Dictionary = ZoneProgression.pick_story_battle(save)
		assert_eq(pick["battle_id"], zone * 100 + _progress_max(zone), preset_name)
		assert_eq(pick["is_boss"], zone != 4, preset_name)
		assert_true(pick["is_story_progress"], "%s has not beaten the boss yet" % preset_name)
		assert_true(ZoneProgression.is_zone_unlocked(save, zone), "%s can reach its zone" % preset_name)


func test_zone_boss_difficulties_open_their_zones():
	for zone in range(1, 7):
		var save: PlayerSave = _load_preset("zone%d_boss" % zone)
		assert_eq(save.difficulty, CombatUnit.Difficulty.NORMAL)
		assert_true(zone <= ZoneProgression.max_zone(save.difficulty))
	var zone_seven: PlayerSave = _load_preset("zone7_boss")
	assert_eq(zone_seven.difficulty, CombatUnit.Difficulty.HARD)
	assert_true(_unlocked_achievements("zone7_boss")[Achievements.NAMES.find("Legend")])
	assert_eq(ZoneProgression.max_zone(zone_seven.difficulty, true), 7)


func test_postgame_presets_beat_every_zone_their_difficulty_opens():
	var difficulties: Dictionary = {
		"postgame_easy": CombatUnit.Difficulty.EASY,
		"postgame_normal": CombatUnit.Difficulty.NORMAL,
		"postgame_heroic": CombatUnit.Difficulty.HARD,
	}
	for preset_name: String in difficulties:
		var save: PlayerSave = _load_preset(preset_name)
		assert_eq(save.difficulty, difficulties[preset_name], preset_name)
		_assert_progress(save, preset_name, _past_zones(ZoneProgression.max_zone(save.difficulty)))
		assert_eq(save.section_in, 1, preset_name)
		assert_true(save.used_training, "%s has trained like slot 4" % preset_name)


func test_postgame_heroic_keeps_zone_seven_closed():
	var legend_id: int = Achievements.NAMES.find("Legend")
	assert_false(_unlocked_achievements("postgame_heroic")[legend_id])


func test_heroic_legend_opens_zone_seven_at_its_first_fight():
	var save: PlayerSave = _load_preset("heroic_legend")
	assert_eq(save.difficulty, CombatUnit.Difficulty.HARD)
	assert_true(_unlocked_achievements("heroic_legend")[Achievements.NAMES.find("Legend")])
	_assert_progress(save, "heroic_legend", _past_zones(6))
	assert_eq(ZoneProgression.max_zone(save.difficulty, true), 7)
	assert_true(ZoneProgression.is_zone_unlocked(save, 7))
	save.section_in = 7
	assert_eq(ZoneProgression.pick_story_battle(save)["battle_id"], 700)


func test_no_training_presets_can_still_earn_predator_and_legend():
	var expected: Dictionary = {"no_training_predator": "Predator", "no_training_legend": "Legend"}
	for preset_name: String in expected:
		var save: PlayerSave = _load_preset(preset_name)
		var achievement_id: int = Achievements.NAMES.find(expected[preset_name])
		assert_eq(save.difficulty, CombatUnit.Difficulty.HARD, preset_name)
		assert_false(save.used_training, preset_name)
		var pick: Dictionary = ZoneProgression.pick_story_battle(save)
		assert_true(achievement_id in Achievements.check_battle_victory(save, pick["battle_id"], true, {}), "%s qualifies on winning its boss" % preset_name)
		assert_false(_unlocked_achievements(preset_name)[achievement_id], "%s has not earned it yet" % preset_name)
		assert_gt(ZoneProgression.quest_progress(save, 1), _progress_max(1), "%s can replay zone 1's boss" % preset_name)


func test_every_heroic_preset_states_whether_legend_is_unlocked():
	for preset_name in _all_presets():
		if _load_preset(preset_name).difficulty == CombatUnit.Difficulty.HARD:
			assert_true(preset_name in ACHIEVEMENT_VARIANTS, "%s replaces achievements.cfg" % preset_name)


func test_strong_presets_beat_their_bosses_quickly():
	seed(4000)
	for preset_name in ZONE_BOSS_PRESETS + NO_TRAINING_PRESETS:
		var result: Dictionary = _fight_next_story_battle(_load_preset(preset_name), true)
		assert_eq(result["outcome"], BattleRunner.Outcome.WIN, preset_name)
		assert_true(result["moves"] <= MAX_STRONG_MOVES, "%s won in %d moves" % [preset_name, result["moves"]])


func test_weak_preset_can_buy_something_and_then_loses_quickly():
	seed(1000)
	var save: PlayerSave = _load_preset("weak")
	assert_eq(save.level, 1)
	assert_eq(save.difficulty, CombatUnit.Difficulty.NORMAL)
	assert_false(save.used_training)
	var cheapest: int = 1 << 30
	for item_id in StoreManager.KRIN_SHOP_ITEMS[StoreManager.ZONE_SHOP_IDS[save.section_in]]:
		if item_id != 0:
			cheapest = mini(cheapest, ItemManagerAuto.get_item(item_id).price)
	assert_true(save.euro >= cheapest, "the cheapest item costs %d" % cheapest)
	var result: Dictionary = _fight_next_story_battle(save, false)
	assert_eq(result["outcome"], BattleRunner.Outcome.LOSS)
	assert_true(result["half_turns"] <= MAX_WEAK_HALF_TURNS, "lost in %d half-turns" % result["half_turns"])


func test_rich_preset_reaches_every_normal_shop_and_keeps_level_gates():
	var save: PlayerSave = _load_preset("rich")
	assert_eq(save.level, 1)
	assert_eq(save.difficulty, CombatUnit.Difficulty.NORMAL)
	assert_eq(save.item_array.count(0), save.item_array.size(), "the inventory has room for purchases")
	var dearest: int = 0
	var highest_required_level: int = 0
	for zone in range(1, ZoneProgression.max_zone(save.difficulty) + 1):
		assert_true(ZoneProgression.is_zone_unlocked(save, zone), "zone %d" % zone)
		for item_id in StoreManager.KRIN_SHOP_ITEMS[StoreManager.ZONE_SHOP_IDS[zone]]:
			if item_id != 0:
				var item: GameItem = ItemManagerAuto.get_item(item_id)
				dearest = maxi(dearest, item.price)
				highest_required_level = maxi(highest_required_level, item.required_level)
	assert_true(save.euro >= dearest, "the dearest item costs %d" % dearest)
	assert_gt(highest_required_level, save.level, "some shop items are still gated by level")
