# Unit tests for ZoneProgression + Party - story/training battle selection,
# zone unlocks, post-battle progression, companion roster/stats/XP. Expected
# values from the SWF source (orb buttons, frame_219, frame_449,
# frame_42/DoAction_17 - see the class headers).
extends GutTest

const BATTLES_FILE = "res://dev/converted_json/battles.json"
const ACHIEVEMENTS_FILE = "user://test_zone_progression_achievements.cfg"

var save: PlayerSave


func before_each():
	save = PlayerSave.new_game("Test", 0)


func test_new_game_progression_state():
	assert_eq(save.section_in, 1, "starts in the Prison zone")
	assert_eq(save.quest_progress.size(), 14, "EMPTY + 13 slots")
	assert_eq(save.quest_progress[0], "EMPTY")
	assert_eq(save.party_roster, [0, 1, -1, -1, -1, -1], "player + Veradux")
	assert_eq(save.party_deployed, [1, 2], "Veradux + (future) Roald deployed")
	assert_eq(save.party_levels[1], 1, "Veradux starts at level 1")
	assert_eq(save.party_levels[2], 11, "Roald seed level 11")
	assert_eq(save.party_levels[3], 22, "Felicity seed level 22")


func test_story_battle_selection():
	var pick = ZoneProgression.pick_story_battle(save)
	assert_eq(pick["battle_id"], 100, "zone * 100 + progress")
	assert_true(pick["is_story_progress"])
	assert_false(pick["is_boss"])

	save.quest_progress[1] = 9
	pick = ZoneProgression.pick_story_battle(save)
	assert_eq(pick["battle_id"], 109, "progress_max fight is the boss")
	assert_true(pick["is_boss"])
	assert_true(pick["is_story_progress"])

	save.quest_progress[1] = 10
	pick = ZoneProgression.pick_story_battle(save)
	assert_eq(pick["battle_id"], 109, "boss repeats after the zone is done")
	assert_true(pick["is_boss"])
	assert_false(pick["is_story_progress"], "repeat wins do not advance progress")


# The tutorial is battle 2 (frame_165/DoAction.as:2), and
# frame_42/DoAction_14.as:311 puts Metabii (49) against Sonny with Louis the
# Blind (48) beside him.
func test_every_story_battle_and_the_tutorial_load():
	for zone in ZoneProgression.QUEST_HUB:
		for progress in range(int(ZoneProgression.QUEST_HUB[zone]["progress_max"]) + 1):
			var battle_id: int = zone * 100 + progress
			assert_not_null(BattleSetup.load_battle(battle_id), "story battle %d loads" % battle_id)

	var tutorial: BattleFight = BattleSetup.load_battle(2)
	var players: Array = tutorial.players.map(func(player): return int(player["id"])) if tutorial else []
	assert_eq(players, [49, 0, 0, 48, 0], "battle 2 is the tutorial")


# Each converted battle is saved as <id>_<id_name>.tres, so a file whose id
# disagrees with its name is a battle stored under the wrong id.
func test_every_battle_file_holds_the_battle_its_name_says():
	var dir_path := "res://resources/battles/"
	var seen: Dictionary = {}
	for file_name in DirAccess.get_files_at(dir_path):
		if not file_name.ends_with(".tres"):
			continue
		var battle: BattleFight = load(dir_path + file_name)
		assert_eq(file_name, "%d_KBR%d.tres" % [battle.id, battle.id], "%s holds battle %d" % [file_name, battle.id])
		assert_eq(battle.id_name, "KBR%d" % battle.id, "%s id_name" % file_name)
		assert_false(seen.has(battle.id), "battle %d is stored once" % battle.id)
		seen[battle.id] = true
	assert_eq(seen.size(), 99, "every converted battle has a file")


# Every story orb flags the fight at its zone's progressMax as a boss fight
# except the TUNNELS orb, which compares the progress against progressMax1, a
# field no questHub entry has (DefineButton2_3239 on(press), line 14). So the
# first fight at 409 isn't a boss fight in the original.
func test_the_first_fight_at_409_is_the_only_progress_max_fight_without_the_boss_flag():
	for zone in ZoneProgression.QUEST_HUB:
		var progress_max: int = int(ZoneProgression.QUEST_HUB[zone]["progress_max"])
		save.section_in = zone
		save.quest_progress[zone] = progress_max
		var pick = ZoneProgression.pick_story_battle(save)
		assert_eq(pick["battle_id"], zone * 100 + progress_max, "zone %d's progressMax fight" % zone)
		assert_true(pick["is_story_progress"], "zone %d's first fight at its progressMax advances the story" % zone)
		assert_eq(pick["is_boss"], zone != 4, "zone %d's first fight at its progressMax" % zone)


