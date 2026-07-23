# test_ability_tooltip_builder.gd
extends GutTest


func test_active_node_fields_at_rank_zero():
	var save: PlayerSave = PlayerSave.new_game("Test", 0)
	var node: Dictionary = TalentTree.get_talent_node(0, 0).duplicate()
	node["_node_index"] = 0
	var move: Ability = MoveManagerAuto.get_move(TalentTree.granted_move_id(node, 1))
	var fields: Dictionary = AbilityTooltipBuilder.build_fields(node, save, move, null)
	assert_eq(fields["title"], move.display_name)
	assert_eq(fields["description"], move.tooltip_description)
	assert_eq(fields["cost"], move.tooltip_cost)
	assert_eq(fields["next_rank_text"], "Next Tier (Lvl. 1)")


func test_passive_node_at_max_rank_shows_max():
	var save: PlayerSave = PlayerSave.new_game("Test", 0)
	# Node 1 in class 0's tree is the INTEGRITY passive, max_rank 4.
	var node: Dictionary = TalentTree.get_talent_node(0, 1).duplicate()
	node["_node_index"] = 1
	save.talent_main_array[1] = 4
	var buff: Buff = BuffManagerAuto.get_buff_by_name(TalentTree.granted_buff_name(node, 4))
	var fields: Dictionary = AbilityTooltipBuilder.build_fields(node, save, null, buff)
	assert_eq(fields["title"], "Integrity")
	assert_eq(fields["cost"], "Passive")
	assert_eq(fields["next_rank_text"], "MAX")
	# Verified fact, not a bug: every tree-passive buff's tooltip_description
	# is empty in the source data (AS3 undefined -> "" via Buff._text()).
	assert_eq(fields["description"], "", "source data has no tooltip text for tree-passive buffs")


func test_pool_row_hover_has_no_next_rank_text():
	var move: Ability = MoveManagerAuto.get_move(1)
	var fields: Dictionary = AbilityTooltipBuilder.build_fields({}, null, move, null)
	assert_eq(fields["next_rank_text"], "", "no rank progress to show outside a tree-node hover")
