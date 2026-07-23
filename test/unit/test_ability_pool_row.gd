# test_ability_pool_row.gd
extends GutTest


func test_populate_sets_name_and_icon():
	var row: AbilityPoolRow = load("res://scenes/ui/menu/ability_pool_row.tscn").instantiate()
	add_child_autofree(row)
	var move: Ability = MoveManagerAuto.get_move(1)  # Leading Strike
	row.populate(move, "res://assets/ui/abilities/Leading_Strike.png")
	assert_eq(row.name_label.text, move.display_name)
	assert_not_null(row.icon_rect.texture)
	assert_true(row.visible)


func test_clear_hides_and_empties_the_row():
	var row: AbilityPoolRow = load("res://scenes/ui/menu/ability_pool_row.tscn").instantiate()
	add_child_autofree(row)
	var move: Ability = MoveManagerAuto.get_move(1)
	row.populate(move, "res://assets/ui/abilities/Leading_Strike.png")
	row.clear()
	assert_false(row.visible)
	assert_eq(row.name_label.text, "")
	assert_null(row.icon_rect.texture)
