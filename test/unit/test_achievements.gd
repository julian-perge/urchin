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


func _damage(amount: float, direction: MoveResult.Direction) -> MoveResult:
	var result := MoveResult.new()
	result.kind = MoveResult.Kind.DAMAGE
	result.direction = direction
	result.amount = amount
	return result


func _player_move(result: MoveResult) -> Dictionary:
	return {"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2, "result": result}


# The original adds to AchVal1 only in its Full Damage branch, and there only
# when the target has no sswitch buff (frame_42/DoAction_8.as:82-93). So damage
# that healed under sswitch is left out, and so is a heal that hurt.
func test_damage_that_healed_under_sswitch_is_not_damage_dealt():
	var heal_that_hurt := MoveResult.new()
	heal_that_hurt.kind = MoveResult.Kind.HEAL
	heal_that_hurt.direction = MoveResult.Direction.HARM
	heal_that_hurt.amount = 5.0
	var runner := BattleRunner.new()
	runner.events = [
		_player_move(_damage(10.0, MoveResult.Direction.HARM)),
		_player_move(_damage(7.0, MoveResult.Direction.HEAL)),
		_player_move(heal_that_hurt),
	]
	var counters: Dictionary = Achievements.collect_battle_counters(runner, {})
	assert_eq(counters["player_damage_dealt"], 10.0, "only the hit that harmed counts")


# The original takes the shield off the damage before it adds the damage to
# AchVal1 (frame_42/DoAction_8.as:79-93), and the branch where the shield takes
# the whole hit adds nothing (lines 70-76).
func test_only_damage_that_got_past_a_shield_is_damage_dealt():
	var blocked: MoveResult = _damage(0.0, MoveResult.Direction.HARM)
	blocked.shield_took_all = true
	var runner := BattleRunner.new()
	runner.events = [
		_player_move(_damage(10.0, MoveResult.Direction.HARM)),
		_player_move(blocked),
	]
	var counters: Dictionary = Achievements.collect_battle_counters(runner, {})
	assert_eq(counters["player_damage_dealt"], 10.0, "what the shields took is left out")


# The original counts a teammate in AchVal2 and AchVal3 only when
# krinAddNewUnit spawns a companion (frame_42/DoAction_14.as:190-191). A guest
# in the same slots is not a companion, so it adds nothing.
func test_a_guest_in_a_teammate_slot_is_not_a_teammate():
	var companion := CombatUnit.new()
	companion.origin = CombatUnit.Origin.COMPANION
	var guest := CombatUnit.new()
	guest.origin = CombatUnit.Origin.GUEST
	var counters: Dictionary = Achievements.collect_battle_counters(BattleRunner.new(), {3: companion, 5: guest})
	assert_eq(counters["teammate_count"], 1, "only the companion counts")
	assert_true(counters["had_teammates"])
	counters = Achievements.collect_battle_counters(BattleRunner.new(), {3: guest, 5: guest})
	assert_eq(counters["teammate_count"], 0)
	assert_false(counters["had_teammates"], "a battle with only guests has no teammates")


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
