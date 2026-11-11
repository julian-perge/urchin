# zone_progression.gd
# Zone quest/battle progression rules, ported from the full SWF script export
# (2026-07-18): the story/training fight orb buttons (DefineButton2_3204/3242
# and siblings), the post-battle progression frame (frame_219), the zone-map
# unlock rules (frame_449), and the frame41 questHub/trainFight data.
#
# Story battles: id = zone * 100 + quest_progress[zone]. Reaching progress_max
# is the zone boss; past it the boss is repeatable (no more progression),
# except that zone 4 replays the fight before it, the Hydra.
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

# Story battles that trigger a cutscene when won (frame_219). The original
# AS checks Krin.BattlePick against 109/210/409/513, and all four of those
# battles are real - frame_42/DoAction_14.as creates 100-109 for zone 1,
# 400-409 for zone 4 and 500-513 for zone 5.
#
# 2026-08-18: was keyed to 108/408/512 for a while - three of the four ids
# were unreachable, because dev/urchin_dev/convert/battles.py's raw input
# (dev/data_json/swf_battles.json) stamped each zone's real final battle
# with the *next* block's seed id (109 came through labelled 199, 409 as 499,
# 513 as 599 - see that converter's MISLABELED_BATTLE_IDS comment for the
# full mechanism). That made resources/battles/ missing 109/409/513
# entirely, so this table keyed to the id that DID exist per zone as a
# workaround - which is also why the cutscene used to fire one battle early.
# Fixed at the source (battles.py corrects the id at conversion time,
# resources/battles/109_KBR109.tres etc. regenerated), so this is back to
# the ids the original game actually checks.
const CUTSCENE_BATTLES: Dictionary = {109: "CS_CUT2", 210: "CS_CUT3", 409: "CS_CUT4", 513: "CS_CUT5"}

# Where each cutscene sends the player afterward (frame_219's gotoSceneKrin,
# set alongside afterCut in the same battle_id checks above): "overMap" opens
# the zone map on landing (CS_CUT2/CS_CUT4 both unlock a new zone - the
# original shows it off immediately rather than dropping back into the same
# hub), "Navigation" is the current zone hub (CS_CUT3 follows battle 210, two
# fights before zone 2's boss, 212 at progressMax 12 in
# frame_41/DoAction_2.as:47, so nothing new is unlocked yet), and "endMenu" is
# the ending screen, root frame 116, whose OK! goes to the hub
# (DefineButton2_2797 on(release), line 2). The world map still opens zones 6
# and 7 after it, because the original sets no flag on the way.
const CUTSCENE_GOTO_SCENE: Dictionary = {
	"CS_CUT2": "overMap", "CS_CUT3": "Navigation", "CS_CUT4": "overMap", "CS_CUT5": "endMenu",
}

# The fight a new game opens on, as the pick ZoneManager hands the Battle screen:
# battle 100 as a Story fight, with CS_INTRO2 played first. The Start button
# sends the player to CS_INTRO2 when the Tutorial is off
# (DefineButton2_2770 on(release), lines 7-10), the clip's end goes on to
# IntroSeq2 (frame_293/DoAction.as:1), and IntroSeq2's last frame starts
# battle 100 with progressFight on (frame_180/DoAction.as:2-3). Nothing on that
# path sets bossFight, so it is not a boss fight.
const FIRST_STORY_FIGHT: Dictionary = {
	"battle_id": 100,
	"is_story_progress": true,
	"is_boss": false,
	"cutscene_before": "CS_INTRO2",
}

# The Tutorial is battle 2 (frame_165/DoAction.as:2).
const TUTORIAL_BATTLE_ID: int = 2

# The fight a new game opens on when the Tutorial option is on, as the pick
# ZoneManager hands the Battle screen. The Start button sends the player to
# CS_INTRO when the option is on (DefineButton2_2770 on(release), lines 2-6), the
# clip's end goes on to IntroSeq (the button's gotoSceneKrin), and IntroSeq's
# last frame starts battle 2 with progressFight off (frame_165/DoAction.as:2-3).
# Nothing on that path sets bossFight either.
const TUTORIAL_FIGHT: Dictionary = {
	"battle_id": TUTORIAL_BATTLE_ID,
	"is_story_progress": false,
	"is_boss": false,
	"cutscene_before": "CS_INTRO",
}


static func quest_progress(save: PlayerSave, zone: int) -> int:
	if zone < 0 or zone >= save.quest_progress.size():
		return 0
	var value = save.quest_progress[zone]
	return int(value) if value is int or value is float else 0


