# test_ability_tooltip_builder.gd
extends GutTest


func _section_texts(result: Dictionary) -> Array:
	var texts: Array = []
	for section in result["sections"]:
		for line in section["lines"]:
			texts.append(line["text"])
	return texts


func test_active_node_fields_at_rank_zero():
	var save: PlayerSave = PlayerSave.new_game("Test", 0)
	var node: Dictionary = TalentTree.get_talent_node(0, 0).duplicate()
	node["_node_index"] = 0
	var move: Ability = MoveManagerAuto.get_move(TalentTree.granted_move_id(node, 1))
	var result: Dictionary = AbilityTooltipBuilder.build_sections(node, save, move)
	var texts: Array = _section_texts(result)
	assert_has(texts, move.display_name)
	assert_has(texts, move.tooltip_cost)
	assert_has(texts, move.tooltip_description)
	assert_has(texts, "Next Tier (Lvl. 1)")


func test_passive_node_at_max_rank_shows_max():
	var save: PlayerSave = PlayerSave.new_game("Test", 0)
	# Node 1 in class 0's tree is the INTEGRITY passive, max_rank 4.
	var node: Dictionary = TalentTree.get_talent_node(0, 1).duplicate()
	node["_node_index"] = 1
	save.talent_main_array[1] = 4
	var result: Dictionary = AbilityTooltipBuilder.build_sections(node, save, null)
	var texts: Array = _section_texts(result)
	assert_has(texts, "Integrity")
	assert_has(texts, AbilityTooltipBuilder.PASSIVE_COST)
	assert_has(texts, "MAX")
	assert_has(texts, "Passively restores 25 Focus and 3% of your Life every turn.")


func test_passive_node_describes_rank_one_before_it_is_learned():
	var save: PlayerSave = PlayerSave.new_game("Test", 0)
	var node: Dictionary = TalentTree.get_talent_node(0, 1).duplicate()
	node["_node_index"] = 1
	assert_eq(int(save.talent_main_array[1]), 0, "starts unlearned")
	var texts: Array = _section_texts(AbilityTooltipBuilder.build_sections(node, save, null))
	assert_has(texts, "Passively restores 10 Focus every turn.", "previews what rank 1 grants")


func test_passive_titles_come_from_the_source_table_not_the_family_name():
	var save: PlayerSave = PlayerSave.new_game("Test", 0)
	# MARATHON is titled "Endurance" in the original, so capitalizing the
	# buff_family would print the wrong name here.
	var node_index: int = -1
	for i in TalentTree.NODES_PER_CLASS:
		if str(TalentTree.get_talent_node(0, i).get("buff_family", "")) == "MARATHON":
			node_index = i
			break
	assert_gt(node_index, -1, "class 0 has a MARATHON node")
	var node: Dictionary = TalentTree.get_talent_node(0, node_index).duplicate()
	node["_node_index"] = node_index
	var texts: Array = _section_texts(AbilityTooltipBuilder.build_sections(node, save, null))
	assert_has(texts, "Endurance")
	assert_does_not_have(texts, "Marathon")


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


func test_pool_row_hover_has_no_next_rank_section():
	var move: Ability = MoveManagerAuto.get_move(1)
	var result: Dictionary = AbilityTooltipBuilder.build_sections({}, null, move)
	for section in result["sections"]:
		assert_ne(section["bg_color"], TooltipTheme.BG_NEXT_RANK, "no rank progress to show outside a tree-node hover")
