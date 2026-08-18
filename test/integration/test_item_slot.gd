# ItemSlot's hover highlight now lives in the .tscn as a real "Highlight"
# child node instead of being constructed at runtime in _ready() - this
# locks in that it's wired correctly and still toggles on hover.
extends GutTest

const ItemSlotScene = preload("res://scenes/ui/item_slot.tscn")


func test_highlight_node_exists_and_starts_hidden():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	var highlight: TextureRect = slot.get_node("Highlight")
	assert_not_null(highlight, "Highlight child exists in the scene")
	assert_false(highlight.visible, "highlight starts hidden")


func test_highlight_toggles_on_hover_signals():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	var highlight: TextureRect = slot.get_node("Highlight")
	slot.mouse_entered.emit()
	assert_true(highlight.visible, "highlight shows on mouse_entered")
	slot.mouse_exited.emit()
	assert_false(highlight.visible, "highlight hides on mouse_exited")


# Drag source (.claude/plan_item_drag_and_drop.md Task 2) - "drag_source"/
# "drag_index" are set by whichever host owns the slot (inventory_panel.gd/
# equip_doll_view.gd), not by ItemSlot itself, so an unowned slot in this
# test falls back to the same defaults _get_drag_data() itself declares.
func test_get_drag_data_on_empty_slot_starts_no_drag():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	assert_null(slot._get_drag_data(Vector2.ZERO), "nothing to drag from an empty slot")


func test_drag_payload_returns_item_and_host_metadata():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	var item: GameItem = ItemManagerAuto.items_by_id.values()[0]
	slot.set_item(item)
	slot.set_meta("drag_source", "equip")
	slot.set_meta("drag_index", 5)
	var payload = slot._drag_payload()
	assert_eq(payload["item"], item)
	assert_eq(payload["source"], "equip")
	assert_eq(payload["index"], 5)


func test_drag_payload_defaults_to_inventory_source_with_no_host_meta():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	var item: GameItem = ItemManagerAuto.items_by_id.values()[0]
	slot.set_item(item)
	var payload = slot._drag_payload()
	assert_eq(payload["source"], "inventory")
	assert_eq(payload["index"], -1)


# Drop target (.claude/plan_item_drag_and_drop.md Task 3) - inventory<->
# inventory swaps, inventory<->equip equips/unequips.
func after_each():
	GameData.current_save = null


func _find_basic_equippable() -> GameItem:
	var best: GameItem = null
	for item in ItemManagerAuto.items_by_id.values():
		if item.required_level > 1 or item.required_unit_id != 0:
			continue
		if Equipment.slot_for_item(item) == -1:
			continue
		if best == null or item.id < best.id:
			best = item
	return best


func test_can_drop_data_inventory_accepts_inventory_and_equip_sources():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	slot.set_meta("drag_source", "inventory")
	assert_true(slot._can_drop_data(Vector2.ZERO, {"item": true, "source": "inventory", "index": 0}))
	assert_true(slot._can_drop_data(Vector2.ZERO, {"item": true, "source": "equip", "index": 0}))


func test_can_drop_data_equip_only_accepts_inventory_source():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	slot.set_meta("drag_source", "equip")
	assert_true(slot._can_drop_data(Vector2.ZERO, {"item": true, "source": "inventory", "index": 0}))
	assert_false(slot._can_drop_data(Vector2.ZERO, {"item": true, "source": "equip", "index": 0}), "equip<->equip makes no sense")


func test_can_drop_data_rejects_malformed_payload():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	assert_false(slot._can_drop_data(Vector2.ZERO, "not a dictionary"))
	assert_false(slot._can_drop_data(Vector2.ZERO, {}))


func test_drop_data_inventory_to_inventory_swaps():
	var save: PlayerSave = PlayerSave.new_game("DropTest", 0)
	GameData.current_save = save
	save.item_array[0] = 5
	save.item_array[1] = 9
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	slot.set_meta("drag_source", "inventory")
	slot.set_meta("drag_index", 0)
	slot._drop_data(Vector2.ZERO, {"item": true, "source": "inventory", "index": 1})
	assert_eq(int(save.item_array[0]), 9)
	assert_eq(int(save.item_array[1]), 5)


func test_drop_data_equip_source_to_inventory_slot_unequips_to_that_cell():
	var save: PlayerSave = PlayerSave.new_game("DropTest", 0)
	GameData.current_save = save
	var item: GameItem = _find_basic_equippable()
	assert_not_null(item, "an unrestricted level-1 equippable exists")
	var equip_slot: int = Equipment.slot_for_item(item)
	save.equip_array[equip_slot] = item.id
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	slot.set_meta("drag_source", "inventory")
	slot.set_meta("drag_index", 3)
	slot._drop_data(Vector2.ZERO, {"item": item, "source": "equip", "index": equip_slot})
	assert_eq(int(save.item_array[3]), item.id, "landed at the destination cell, not the first free one")
	assert_eq(int(save.equip_array[equip_slot]), 0)


func test_drop_data_inventory_source_to_equip_slot_equips():
	var save: PlayerSave = PlayerSave.new_game("DropTest", 0)
	GameData.current_save = save
	var item: GameItem = _find_basic_equippable()
	assert_not_null(item)
	save.item_array[2] = item.id
	var equip_slot: int = Equipment.slot_for_item(item)
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	slot.set_meta("drag_source", "equip")
	slot.set_meta("drag_index", equip_slot)
	slot._drop_data(Vector2.ZERO, {"item": item, "source": "inventory", "index": 2})
	assert_eq(int(save.equip_array[equip_slot]), item.id)
	assert_eq(int(save.item_array[2]), 0)