func test_story_orb_replays_once_the_zone_is_done():
	save.section_in = 4
	save.quest_progress[4] = 10
	var pick = ZoneProgression.pick_story_battle(save)
	assert_eq(pick["battle_id"], 408, "the TUNNELS orb replays progressMax - 1, the Hydra")
	assert_false(pick["is_story_progress"], "the replay does not advance progress")
	assert_true(pick["is_boss"], "the replay is a boss fight")

	var replays = {1: 109, 2: 212, 3: 308, 5: 513, 6: 603, 7: 703}
	for zone in replays:
		save.section_in = zone
		save.quest_progress[zone] = ZoneProgression.QUEST_HUB[zone]["progress_max"] + 1
		pick = ZoneProgression.pick_story_battle(save)
		assert_eq(pick["battle_id"], replays[zone], "zone %d's orb replays its progressMax fight" % zone)


# Zones 6 and 7 share the ROME and JAPAN story orb, DefineButton2_3243, the only
# story orb that replays a beaten boss without setting usedTraining.
func test_boss_replay_counts_as_training_in_zones_1_to_5():
	save.section_in = 2
	save.quest_progress[2] = 12
	var pick = ZoneProgression.pick_story_battle(save)
	assert_eq(pick.get("counts_as_training"), false, "the first fight against zone 2's boss is not training")

	var counts_as_training = {1: true, 2: true, 3: true, 4: true, 5: true, 6: false, 7: false}
	for zone in counts_as_training:
		save.section_in = zone
		save.quest_progress[zone] = ZoneProgression.QUEST_HUB[zone]["progress_max"] + 1
		pick = ZoneProgression.pick_story_battle(save)
		assert_eq(pick.get("counts_as_training"), counts_as_training[zone], "zone %d's boss replay" % zone)


func test_boss_replay_from_the_story_orb_sets_used_training():
	var previous_save: PlayerSave = GameData.current_save
	var previous_zone: int = ZoneManager.current_zone
	var previous_auto_start: bool = ZoneManager.auto_start_battles
	var previous_pending: Dictionary = ZoneManager.pending_battle
	GameData.current_save = save
	ZoneManager.current_zone = 2
	ZoneManager.auto_start_battles = false
	save.quest_progress[2] = 12
	ZoneManager.request_story_fight()
	assert_false(save.used_training, "the first fight against zone 2's boss leaves used_training alone")
	save.quest_progress[2] = 13
	ZoneManager.request_story_fight()
	assert_true(save.used_training, "replaying zone 2's boss sets used_training")

	ZoneManager.pending_battle = previous_pending
	ZoneManager.auto_start_battles = previous_auto_start
	ZoneManager.current_zone = previous_zone
	GameData.current_save = previous_save


# Zones 1 to 5 share one training orb, DefineButton2_3186, which sets
# usedTraining (on(press), line 15). The ROME orb, DefineButton2_3242, doesn't,
# and the JAPAN frame of the hub has no training orb at all.
func test_only_the_training_orb_of_zones_1_to_5_counts_as_training():
	for zone in ZoneProgression.QUEST_HUB:
		save.section_in = zone
		var pick = ZoneProgression.pick_training_battle(save)
		assert_eq(pick.get("counts_as_training"), zone <= 5, "zone %d's training fight" % zone)


func test_training_in_rome_leaves_used_training_alone():
	var previous_save: PlayerSave = GameData.current_save
	var previous_zone: int = ZoneManager.current_zone
	var previous_auto_start: bool = ZoneManager.auto_start_battles
	var previous_pending: Dictionary = ZoneManager.pending_battle
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	save.quest_progress[5] = 14
	save.quest_progress[6] = 1
	ZoneManager.current_zone = 6
	assert_eq(ZoneManager.request_training_fight().get("battle_id"), 1026, "ROME's only training fight")
	assert_false(save.used_training, "a training fight in ROME leaves used_training alone")
	ZoneManager.current_zone = 5
	ZoneManager.request_training_fight()
	assert_true(save.used_training, "a training fight in CITY sets used_training")

	ZoneManager.pending_battle = previous_pending
	ZoneManager.auto_start_battles = previous_auto_start
	ZoneManager.current_zone = previous_zone
	GameData.current_save = previous_save


