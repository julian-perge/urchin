# Integration tests for the battle turn-loop (GUT): BattleRunner + BattleAI +
# BattleManager + CombatUnit + TalentTree against the real converted data.
# Run headless: $GODOT --headless -s res://addons/gut/gut_cmdln.gd --path .
# (config in .gutconfig.json), or via the GUT panel in the editor.
extends GutTest

# A fight that reaches this cap fails its is_over assert instead of hanging the
# suite. The longest of 300 seeded runs of each fight here took 149 half-turns.
const MAX_HALF_TURNS = 900

var moves_by_id: Dictionary = {}
var buffs_by_id: Dictionary = {}
var buffs_by_name: Dictionary = {}
var unit_templates: Dictionary = {}  # id -> Character


func before_all():
	moves_by_id = MoveManagerAuto.moves_by_id
	buffs_by_id = BuffManagerAuto.buffs_by_id
	buffs_by_name = BuffManagerAuto.buffs_by_internal_name
	unit_templates = UnitManagerAuto.units_by_id


func test_all_moves_parse_including_undefined_heavy_move_0():
	assert_eq(moves_by_id.size(), 479)
	assert_true(moves_by_id.has(0), "move 0 present")
	assert_eq(moves_by_id[0].focus_cost, 0.0, "Undefined JSON values coerced to defaults")


func test_all_buffs_parse_with_decoded_fields():
	assert_eq(buffs_by_id.size(), 470)
	var unique_count = 0
	for buff in buffs_by_id.values():
		if buff.is_unique:
			unique_count += 1
	assert_eq(unique_count, 142, "142 'cannot stack' buffs carry is_unique")


func test_unit_id_corrections_applied():
	assert_eq(unit_templates.size(), 75)
	assert_eq(unit_templates[15].name, "Doctor Hedger", "Steam dump said 19, true id 15")
	assert_eq(unit_templates[34].name, "ZPCI Sniper", "Steam dump said 39, true id 34")


# All three factories start from CombatUnit.new(), so each unit has to get its
# own arrays and buff slots from it, and the change arrays have to keep the
# fractions buffs add to them.
func test_a_new_unit_has_its_own_blank_buff_state():
	var first: CombatUnit = CombatUnit.new()
	var second: CombatUnit = CombatUnit.new()
	assert_eq(first.change_array.size(), 12)
	assert_eq(first.change_array_ep.size(), 8)
	assert_eq(first.change_array_ep2.size(), 8)
	assert_eq(first.change_array_ed.size(), 8)
	assert_eq(first.change_array_ed2.size(), 8)
	assert_eq(first.dot_ticker_array.size(), 10)
	assert_eq(first.buff_slots.size(), CombatUnit.MAX_BUFF_LIMIT)
	assert_eq(first.buff_slots[39], {"cd": 0, "buff_id": -1, "buff_value": 0.0, "shield_buff_value": 0.0})

	first.change_array[5] = -0.3
	first.buff_slots[0]["cd"] = 4
	assert_eq(first.change_array[5], -0.3, "a fraction stays a fraction")
	assert_eq(second.change_array[5], 0.0, "the other unit's array is its own")
	assert_eq(second.buff_slots[0]["cd"], 0, "and so are its buff slots")


func test_every_factory_starts_its_unit_at_full_life_and_focus():
	var save: PlayerSave = PlayerSave.new_game("Full", PlayerSave.PlayerClass.BIOLOGICAL)
	var built: Array = [
		CombatUnit.from_player_save(save),
		CombatUnit.from_character(unit_templates[5], 10, CombatUnit.Difficulty.NORMAL, 2),
		Party.build_companion_unit(save, 1, unit_templates, 3),
	]
	for unit in built:
		assert_gt(unit.base_life, 0.0, "%s has life to start with" % unit.player_name)
		assert_eq(unit.life_n, unit.base_life, "%s's current life is full" % unit.player_name)
		assert_eq(unit.life_u, unit.base_life, "%s's maximum life is its base life" % unit.player_name)
		assert_eq(unit.focus_n, unit.base_focus, "%s's current focus is full" % unit.player_name)
		assert_eq(unit.focus_u, unit.base_focus, "%s's maximum focus is its base focus" % unit.player_name)
		assert_eq(unit.speed_u, unit.base_speed, "%s's derived stats are worked out" % unit.player_name)


# Unit 11 is the Felicity boss, whose record holds five absolute moves with
# phase locks, and the companion Veradux uses the pools of unit 4.
func test_a_units_moves_come_from_its_template_with_every_cooldown_at_zero():
	var boss: CombatUnit = CombatUnit.from_character(unit_templates[11], 7, CombatUnit.Difficulty.HARD, 2)
	assert_eq(boss.move_pool_absolute[2], {"id": 530, "phase": 2})
	assert_not_same(boss.move_pool_absolute[2], unit_templates[11].moves["absolute"][2], "each absolute entry is the unit's own copy")
	assert_eq(boss.cooldowns_absolute, [0, 0, 0, 0, 0])
	assert_eq(boss.cooldowns_attack.size(), boss.move_pool_attack.size())
	assert_eq(boss.cooldowns_defense.size(), boss.move_pool_defense.size())

	var save: PlayerSave = PlayerSave.new_game("Moves", PlayerSave.PlayerClass.BIOLOGICAL)
	var veradux: CombatUnit = Party.build_companion_unit(save, 1, unit_templates, 3)
	var template_moves: Array = unit_templates[4].moves["attack"]
	assert_eq(veradux.move_pool_attack, template_moves)
	assert_not_same(veradux.move_pool_attack, template_moves, "the unit's pool is its own copy")
	assert_eq(veradux.cooldowns_attack, [0, 0])


func test_element_from_name_matches_element_order_position():
	assert_eq(CombatUnit.element_from_name("Physical"), CombatUnit.Element.PHYSICAL)
	assert_eq(CombatUnit.element_from_name("Fire"), CombatUnit.Element.FIRE)
	assert_eq(CombatUnit.element_from_name("Poison"), CombatUnit.Element.POISON)
	assert_eq(CombatUnit.element_from_name("NotAnElement"), -1, "unknown name returns -1, same as ELEMENT_ORDER.find()")


