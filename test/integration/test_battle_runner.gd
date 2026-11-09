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


# The original names the player's battle unit "Sonny" whatever the save is
# called (frame_201/DoAction.as:201), so battle 100's "Sonny" line finds the
# player as its speaker instead of falling back to the narrator's slot 0.
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


# FROST1 takes 30% off speed. Its field 7 is -0.3, applyBuffKrin adds that to
# changeArray[5], and applyChangesKrin sets SPEEDU to
# ceil((SPEED + changeArray[4]) * (1 + changeArray[5]))
# (frame_42/DoAction_10.as:188, 261). The player, enemies and companions each
# build their change arrays in their own constructor, so the test covers one of
# each, and runs FROST1's 12 turns out to check that speed comes back.
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