func test_training_battle_unlocks():
	assert_eq(ZoneProgression.available_training_battle_ids(save), [1000], "-1 entries always unlocked")
	save.quest_progress[1] = 6
	assert_eq(
		ZoneProgression.available_training_battle_ids(save), [1000, 1001],
		"progress must EXCEED the unlock value (6 > 5, but not > 6)"
	)
	save.quest_progress[1] = 7
	assert_eq(ZoneProgression.available_training_battle_ids(save), [1000, 1001, 1002])
	var pick = ZoneProgression.pick_training_battle(save)
	assert_has([1000, 1001, 1002], pick["battle_id"])
	assert_eq(pick["train_cap"], 9, "zone 1 finalTrainCap")


func test_zone_unlock_rules():
	assert_true(ZoneProgression.is_zone_unlocked(save, 1))
	assert_false(ZoneProgression.is_zone_unlocked(save, 2))
	save.quest_progress[1] = 9
	assert_false(ZoneProgression.is_zone_unlocked(save, 2), "reaching the boss is not enough")
	save.quest_progress[1] = 10
	assert_true(ZoneProgression.is_zone_unlocked(save, 2), "boss beaten (progress past max)")
	assert_false(ZoneProgression.is_zone_unlocked(save, 3), "each zone needs its own link")
	assert_eq(ZoneProgression.max_zone(0), 5, "easy caps the map at zone 5")
	assert_eq(ZoneProgression.max_zone(1), 6)
	assert_eq(ZoneProgression.max_zone(2), 6, "zone 7 needs Legend")
	assert_eq(ZoneProgression.max_zone(2, true), 7)


# frame_449/DoAction.as:4-16 opens zone 7 only on Heroic with achGet[4], Legend,
# set. achGet belongs to no save (frame_46/DoAction_2.as:12-31), so the port
# reads it from the achievements file.
func test_zone_7_opens_on_heroic_once_legend_is_earned():
	var previous_save: PlayerSave = GameData.current_save
	var previous_path: String = ZoneManager.achievements_path
	if FileAccess.file_exists(ACHIEVEMENTS_FILE):
		DirAccess.remove_absolute(ACHIEVEMENTS_FILE)
	ZoneManager.achievements_path = ACHIEVEMENTS_FILE
	GameData.current_save = save
	save.difficulty = CombatUnit.Difficulty.HARD
	save.quest_progress[6] = 4
	assert_false(ZoneManager.can_access_zone(7), "zone 7 stays closed on Heroic without Legend")

	Achievements.unlock(4, ACHIEVEMENTS_FILE)
	assert_true(ZoneManager.can_access_zone(7), "Legend opens zone 7 on Heroic once zone 6's boss is beaten")
	save.quest_progress[6] = 3
	assert_false(ZoneManager.can_access_zone(7), "Legend does not skip zone 6's boss")
	save.quest_progress[6] = 4
	save.difficulty = CombatUnit.Difficulty.NORMAL
	assert_false(ZoneManager.can_access_zone(7), "zone 7 stays closed on Normal with Legend")

	GameData.current_save = previous_save
	ZoneManager.achievements_path = previous_path
	DirAccess.remove_absolute(ACHIEVEMENTS_FILE)


func test_after_battle_won_progression_and_cutscenes():
	var result = ZoneProgression.after_battle_won(save, 100, true)
	assert_eq(save.quest_progress[1], 1, "story win advances progress")
	assert_true(result["progress_advanced"])
	assert_eq(result["cutscene"], "")

	save.quest_progress[1] = 9
	result = ZoneProgression.after_battle_won(save, 109, true)
	assert_eq(result["cutscene"], "CS_CUT2", "zone 1's boss win triggers the cutscene")

	result = ZoneProgression.after_battle_won(save, 109, false)
	assert_eq(save.quest_progress[1], 10, "repeat wins do not advance further")


