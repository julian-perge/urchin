# Integration tests for the battle turn-loop (GUT): BattleRunner + BattleAI +
# BattleManager + CombatUnit + TalentTree against the real converted data.
# Run headless: $GODOT --headless -s res://addons/gut/gut_cmdln.gd --path .
# (config in .gutconfig.json), or via the GUT panel in the editor.
extends GutTest

const CharacterScript = preload("res://scripts/entities/character.gd")
const BattleFightScript = preload("res://scripts/battle/battle_fight.gd")

const MOVES_FILE = "res://dev/converted_json/moves_abilities.json"
const BUFFS_FILE = "res://dev/converted_json/buffs.json"
const UNITS_FILE = "res://dev/converted_json/units.json"
const BATTLES_FILE = "res://dev/converted_json/battles.json"

const AGGRESSION_ORDER = ["Phalanx", "Defensive", "Tactical", "Aggressive", "Relentless"]
const ELEMENT_ORDER = ["Physical", "Magic", "Ice", "Fire", "Lightning", "Earth", "Shadow", "Poison"]
# Battle 51 (endGame-phase boss) is heal-heavy on both sides - its RNG tail
# has been observed past 300 half-turns, hence the generous cap.
const MAX_HALF_TURNS = 900

var moves_by_id: Dictionary = {}
var buffs_by_id: Dictionary = {}
var buffs_by_name: Dictionary = {}
var unit_templates: Dictionary = {}  # id -> Character
var battles: Dictionary = {}  # id -> BattleFight


func before_all():
	for move_data in _load_json(MOVES_FILE):
		var ability = Ability.from_json(move_data)
		moves_by_id[ability.id] = ability
	for buff_data in _load_json(BUFFS_FILE):
		var buff = Buff.from_json(buff_data)
		buffs_by_id[buff.id] = buff
		buffs_by_name[buff.internal_name] = buff
	for unit_data in _load_json_dict(UNITS_FILE).get("units", []):
		unit_templates[int(unit_data["id"])] = _character_from_json(unit_data)
	for battle_data in _load_json_dict(BATTLES_FILE).get("battles", []):
		battles[int(battle_data["id"])] = _battle_from_json(battle_data)


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


