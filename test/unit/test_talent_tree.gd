# Unit tests for TalentTree + PlayerSave talent state (GUT).
# Run headless: $GODOT --headless -s res://addons/gut/gut_cmdln.gd --path .
# (config in .gutconfig.json), or via the GUT panel in the editor.
extends GutTest

const MOVES_FILE = "res://dev/converted_json/moves_abilities.json"
const BUFFS_FILE = "res://dev/converted_json/buffs.json"

var save: PlayerSave


func before_each():
	save = PlayerSave.new_game("Test", 0)


func test_new_game_defaults():
	assert_eq(save.move_matrix2, [1, 6], "class 0 starting pool: Leading Strike + Destroy")
	assert_eq(save.skill_points, TalentTree.STARTING_SKILL_POINTS, "preStartSkill = 5")
	assert_eq(save.talent_main_array.size(), 38)
	assert_eq(save.skill_adder_matrix.size(), 38)
	assert_eq(save.buff_adder_matrix.size(), 38)
	# The class-select buttons (DefineButton2_2735 and siblings) seed the bar
	# with the starting moves at new game - a fresh character can fight.
	assert_eq(save.move_matrix, [1, 6, 0, 0, 0, 0, 0, 0], "starting moves on the action bar")


func test_new_game_other_class_starting_pool():
	var hydraulic_save = PlayerSave.new_game("Test2", 2)
	assert_eq(hydraulic_save.move_matrix2, [276, 277], "Vapour Cannon + Slam")


func test_active_node_rank_up_replaces_move_everywhere():
	save.skill_points = 20
	assert_eq(TalentTree.learn(save, 0), TalentTree.LearnResult.OK)
	assert_eq(save.skill_adder_matrix[0], 100, "rank 1 grants base move id")
	assert_eq(save.move_matrix2, [1, 6, 100], "pool gains the move")
	save.move_matrix[0] = 100  # equip it, then upgrade past it
	assert_eq(TalentTree.learn(save, 0), TalentTree.LearnResult.OK)
	assert_eq(TalentTree.learn(save, 0), TalentTree.LearnResult.OK)
	assert_eq(TalentTree.learn(save, 0), TalentTree.LearnResult.OK)
	assert_eq(TalentTree.learn(save, 0), TalentTree.LearnResult.MAX_RANK, "rank 5 blocked")
	assert_eq(TalentTree.get_rank(save, 0), 4)
	assert_eq(save.skill_adder_matrix[0], 103, "granted move upgraded to final rank")
	assert_eq(save.move_matrix2, [1, 6, 103], "pool upgraded in place")
	assert_eq(save.move_matrix[0], 103, "equipped bar upgraded in place")
	assert_eq(save.skill_points, 16, "1 point per rank")


func test_level_gates():
	save.skill_points = 20
	TalentTree.learn(save, 0)  # node 4's prerequisite
	assert_eq(TalentTree.learn(save, 4), TalentTree.LearnResult.OK, "rank 1 fine at level 1")
	assert_eq(
		TalentTree.learn(save, 4),
		TalentTree.LearnResult.LEVEL_TOO_LOW,
		"rank 2 needs level_min + level_scale * rank = 2"
	)
	assert_eq(
		TalentTree.learn(save, 12),
		TalentTree.LearnResult.LEVEL_TOO_LOW,
		"SAVAGERY needs level 4"
	)


func test_is_prerequisite_learned():
	save.skill_points = 20
	assert_false(TalentTree.is_prerequisite_learned(save, 0), "not learned yet")
	TalentTree.learn(save, 0)
	assert_true(TalentTree.is_prerequisite_learned(save, 0), "learned after spending a point")


func test_prerequisite_gate():
	save.skill_points = 20
	save.level = 10
	assert_eq(
		TalentTree.learn(save, 16),
		TalentTree.LearnResult.MISSING_PREREQUISITE,
		"node 16 blocked without node 12"
	)
	TalentTree.learn(save, 12)
	assert_eq(TalentTree.learn(save, 16), TalentTree.LearnResult.OK, "unblocked once learned")


func test_passive_node_stores_buff_names():
	save.skill_points = 20
	TalentTree.learn(save, 1)
	assert_eq(save.buff_adder_matrix[1], "INTEGRITY1")
	TalentTree.learn(save, 1)
	assert_eq(save.buff_adder_matrix[1], "INTEGRITY2", "rank appended to family name")
	assert_eq(save.skill_adder_matrix[1], 0, "passive grants no move")
	assert_eq(save.move_matrix2, [1, 6], "pool unchanged")
	assert_eq(TalentTree.get_passive_buff_names(save), ["INTEGRITY2"])


func test_point_and_validity_gates():
	save.skill_points = 0
	assert_eq(TalentTree.learn(save, 0), TalentTree.LearnResult.NOT_ENOUGH_POINTS)
	save.skill_points = 5
	assert_eq(TalentTree.learn(save, 99), TalentTree.LearnResult.INVALID_NODE)
	assert_eq(
		TalentTree.LEARN_RESULT_MESSAGES[TalentTree.LearnResult.LEVEL_TOO_LOW],
		"Your Level is not high enough.",
		"original TALENTERROR3 string preserved"
	)


# Every rank of every node in all 3 trees must resolve to real data: active
# ranks to consecutive move ids sharing one display name, passive ranks to
# existing buff internal_names.
func test_data_sweep_all_trees():
	var move_names = {}
	for move_data in _load_json(MOVES_FILE):
		if typeof(move_data.get("1_id")) in [TYPE_FLOAT, TYPE_INT]:
			move_names[int(move_data["1_id"])] = move_data["0_display_name"]
	var buff_names = {}
	for buff_data in _load_json(BUFFS_FILE):
		var internal_name = buff_data.get("internal_name")
		if internal_name is String:
			buff_names[internal_name] = true

	var problems = []
	for player_class in TalentTree.TREES:
		var nodes = TalentTree.TREES[player_class]
		if nodes.size() != TalentTree.NODES_PER_CLASS:
			problems.append("class %d has %d nodes" % [player_class, nodes.size()])
		for node_index in nodes.size():
			var node = nodes[node_index]
			var tag = "class %d node %d" % [player_class, node_index]
			for prerequisite_index in node["prerequisites"]:
				if prerequisite_index < 0 or prerequisite_index >= nodes.size():
					problems.append(tag + ": prerequisite out of range")
			for rank in range(1, node["max_rank"] + 1):
				if TalentTree.is_passive(node):
					var buff_name = TalentTree.granted_buff_name(node, rank)
					if not buff_names.has(buff_name):
						problems.append(tag + ": missing buff " + buff_name)
				else:
					var move_id = TalentTree.granted_move_id(node, rank)
					if not move_names.has(move_id):
						problems.append(tag + ": missing move %d" % move_id)
					elif move_names[move_id] != move_names[node["move_id"]]:
						problems.append(tag + ": move %d name mismatch" % move_id)
	for player_class in TalentTree.STARTING_MOVES:
		for starting_move_id in TalentTree.STARTING_MOVES[player_class]:
			if not move_names.has(starting_move_id):
				problems.append("class %d starting move %d missing" % [player_class, starting_move_id])

	assert_eq(problems, [], "84 nodes + 6 starting moves all resolve against real data")


func _load_json(path: String) -> Array:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		fail_test("Could not open " + path)
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Array else []