# Standing regression guard that CUTSCENE_BATTLES stays keyed to battles this
# port can actually load, matching the original game's own BattlePick checks
# (109/210/409/513) now that battles.py corrects the mislabeled ids at
# conversion time (see that file's MISLABELED_BATTLE_IDS comment).
func test_cutscene_battles_keys_load_from_current_battle_data():
	var battle_ids: Dictionary = _load_battle_ids()
	for battle_id in ZoneProgression.CUTSCENE_BATTLES:
		assert_true(battle_ids.has(battle_id), "battle %s (%s) is not in battles.json" % [battle_id, ZoneProgression.CUTSCENE_BATTLES[battle_id]])


func test_after_battle_won_returns_each_cutscene():
	for battle_id in [109, 210, 409, 513]:
		var result = ZoneProgression.after_battle_won(save, battle_id, true)
		assert_eq(result["cutscene"], ZoneProgression.CUTSCENE_BATTLES[battle_id], "battle %s should trigger its cutscene" % battle_id)


# gotoSceneKrin (frame_219/DoAction.as:36-55): CS_CUT2 and CS_CUT4 unlock a
# new zone and open the map, CS_CUT3 doesn't unlock anything so it stays on the
# current hub, and CS_CUT5 goes to endMenu, the ending screen.
func test_after_battle_won_returns_goto_scene_per_cutscene():
	var result = ZoneProgression.after_battle_won(save, 109, true)
	assert_eq(result["goto_scene"], "overMap", "CS_CUT2 unlocks zone 2, opens the map")

	save.section_in = 2
	result = ZoneProgression.after_battle_won(save, 210, true)
	assert_eq(result["goto_scene"], "Navigation", "CS_CUT3 doesn't unlock a new zone")

	save.section_in = 4
	result = ZoneProgression.after_battle_won(save, 409, true)
	assert_eq(result["goto_scene"], "overMap", "CS_CUT4 unlocks zone 5, opens the map")

	save.section_in = 5
	result = ZoneProgression.after_battle_won(save, 513, true)
	assert_eq(result["cutscene"], "CS_CUT5")
	assert_eq(result["goto_scene"], "endMenu", "CS_CUT5 ends on the ending screen")

	result = ZoneProgression.after_battle_won(save, 100, true)
	assert_eq(result["goto_scene"], "", "non-cutscene wins don't carry a goto_scene")


func _load_battle_ids() -> Dictionary:
	var file := FileAccess.open(BATTLES_FILE, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	var ids: Dictionary = {}
	for battle_data in parsed.get("battles", []):
		ids[int(battle_data["id"])] = true
	return ids


func test_companions_join_at_thresholds():
	save.section_in = 2
	save.quest_progress[2] = 1
	var result = ZoneProgression.after_battle_won(save, 201, true)  # progress -> 2
	assert_true(result["roster_changed"], "Roald joins once zone 2 progress passes 1")
	assert_eq(save.party_roster, [0, 1, 2, -1, -1, -1])

	save.section_in = 5
	save.quest_progress[5] = 4
	result = ZoneProgression.after_battle_won(save, 504, true)  # progress -> 5
	assert_true(result["roster_changed"], "Felicity joins once zone 5 progress passes 4")
	assert_eq(save.party_roster, [0, 1, 2, 3, -1, -1])


func test_deployed_party_id_gates_on_roster():
	assert_eq(Party.deployed_party_id(save, -2), 1, "first companion slot is Veradux")
	assert_eq(Party.deployed_party_id(save, -1), -1, "Roald deployed but not joined yet")
	save.quest_progress[2] = 2
	Party.update_roster_after_battle(save)
	assert_eq(Party.deployed_party_id(save, -1), 2, "Roald fills the slot once joined")


func test_companion_experience_no_points():
	var skill_points_before = save.skill_points
	var stat_points_before = save.stat_points
	var gained = Party.grant_companion_experience(save, 1, 250.0)
	assert_eq(gained, 2)
	assert_eq(save.party_levels[1], 3)
	assert_almost_eq(save.party_exp[1], 50.0, 0.001)
	assert_eq(save.skill_points, skill_points_before, "companions grant the player nothing")
	assert_eq(save.stat_points, stat_points_before)
	save.party_levels[1] = Leveling.MAX_LEVEL
	assert_eq(Party.grant_companion_experience(save, 1, 500.0), 0, "capped at 30")
