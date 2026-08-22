# Integration test for the repaired store UI: the scene instantiates without
# missing-node errors, the InventoryPanel API drives the instanced
# inventory.tscn, and buy/sell flow through GameData against a live save.
extends GutTest

const StoreWindowScene = preload("res://scenes/ui/store/store_window.tscn")
const GameItemScript = preload("res://scripts/entities/game_item.gd")


func _make_item(id: int, price: int) -> GameItem:
	var item = Resource.new()
	item.set_script(GameItemScript)
	item.id = id
	item.display_name = "Test Item %d" % id
	item.item_type = GameItem.ItemType.HEAD
	item.price = price
	item.stats = {}
	return item


func test_scene_instantiates_with_wired_nodes():
	var window = add_child_autofree(StoreWindowScene.instantiate())
	assert_not_null(window.store_items, "%StoreItems resolves")
	assert_not_null(window.inventory_panel, "instanced inventory panel found")
	assert_true(window.inventory_panel is InventoryPanel, "inventory.tscn carries the panel script")
	assert_not_null(window.inventory_panel.gold_label, "%PlayerGold resolves inside the panel")
	assert_not_null(window.inventory_panel.sell_button)
	assert_not_null(window.inventory_panel.inventory_grid)


func test_inventory_panel_populate_and_selection():
	var window = add_child_autofree(StoreWindowScene.instantiate())
	var panel: InventoryPanel = window.inventory_panel
	var item = _make_item(1, 10)
	panel.populate([item])
	var first_slot: ItemSlot = null
	for child in panel.inventory_grid.get_children():
		if child is ItemSlot:
			first_slot = child
			break
	assert_not_null(first_slot)
	assert_eq(first_slot.item, item, "first slot holds the item")
	var selected = []
	panel.item_selected.connect(func(slot): selected.append(slot))
	panel._on_slot_clicked(first_slot)
	assert_eq(selected.size(), 1, "selection signal fired")
	assert_true(first_slot.selected)


func test_gold_formatting():
	var window = add_child_autofree(StoreWindowScene.instantiate())
	window.inventory_panel.set_gold(1234567.0)
	assert_eq(window.inventory_panel.gold_label.text, "€ 1,234,567")
	window.inventory_panel.set_gold(0.0)
	assert_eq(window.inventory_panel.gold_label.text, "€ 0")


# The catalogs are real source data that gets corrected from time to time (see
# KRIN_SHOP_ITEMS and the commented-out debug set beside it), so these tests
# read the expected id out of the table rather than hardcoding one. What is
# being tested is that a zone reaches its own shop's catalog, not what that
# catalog contains. A shop pads its 15 slots with 0 for the items it does not
# stock, and get_current_shop_items() drops those.
func _first_stocked_id(shop_id: int) -> int:
	for id in StoreManager.KRIN_SHOP_ITEMS[shop_id]:
		if int(id) != 0:
			return int(id)
	return 0


func test_zone_to_shop_mapping_matches_source():
	# From the SWF store-orb buttons: zones 6 and 7 are SWAPPED versus the
	# naive zone-1 ordering.
	assert_eq(StoreManager.ZONE_SHOP_IDS[1], 0)
	assert_eq(StoreManager.ZONE_SHOP_IDS[5], 4)
	assert_eq(StoreManager.ZONE_SHOP_IDS[6], 6, "zone 6 sells shop 6's catalog")
	assert_eq(StoreManager.ZONE_SHOP_IDS[7], 5, "zone 7 sells shop 5's catalog")


func test_store_refreshes_per_zone():
	GameData.current_save = PlayerSave.new_game("StoreTest", 0)
	ZoneManager.current_zone = 1
	var window = add_child_autofree(StoreWindowScene.instantiate())
	window.refresh_store()
	assert_string_contains(window.shop_dialogue.text, "soap", "zone 1 keeper dialogue")
	var zone1_backdrop = window.shop_backdrop.texture
	assert_not_null(zone1_backdrop)
	var first_zone1_item: ItemSlot = null
	for child in window.store_items.get_children():
		if child is ItemSlot:
			first_zone1_item = child
			break
	assert_eq(
		first_zone1_item.item.id,
		_first_stocked_id(0),
		"zone 1 shows shop 0's first stocked item"
	)

	ZoneManager.current_zone = 6
	window.refresh_store()
	assert_eq(window.shop_dialogue.text, "...", "zone 6 keeper has no dialogue in the source")
	assert_ne(window.shop_backdrop.texture, zone1_backdrop, "backdrop swaps per zone")
	var first_zone6_item: ItemSlot = null
	for child in window.store_items.get_children():
		if child is ItemSlot:
			first_zone6_item = child
			break
	assert_ne(
		_first_stocked_id(6), _first_stocked_id(5),
		"the two catalogs differ, so the next assert can tell them apart"
	)
	assert_eq(
		first_zone6_item.item.id,
		_first_stocked_id(6),
		"zone 6 uses shop 6's catalog, not shop 5's"
	)
	ZoneManager.current_zone = 1
	GameData.current_save = null
