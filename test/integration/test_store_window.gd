# Integration test for the Store window: the scene instances RightColumn with
# its sell slot shown, and buy and sell flow through GameData against a live
# save.
extends GutTest

const StoreWindowScene = preload("res://scenes/ui/store/store_window.tscn")


func after_each():
	GameData.current_save = null


func test_scene_instantiates_with_wired_nodes():
	var window = add_child_autofree(StoreWindowScene.instantiate())
	assert_not_null(window.store_items, "%StoreItems resolves")


# The shop frame is the one frame that places the sell slot
# (spec/107-window-shell.md, RightColumn).
func test_the_store_instances_the_right_column_with_the_sell_slot_shown():
	var window: Control = add_child_autofree(StoreWindowScene.instantiate())
	await wait_process_frames(2)
	var columns: Array[Node] = window.find_children("*", "RightColumn", true, false)
	assert_eq(columns.size(), 1)
	assert_eq(window.right_column, columns[0])
	assert_eq(window.right_column.owner, window, "the column is a node of store_window.tscn")
	assert_true(window.right_column.sell_button.visible)
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/screen_rects.json"))
	var rect: Array = record["scenes"]["res://scenes/ui/window/right_column.tscn"]["pieces"]["TallPanel"]["rect"]
	assert_almost_eq(window.right_column.global_position, Vector2(rect[0], rect[1]), Vector2(0.5, 0.5))


# The sell slot reaches the window through the [connection] lines in
# right_column.tscn and store_window.tscn.
func test_the_sell_slot_sells_the_selected_item_and_shows_the_new_amount():
	GameData.current_save = PlayerSave.new_game("StoreSellTest", 0)
	var item: GameItem = null
	for candidate: GameItem in ItemManagerAuto.items_by_id.values():
		if candidate.price > 0.0:
			item = candidate
			break
	GameData.current_save.item_array[0] = item.id
	var window = add_child_autofree(StoreWindowScene.instantiate())
	window.refresh_store()
	var euro_before: float = GameData.current_save.euro
	window.right_column.selected_slot = window.right_column.slots[0]
	window.right_column.sell_button.pressed.emit()
	assert_eq(int(GameData.current_save.item_array[0]), 0)
	assert_eq(GameData.current_save.euro, euro_before + ceil(item.price * 0.15))
	assert_eq(window.right_column.amount_label.text, str(int(GameData.current_save.euro)))
	assert_null(window.right_column.slots[0].item)


# The shop frame fills its vb1 field with MENU[6]
# (DefineSprite_3142/frame_16/DoAction.as:96, frame_1/DoAction.as:214).
func test_purchase_hint_is_the_original_string():
	var window = add_child_autofree(StoreWindowScene.instantiate())
	assert_eq(window.get_node("PurchaseHintLabel").text, "Click on items to purchase:")


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