func test_from_character_populates_ai_fields():
	var veradux = CombatUnit.from_character(unit_templates[4], 5, CombatUnit.Difficulty.HARD, 5)
	assert_true(veradux.ai_enabled)
	assert_eq(veradux.aggression, 50.0)
	assert_eq(veradux.life_boundary_1, 80.0)
	assert_eq(veradux.life_boundary_2, 20.0)
	assert_eq(veradux.focus_aggression, 50.0)
	assert_eq(veradux.focus_regen_limit, 15.0)
	assert_eq(veradux.move_pool_attack.size(), 2)
	assert_eq(veradux.move_pool_defense.size(), 1)


# The expected values are what krinAddNewUnit (frame_42/DoAction_14.as) gives
# Prison Guard on Normal. Below level 10 the original shrinks the difficulty
# multipliers further, and level 10 is the first level where it does not.
func test_from_character_shrinks_stats_below_level_10():
	var expected_by_level: Dictionary = {
		1: {"life": 212.0, "strength": 8.0, "magic": 4.0, "speed": 12.0},
		5: {"life": 484.0, "strength": 16.0, "magic": 8.0, "speed": 23.0},
		9: {"life": 986.0, "strength": 29.0, "magic": 14.0, "speed": 43.0},
		10: {"life": 1193.0, "strength": 34.0, "magic": 17.0, "speed": 51.0},
	}
	for level in expected_by_level:
		var expected: Dictionary = expected_by_level[level]
		var guard: CombatUnit = CombatUnit.from_character(unit_templates[5], level, CombatUnit.Difficulty.NORMAL, 2)
		assert_eq(guard.base_life, expected["life"], "life at level %d" % level)
		assert_eq(guard.base_strength, expected["strength"], "strength at level %d" % level)
		assert_eq(guard.base_magic, expected["magic"], "magic at level %d" % level)
		assert_eq(guard.base_speed, expected["speed"], "speed at level %d" % level)


# Bunny's record never sets voiceDie (frame_42/DoAction_13.as:543-551), and the
# original's addSound plays nothing for an undefined cue
# (frame_42/DoAction.as:7), so the port gives Bunny an empty die voice, which
# AudioManager.play_effect skips. Battle 406 fields Bunny at level 18 in slot 2.
func test_from_character_gives_bunny_an_empty_die_voice():
	var bunny: Character = load("res://resources/units/56_bunny.tres")
	var unit: CombatUnit = CombatUnit.from_character(bunny, 18, CombatUnit.Difficulty.NORMAL, 2)
	assert_not_null(unit, "from_character finished building Bunny")
	assert_eq(unit.voice_die, "")


func test_player_from_save_with_talent_passives():
	var save = PlayerSave.new_game("Smoke", 0)
	save.level = 5
	save.skill_points = 10
	TalentTree.learn(save, 0)  # Vicious Strike rank 1
	TalentTree.learn(save, 0)  # rank 2 -> move 101
	TalentTree.learn(save, 1)  # INTEGRITY1 passive
	var player = CombatUnit.from_player_save(save)
	assert_eq(player.life_u, round(save.life * 33), "player stats absolute, not getStat curves")
	assert_eq(
		player.base_per[CombatUnit.Element.PHYSICAL], 100.0 + 15.0 * save.level,
		"PER = allocation + 100 + 15 per level"
	)
	assert_has(TalentTree.get_known_move_ids(save), 101, "upgraded rank in known moves")

	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	player.ai_enabled = true
	player.move_pool_attack = TalentTree.get_known_move_ids(save)
	player.cooldowns_attack = []
	for i in player.move_pool_attack.size():
		player.cooldowns_attack.append(0)
	var enemy = CombatUnit.from_character(unit_templates[5], 1, CombatUnit.Difficulty.HARD, 2)
	runner.setup(
		{1: player, 2: enemy}, null, moves_by_id, buffs_by_id, buffs_by_name, manager,
		TalentTree.get_passive_buff_names(save)
	)
	assert_true(
		_has_active_buff(player, "INTEGRITY1"),
		"passive applied at battle load (duration -1 = permanent)"
	)
	var half_turns = _run_to_completion(runner)
	assert_true(runner.is_over(), "skirmish terminates (took %d half-turns)" % half_turns)


# The original adds the player's heal to healedThisTurn when the pick is made
# (frame_42/DoAction_11.as:92-95), and the AI allies decide after that: once
# the pick is in on Easy and Normal, and one frame before the half-turn starts
# on Heroic (frame_217/PlaceObject2_3389_480 enterFrame, lines 643-670 and
# 674-698). Restore rank 1 multiplies strength and magic by 1
# (frame_42/DoAction_6.as:899-902), so Sonny's 100 strength and 100 magic queue
# 200 on Veradux. That lifts Veradux from 40% to a predicted 80%, above Sonny's
# 60%, so Veradux heals Sonny instead of himself.
func test_an_ally_heals_someone_else_when_the_player_already_heals_it():
	var runner: BattleRunner = _queued_heal_runner()
	var events: Array = runner.advance_half_turn({"target_slot": 3, "move_id": 228})
	assert_eq(runner.healed_this_turn[3], 200.0, "Sonny's Restore is queued on Veradux")
	assert_eq(_move_target(events, 3), BattleRunner.PLAYER_SLOT, "so Veradux heals Sonny")


# The same fight with Sonny passing, which queues nothing, so Veradux at 40% is
# below Sonny's 60% and heals himself. It shows that the choice in the test
# above comes from Sonny's queued heal.
func test_an_ally_heals_itself_when_the_player_passes():
	var runner: BattleRunner = _queued_heal_runner()
	var events: Array = runner.advance_half_turn({})
	assert_eq(_move_target(events, 3), 3, "Veradux heals himself")