func test_all_battles_built():
	assert_eq(battles.size(), 99)


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
	var player: CombatUnit = CombatUnit.from_player_save(save)
	assert_eq(player.player_name, "Sonny", "the player's battle unit")

	var battle: BattleFight = battles.get(100)
	var units: Dictionary = _build_battle_units(battle)
	units[BattleRunner.PLAYER_SLOT] = player
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	var setup_events: Array = runner.setup(units, battle, moves_by_id, buffs_by_id, buffs_by_name, manager, [])
	var doorbell: Dictionary = {}
	for event in setup_events:
		if event["type"] == BattleRunner.EventType.SPEECH and event["say"] == "Sorry about the gate, I couldn't find the doorbell.":
			doorbell = event
	assert_false(doorbell.is_empty(), "battle 100's Sonny line plays as the battle starts")
	assert_eq(doorbell.get("speaker_slot", -1), BattleRunner.PLAYER_SLOT, "and the player says it")


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
	var battle: BattleFight = battles.get(105)
	assert_not_null(battle)
	assert_eq(battle.speeches.size(), 1)
	assert_eq(int(battle.speeches[0]["turnTime"]), 0, "the one speech fires at battle start, not mid-turn")
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	var setup_events: Array = runner.setup(
		_build_battle_units(battle), battle, moves_by_id, buffs_by_id, buffs_by_name, manager, []
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
# lines 813-818 and 852-856). The harness puts Veradux in both companion slots,
# so battle 403 has no Roald: Veradux's opening line plays, Roald's reply is
# skipped, and Sonny's answer to Roald never plays.
func test_a_line_whose_speaker_is_not_on_the_field_is_skipped():
	var battle: BattleFight = battles.get(403)
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	var setup_events: Array = runner.setup(
		_build_battle_units(battle), battle, moves_by_id, buffs_by_id, buffs_by_name, manager, []
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
		var battle: BattleFight = battles.get(battle_id)
		var runner = BattleRunner.new()
		var manager: BattleManager = autofree(BattleManager.new())
		var setup_events: Array = runner.setup(
			_build_battle_units(battle), battle, moves_by_id, buffs_by_id, buffs_by_name, manager, []
		)
		var said: Array = setup_events.filter(func(event): return event["type"] == BattleRunner.EventType.SPEECH)
		assert_eq(said.size(), opening_lines[battle_id], "battle %d plays its opening lines" % battle_id)
		assert_eq(runner.win_condition, BattleRunner.Outcome.WIN, "and battle %d is won before a half-turn" % battle_id)


# 109, 201 and 212 flag a later phase entry instead, so each is won once the
# phase after it opens and that phase's lines are done: 109 and 212 at phase 4,
# when the watched boss falls to 10% and 15% life, and 201 at phase 2. Every
# phase advance moves the phase on and sets turnTimeKKK2 back to 0 before the
# speech pass looks for lines (lines 176-193), which is the walk below. Battle
# 212's phase 4 opens with Roald, so he stands in slot 5 here.
func test_the_phase_after_an_end_game_entry_ends_the_battle_after_its_lines():
	var lines_at_the_end: Dictionary = {109: 2, 201: 12, 212: 2}
	var last_phase: Dictionary = {109: 4, 201: 2, 212: 4}
	for battle_id in lines_at_the_end:
		var battle: BattleFight = battles.get(battle_id)
		var units: Dictionary = _build_battle_units(battle)
		if battle_id == 212:
			units[5] = CombatUnit.from_character(unit_templates[32], 1, CombatUnit.Difficulty.HARD, 5)
		var runner = BattleRunner.new()
		var manager: BattleManager = autofree(BattleManager.new())
		runner.setup(units, battle, moves_by_id, buffs_by_id, buffs_by_name, manager, [])
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
	var battle: BattleFight = battles.get(2)
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	runner.setup(_build_battle_units(battle), battle, moves_by_id, buffs_by_id, buffs_by_name, manager, [])
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
# This seed gives 6 misses over 45 half-turns, the same every run. The global
# RNG is handed back at the end so the tests after this one are unaffected.
func test_misses_are_move_events_not_a_separate_type():
	seed(20260823)
	var battle: BattleFight = battles.get(51)
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	runner.setup(_build_battle_units(battle), battle, moves_by_id, buffs_by_id, buffs_by_name, manager, [])
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


# Runs a full battle with AI on both sides; returns event-type counts.
func _assert_battle_runs(battle_id: int) -> Dictionary:
	var battle: BattleFight = battles.get(battle_id)
	assert_not_null(battle, "battle %d exists" % battle_id)
	if battle == null:
		return {}
	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	runner.setup(_build_battle_units(battle), battle, moves_by_id, buffs_by_id, buffs_by_name, manager, [])
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


# players[i] -> slot i+2; positive ids are unit templates, negative are story
# companion markers (Veradux stands in), 0 is empty. Slot 1 is a player
# stand-in driven by the AI (template 1 "Bio") so the loop runs autonomously.
func _build_battle_units(battle: BattleFight) -> Dictionary:
	var units = {}
	var player_level = 1
	for i in battle.players.size():
		var template_id = int(battle.players[i].get("id", 0))
		if template_id > 0:
			player_level = max(player_level, _resolve_level(battle.players_levels, i, 1))
	for i in battle.players.size():
		var template_id = int(battle.players[i].get("id", 0))
		var slot = i + 2
		var level = _resolve_level(battle.players_levels, i, player_level)
		if template_id > 0 and unit_templates.has(template_id):
			units[slot] = CombatUnit.from_character(unit_templates[template_id], level, CombatUnit.Difficulty.HARD, slot)
		elif template_id < 0:
			units[slot] = CombatUnit.from_character(unit_templates[4], player_level, CombatUnit.Difficulty.HARD, slot)
	units[1] = CombatUnit.from_character(unit_templates[1], player_level, CombatUnit.Difficulty.HARD, 1)
	return units


# players_levels entries can be "X" (player level - 2) or "Z" (player level
# + 5) - the training-fight level scalers.
func _resolve_level(levels: Array, index: int, player_level: int) -> int:
	if index >= levels.size():
		return 1
	var raw = levels[index]
	if raw is String:
		if raw == "X":
			return max(player_level - 2, 1)
		if raw == "Z":
			return player_level + 5
		return 1
	return max(int(raw), 1)


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


func _character_from_json(unit_data: Dictionary) -> Character:
	var character = Resource.new()
	character.set_script(CharacterScript)
	character.name = unit_data["name"]
	character.vitality = float(unit_data["health"])
	character.strength = float(unit_data["strength"])
	character.magic = float(unit_data["magic"])
	character.speed = float(unit_data["speed"])
	character.focus = float(unit_data["focus"])
	var absolute = []
	for move in unit_data["moves"]["absolute"]:
		absolute.append({"id": int(move["id"]), "phase": int(move["turn"])})
	var attack = []
	for move in unit_data["moves"]["attack"]:
		attack.append(int(move["id"]))
	var defense = []
	for move in unit_data["moves"]["defense"]:
		defense.append(int(move["id"]))
	character.moves = {"absolute": absolute, "attack": attack, "defense": defense}
	character.stats = {
		"aggression": _ordered(unit_data["stats"]["aggression"], AGGRESSION_ORDER),
		"piercing": _ordered(unit_data["stats"]["piercing"], ELEMENT_ORDER),
		"defense": _ordered(unit_data["stats"]["defense"], ELEMENT_ORDER),
	}
	character.visuals = {"voice": unit_data["visuals"]["voice"]}
	return character


func _battle_from_json(battle_data: Dictionary) -> BattleFight:
	var battle = Resource.new()
	battle.set_script(BattleFightScript)
	battle.id = int(battle_data["id"])
	battle.absolute_start = int(battle_data.get("absolute_start", 0))
	battle.time_lock = battle_data.get("time_lock")
	battle.win_date = int(battle_data.get("win_date", -1))
	battle.win_date_condition = int(battle_data.get("win_date_condition", 0))
	battle.phases = battle_data.get("phases", {})
	battle.players = battle_data.get("players", [])
	battle.players_levels = battle_data.get("players_levels", [])
	var speeches: Array[Dictionary] = []
	for speech in battle_data.get("speeches", []):
		speeches.append(speech)
	battle.speeches = speeches
	return battle


func _ordered(stat_dict: Dictionary, order: Array) -> Array:
	var result = []
	for key in order:
		result.append(stat_dict[key])
	return result


func _load_json(path: String) -> Array:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		fail_test("Could not open " + path)
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Array else []


func _load_json_dict(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		fail_test("Could not open " + path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
