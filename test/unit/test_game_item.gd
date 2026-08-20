# test_game_item.gd
extends GutTest


func test_slot_type_display_name_covers_every_equip_slot():
	var item := GameItem.new()
	item.item_type = GameItem.ItemType.MAINHAND
	assert_eq(item.slot_type_display_name(), "Primary Arms")
	item.item_type = GameItem.ItemType.TWOHAND
	assert_eq(item.slot_type_display_name(), "Two-Handed Arms")
	item.item_type = GameItem.ItemType.OFFHAND
	assert_eq(item.slot_type_display_name(), "Secondary Arms")
	item.item_type = GameItem.ItemType.HEAD
	assert_eq(item.slot_type_display_name(), "Headwear")
	item.item_type = GameItem.ItemType.CHEST
	assert_eq(item.slot_type_display_name(), "Bodywear")
	item.item_type = GameItem.ItemType.HAND
	assert_eq(item.slot_type_display_name(), "Gloves")
	item.item_type = GameItem.ItemType.LEGS
	assert_eq(item.slot_type_display_name(), "Leggings")
	item.item_type = GameItem.ItemType.FOOT
	assert_eq(item.slot_type_display_name(), "Footwear")
	item.item_type = GameItem.ItemType.TOOL
	assert_eq(item.slot_type_display_name(), "Tool")


func test_slot_type_display_name_is_empty_for_none():
	var item := GameItem.new()
	item.item_type = GameItem.ItemType.NONE
	assert_eq(item.slot_type_display_name(), "")