# TeamSelect fixes who acts in what order once per full turn. It runs only when
# TurnTime reaches 0 (frame_217/PlaceObject2_3389_480 enterFrame, lines 147
# and 262-264), its TeamSpeedAdder writes each unit's teamAdder
# (frame_217/DoAction_2.as:284-310), and krinAddMove files the unit's move at
# that position (frame_42/DoAction_4.as:28-33). Slot 2 starts faster than slot
# 4, and after the first half-turn it loses 20 speed, the way a speed debuff
# landing in that half-turn would lower it, which drops it below slot 4. Slot 2
# still acts first in the second half-turn, and slot 4 only goes first from the
# next full turn.
func test_a_speed_change_reorders_a_team_from_the_next_full_turn():
	var save: PlayerSave = PlayerSave.new_game("Sonny")
	save.speed = 100.0
	save.life = 1000.0
	var player: CombatUnit = CombatUnit.from_player_save(save)
	var bio: CombatUnit = CombatUnit.from_character(unit_templates[1], 10, CombatUnit.Difficulty.HARD, 2)
	var guard: CombatUnit = CombatUnit.from_character(unit_templates[5], 10, CombatUnit.Difficulty.HARD, 4)
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	runner.setup({1: player, 2: bio, 4: guard}, null, moves_by_id, buffs_by_id, buffs_by_name, manager, [])
	assert_true(runner.is_player_turn(), "Sonny's team opens")
	assert_gt(bio.speed_u, guard.speed_u, "slot 2 starts faster than slot 4")

	runner.advance_half_turn()
	bio.change_array[4] -= 20
	bio.apply_changes()
	assert_lt(bio.speed_u, guard.speed_u, "slot 2 is now slower than slot 4")
	var second_half: Array = runner.advance_half_turn()
	assert_eq(_acting_order(second_half), [2, 4], "the second half-turn keeps the order the full turn started with")

	runner.advance_half_turn()
	var next_full_turn: Array = runner.advance_half_turn()
	assert_eq(_acting_order(next_full_turn), [4, 2], "the next full turn sorts by the new speeds")


# The original names the player's battle unit "Sonny" whatever the save is
# called (frame_201/DoAction.as:201), so battle 100's "Sonny" line finds the
# player as its speaker instead of finding nobody and being skipped.
func test_the_players_battle_unit_is_sonny_whatever_the_save_is_named():
	var save = PlayerSave.new_game("< Enter Name Here >", 0)
	var battle: BattleFight = BattleSetup.load_battle(100)
	var units: Dictionary = _roster_for(battle, save)
	assert_eq(units[BattleRunner.PLAYER_SLOT].player_name, "Sonny", "the player's battle unit")
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	var setup_events: Array = runner.setup(units, battle, moves_by_id, buffs_by_id, buffs_by_name, manager, [])
	var doorbell: Dictionary = {}
	for event in setup_events:
		if event["type"] == BattleRunner.EventType.SPEECH and event["say"] == "Sorry about the gate, I couldn't find the doorbell.":
			doorbell = event
	assert_false(doorbell.is_empty(), "battle 100's Sonny line plays as the battle starts")
	assert_eq(doorbell.get("speaker_slot", -1), BattleRunner.PLAYER_SLOT, "and the player says it")


# FROST1 takes 30% off speed. Its field 7 is -0.3, applyBuffKrin adds that to
# changeArray[5], and applyChangesKrin sets SPEEDU to
# ceil((SPEED + changeArray[4]) * (1 + changeArray[5]))
# (frame_42/DoAction_10.as:188, 261). The test covers one unit from each factory
# and runs FROST1's 12 turns out to check that speed comes back.
func test_frost_takes_30_percent_off_speed_for_a_player_an_enemy_and_a_companion():
	var save: PlayerSave = PlayerSave.new_game("Frost", PlayerSave.PlayerClass.BIOLOGICAL)
	save.level = 10
	Leveling.compute_stats(save)
	var frost: Buff = buffs_by_name["FROST1"]
	var cases: Array = [
		["the level 10 player", CombatUnit.from_player_save(save), 17.0, 12.0],
		["a level 10 Prison Guard", CombatUnit.from_character(unit_templates[5], 10, CombatUnit.Difficulty.NORMAL, 2), 51.0, 36.0],
		["Veradux at level 1", Party.build_companion_unit(save, 1, unit_templates, 3), 19.0, 14.0],
	]
	for case in cases:
		var unit: CombatUnit = case[1]
		assert_eq(unit.speed_u, case[2], "%s before FROST1" % case[0])
		unit.apply_buff(frost, 1, unit)
		unit.apply_changes()
		assert_eq(unit.speed_u, case[3], "%s under FROST1 is ceil(%d * 0.7)" % [case[0], case[2]])
		for turn in frost.duration_turns:
			unit.tick_buffs(buffs_by_id)
		assert_eq(unit.speed_u, case[2], "%s once FROST1 runs out" % case[0])


# Surprise Shot takes 70% off speed and is not unique, so a second one stacks
# and leaves 1 - 1.4 = -0.4 of the unit's speed. applyChangesKrin rounds that up
# and then clamps SPEEDU at 0 (frame_42/DoAction_10.as:261, 270-273).
func test_two_surprise_shots_leave_speed_at_0_not_below():
	var save: PlayerSave = PlayerSave.new_game("Shot", PlayerSave.PlayerClass.BIOLOGICAL)
	save.level = 10
	Leveling.compute_stats(save)
	var player: CombatUnit = CombatUnit.from_player_save(save)
	var surprise_shot: Buff = buffs_by_name["PSURPRISESHOT"]
	assert_false(surprise_shot.is_unique, "a second Surprise Shot stacks instead of refreshing the first")
	player.apply_buff(surprise_shot, 1, player)
	player.apply_changes()
	assert_eq(player.speed_u, 6.0, "one Surprise Shot leaves ceil(17 * 0.3)")
	player.apply_buff(surprise_shot, 1, player)
	player.apply_changes()
	assert_eq(player.speed_u, 0.0, "two leave ceil(17 * -0.4) = -6, clamped to 0")


# Assault Tactics gives the Secret Police "25% more damage". SPASSAULTTACTICS
# field 11 is 0.25, applyBuffKrin adds it to changeArray[9], applyChangesKrin
# copies that to DMG2, and executeMove multiplies the hit by 1 + DMG2
# (frame_42/DoAction_10.as:188, 310; frame_42/DoAction_8.as:60). Both hits run
# on the same seed, so they make the same crit roll. The plain hit is some x
# rounded up and the buffed hit is 1.25 * x rounded up, which puts the buffed
# hit between ceil(1.25 * (plain - 1)) and ceil(1.25 * plain).
func test_assault_tactics_makes_the_secret_police_hit_25_percent_harder():
	var manager: BattleManager = autofree(BattleManager.new())
	var secret_police: CombatUnit = CombatUnit.from_character(unit_templates[62], 21, CombatUnit.Difficulty.HARD, 2)
	var snipe: Ability = moves_by_id[734]
	assert_eq(snipe.status_effect_id, "", "Snipe applies no buff of its own")
	seed(20261108)
	var plain_target: CombatUnit = CombatUnit.from_character(unit_templates[5], 21, CombatUnit.Difficulty.HARD, 1)
	var plain: float = manager.execute_move(snipe, secret_police, plain_target, buffs_by_name)["amount"]
	secret_police.apply_buff(buffs_by_name["SPASSAULTTACTICS"], 1, secret_police)
	secret_police.apply_changes()
	assert_eq(secret_police.dmg2, 0.25, "DMG2 holds the buff's 0.25")
	seed(20261108)
	var buffed_target: CombatUnit = CombatUnit.from_character(unit_templates[5], 21, CombatUnit.Difficulty.HARD, 1)
	var buffed: float = manager.execute_move(snipe, secret_police, buffed_target, buffs_by_name)["amount"]
	assert_between(buffed, ceil(1.25 * (plain - 1)), ceil(1.25 * plain), "Snipe hit for %d without the buff" % plain)
	randomize()


