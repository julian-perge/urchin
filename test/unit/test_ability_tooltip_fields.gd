# test_ability_tooltip_fields.gd
# Ability.tooltip_description/tooltip_cost load the original game's
# pre-formatted tooltip strings from ability_two[17]/[18].
extends GutTest


func test_leading_strike_has_real_tooltip_text():
	var move: Ability = MoveManagerAuto.get_move(1)
	assert_not_null(move, "move id 1 (Leading Strike) exists")
	assert_eq(move.tooltip_description, "Attack the enemy for 170% of your Strength, and restores 50 Focus to you. ")
	assert_eq(move.tooltip_cost, "This move costs nothing")


func test_same_family_different_ranks_have_different_descriptions():
	# Vicious Strike (100-103): shared display_name, rank-scaled tooltip text.
	var rank1: Ability = MoveManagerAuto.get_move(100)
	var rank4: Ability = MoveManagerAuto.get_move(103)
	assert_eq(rank1.display_name, rank4.display_name, "same family shares a display name")
	assert_ne(rank1.tooltip_description, rank4.tooltip_description, "rank-scaled tooltip text differs")
