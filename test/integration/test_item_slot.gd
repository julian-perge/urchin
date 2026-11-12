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
# "drag_index" are set by whichever host owns the slot (right_column.gd/
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
	GameTooltip.hide_tooltip()


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


func test_hover_shows_a_tooltip_for_a_filled_slot():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	var item: GameItem = ItemManagerAuto.items_by_id.values()[0]
	slot.set_item(item)
	slot.mouse_entered.emit()
	assert_true(GameTooltip._root.visible, "tooltip shown for a real item")
	var header_label: Label = GameTooltip._sections.get_child(0).get_child(0).get_child(0)
	assert_eq(header_label.text, item.display_name)


func test_hover_on_an_empty_slot_shows_no_tooltip():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	slot.mouse_entered.emit()
	assert_false(GameTooltip._root.visible, "nothing to show for an empty slot")


func test_hover_exit_hides_the_tooltip():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	var item: GameItem = ItemManagerAuto.items_by_id.values()[0]
	slot.set_item(item)
	slot.mouse_entered.emit()
	slot.mouse_exited.emit()
	assert_false(GameTooltip._root.visible, "hidden on mouse exit")


func test_tooltip_skips_the_type_line_for_a_none_type_item():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	var item: GameItem = GameItem.new()
	item.display_name = "Test Consumable"
	item.item_type = GameItem.ItemType.NONE
	slot.set_item(item)
	slot.mouse_entered.emit()
	# This item has no tooltipAlt/tooltip/price content either, so a correct
	# build produces exactly one section (the header) - the type line and
	# the body both use TooltipAlt/tooltip/price data this item doesn't
	# have, so counting sections is the real assertion here, not checking
	# for a specific missing bg_color (the type line uses BG_HEADER, same
	# as the title section it'd sit next to - checking "no BG_COST section"
	# would pass even if the skip were broken, since BG_COST is never used
	# by item tooltips at all).
	assert_eq(GameTooltip._sections.get_child_count(), 1, "just the header - no type line for NONE, no body with nothing to show")


func _tooltip_texts() -> Array:
	var texts: Array = []
	for section in GameTooltip._sections.get_children():
		for label in section.get_child(0).get_children():
			texts.append(label.text)
	return texts


# The original shows an item that isn't equipment in its plain tooltip layout,
# which fills only a title and a body from the item's name and flavor text
# (DefineButton2_3012 on(rollOver), lines 4-15). The stat line here is one the
# original never builds for such an item (frame_42/DoAction_16.as:57), so it
# proves the layout leaves stat lines out rather than that the data has none.
func test_a_non_equipment_item_shows_only_its_name_and_flavor_text():
	var slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	var item: GameItem = GameItem.new()
	item.display_name = "Broken Emerald Shard"
	item.item_type = GameItem.ItemType.NONE
	item.tooltipAlt = ["Focus +5"]
	item.tooltip = "It's probably worth quite a bit of money."
	slot.set_item(item)
	slot.mouse_entered.emit()
	assert_eq(_tooltip_texts(), [item.display_name, item.tooltip], "the name over the flavor text, and nothing else")
	assert_eq(
		GameTooltip._sections.get_child(1).get_child(0).get_child(0).get_theme_color("font_color"),
		Color("ffffff"),
		"in the plain layout's white body"
	)
	slot.mouse_exited.emit()


# The shop titles a catalog item with a euro sign, its price, KRINITEM[5], and
# its name, and shows the price nowhere else. A victory drop and an inventory
# item take the name alone (DefineButton2_3012 on(rollOver), lines 6-13 and
# 19-26, DefineButton2_2985 on(rollOver), lines 6 and 12). Metal Mask is the
# first item zone 1's shop sells, and the reference capture
# zone1_itemshop_menu_on_store_item_hover shows its title as "€22 - Metal Mask".
func test_a_shop_slot_titles_the_item_with_its_price_and_other_slots_with_its_name():
	var item: GameItem = ItemManagerAuto.items_by_id[508]
	var shop_slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	shop_slot.show_price = true
	shop_slot.set_item(item)
	shop_slot.mouse_entered.emit()
	var shop_texts: Array = _tooltip_texts()
	assert_eq(shop_texts[0], "€22 - Metal Mask", "the shop's title carries the price")
	assert_eq(shop_texts.filter(func(text): return text.contains("22")).size(), 1, "and no other line repeats it")
	shop_slot.mouse_exited.emit()
	var inventory_slot: ItemSlot = add_child_autofree(ItemSlotScene.instantiate())
	inventory_slot.set_item(item)
	inventory_slot.mouse_entered.emit()
	assert_eq(_tooltip_texts()[0], "Metal Mask", "an inventory or victory slot's title is the name alone")
	inventory_slot.mouse_exited.emit()