# Burning Acid lowers "Fire Defense by 20%". BURNINGACID field 24 is -0.2,
# applyBuffKrin adds it to changeArrayED2 at the buff's own element only, and
# applyChangesKrin sets DEFU to (DEF + changeArrayED) * (changeArrayED2 + 1)
# (frame_42/DoAction_10.as:227-232, 332-333). A level 10 player's defense is
# 100 + 15 * 10 = 250 in every element, so Fire drops to 200 and Physical
# stays at 250.
func test_burning_acid_takes_20_percent_off_fire_defense_only():
	var save: PlayerSave = PlayerSave.new_game("Acid", PlayerSave.PlayerClass.BIOLOGICAL)
	save.level = 10
	var player: CombatUnit = CombatUnit.from_player_save(save)
	player.apply_buff(buffs_by_name["BURNINGACID"], 1, player)
	player.apply_changes()
	assert_eq(player.def_u[CombatUnit.Element.FIRE], 200.0, "Fire defense is 250 * 0.8")
	assert_eq(player.def_u[CombatUnit.Element.PHYSICAL], 250.0, "Physical defense is untouched")


func test_battle_100_simple_fight():
	_assert_battle_runs(100)


func test_battle_104_boss_phases_and_speeches():
	var counts = _assert_battle_runs(104)
	assert_gt(counts.get(BattleRunner.EventType.SPEECH, 0), 0, "scripted dialogue fired")


# battle_scene.gd never reads runner.events directly - it only ever plays
# whatever advance_half_turn() returns, which slices runner.events from that
# specific call's own starting size. A turnTime:0 speech (meant to play the
# instant the battle begins) gets drained by setup()'s own pre-loop
# _drain_speeches() call, before any advance_half_turn() has run - so it
# lands in runner.events ahead of every future call's slice window and is
# never actually shown in play, even though runner.events (what
# test_battle_104_boss_phases_and_speeches checks) does contain it. Battle
# 105 (a Doctor Leath fight - "Twisted Experiment") has exactly one speech,
# at turnTime:0, so it's a clean single-speech reproduction of the bug.
func test_setup_returns_its_own_turn_time_zero_speeches():
	var battle: BattleFight = BattleSetup.load_battle(105)
	assert_not_null(battle)
	assert_eq(battle.speeches.size(), 1)
	assert_eq(int(battle.speeches[0]["turnTime"]), 0, "the one speech fires at battle start, not mid-turn")
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	var setup_events: Array = runner.setup(
		_roster_for(battle), battle, moves_by_id, buffs_by_id, buffs_by_name, manager, []
	)
	var has_speech: bool = false
	for event in setup_events:
		if event["type"] == BattleRunner.EventType.SPEECH:
			has_speech = true
	assert_true(has_speech, "the turnTime:0 speech is returned by setup(), not left stranded in runner.events")


# getPNum looks a named speaker up in slots 1 to 6 and returns NaN when no unit
# there has that name (frame_42/DoAction_14.as:285-302). The conductor skips
# such a line, because no playerKrinNaN exists to be active, and it only moves
# on to the next line of a conversation after showing one, so the line after a
# skipped one never plays either (frame_217/PlaceObject2_3389_480 enterFrame,
# lines 813-818 and 852-856). A fresh save hasn't joined Roald, so battle 403
# has no Roald: Veradux's opening line plays, Roald's reply is skipped, and
# Sonny's answer to Roald never plays.
func test_a_line_whose_speaker_is_not_on_the_field_is_skipped():
	var battle: BattleFight = BattleSetup.load_battle(403)
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	var setup_events: Array = runner.setup(
		_roster_for(battle), battle, moves_by_id, buffs_by_id, buffs_by_name, manager, []
	)
	var lines: Array = []
	for event in setup_events:
		if event["type"] == BattleRunner.EventType.SPEECH:
			lines.append([event["speaker_slot"], event["say"]])
	assert_eq(
		lines, [[3, "That one looks just like Sonny! Haha!"]],
		"only Veradux speaks, and neither Roald's line nor the answer to it plays"
	)


# Once a batch of lines is done, or straight away when none plays, the conductor
# checks the phase entry it has just passed for endGame and takes its winOrLose
# (frame_217/PlaceObject2_3389_480 enterFrame, lines 862-870). Battles 210, 409,
# 504 and 508 push their only phase entry, flagged endGame, as phases[0]
# (frame_42/DoAction_14.as:1093 for 504), and phase starts at 1, so each is won
# as soon as its opening lines are done, before anyone fights.
func test_a_battle_whose_first_phase_ends_it_is_won_after_its_opening_lines():
	var opening_lines: Dictionary = {210: 4, 409: 2, 504: 2, 508: 4}
	for battle_id in opening_lines:
		var battle: BattleFight = BattleSetup.load_battle(battle_id)
		var runner = BattleRunner.new()
		var manager: BattleManager = autofree(BattleManager.new())
		var setup_events: Array = runner.setup(
			_roster_for(battle), battle, moves_by_id, buffs_by_id, buffs_by_name, manager, []
		)
		var said: Array = setup_events.filter(func(event): return event["type"] == BattleRunner.EventType.SPEECH)
		assert_eq(said.size(), opening_lines[battle_id], "battle %d plays its opening lines" % battle_id)
		assert_eq(runner.win_condition, BattleRunner.Outcome.WIN, "and battle %d is won before a half-turn" % battle_id)


