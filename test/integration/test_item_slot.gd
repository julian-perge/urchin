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
