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
		player.base_per["Physical"], 100.0 + 15.0 * save.level,
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


func test_battle_100_simple_fight():
	_assert_battle_runs(100)


func test_battle_104_boss_phases_and_speeches():
	var counts = _assert_battle_runs(104)
	assert_gt(counts.get("speech", 0), 0, "scripted dialogue fired")


func test_battle_51_end_game_phase():
	_assert_battle_runs(51)


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
	assert_gt(counts.get("move", 0), 0, "moves were executed")
	if not battle.phases.is_empty():
		assert_true(
			counts.get("phase_advanced", 0) > 0 or runner.is_over(),
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