# 109, 201 and 212 flag a later phase entry instead, so each is won once the
# phase after it opens and that phase's lines are done: 109 and 212 at phase 4,
# when the watched boss falls to 10% and 15% life, and 201 at phase 2. Every
# phase advance moves the phase on and sets turnTimeKKK2 back to 0 before the
# speech pass looks for lines (lines 176-193), which is the walk below. Battle
# 212's phase 4 opens with Roald, so the save here has him joined.
func test_the_phase_after_an_end_game_entry_ends_the_battle_after_its_lines():
	var lines_at_the_end: Dictionary = {109: 2, 201: 12, 212: 2}
	var last_phase: Dictionary = {109: 4, 201: 2, 212: 4}
	for battle_id in lines_at_the_end:
		var battle: BattleFight = BattleSetup.load_battle(battle_id)
		var save: PlayerSave = _save_for(battle)
		save.party_roster = [0, 1, 2, -1, -1, -1]
		var runner = BattleRunner.new()
		var manager: BattleManager = autofree(BattleManager.new())
		runner.setup(_roster_for(battle, save), battle, moves_by_id, buffs_by_id, buffs_by_name, manager, [])
		var said: Array = []
		var over_early: bool = false
		for next_phase in range(2, last_phase[battle_id] + 1):
			over_early = over_early or runner.is_over()
			runner.phase = next_phase
			runner.turns_in_phase = 0
			var start: int = runner.events.size()
			runner._drain_speeches()
			said = runner.events.slice(start).filter(func(event): return event["type"] == BattleRunner.EventType.SPEECH)
		assert_false(over_early, "battle %d is still on before its last phase" % battle_id)
		assert_eq(said.size(), lines_at_the_end[battle_id], "battle %d plays the lines that open its last phase" % battle_id)
		assert_eq(runner.win_condition, BattleRunner.Outcome.WIN, "and battle %d is won after them" % battle_id)


# Space ends the line on screen and sets hardSkip
# (frame_217/PlaceObject2_3367_634 onClipEvent(keyDown), lines 2-9). While it
# holds, the conductor skips the next line of the conversation without counting
# it (frame_217/PlaceObject2_3389_480 enterFrame, lines 815 and 852-856), so if
# the conversation goes on, the line after that never matches and no later line
# plays. Cut during Sonny's reply, the tutorial skips its third line and never
# reaches its turnTime 2 conversation. Cut during the opening's fourth line, the
# skip takes the fifth and last, and cut during that last line nothing is left
# to skip, so in both the turnTime 2 conversation still plays.
func test_space_skips_the_next_line_and_strands_the_rest():
	assert_eq(_tutorial_turn_2_lines_after_space_on(1), [], "cut on Sonny's reply, nothing more plays")
	assert_eq(_tutorial_turn_2_lines_after_space_on(3).size(), 4, "cut on the fourth line, the next conversation plays")
	assert_eq(_tutorial_turn_2_lines_after_space_on(4).size(), 4, "cut on the last line, the next conversation plays")


# Runs the tutorial's opening, has Space cut the given line, and returns the
# SPEECH events the turnTime 2 conversation plays when its time comes.
func _tutorial_turn_2_lines_after_space_on(speech_index: int) -> Array:
	var battle: BattleFight = BattleSetup.load_battle(2)
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	runner.setup(_roster_for(battle), battle, moves_by_id, buffs_by_id, buffs_by_name, manager, [])
	runner.hard_skip(speech_index)
	runner.turns_in_phase = 2
	var start: int = runner.events.size()
	runner._drain_speeches()
	return runner.events.slice(start).filter(func(event): return event["type"] == BattleRunner.EventType.SPEECH)


func test_battle_51_end_game_phase():
	_assert_battle_runs(51)


# A miss used to be logged as its own bare "miss" event, which
# battle_scene.gd played as a standalone floating label with no animation -
# _play_move_event() (the run/swing/cast presentation) only ever triggers on
# a "move" event. This asserts every miss is shaped like every other move
# result (type "move", a real result.type of "miss") instead of the old
# standalone shape.
#
# The run is seeded because battle 51's misses come from the real miss_chance
# formula and its AI picks moves with randi_range, so an unseeded run produced
# a different number of misses every time and occasionally none at all, which
# failed the count assert below and drifted the whole suite's assert total.
# This seed gives 7 misses over 26 half-turns, the same every run. The global
# RNG is handed back at the end so the tests after this one are unaffected.
func test_misses_are_move_events_not_a_separate_type():
	seed(20260823)
	var battle: BattleFight = BattleSetup.load_battle(51)
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	runner.setup(_ai_driven_roster_for(battle), battle, moves_by_id, buffs_by_id, buffs_by_name, manager, [])
	_run_to_completion(runner)
	var miss_count: int = 0
	for event in runner.events:
		if event.get("type") == BattleRunner.EventType.MOVE and event.get("result", {}).get("type") == BattleManager.ResultType.MISS:
			miss_count += 1
			assert_ne(
				int(event["caster_slot"]), int(event["target_slot"]),
				"miss still names the real target, not the attacker"
			)
	assert_gt(miss_count, 0, "battle 51 produces at least one miss")
	randomize()


# The original's hit roll divides the target's speed by the caster's speed
# times the move's speed modifier with no guard (the conductor, line 362).
# With both speeds at 0 that is 0 divided by 0, and the result fails every
# comparison after it, so the move always misses. The test sets both speeds
# directly, because in play only stacked speed debuffs take a unit to 0.
func test_accuracy_roll_always_misses_when_both_speeds_are_0():
	var runner = BattleRunner.new()
	var caster: CombatUnit = CombatUnit.from_character(unit_templates[5], 10, CombatUnit.Difficulty.HARD, 2)
	var target: CombatUnit = CombatUnit.from_character(unit_templates[5], 10, CombatUnit.Difficulty.HARD, 1)
	caster.speed_u = 0.0
	target.speed_u = 0.0
	var hits: int = 0
	for attempt in 200:
		if runner._accuracy_roll(caster, target, moves_by_id[1]):
			hits += 1
	assert_eq(hits, 0, "Leading Strike never hits when both speeds are 0")


