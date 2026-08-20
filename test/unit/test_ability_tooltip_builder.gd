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
	var result: Dictionary = AbilityTooltipBuilder.build_sections(node, save, move, null)
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
	var buff: Buff = BuffManagerAuto.get_buff_by_name(TalentTree.granted_buff_name(node, 4))
	var result: Dictionary = AbilityTooltipBuilder.build_sections(node, save, null, buff)
	var texts: Array = _section_texts(result)
	assert_has(texts, "Integrity")
	assert_has(texts, "Passive")
	assert_has(texts, "MAX")
	# Verified fact, not a bug: every tree-passive buff's tooltip_description
	# is empty in the source data (AS3 undefined -> "" via Buff._text()) - so
	# no body section is built at all for this hover.
	for section in result["sections"]:
		assert_ne(section["bg_color"], TooltipTheme.BG_BODY, "no description text, so no body section")


func test_pool_row_hover_has_no_next_rank_section():
	var move: Ability = MoveManagerAuto.get_move(1)
	var result: Dictionary = AbilityTooltipBuilder.build_sections({}, null, move, null)
	for section in result["sections"]:
		assert_ne(section["bg_color"], TooltipTheme.BG_NEXT_RANK, "no rank progress to show outside a tree-node hover")
