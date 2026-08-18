# Unit tests for ZoneProgression + Party - story/training battle selection,
# zone unlocks, post-battle progression, companion roster/stats/XP. Expected
# values from the SWF source (orb buttons, frame_219, frame_449,
# frame_42/DoAction_17 - see the class headers).
extends GutTest

const BATTLES_FILE = "res://dev/converted_json/battles.json"

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
	assert_eq(ZoneProgression.max_zone(2), 6, "zone 7 needs the all-star achievement")
	assert_eq(ZoneProgression.max_zone(2, true), 7)


func test_after_battle_won_progression_and_cutscenes():
	var result = ZoneProgression.after_battle_won(save, 100, true)
	assert_eq(save.quest_progress[1], 1, "story win advances progress")
	assert_true(result["progress_advanced"])
	assert_eq(result["cutscene"], "")

	save.quest_progress[1] = 8
	result = ZoneProgression.after_battle_won(save, 108, true)
	assert_eq(result["cutscene"], "CS_CUT2", "zone 1's last real battle win triggers the cutscene")

	result = ZoneProgression.after_battle_won(save, 108, false)
	assert_eq(save.quest_progress[1], 9, "repeat wins do not advance further")


# Standing regression guard that CUTSCENE_BATTLES stays keyed to battles this
# port can actually load, so every cutscene is reachable in play. It checks
# the keys against battles.json as it stands today, which is not the same
# thing as checking them against the original game's design - the original
# triggers these cutscenes on 109/210/409/513, and battles.json is missing
# three of those because of a converter-input bug described in the const's
# own comment. Passing here means the cutscenes fire on some battle players
# can reach, not that they fire on the battle the original chose.
func test_cutscene_battles_keys_load_from_current_battle_data():
	var battle_ids: Dictionary = _load_battle_ids()
	for battle_id in ZoneProgression.CUTSCENE_BATTLES:
		assert_true(battle_ids.has(battle_id), "battle %s (%s) is not in battles.json" % [battle_id, ZoneProgression.CUTSCENE_BATTLES[battle_id]])


func test_after_battle_won_returns_each_cutscene():
	for battle_id in [108, 210, 408, 512]:
		var result = ZoneProgression.after_battle_won(save, battle_id, true)
		assert_eq(result["cutscene"], ZoneProgression.CUTSCENE_BATTLES[battle_id], "battle %s should trigger its cutscene" % battle_id)


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
