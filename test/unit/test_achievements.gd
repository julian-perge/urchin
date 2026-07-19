# Unit tests for Achievements - grant table from the victory screen
# (DefineSprite_3142/frame_9/DoAction_2.as), all-star scan, persistence.
extends GutTest

const TEST_SAVE_PATH = "user://test_achievements.cfg"

var save: PlayerSave


func before_each():
	save = PlayerSave.new_game("Test", 0)
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)


func after_all():
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)


func _counters(damage: float = 0.0, teammates: int = 0, turns: int = 10) -> Dictionary:
	return {
		"player_damage_dealt": damage,
		"had_teammates": teammates > 0,
		"teammate_count": teammates,
		"turns": turns,
	}


func test_the_tape():
	assert_has(Achievements.check_battle_victory(save, 109, true, _counters()), 0)
	assert_eq(Achievements.check_battle_victory(save, 109, false, _counters()), [], "repeat boss win does not count")


func test_difficulty_gated_achievements():
	save.difficulty = 0
	assert_eq(Achievements.check_battle_victory(save, 308, true, _counters()), [], "Black Magic needs Challenging+")
	save.difficulty = 1
	assert_has(Achievements.check_battle_victory(save, 308, true, _counters(0, 0)), 1)
	assert_eq(Achievements.check_battle_victory(save, 308, true, _counters(0, 2)), [], "no teammates allowed")
	assert_has(Achievements.check_battle_victory(save, 408, true, _counters(1999)), 2)
	assert_eq(Achievements.check_battle_victory(save, 408, true, _counters(2000)), [], "Pacifist damage cap")


func test_heroic_no_training_achievements():
	save.difficulty = 2
	save.used_training = false
	assert_has(Achievements.check_battle_victory(save, 212, true, _counters()), 3)
	assert_has(Achievements.check_battle_victory(save, 513, true, _counters()), 4)
	save.used_training = true
	assert_eq(Achievements.check_battle_victory(save, 212, true, _counters()), [], "training use disqualifies")


func test_zone_6_and_7_achievements():
	assert_has(Achievements.check_battle_victory(save, 600, false, _counters(0, 1)), 6)
	assert_eq(Achievements.check_battle_victory(save, 600, false, _counters(0, 2)), [], "Jail Break wants exactly one teammate")
	assert_has(Achievements.check_battle_victory(save, 601, false, _counters(0, 0, 40)), 7)
	assert_eq(Achievements.check_battle_victory(save, 601, false, _counters(0, 0, 41)), [], "Doomsday turn limit")
	assert_has(Achievements.check_battle_victory(save, 602, false, _counters(0, 0)), 8)
	assert_has(Achievements.check_battle_victory(save, 703, false, _counters()), 9)


func test_all_star():
	var saves = []
	for player_class in 3:
		var clear = PlayerSave.new_game("Class%d" % player_class, player_class)
		clear.difficulty = 2
		clear.quest_progress[5] = 14
		saves.append(clear)
	assert_true(Achievements.check_all_star(saves))
	saves[2].difficulty = 1
	assert_false(Achievements.check_all_star(saves), "all three must be Heroic clears")
	saves[2].difficulty = 2
	saves[2].quest_progress[5] = 13
	assert_false(Achievements.check_all_star(saves), "zone 5 boss must be beaten (progress past 13)")


func test_persistence():
	assert_eq(Achievements.load_unlocked(TEST_SAVE_PATH), [false, false, false, false, false, false, false, false, false, false])
	assert_true(Achievements.unlock(0, TEST_SAVE_PATH), "first unlock is new")
	assert_false(Achievements.unlock(0, TEST_SAVE_PATH), "second unlock is not")
	var unlocked = Achievements.load_unlocked(TEST_SAVE_PATH)
	assert_true(unlocked[0])
	assert_false(unlocked[1])
	assert_false(Achievements.unlock(99, TEST_SAVE_PATH), "out of range rejected")
