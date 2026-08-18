# Unit tests for GameData's inventory-slot operations that drag-and-drop
# needs but click never required (.claude/plan_item_drag_and_drop.md Task
# 1) - swapping two inventory cells in place, and unequipping into a
# specific cell rather than always the first free one.
extends GutTest

var save: PlayerSave


func before_each():
	save = PlayerSave.new_game("DragTest", 0)
	GameData.current_save = save


func after_each():
	GameData.current_save = null


func _find_basic_equippable(exclude_id: int = -1) -> GameItem:
	var best: GameItem = null
	for item in ItemManagerAuto.items_by_id.values():
		if item.id == exclude_id:
			continue
		if item.required_level > 1 or item.required_unit_id != 0:
			continue
		if Equipment.slot_for_item(item) == -1:
			continue
		if best == null or item.id < best.id:
			best = item
	return best


func test_swap_inventory_slots_exchanges_two_occupied_cells():
	save.item_array[2] = 5
	save.item_array[5] = 9
	assert_true(GameData.swap_inventory_slots(2, 5))
	assert_eq(int(save.item_array[2]), 9)
	assert_eq(int(save.item_array[5]), 5)


func test_swap_inventory_slots_with_one_empty_cell():
	save.item_array[3] = 5
	assert_true(GameData.swap_inventory_slots(3, 4))
	assert_eq(int(save.item_array[3]), 0, "the occupied cell's contents moved out")
	assert_eq(int(save.item_array[4]), 5, "into the previously-empty cell")


func test_swap_inventory_slots_rejects_out_of_range():
	assert_false(GameData.swap_inventory_slots(-1, 0))
	assert_false(GameData.swap_inventory_slots(0, save.item_array.size()))


func test_swap_inventory_slots_no_save_returns_false():
	GameData.current_save = null
	assert_false(GameData.swap_inventory_slots(0, 1))


func test_unequip_to_slot_into_empty_cell():
	var item_a: GameItem = _find_basic_equippable()
	assert_not_null(item_a, "an unrestricted level-1 equippable exists")
	var equip_slot: int = Equipment.slot_for_item(item_a)
	save.equip_array[equip_slot] = item_a.id
	assert_true(GameData.unequip_to_slot(equip_slot, 3))
	assert_eq(int(save.item_array[3]), item_a.id, "unequipped item lands at the requested cell")
	assert_eq(int(save.equip_array[equip_slot]), 0, "equip slot cleared")


func test_unequip_to_slot_into_occupied_cell_displaces_to_first_free():
	var item_a: GameItem = _find_basic_equippable()
	assert_not_null(item_a)
	var item_b: GameItem = _find_basic_equippable(item_a.id)
	assert_not_null(item_b)
	var equip_slot: int = Equipment.slot_for_item(item_a)
	save.equip_array[equip_slot] = item_a.id
	save.item_array[3] = item_b.id
	assert_true(GameData.unequip_to_slot(equip_slot, 3))
	assert_eq(int(save.item_array[3]), item_a.id, "unequipped item lands at the requested cell")
	assert_eq(int(save.item_array[0]), item_b.id, "displaced item moves to the first free cell")


func test_unequip_to_slot_empty_slot_returns_false():
	assert_false(GameData.unequip_to_slot(0, 3))


func test_unequip_to_slot_no_save_returns_false():
	GameData.current_save = null
	assert_false(GameData.unequip_to_slot(0, 3))