# With only the caster's speed at 0 the same division gives Infinity, which the
# original caps at a miss chance of 75, so the move hits on any roll above 75.
# Each seed runs twice, once to read the roll it gives and once through
# _accuracy_roll, and the global RNG is handed back at the end.
func test_accuracy_roll_keeps_a_75_miss_chance_when_only_the_casters_speed_is_0():
	var runner = BattleRunner.new()
	var caster: CombatUnit = CombatUnit.from_character(unit_templates[5], 10, CombatUnit.Difficulty.HARD, 2)
	var target: CombatUnit = CombatUnit.from_character(unit_templates[5], 10, CombatUnit.Difficulty.HARD, 1)
	caster.speed_u = 0.0
	var mismatches: int = 0
	for roll_seed in 200:
		seed(roll_seed)
		var roll: int = randi_range(0, 99)
		seed(roll_seed)
		if runner._accuracy_roll(caster, target, moves_by_id[1]) != (roll > 75):
			mismatches += 1
	assert_eq(mismatches, 0, "Leading Strike hits exactly when the roll is above 75")
	randomize()


# Shatter Bolt (move 521) is the one move whose effect_category is "Attack",
# and the original's executeMove() has no branch for that category. The
# conductor still applies the move's status effect after executeMove(), and a
# proc chance of 2.4 means every hit lands SHATTERBOLT, a unique Ice debuff with
# stun 1 and duration 2 (frame_42/DoAction_6.as:1716-1719,
# frame_42/DoAction_10.as:1629-1636).
func test_shatter_bolt_stuns_its_target():
	var frost_terror: CombatUnit = CombatUnit.from_character(unit_templates[25], 9, CombatUnit.Difficulty.HARD, 2)
	var target: CombatUnit = CombatUnit.from_character(unit_templates[1], 9, CombatUnit.Difficulty.HARD, 1)
	var manager: BattleManager = autofree(BattleManager.new())
	var result: Dictionary = manager.execute_move(moves_by_id[521], frost_terror, target, buffs_by_name)

	assert_false(result.has("amount"), "Shatter Bolt deals no damage, so its result carries no amount")
	var shatterbolt: Buff = buffs_by_name["SHATTERBOLT"]
	var turns_left: Array = []
	for slot in target.buff_slots:
		if slot["buff_id"] == shatterbolt.id:
			turns_left.append(slot["cd"])
	assert_eq(turns_left, [2], "the target holds one SHATTERBOLT with its full duration of 2")
	assert_eq(target.stun, 1.0, "SHATTERBOLT stuns by 1")
	assert_push_warning_count(0, "execute_move takes move 521 without a warning")


# The original sorts a unit's 40 buff slots by turns left, most first, at the
# end of every applyChangesKrin (frame_42/DoAction_10.as:344), which runs after
# every hit on the unit, and a dispel takes matching slots in that order (lines
# 22-53 of the conductor's enterFrame handler). Flash Player's sort can move
# slots that hold the same number of turns past each other, so tied buffs don't
# always keep the order they landed in. Here the target holds Liquid Veins with
# 4 turns left, then Iron Jaws and Apprehend with 3 each, all Ice debuffs, and
# Dux Heal (move 8) dispels one Ice debuff per cast. The first cast takes Liquid
# Veins from slot 0, and the sort after that hit puts Apprehend ahead of Iron
# Jaws, so the second cast takes Apprehend.
func test_dispel_takes_tied_buffs_in_the_order_the_original_sorts_them():
	var veradux: CombatUnit = CombatUnit.from_character(unit_templates[4], 9, CombatUnit.Difficulty.HARD, 3)
	var target: CombatUnit = CombatUnit.from_character(unit_templates[1], 9, CombatUnit.Difficulty.HARD, 5)
	var enemy: CombatUnit = CombatUnit.from_character(unit_templates[5], 9, CombatUnit.Difficulty.HARD, 2)
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	runner.setup({2: enemy, 3: veradux, 5: target}, null, moves_by_id, buffs_by_id, buffs_by_name, manager, [])
	for buff_name in ["LIQUIDVEINS", "IRONJAWS", "APPREHEND"]:
		target.apply_buff(buffs_by_name[buff_name], 1, enemy)
		target.apply_changes()

	var removed: Array = []
	for _cast in 2:
		var events_start: int = runner.events.size()
		runner._execute_action({"caster_slot": 3, "target_slot": 5, "move_id": 8})
		for event in runner.events.slice(events_start):
			if event["type"] == BattleRunner.EventType.DISPEL:
				removed.append_array(event["removed"])
	assert_eq(removed, ["LIQUIDVEINS", "APPREHEND"], "the second Dux Heal takes Apprehend, which the sort moved ahead of Iron Jaws")
	assert_true(_has_active_buff(target, "IRONJAWS"), "Iron Jaws is still on the target")


# Keeps the target's stun and incoming damage multiplier as they are when
# execute_move resolves the hit.
class HitWatcher extends BattleManager:
	var stun_at_hit: float = -1.0
	var idmgp2_at_hit: float = -1.0

	func execute_move(ability: Ability, caster: CombatUnit, target: CombatUnit, buffs_by_name: Dictionary = {}) -> Dictionary:
		stun_at_hit = target.stun
		idmgp2_at_hit = target.idmgp2
		return super.execute_move(ability, caster, target, buffs_by_name)


# The original resolves the hit in executeMove (conductor lines 54-69) and only
# then recomputes the target's stats with applyChangesKrin (line 103). The
# dispel's applyBuffKrin call takes a removed buff's STUN off straight away
# (frame_42/DoAction_10.as:140), but IDMGP2, the multiplier on the damage the
# target takes, is only worked out in applyChangesKrin (line 313). SHATTERBOLT
# stuns by 1 and halves the damage its holder takes, and Shatter (move 224)
# dispels Ice debuffs, so the Shatter hit that removes SHATTERBOLT lands on a
# target that is no longer stunned and still takes half damage.
func test_a_dispelled_buffs_stats_still_count_for_the_hit_that_removes_it():
	var caster: CombatUnit = CombatUnit.from_character(unit_templates[1], 9, CombatUnit.Difficulty.HARD, 1)
	var target: CombatUnit = CombatUnit.from_character(unit_templates[5], 9, CombatUnit.Difficulty.HARD, 2)
	var runner = BattleRunner.new()
	var watcher: HitWatcher = autofree(HitWatcher.new())
	runner.setup({1: caster, 2: target}, null, moves_by_id, buffs_by_id, buffs_by_name, watcher, [])
	target.apply_buff(buffs_by_name["SHATTERBOLT"], 1, caster)
	target.apply_changes()

	runner._execute_action({"caster_slot": 1, "target_slot": 2, "move_id": 224})

	var removed: Array = []
	for event in runner.events:
		if event["type"] == BattleRunner.EventType.DISPEL:
			removed.append_array(event["removed"])
	assert_eq(removed, ["SHATTERBOLT"], "Shatter dispels SHATTERBOLT")
	assert_eq(watcher.stun_at_hit, 0.0, "the stun is gone before the hit lands")
	assert_eq(watcher.idmgp2_at_hit, 0.5, "the hit still takes SHATTERBOLT's halving")
	assert_eq(target.idmgp2, 1.0, "the halving is gone once the move resolves")


