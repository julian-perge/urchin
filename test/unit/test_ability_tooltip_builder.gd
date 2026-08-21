# test_ability_tooltip_builder.gd
# The four lines a tree-node tooltip shows, checked against krinRemakeTree
# (DefineSprite_3142/frame_25): "(rank/tier)  Name", the cost or SKILLAURA
# line, the description of the rank you have (SKILLTALENTTIP2 when you have
# none), and the next tier's level plus what it grants (SKILLTALENTTIP3 once
# maxed). Class 0's node 0 is the active Vicious Strike family and node 1 is
# the INTEGRITY passive, both max_rank 4.
extends GutTest

const ACTIVE_NODE: int = 0
const PASSIVE_NODE: int = 1


func _section_texts(result: Dictionary) -> Array:
	var texts: Array = []
	for section in result["sections"]:
		for line in section["lines"]:
			texts.append(line["text"])
	return texts


# A tree node hover at a given rank, with the move ids abilities_window.gd
# resolves for the builder.
func _hover(node_index: int, rank: int) -> Dictionary:
	var save: PlayerSave = PlayerSave.new_game("Test", 0)
	var node: Dictionary = TalentTree.get_talent_node(0, node_index).duplicate()
	node["_node_index"] = node_index
	save.talent_main_array[node_index] = rank
	var move: Ability = null
	var next_move: Ability = null
	if not TalentTree.is_passive(node):
		move = MoveManagerAuto.get_move(TalentTree.granted_move_id(node, max(rank, 1)))
		if rank < int(node["max_rank"]):
			next_move = MoveManagerAuto.get_move(TalentTree.granted_move_id(node, rank + 1))
	return AbilityTooltipBuilder.build_sections(node, save, move, next_move)


func test_title_carries_the_rank_over_the_max_rank():
	assert_has(_section_texts(_hover(ACTIVE_NODE, 2)), "(2/4)  Vicious Strike")
	assert_has(_section_texts(_hover(PASSIVE_NODE, 3)), "(3/4)  Integrity")


func test_active_at_rank_zero_says_it_is_unlearned_and_previews_rank_one():
	var texts: Array = _section_texts(_hover(ACTIVE_NODE, 0))
	var rank_one: Ability = MoveManagerAuto.get_move(100)
	assert_has(texts, AbilityTooltipBuilder.UNLEARNED_DESCRIPTION)
	assert_does_not_have(texts, rank_one.tooltip_description, "its own text moves to the next-tier line")
	assert_has(texts, rank_one.tooltip_cost)
	assert_has(
		texts,
		AbilityTooltipBuilder.NEXT_TIER_PREFIX % [1, rank_one.tooltip_description],
		"the next-tier line previews what rank 1 grants"
	)


func test_active_describes_the_rank_it_has_and_the_one_above():
	var texts: Array = _section_texts(_hover(ACTIVE_NODE, 1))
	var rank_one: Ability = MoveManagerAuto.get_move(100)
	var rank_two: Ability = MoveManagerAuto.get_move(101)
	assert_ne(rank_one.tooltip_description, rank_two.tooltip_description, "the ranks read differently")
	assert_has(texts, rank_one.tooltip_description, "the rank in hand")
	assert_has(
		texts,
		AbilityTooltipBuilder.NEXT_TIER_PREFIX % [1, rank_two.tooltip_description],
		"the rank above it"
	)


func test_passive_at_rank_zero_says_it_is_unlearned_and_previews_rank_one():
	var texts: Array = _section_texts(_hover(PASSIVE_NODE, 0))
	assert_has(texts, AbilityTooltipBuilder.UNLEARNED_DESCRIPTION)
	assert_has(texts, AbilityTooltipBuilder.PASSIVE_COST)
	assert_does_not_have(texts, "Passively restores 10 Focus every turn.")
	assert_has(
		texts,
		AbilityTooltipBuilder.NEXT_TIER_PREFIX % [1, "Passively restores 10 Focus every turn."]
	)


func test_passive_describes_the_rank_it_has_and_the_one_above():
	var texts: Array = _section_texts(_hover(PASSIVE_NODE, 1))
	assert_has(texts, "Passively restores 10 Focus every turn.")
	assert_has(
		texts,
		AbilityTooltipBuilder.NEXT_TIER_PREFIX % [
			1, "Passively restores 15 Focus and 1% of your Life every turn."
		]
	)


func test_a_maxed_node_says_so_instead_of_previewing_a_next_tier():
	for node_index in [ACTIVE_NODE, PASSIVE_NODE]:
		var texts: Array = _section_texts(_hover(node_index, 4))
		assert_has(texts, AbilityTooltipBuilder.MAX_TIER, "node %d" % node_index)
		for text in texts:
			assert_false(
				str(text).begins_with("Next Tier"), "node %d shows no next tier at max" % node_index
			)
	assert_has(
		_section_texts(_hover(PASSIVE_NODE, 4)),
		"Passively restores 25 Focus and 3% of your Life every turn.",
		"a maxed node still describes the rank it has"
	)


func test_passive_titles_come_from_the_source_table_not_the_family_name():
	# MARATHON is titled "Endurance" in the original, so capitalizing the
	# buff_family would print the wrong name here.
	var node_index: int = -1
	for i in TalentTree.NODES_PER_CLASS:
		if str(TalentTree.get_talent_node(0, i).get("buff_family", "")) == "MARATHON":
			node_index = i
			break
	assert_gt(node_index, -1, "class 0 has a MARATHON node")
	var texts: Array = _section_texts(_hover(node_index, 1))
	var titles: Array = texts.filter(func(t): return str(t).contains("Endurance"))
	assert_eq(titles.size(), 1, "titled Endurance")
	for text in texts:
		assert_false(str(text).contains("Marathon"), "never titled by its buff_family")


# Every passive node has to resolve to a title and a description, and there is
# one entry per rank - a family missing from BUFF_TEXT would show a blank
# header, and a short rank list would describe the wrong rank.
func test_every_passive_node_has_text_for_all_of_its_ranks():
	for class_id in PlayerSave.CLASS_NAMES.size():
		for i in TalentTree.NODES_PER_CLASS:
			var node: Dictionary = TalentTree.get_talent_node(class_id, i)
			if not TalentTree.is_passive(node):
				continue
			var family: String = str(node["buff_family"])
			assert_true(TalentTree.BUFF_TEXT.has(family), "%s has BUFF_TEXT" % family)
			assert_false(TalentTree.buff_display_name(node).is_empty(), "%s has a title" % family)
			var ranks: Array = TalentTree.BUFF_TEXT[family]["ranks"]
			assert_eq(ranks.size(), int(node["max_rank"]), "%s: one description per rank" % family)
			for rank in range(1, int(node["max_rank"]) + 1):
				assert_false(
					TalentTree.buff_rank_description(node, rank).is_empty(),
					"%s rank %d has a description" % [family, rank]
				)


func test_pool_row_hover_has_no_rank_prefix_or_next_rank_section():
	var move: Ability = MoveManagerAuto.get_move(1)
	var result: Dictionary = AbilityTooltipBuilder.build_sections({}, null, move)
	assert_has(_section_texts(result), move.display_name, "the bare name, with no (rank/tier)")
	for section in result["sections"]:
		assert_ne(
			section["bg_color"],
			TooltipTheme.BG_NEXT_RANK,
			"no rank progress to show outside a tree-node hover"
		)
