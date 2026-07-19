# achievements.gd
# The 10 achievements, ported from the full SWF script export (2026-07-18):
# definitions from frame1/sonny2_achievements.txt, the grant table from the
# victory screen (DefineSprite_3142/frame_9/DoAction_2.as), awardAch +
# SharedObject persistence from frame_46, checkIfAllStar from frame_42.
#
# Achievements are GLOBAL across saves (the original used a separate
# SharedObject; here a ConfigFile at user://achievements.cfg).
#
# Battle counters (the original's AchVal1-4) come from a finished
# BattleRunner via collect_battle_counters() - damage dealt by the player,
# whether/how many companions fought, and the half-turn count.
class_name Achievements
extends RefCounted

const SAVE_PATH = "user://achievements.cfg"
const ACHIEVEMENT_COUNT = 10

const NAMES = [
	"The Tape", "Black Magic", "Pacifist", "Predator", "Legend",
	"All Star", "Jail Break", "Doomsday", "Old Ghosts", "Over the Ashes",
]
const DESCRIPTIONS = [
	"Retrieve the tape from Felicity.",
	"Defeat Clemons for the first time, without using any team mates. This can only be done on Challenging or Heroic difficulty.",
	"Defeat the Hydra for the first time, without dealing more than 2000 damage throughout the whole fight. This can only be done on Challenging or Heroic difficulty.",
	"Defeat Captain Hunt without using any training fights, and without repeating any defeated bosses. This can only be done on Heroic difficulty.",
	"Defeat the Mayor without using any training fights, and without repeating any defeated bosses. This can only be done on Heroic difficulty.",
	"Defeat the Mayor on Heroic difficulty with all three classes",
	"Defeat Metal Warden using only one team member.",
	"Defeat the Time Bomb in less than 40 turns.",
	"Defeat Nostalgia without using any team members.",
	"Defeat the Corruptor in Zone 7.",
]


# The victory-screen grant table. counters: {player_damage_dealt (AchVal1),
# had_teammates (AchVal2), teammate_count (AchVal3), turns (AchVal4)}.
# Returns the achievement ids earned by this victory (unfiltered - the
# caller unlocks them; already-unlocked ids are ignored by unlock()).
static func check_battle_victory(save: PlayerSave, battle_id: int, was_story_progress: bool, counters: Dictionary) -> Array:
	var earned = []
	if was_story_progress:
		if battle_id == 109:
			earned.append(0)  # The Tape
		if save.difficulty > 0:
			if battle_id == 308 and not counters.get("had_teammates", false):
				earned.append(1)  # Black Magic
			if battle_id == 408 and counters.get("player_damage_dealt", 0.0) < 2000:
				earned.append(2)  # Pacifist
		if save.difficulty == 2 and not save.used_training:
			if battle_id == 212:
				earned.append(3)  # Predator
			if battle_id == 513:
				earned.append(4)  # Legend
	if battle_id == 600 and int(counters.get("teammate_count", 0)) == 1:
		earned.append(6)  # Jail Break
	if battle_id == 601 and int(counters.get("turns", 999)) <= 40:
		earned.append(7)  # Doomsday
	if battle_id == 602 and not counters.get("had_teammates", false):
		earned.append(8)  # Old Ghosts
	if battle_id == 703:
		earned.append(9)  # Over the Ashes
	return earned


# checkIfAllStar(): a Heroic-difficulty clear (zone 5 boss beaten -
# questProgress[5] > 13) on each of the 3 classes, scanned across every save
# (pass all slot saves plus the live one).
static func check_all_star(saves: Array) -> bool:
	var classes_cleared = {}
	for save in saves:
		if save == null:
			continue
		if save.difficulty == 2 and _quest_progress(save, 5) > 13:
			classes_cleared[save.player_class] = true
	return classes_cleared.size() >= 3


# Derives the original AchVal1-4 from a finished battle: total damage the
# PLAYER dealt (move events from slot 1, damage results, all-enemy splash
# included), companion presence/count (slots 3/5), and the half-turn count.
static func collect_battle_counters(runner: BattleRunner, units: Dictionary) -> Dictionary:
	var player_damage = 0.0
	for event in runner.events:
		if event.get("type") != "move" or int(event.get("caster_slot", 0)) != BattleRunner.PLAYER_SLOT:
			continue
		var result: Dictionary = event.get("result", {})
		if result.get("type") == "damage":
			player_damage += float(result.get("amount", 0.0)) + float(result.get("shielded_amount", 0.0))
	var teammate_count = 0
	for slot in [3, 5]:
		if units.get(slot) != null:
			teammate_count += 1
	return {
		"player_damage_dealt": player_damage,
		"had_teammates": teammate_count > 0,
		"teammate_count": teammate_count,
		"turns": runner.turn_count,
	}


# --- Global persistence (the original's achSlot SharedObject) ---

static func load_unlocked(path: String = SAVE_PATH) -> Array:
	var unlocked = []
	unlocked.resize(ACHIEVEMENT_COUNT)
	unlocked.fill(false)
	var config = ConfigFile.new()
	if config.load(path) == OK:
		for i in ACHIEVEMENT_COUNT:
			unlocked[i] = config.get_value("achievements", str(i), false)
	return unlocked


# Unlocks an achievement; returns true only when it was NEWLY unlocked (the
# original plays the "New Achievement!" banner on that).
static func unlock(achievement_id: int, path: String = SAVE_PATH) -> bool:
	if achievement_id < 0 or achievement_id >= ACHIEVEMENT_COUNT:
		return false
	var config = ConfigFile.new()
	config.load(path)  # missing file is fine - starts empty
	if config.get_value("achievements", str(achievement_id), false):
		return false
	config.set_value("achievements", str(achievement_id), true)
	config.save(path)
	return true


static func _quest_progress(save: PlayerSave, zone: int) -> int:
	if zone < 0 or zone >= save.quest_progress.size():
		return 0
	var value = save.quest_progress[zone]
	return int(value) if value is int or value is float else 0