# The dispel takes a removed buff's SSWITCH off straight away too
# (frame_42/DoAction_10.as:171), and executeMove reads SSWITCH when the hit
# lands to decide whether the damage heals instead (frame_42/DoAction_8.as:82).
# RETROGRADED is a beneficial Shadow buff with SSWITCH, and Shock Therapy (move
# 434) dispels one beneficial Shadow buff, so its hit on a target holding
# RETROGRADED takes RETROGRADED off and then deals damage.
func test_a_dispelled_sswitch_no_longer_turns_the_hit_into_healing():
	var caster: CombatUnit = CombatUnit.from_character(unit_templates[1], 9, CombatUnit.Difficulty.HARD, 1)
	var target: CombatUnit = CombatUnit.from_character(unit_templates[5], 9, CombatUnit.Difficulty.HARD, 2)
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	runner.setup({1: caster, 2: target}, null, moves_by_id, buffs_by_id, buffs_by_name, manager, [])
	target.apply_buff(buffs_by_name["RETROGRADED"], 1, target)
	target.apply_changes()
	var life_before: float = target.life_n

	runner._execute_action({"caster_slot": 1, "target_slot": 2, "move_id": 434})

	var removed: Array = []
	var result: Dictionary = {}
	for event in runner.events:
		if event["type"] == BattleRunner.EventType.DISPEL:
			removed.append_array(event["removed"])
		elif event["type"] == BattleRunner.EventType.MOVE:
			result = event["result"]
	assert_eq(removed, ["RETROGRADED"], "Shock Therapy dispels RETROGRADED")
	assert_eq(result.get("type"), BattleManager.ResultType.DAMAGE, "the hit is damage")
	assert_false(result.get("sswitched", true), "and isn't turned into healing")
	assert_lt(target.life_n, life_before, "so the target loses life")


# Damage on a target under an sswitch buff heals it, capped at max life
# (frame_42/DoAction_8.as:133-149). FighterPresenter raises the bar by this
# result's amount, so the amount has to be what the target really gained.
func test_damage_under_sswitch_heals_the_target_by_the_result_amount():
	var caster: CombatUnit = CombatUnit.from_character(unit_templates[1], 9, CombatUnit.Difficulty.HARD, 1)
	var target: CombatUnit = CombatUnit.from_character(unit_templates[5], 9, CombatUnit.Difficulty.HARD, 2)
	var manager: BattleManager = autofree(BattleManager.new())
	target.apply_buff(buffs_by_name["TIEDYE"], 1, caster)
	target.apply_changes()
	target.life_n = floorf(target.life_u / 2.0)
	var life_before: float = target.life_n

	var result: Dictionary = manager.execute_move(moves_by_id[5], caster, target, buffs_by_name)  # Nuke

	assert_eq(result.get("type"), BattleManager.ResultType.DAMAGE, "the result is still damage")
	assert_true(result.get("sswitched", false), "and says the damage healed")
	assert_gt(target.life_n, life_before, "the target gains life")
	assert_eq(target.life_n, minf(life_before + result["amount"], target.life_u), "by the amount the result reports")


# A heal on a target under an sswitch buff hurts it
# (frame_42/DoAction_8.as:189-207). FighterPresenter lowers the bar by this
# result's amount, so the amount has to be what the target really lost.
func test_a_heal_under_sswitch_hurts_the_target_by_the_result_amount():
	var caster: CombatUnit = CombatUnit.from_character(unit_templates[1], 9, CombatUnit.Difficulty.HARD, 1)
	var target: CombatUnit = CombatUnit.from_character(unit_templates[5], 9, CombatUnit.Difficulty.HARD, 2)
	var manager: BattleManager = autofree(BattleManager.new())
	target.apply_buff(buffs_by_name["RETROGRADED"], 1, caster)
	target.apply_changes()
	var life_before: float = target.life_n

	var result: Dictionary = manager.execute_move(moves_by_id[4], caster, target, buffs_by_name)  # Heal

	assert_eq(result.get("type"), BattleManager.ResultType.HEAL, "the result is still a heal")
	assert_true(result.get("sswitched", false), "and says the heal hurt")
	assert_lt(target.life_n, life_before, "the target loses life")
	assert_eq(target.life_n, maxf(life_before - result["amount"], 0.0), "by the amount the result reports")


# A move can send its status buff to its own caster (ability_two[21],
# conductor lines 76-83), but the conductor's only applyChangesKrin after a hit
# is on the target (line 103), so the caster's stats and slot order wait for
# its own buffTicker. That tick works out its DoT damage
# (frame_42/DoAction_10.as:31) before it calls applyChangesKrin (line 135), so
# it still reads the caster's old stats. Honor and Duty (move 755) hits someone
# else and lands HONORDUTY on the Police Colonel, which cuts the damage he takes
# by 20%. He holds Cold Justice, a 500-a-turn Ice DoT, and his Ice defense is
# 100 + 15 per level, so with the old IDMGP2 of 1 that tick takes exactly 500.
# The test calls the two halves of _execute_action, the move and the tick, one
# at a time to look in between.
func test_a_buff_a_move_lands_on_its_caster_waits_for_the_casters_tick():
	var colonel: CombatUnit = CombatUnit.from_character(unit_templates[61], 22, CombatUnit.Difficulty.HARD, 2)
	var target: CombatUnit = CombatUnit.from_character(unit_templates[1], 22, CombatUnit.Difficulty.HARD, 1)
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	runner.setup({1: target, 2: colonel}, null, moves_by_id, buffs_by_id, buffs_by_name, manager, [])
	for buff_name in ["PERSECUTE", "CHAINS"]:
		colonel.apply_buff(buffs_by_name[buff_name], 1, target)
		colonel.apply_changes()
	# A stunned target can't dodge the Melee hit (conductor lines 360-386).
	target.apply_buff(buffs_by_name["APPREHEND"], 1, colonel)
	target.apply_changes()

	runner._execute_move_action({"caster_slot": 2, "target_slot": 1, "move_id": 755}, colonel, target)
	assert_eq(_live_buff_names(colonel), ["PERSECUTE", "CHAINS", "HONORDUTY"], "HONORDUTY waits in the slot it landed in")
	assert_eq(colonel.idmgp2, 1.0, "the damage the colonel takes doesn't change yet")

	var life_before_tick: float = colonel.life_n
	colonel.tick_buffs(buffs_by_id)
	assert_eq(life_before_tick - colonel.life_n, 500.0, "Cold Justice's tick still reads the old IDMGP2")
	assert_almost_eq(colonel.idmgp2, 0.8, 0.000001, "the tick's own recompute brings HONORDUTY in")
	assert_eq(_live_buff_names(colonel), ["PERSECUTE", "HONORDUTY", "CHAINS"], "and sorts it ahead of Chains of Justice")


