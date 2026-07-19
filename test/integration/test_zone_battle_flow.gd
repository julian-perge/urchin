# Integration test for the full zone-driven battle loop: story battle picked
# from progression -> battle .tres loaded -> roster built (player + deployed
# companion + enemies) -> fight runs to completion -> victory advances quest
# progress and pays out rewards including companion XP.
extends GutTest

const CharacterScript = preload("res://scripts/entities/character.gd")

const MOVES_FILE = "res://python_conversion_scripts/converted_json/moves_abilities.json"
const BUFFS_FILE = "res://python_conversion_scripts/converted_json/buffs.json"
const UNITS_FILE = "res://python_conversion_scripts/converted_json/units.json"

const AGGRESSION_ORDER = ["Phalanx", "Defensive", "Tactical", "Aggressive", "Relentless"]
const ELEMENT_ORDER = ["Physical", "Magic", "Ice", "Fire", "Lightning", "Earth", "Shadow", "Poison"]
const MAX_HALF_TURNS = 300

var moves_by_id: Dictionary = {}
var buffs_by_id: Dictionary = {}
var buffs_by_name: Dictionary = {}
var unit_templates: Dictionary = {}


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


func test_battle_resources_load_by_id():
	var battle = BattleSetup.load_battle(100)
	assert_not_null(battle, "story battle 100 resource")
	assert_eq(battle.id, 100)
	assert_eq(battle.players.size(), 5)
	var training = BattleSetup.load_battle(1000)
	assert_not_null(training, "training battle 1000 resource")


func test_roster_build_places_player_companion_and_enemies():
	var save = PlayerSave.new_game("Flow", 0)
	var battle = BattleSetup.load_battle(100)  # players [5, -2, 0, -1, 0]
	var units = BattleSetup.build_units(battle, save, unit_templates, CombatUnit.Difficulty.HARD)
	assert_true(units.has(1), "player in slot 1")
	assert_false(units[1].ai_enabled, "player is human-controlled")
	assert_true(units.has(2), "Prison Guard enemy in slot 2")
	assert_eq(units[2].player_name, "Prison Guard")
	assert_true(units.has(3), "Veradux (deployed companion) in slot 3")
	assert_eq(units[3].player_name, "Veradux")
	assert_true(units[3].ai_enabled)
	assert_eq(units[3].life_boundary_1, 75.0, "companions use the Tactical AI preset")
	assert_false(units.has(5), "Roald deployed but not joined - slot stays empty")


func test_companion_stat_model():
	var save = PlayerSave.new_game("Flow", 0)
	var veradux = Party.build_companion_unit(save, 1, unit_templates, 3)
	# Level 1 Veradux (template ratios all 20): allocation + ceil(curve).
	var curve = ceil(CombatUnit.get_stat(20, 1, true))
	assert_eq(veradux.base_life, round(9 + curve) * 33)
	assert_eq(veradux.base_strength, round(12 + curve))
	assert_eq(veradux.base_per["Lightning"], 100.0 + 15.0 + 82.0, "PerSets seed applies")
	assert_eq(veradux.base_def["Lightning"], 100.0 + 5.0, "faithful Lightning-defense 5/level quirk")
	assert_eq(veradux.base_def["Physical"], 100.0 + 15.0)


func test_full_zone_battle_loop():
	var save = PlayerSave.new_game("Flow", 0)
	save.skill_points = 8
	TalentTree.learn(save, 0)
	TalentTree.learn(save, 1)

	var pick = ZoneProgression.pick_story_battle(save)
	assert_eq(pick["battle_id"], 100)
	var battle = BattleSetup.load_battle(pick["battle_id"])
	var units = BattleSetup.build_units(battle, save, unit_templates, CombatUnit.Difficulty.HARD)

	# Headless autonomy: let the AI drive the player unit with their talent
	# moves (the battle UI will feed real input later).
	var player: CombatUnit = units[1]
	player.ai_enabled = true
	player.move_pool_attack = TalentTree.get_known_move_ids(save)
	player.cooldowns_attack = []
	for i in player.move_pool_attack.size():
		player.cooldowns_attack.append(0)

	var runner = BattleRunner.new()
	var manager: BattleManager = autofree(BattleManager.new())
	runner.setup(units, battle, moves_by_id, buffs_by_id, buffs_by_name, manager, TalentTree.get_passive_buff_names(save))
	var half_turns = 0
	while not runner.is_over() and half_turns < MAX_HALF_TURNS:
		runner.advance_half_turn()
		half_turns += 1
	assert_true(runner.is_over(), "zone-driven battle terminates")
	gut.p("battle 100 outcome=%d turns=%d" % [runner.win_condition, runner.turn_count])

	if runner.win_condition == BattleRunner.Outcome.WIN:
		var progression = ZoneProgression.after_battle_won(save, pick["battle_id"], pick["is_story_progress"])
		assert_eq(ZoneProgression.quest_progress(save, 1), 1, "story win advanced progress")
		assert_true(progression["progress_advanced"])
		var enemy_levels = BattleRewards.unit_levels_from_slots(units, [2, 4, 6])
		var spawned_levels = enemy_levels  # battle 100's only positive-id unit is the enemy
		var rewards = BattleRewards.apply_victory(save, spawned_levels, enemy_levels, [1])
		assert_gt(rewards["money_gained"], 0)
		assert_true(save.party_exp[1] > 0.0 or save.party_levels[1] > 1, "Veradux earned XP")
		gut.p("rewards: %s" % [rewards])


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
