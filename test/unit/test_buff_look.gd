# BuffLook on hand-made buff slots. The order that picks a winner, and the names,
# come from buff_looks.json, which convert_buff_looks reads from applyChangesKrin.
extends GutTest

var _buffs_by_id: Dictionary = {}


func before_each():
	_buffs_by_id = {}
	# Buff id n has visual filter index n.
	for index in range(0, 20):
		var buff := Buff.new()
		buff.id = index
		buff.visual_filter_index = index
		_buffs_by_id[index] = buff


func _slots(ids: Array, cd: int = 3) -> Array:
	return ids.map(func(id): return {"cd": cd, "buff_id": id, "buff_value": 0.0, "shield_buff_value": 0.0})


func _table() -> Dictionary:
	return BuffLook.looks()


func test_a_unit_with_no_buffs_looks_normal():
	var look: BuffLook = BuffLook.resolve(_slots([]), _buffs_by_id)
	assert_eq(look.color, _table()["default_color"])
	assert_eq(look.filter, _table()["default_filter"])


func test_a_poison_buff_gives_the_poison_color_and_no_filter():
	var look: BuffLook = BuffLook.resolve(_slots([1]), _buffs_by_id)
	assert_eq(look.color, "Poison")
	assert_eq(look.filter, _table()["default_filter"])


func test_a_frost_buff_gives_the_frost_filter_and_no_color():
	var look: BuffLook = BuffLook.resolve(_slots([2]), _buffs_by_id)
	assert_eq(look.filter, "Frost")
	assert_eq(look.color, _table()["default_color"])


func test_of_two_colors_the_one_that_runs_last_wins():
	var order: Array = _table()["color_by_index"]
	assert_gt(order.size(), 1, "sanity: the table has two colors")
	for first in order.size():
		for second in range(first + 1, order.size()):
			var look: BuffLook = BuffLook.resolve(_slots([int(order[second][0]), int(order[first][0])]), _buffs_by_id)
			assert_eq(look.color, order[second][1], "%s over %s" % [order[second][1], order[first][1]])


func test_of_two_filters_the_one_that_runs_last_wins():
	var order: Array = _table()["filter_by_index"]
	assert_gt(order.size(), 1, "sanity: the table has several filters")
	for first in order.size():
		for second in range(first + 1, order.size()):
			var look: BuffLook = BuffLook.resolve(_slots([int(order[second][0]), int(order[first][0])]), _buffs_by_id)
			assert_eq(look.filter, order[second][1], "%s over %s" % [order[second][1], order[first][1]])


func test_a_color_and_a_filter_show_together():
	var look: BuffLook = BuffLook.resolve(_slots([1, 2]), _buffs_by_id)
	assert_eq(look.color, "Poison")
	assert_eq(look.filter, "Frost")


func test_a_slot_with_no_turns_left_counts_for_nothing():
	var look: BuffLook = BuffLook.resolve(_slots([1, 2], 0), _buffs_by_id)
	assert_eq(look.color, _table()["default_color"])
	assert_eq(look.filter, _table()["default_filter"])


func test_a_buff_the_table_does_not_hold_counts_for_nothing():
	var look: BuffLook = BuffLook.resolve(_slots([99, -1]), _buffs_by_id)
	assert_eq(look.color, _table()["default_color"])
	assert_eq(look.filter, _table()["default_filter"])


func test_a_buff_of_visual_filter_index_0_counts_for_nothing():
	var look: BuffLook = BuffLook.resolve(_slots([0]), _buffs_by_id)
	assert_eq(look.filter, _table()["default_filter"])
