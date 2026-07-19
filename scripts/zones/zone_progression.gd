# zone_progression.gd
# Zone quest/battle progression rules, ported from the full SWF script export
# (2026-07-18): the story/training fight orb buttons (DefineButton2_3204/3242
# and siblings), the post-battle progression frame (frame_219), the zone-map
# unlock rules (frame_449), and the frame41 questHub/trainFight data.
#
# Story battles: id = zone * 100 + quest_progress[zone]. Reaching progress_max
# is the zone boss; past it the boss is repeatable (no more progression).
# Training battles: per-zone [battle_id, unlock_progress] pools, available
# once quest_progress[zone] > unlock_progress (-1 = always).
#
# No autoload references - operates on PlayerSave (ZoneManager delegates).
class_name ZoneProgression
extends RefCounted

# questHub (frame41): progress_max = story fights in the zone (the fight AT
# progress_max is the boss); linked_zone = the zone whose boss unlocks this
# one on the travel map.
const QUEST_HUB: Dictionary = {
	1: {"progress_max": 9, "linked_zone": 0, "label": "Prison"},
	2: {"progress_max": 12, "linked_zone": 1, "label": "Village"},
	3: {"progress_max": 8, "linked_zone": 2, "label": "Train"},
	4: {"progress_max": 9, "linked_zone": 3, "label": "Tunnels"},
	5: {"progress_max": 13, "linked_zone": 4, "label": "City"},
	6: {"progress_max": 3, "linked_zone": 5, "label": "Zone 6"},
	7: {"progress_max": 3, "linked_zone": 6, "label": "Zone 7"},
}

# trainFight[zone] (frame41): [battle_id, unlock_progress] pairs.
const TRAIN_FIGHTS: Dictionary = {
	1: [[1000, -1], [1001, 5], [1002, 6], [1003, 9]],
	2: [[1004, -1], [1005, 2], [1006, 3], [1007, 5], [1008, 6], [1009, 8], [1010, 9], [1011, 11]],
	3: [[1015, -1], [1012, 2], [1013, 3], [1014, 4]],
	4: [[1016, -1], [1017, 4], [1018, 5], [1019, 6], [1020, 8]],
	5: [[1022, -1], [1021, 4], [1023, 2], [1024, 4], [1025, 10]],
	6: [[1026, -1]],
	7: [[1022, -1], [1021, 4], [1023, 2], [1024, 4], [1025, 10]],
}

# trainFightCap[zone] (frame41) - the level clamp for "X"/"Z" scaling enemies
# in training fights (finalTrainCap).
const TRAIN_FIGHT_CAPS: Dictionary = {1: 9, 2: 12, 3: 15, 4: 18, 5: 23, 6: 40, 7: 30}

# Story battles that trigger a cutscene when won (frame_219).
const CUTSCENE_BATTLES: Dictionary = {109: "CS_CUT2", 210: "CS_CUT3", 409: "CS_CUT4", 513: "CS_CUT5"}


static func quest_progress(save: PlayerSave, zone: int) -> int:
	if zone < 0 or zone >= save.quest_progress.size():
		return 0
	var value = save.quest_progress[zone]
	return int(value) if value is int or value is float else 0


# The story-fight orb (DefineButton2_3204): the next story battle in the
# player's current zone. is_story_progress = winning advances quest_progress;
# is_boss = this is (or repeats) the zone's final fight.
static func pick_story_battle(save: PlayerSave) -> Dictionary:
	var zone = save.section_in
	var hub: Dictionary = QUEST_HUB.get(zone, {})
	if hub.is_empty():
		return {}
	var progress = quest_progress(save, zone)
	var progress_max = int(hub["progress_max"])
	var battle_id = zone * 100 + progress
	var is_story_progress = true
	var is_boss = progress == progress_max
	if progress > progress_max:
		battle_id = zone * 100 + progress_max
		is_story_progress = false
		is_boss = true
	return {"battle_id": battle_id, "is_story_progress": is_story_progress, "is_boss": is_boss}


# The training orb (DefineButton2_3242): battle ids currently unlocked in the
# player's zone (unlock_progress strictly below current progress; -1 always).
static func available_training_battle_ids(save: PlayerSave) -> Array:
	var ids = []
	for entry in TRAIN_FIGHTS.get(save.section_in, []):
		if quest_progress(save, save.section_in) > entry[1]:
			ids.append(entry[0])
	return ids


# Uniform random pick from the unlocked pool, plus the zone's level cap for
# "X"/"Z" enemy scaling. {} when the zone has nothing unlocked.
static func pick_training_battle(save: PlayerSave) -> Dictionary:
	var ids = available_training_battle_ids(save)
	if ids.is_empty():
		return {}
	return {
		"battle_id": ids[randi_range(0, ids.size() - 1)],
		"train_cap": int(TRAIN_FIGHT_CAPS.get(save.section_in, 30)),
	}


# Zone-map unlock rule (frame_449): zone 1 always; otherwise the linked
# zone's boss must be beaten (progress strictly past its progress_max).
static func is_zone_unlocked(save: PlayerSave, zone: int) -> bool:
	if zone == 1:
		return true
	var hub: Dictionary = QUEST_HUB.get(zone, {})
	if hub.is_empty():
		return false
	var linked = int(hub["linked_zone"])
	var linked_hub: Dictionary = QUEST_HUB.get(linked, {})
	if linked_hub.is_empty():
		return false
	return quest_progress(save, linked) > int(linked_hub["progress_max"])


# frame_449's difficulty gate on how much of the map exists at all:
# easy = zones 1-5, normal = 1-6, hard = 1-7 (zone 7 additionally requires
# the all-star achievement in the original).
static func max_zone(difficulty: int, has_all_star_achievement: bool = false) -> int:
	if difficulty <= 0:
		return 5
	if difficulty == 1:
		return 6
	return 7 if has_all_star_achievement else 6


# Post-battle progression (frame_219): a won story-progress fight advances
# quest_progress in the current zone, may trigger a cutscene, and may grow
# the party roster. Call ONLY on victory. Returns
# {progress_advanced, cutscene, roster_changed}.
static func after_battle_won(save: PlayerSave, battle_id: int, was_story_progress: bool) -> Dictionary:
	var cutscene = ""
	var progress_advanced = false
	if was_story_progress:
		save.quest_progress[save.section_in] = quest_progress(save, save.section_in) + 1
		progress_advanced = true
		cutscene = CUTSCENE_BATTLES.get(battle_id, "")
	var roster_changed = Party.update_roster_after_battle(save)
	return {
		"progress_advanced": progress_advanced,
		"cutscene": cutscene,
		"roster_changed": roster_changed,
	}