# Runs a full battle with AI on both sides; returns event-type counts.
func _assert_battle_runs(battle_id: int) -> Dictionary:
	var battle: BattleFight = BattleSetup.load_battle(battle_id)
	assert_not_null(battle, "battle %d exists" % battle_id)
	if battle == null:
		return {}
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	runner.setup(_ai_driven_roster_for(battle), battle, moves_by_id, buffs_by_id, buffs_by_name, manager, [])
	var half_turns = _run_to_completion(runner)
	assert_true(runner.is_over(), "battle %d terminates within %d half-turns" % [battle_id, MAX_HALF_TURNS])
	assert_has([0, 1, 2], runner.win_condition, "outcome is win/loss/draw")
	var counts = {}
	for event in runner.events:
		counts[event["type"]] = counts.get(event["type"], 0) + 1
	assert_gt(counts.get(BattleRunner.EventType.MOVE, 0), 0, "moves were executed")
	if not battle.phases.is_empty():
		assert_true(
			counts.get(BattleRunner.EventType.PHASE_ADVANCED, 0) > 0 or runner.is_over(),
			"phase advanced or battle ended early"
		)
	gut.p("battle %d: outcome=%d turns=%d events=%s" % [battle_id, runner.win_condition, runner.turn_count, counts])
	return counts


func _run_to_completion(runner: BattleRunner) -> int:
	var half_turns = 0
	while not runner.is_over() and half_turns < MAX_HALF_TURNS:
		runner.advance_half_turn()
		half_turns += 1
	return half_turns


# Sonny and Veradux against a Prison Guard, with Sonny at 60% life and Veradux
# at 40%. Veradux keeps only Dux Heal, so with no attack to choose from he
# always heals (frame_42/DoAction_9.as:170-178).
func _queued_heal_runner() -> BattleRunner:
	var save: PlayerSave = PlayerSave.new_game("Sonny")
	save.strength = 100.0
	save.magic = 100.0
	save.speed = 100.0
	save.life = 30.0
	save.focus = 100.0
	var player: CombatUnit = CombatUnit.from_player_save(save)
	var veradux: CombatUnit = CombatUnit.from_character(unit_templates[4], 1, CombatUnit.Difficulty.HARD, 3)
	veradux.move_pool_attack = []
	veradux.cooldowns_attack = []
	var guard: CombatUnit = CombatUnit.from_character(unit_templates[5], 1, CombatUnit.Difficulty.HARD, 2)
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	runner.setup({1: player, 2: guard, 3: veradux}, null, moves_by_id, buffs_by_id, buffs_by_name, manager, [])
	player.life_n = round(player.life_u * 0.6)
	veradux.life_n = round(veradux.life_u * 0.4)
	assert_true(runner.is_player_turn(), "Sonny's team opens")
	return runner


func _move_target(events: Array, caster_slot: int) -> int:
	for event in events:
		if event["type"] == BattleRunner.EventType.MOVE and int(event["caster_slot"]) == caster_slot:
			return int(event["target_slot"])
	return 0


# Every event from a unit's own turn names that unit as caster_slot, so the
# first time each slot appears gives the order the units acted in.
func _acting_order(events: Array) -> Array:
	var order: Array = []
	for event in events:
		var slot = event.get("caster_slot")
		if slot != null and not order.has(slot):
			order.append(slot)
	return order


# This puts Sonny and Veradux at the level of the battle's strongest enemy, so
# that a fight run to its end is a real one. A training battle's "X" and "Z"
# levels are worked out from the player's level, so they can't set it.
func _save_for(battle: BattleFight) -> PlayerSave:
	var save: PlayerSave = PlayerSave.new_game("Runner")
	save.level = int(battle.players_levels.filter(func(level): return not level is String).max())
	Leveling.compute_stats(save)
	save.party_levels[1] = save.level
	return save


func _roster_for(battle: BattleFight, save: PlayerSave = null) -> Dictionary:
	if save == null:
		save = _save_for(battle)
	return BattleSetup.build_units(battle, save, unit_templates, CombatUnit.Difficulty.HARD)


# Sonny is the one unit the AI doesn't control, so this turns the AI on for the
# player's unit, with the moves the save knows, for a fight nobody has to play.
func _ai_driven_roster_for(battle: BattleFight) -> Dictionary:
	var save: PlayerSave = _save_for(battle)
	var units: Dictionary = _roster_for(battle, save)
	var player: CombatUnit = units[BattleRunner.PLAYER_SLOT]
	player.ai_enabled = true
	player.move_pool_attack = TalentTree.get_known_move_ids(save)
	player.cooldowns_attack = []
	for i in player.move_pool_attack.size():
		player.cooldowns_attack.append(0)
	return units


# Passive talent buffs carry duration -1 = permanent (never ticked down, never
# dispellable - the AS3 CD > 0 checks skip them), so "active" is cd != 0.
func _has_active_buff(unit: CombatUnit, buff_name: String) -> bool:
	var buff: Buff = buffs_by_name.get(buff_name)
	if buff == null:
		return false
	for slot in unit.buff_slots:
		if slot["buff_id"] == buff.id and slot["cd"] != 0:
			return true
	return false


func _live_buff_names(unit: CombatUnit) -> Array:
	var names: Array = []
	for slot in unit.buff_slots:
		if slot["cd"] > 0:
			names.append(buffs_by_id[slot["buff_id"]].internal_name)
	return names