# The story-fight orb (DefineButton2_3204): the next story battle in the
# player's current zone. is_story_progress = winning advances quest_progress;
# is_boss is the original's bossFight, which plays _music_boss
# (frame_42/DoAction.as:55-74). The orbs set it for a beaten zone's boss replay
# and for the fight at the zone's progress_max, apart from zone 4's.
# counts_as_training tells ZoneManager to set the save's used_training.
static func pick_story_battle(save: PlayerSave) -> Dictionary:
	var zone: int = save.section_in
	var hub: Dictionary = QUEST_HUB.get(zone, {})
	if hub.is_empty():
		return {}
	var progress: int = quest_progress(save, zone)
	var progress_max: int = int(hub["progress_max"])
	var battle_id: int = zone * 100 + progress
	var is_story_progress: bool = true
	# The TUNNELS orb compares the progress against progressMax1 instead of
	# progressMax (DefineButton2_3239 on(press), line 14). No questHub entry has
	# that field, so the first fight at 409 isn't a boss fight.
	var is_boss: bool = progress == progress_max and zone != 4
	var counts_as_training: bool = false
	if progress > progress_max:
		battle_id = zone * 100 + progress_max
		if zone == 4:
			# The TUNNELS orb replays progressMax - 1 (DefineButton2_3239
			# on(press) line 9), so a beaten zone 4 replays the Hydra in 408
			# instead of 409, the scripted Tunnel Worker fight before CS_CUT4.
			battle_id = zone * 100 + progress_max - 1
		is_story_progress = false
		is_boss = true
		# The original counts a boss replay in zones 1 to 5 as training, so the
		# save can no longer earn Predator or Legend. The PRISON orb sets
		# usedTraining at DefineButton2_3188 on(press) line 9, and the VILLAGE,
		# TRAIN, TUNNELS and CITY orbs set it at line 12 of DefineButton2_3213,
		# 3220, 3239 and 3204. Zones 6 and 7 share the ROME and JAPAN orb,
		# DefineButton2_3243, which replays without setting it.
		counts_as_training = zone <= 5
	return {
		"battle_id": battle_id,
		"is_story_progress": is_story_progress,
		"is_boss": is_boss,
		"counts_as_training": counts_as_training,
	}


# The training orbs (DefineButton2_3186 in zones 1 to 5, 3242 in zone 6) build
# the same pool: battle ids currently unlocked in the player's zone
# (unlock_progress strictly below current progress; -1 always).
static func available_training_battle_ids(save: PlayerSave) -> Array:
	var ids: Array[Variant] = []
	for entry in TRAIN_FIGHTS.get(save.section_in, []):
		if quest_progress(save, save.section_in) > entry[1]:
			ids.append(entry[0])
	return ids


# Uniform random pick from the unlocked pool, plus the zone's level cap for
# "X"/"Z" enemy scaling. {} when the zone has nothing unlocked.
# counts_as_training tells ZoneManager to set the save's used_training, which
# only the zones 1 to 5 orb does (DefineButton2_3186 on(press), line 15). The
# ROME orb leaves it alone, and the JAPAN hub has no training orb.
static func pick_training_battle(save: PlayerSave) -> Dictionary:
	var ids: Array = available_training_battle_ids(save)
	if ids.is_empty():
		return {}
	return {
		"battle_id": ids[randi_range(0, ids.size() - 1)],
		"train_cap": int(TRAIN_FIGHT_CAPS.get(save.section_in, 30)),
		"counts_as_training": save.section_in <= 5,
	}


# Zone-map unlock rule (frame_449): zone 1 always; otherwise the linked
# zone's boss must be beaten (progress strictly past its progress_max).
static func is_zone_unlocked(save: PlayerSave, zone: int) -> bool:
	if zone == 1:
		return true
	var hub: Dictionary = QUEST_HUB.get(zone, {})
	if hub.is_empty():
		return false
	var linked: int = int(hub["linked_zone"])
	var linked_hub: Dictionary = QUEST_HUB.get(linked, {})
	if linked_hub.is_empty():
		return false
	return quest_progress(save, linked) > int(linked_hub["progress_max"])


# frame_449's difficulty gate on how much of the map exists at all:
# easy = zones 1-5, normal = 1-6, hard = 1-7. On hard, zone 7 additionally
# needs achievement 4, Legend (frame_449/DoAction.as:5 tests achGet[4]).
static func max_zone(difficulty: CombatUnit.Difficulty, has_legend_achievement: bool = false) -> int:
	if difficulty <= CombatUnit.Difficulty.EASY:
		return 5
	if difficulty == CombatUnit.Difficulty.NORMAL:
		return 6
	return 7 if has_legend_achievement else 6


# Post-battle progression (frame_219): a won story-progress fight advances
# quest_progress in the current zone, may trigger a cutscene, and may grow
# the party roster. Call ONLY on victory. Returns
# {progress_advanced, cutscene, goto_scene, roster_changed}.
static func after_battle_won(save: PlayerSave, battle_id: int, was_story_progress: bool) -> Dictionary:
	var cutscene: String = ""
	var goto_scene: String = ""
	var progress_advanced: bool = false
	if was_story_progress:
		save.quest_progress[save.section_in] = quest_progress(save, save.section_in) + 1
		progress_advanced = true
		cutscene = CUTSCENE_BATTLES.get(battle_id, "")
		goto_scene = CUTSCENE_GOTO_SCENE.get(cutscene, "")
	var roster_changed: bool = Party.update_roster_after_battle(save)
	return {
		"progress_advanced": progress_advanced,
		"cutscene": cutscene,
		"goto_scene": goto_scene,
		"roster_changed": roster_changed,
	}
