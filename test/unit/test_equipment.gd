# Unit tests for Equipment - validation rules and stat transfer, expected
# behavior from the item-slot click handler (DefineButton2_2981, see
# equipment.gd header).
extends GutTest

const GameItemScript = preload("res://scripts/entities/game_item.gd")

var save: PlayerSave
var items_by_id: Dictionary


func before_each():
	save = PlayerSave.new_game("Test", 0)
	items_by_id = {}


func _make_item(id: int, item_type: int, level: int = 1, unit_id: int = 0, attributes: Dictionary = {}, piercing: Dictionary = {}, defense: Dictionary = {}) -> GameItem:
	var item = Resource.new()
	item.set_script(GameItemScript)
	item.id = id
	item.display_name = "Item %d" % id
	item.item_type = item_type
	item.required_level = level
	item.required_unit_id = unit_id
	item.stats = {"attributes": attributes, "piercing": piercing, "defense": defense}
	items_by_id[id] = item
	return item


func test_slot_for_item():
	assert_eq(Equipment.slot_for_item(_make_item(1, GameItem.ItemType.HEAD)), 0)
	assert_eq(Equipment.slot_for_item(_make_item(2, GameItem.ItemType.MAINHAND)), 5)
	assert_eq(Equipment.slot_for_item(_make_item(3, GameItem.ItemType.TWOHAND)), 5, "two-handed goes to main hand")
	assert_eq(Equipment.slot_for_item(_make_item(4, GameItem.ItemType.OFFHAND)), 6)
	assert_eq(Equipment.slot_for_item(_make_item(5, GameItem.ItemType.TOOL)), -1, "tools are not equipment")


func test_level_and_unit_gates():
	var high_level = _make_item(1, GameItem.ItemType.HEAD, 10)
	assert_eq(Equipment.can_equip(save, high_level, 0), Equipment.EquipResult.LEVEL_TOO_LOW)
	var veradux_gear = _make_item(2, GameItem.ItemType.CHEST, 1, 4)
	assert_eq(
		Equipment.can_equip(save, veradux_gear, 1), Equipment.EquipResult.WRONG_CLASS,
		"unit 4 (Veradux) gear blocked for the player"
	)
	var own_class_gear = _make_item(3, GameItem.ItemType.CHEST, 1, save.player_class + 1)
	assert_eq(Equipment.can_equip(save, own_class_gear, 1), Equipment.EquipResult.OK)


func test_slot_type_gate():
	var helmet = _make_item(1, GameItem.ItemType.HEAD)
	assert_eq(Equipment.can_equip(save, helmet, 1), Equipment.EquipResult.WRONG_SLOT)
	assert_eq(Equipment.can_equip(save, helmet, 0), Equipment.EquipResult.OK)


func test_two_handed_exclusion_rules():
	var two_handed = _make_item(1, GameItem.ItemType.TWOHAND)
	var shield = _make_item(2, GameItem.ItemType.OFFHAND)
	# Secondary equipped -> two-handed blocked.
	save.equip_array[Equipment.SECONDARY_SLOT] = shield.id
	assert_eq(
		Equipment.can_equip(save, two_handed, Equipment.MAIN_HAND_SLOT),
		Equipment.EquipResult.SECONDARY_BLOCKS_TWO_HANDED
	)
	save.equip_array[Equipment.SECONDARY_SLOT] = 0
	# Two-handed equipped -> secondary blocked.
	save.equip_array[Equipment.MAIN_HAND_SLOT] = two_handed.id
	assert_eq(
		Equipment.can_equip_with_lookup(save, shield, Equipment.SECONDARY_SLOT, items_by_id),
		Equipment.EquipResult.TWO_HANDED_BLOCKS_SECONDARY
	)


func test_equip_transfers_stats_and_swaps():
	var strength_before = save.strength
	var sword = _make_item(1, GameItem.ItemType.MAINHAND, 1, 0, {"strength": 5}, {"Fire": 10})
	var outcome = Equipment.equip(save, sword, Equipment.MAIN_HAND_SLOT, items_by_id)
	assert_eq(outcome["result"], Equipment.EquipResult.OK)
	assert_eq(save.strength, strength_before + 5, "attribute bonus lands in the derived stat")
	assert_eq(save.per[CombatUnit.Element.FIRE], 10.0, "piercing bonus lands in the allocation")

	var better_sword = _make_item(2, GameItem.ItemType.MAINHAND, 1, 0, {"strength": 8})
	outcome = Equipment.equip(save, better_sword, Equipment.MAIN_HAND_SLOT, items_by_id)
	assert_eq(outcome["previous_item_id"], 1, "displaced item returned")
	assert_eq(save.strength, strength_before + 8, "old bonus reverted, new applied")
	assert_eq(save.per[CombatUnit.Element.FIRE], 0.0)

	var removed = Equipment.unequip(save, Equipment.MAIN_HAND_SLOT, items_by_id)
	assert_eq(removed, 2)
	assert_eq(save.strength, strength_before, "unequip reverts everything")
	assert_eq(save.equip_array[Equipment.MAIN_HAND_SLOT], 0)


func test_respec_reseeds_equipment_bonuses():
	var sword = _make_item(1, GameItem.ItemType.MAINHAND, 1, 0, {"strength": 5, "health": 2})
	Equipment.equip(save, sword, Equipment.MAIN_HAND_SLOT, items_by_id)
	save.level = 5
	save.euro = 100.0
	var bonuses = Equipment.total_stat_bonuses(save, items_by_id)
	assert_eq(bonuses, [2, 5, 0, 0, 0], "life/strength from the equipped sword")
	assert_true(Leveling.respec(save, bonuses, "2026-07-18"))
	assert_eq(save.stat_allocated, [2, 5, 0, 0, 0], "gear bonuses survive the respec")
