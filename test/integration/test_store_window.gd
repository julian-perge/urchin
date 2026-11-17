# Integration test for the Store window: the scene instances RightColumn with
# its sell slot shown, and buy and sell flow through GameData against a live
# save.
extends GutTest

const StoreWindowScene = preload("res://scenes/ui/store/store_window.tscn")


func after_each():
	GameData.current_save = null


const STRINGS_PATH: String = "res://dev/converted_json/strings.json"
const RECORD_PATH: String = "res://test/fixtures/screen_rects.json"
const WARE_ROW: String = "CentreBottomPanel/Content/Wares/Row%d/Slot%d"
const WARE_COLUMNS: int = 5


func test_scene_instantiates_with_wired_nodes():
	var window = add_child_autofree(StoreWindowScene.instantiate())
	assert_eq(window.ware_slots.size(), 15, "the wares grid holds 15 slots")
	assert_not_null(window.keeper_art)
	assert_not_null(window.keeper_line)
	assert_not_null(window.hint_label)


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


# The tests below read strings.json themselves, so a line typed into the scene
# or the script fails them. The shop frame fills vb1 with MENU[6] and vb2 with
# SHOP[shopId] (DefineSprite_3142/frame_16/DoAction.as:96-97).
func _strings() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(STRINGS_PATH))


# Returns what the window's keeper line and hint show wrong against the table.
func _text_problems(window: Control, shop_id: int) -> Array[String]:
	var found: Array[String] = []
	var table: Dictionary = _strings()
	if window.keeper_line.text != table["SHOP"][shop_id]:
		found.append("keeper line '%s', expected SHOP[%d]" % [window.keeper_line.text, shop_id])
	if window.hint_label.text != table["MENU"][6]:
		found.append("hint '%s', expected MENU[6]" % window.hint_label.text)
	return found


func test_the_keeper_line_and_the_hint_are_the_strings_of_the_original():
	var window = add_child_autofree(StoreWindowScene.instantiate())
	for zone in StoreManager.ZONE_SHOP_IDS:
		ZoneManager.current_zone = zone
		window.refresh_store()
		assert_eq(_text_problems(window, StoreManager.ZONE_SHOP_IDS[zone]), [] as Array[String], "zone %d" % zone)
	ZoneManager.current_zone = 1


func test_control_a_typed_keeper_line_or_hint_fails_the_strings_test():
	ZoneManager.current_zone = 1
	var window = add_child_autofree(StoreWindowScene.instantiate())
	window.refresh_store()
	assert_eq(_text_problems(window, 0), [] as Array[String], "the unchanged window passes")
	window.keeper_line.text = "I got what you need mate."
	assert_eq(_text_problems(window, 0).size(), 1, "a different keeper line fails")
	window.keeper_line.text = _strings()["SHOP"][0]
	window.hint_label.text = "Click on items to buy:"
	assert_eq(_text_problems(window, 0).size(), 1, "a different hint fails")


# Shops 5 and 6 have an empty line in the original, and the port shows none.
func test_shops_5_and_6_show_an_empty_keeper_line():
	var window = add_child_autofree(StoreWindowScene.instantiate())
	for zone in [6, 7]:
		ZoneManager.current_zone = zone
		window.refresh_store()
		assert_eq(window.keeper_line.text, "", "zone %d, shop %d" % [zone, StoreManager.ZONE_SHOP_IDS[zone]])
	ZoneManager.current_zone = 1


# Shop 0 stocks 8 items. The 7 empty slots are hidden without leaving their
# cells, because FloatBox would pull the slots after a `visible = false` slot
# forward.
func test_a_catalog_of_8_items_shows_8_wares_and_hides_7_in_their_cells():
	ZoneManager.current_zone = 1
	var window = add_child_autofree(StoreWindowScene.instantiate())
	await wait_process_frames(2)
	window.refresh_store()
	await wait_process_frames(2)
	assert_eq(StoreManager.get_current_shop_items().size(), 8, "shop 0 stocks 8 items")
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECORD_PATH))
	var pieces: Dictionary = record["scenes"]["res://scenes/ui/store/store_window.tscn"]["pieces"]
	for i in window.ware_slots.size():
		var slot: ItemSlot = window.ware_slots[i]
		var stocked: bool = i < 8
		assert_eq(slot.item != null, stocked, "slot %d holds an item" % i)
		assert_eq(slot.modulate.a, 1.0 if stocked else 0.0, "slot %d alpha" % i)
		assert_eq(slot.mouse_filter, Control.MOUSE_FILTER_STOP if stocked else Control.MOUSE_FILTER_IGNORE, "slot %d mouse filter" % i)
		assert_true(slot.visible, "slot %d stays visible so it keeps its cell" % i)
		var rect: Array = pieces[WARE_ROW % [floori(float(i) / WARE_COLUMNS), i % WARE_COLUMNS]]["rect"]
		assert_almost_eq(slot.global_position, Vector2(rect[0], rect[1]), Vector2(0.5, 0.5), "slot %d cell" % i)


# Clicking a stocked ware buys it. A hidden slot takes no click, because its
# mouse filter ignores the mouse.
func test_a_click_on_a_ware_buys_it_and_a_hidden_slot_takes_no_click():
	ZoneManager.current_zone = 1
	GameData.current_save = PlayerSave.new_game("StoreBuyTest", 0)
	GameData.current_save.euro = 1000000.0
	var window = add_child_autofree(StoreWindowScene.instantiate())
	window.refresh_store()
	var ware: ItemSlot = window.ware_slots[0]
	var euro_before: float = GameData.current_save.euro
	ware.slot_clicked.emit(ware)
	assert_true(GameData.current_save.item_array.has(ware.item.id), "the ware is in the inventory")
	assert_eq(GameData.current_save.euro, euro_before - ware.item.price)
	assert_eq(window.ware_slots[14].mouse_filter, Control.MOUSE_FILTER_IGNORE)


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
	assert_string_contains(window.keeper_line.text, "soap", "zone 1 keeper dialogue")
	var zone1_backdrop = window.keeper_art.texture
	assert_not_null(zone1_backdrop)
	assert_eq(
		window.ware_slots[0].item.id,
		_first_stocked_id(0),
		"zone 1 shows shop 0's first stocked item"
	)

	ZoneManager.current_zone = 6
	window.refresh_store()
	assert_eq(window.keeper_line.text, "", "zone 6 keeper has no dialogue in the source")
	assert_ne(window.keeper_art.texture, zone1_backdrop, "backdrop swaps per zone")
	assert_ne(
		_first_stocked_id(6), _first_stocked_id(5),
		"the two catalogs differ, so the next assert can tell them apart"
	)
	assert_eq(
		window.ware_slots[0].item.id,
		_first_stocked_id(6),
		"zone 6 uses shop 6's catalog, not shop 5's"
	)
	ZoneManager.current_zone = 1
	GameData.current_save = null


# The original does not tint a clicked ware, because a ware you can buy goes
# straight to the inventory. A tint would also stay on the slot after the
# purchase.
func test_clicking_a_ware_leaves_its_slot_untinted():
	ZoneManager.current_zone = 1
	GameData.current_save = PlayerSave.new_game("StoreTintTest", 0)
	GameData.current_save.euro = 1000000.0
	var window = add_child_autofree(StoreWindowScene.instantiate())
	window.refresh_store()
	var ware: ItemSlot = window.ware_slots[0]
	ware.slot_clicked.emit(ware)
	assert_eq(ware.modulate, Color.WHITE, "after a purchase")
	GameData.current_save.euro = 0.0
	ware.slot_clicked.emit(ware)
	assert_eq(ware.modulate, Color.WHITE, "after a refused purchase")


# The Store places a Doll in its scene, as the Inventory does, and the equip
# slots in the scene are the ones that EquipDollView connects. The record's
# position is fitted from the SWF's 16 part clips of the shop frame.
func _store_pieces() -> Dictionary:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECORD_PATH))
	return record["scenes"]["res://scenes/ui/store/store_window.tscn"]["pieces"]


func test_the_doll_stands_where_the_part_placements_put_it_facing_left_behind_the_slots():
	GameData.current_save = PlayerSave.new_game("StoreDoll", 0)
	var window = add_child_autofree(StoreWindowScene.instantiate())
	var doll: Node2D = window.equip_view.get_node("Doll")
	var placed: Dictionary = _store_pieces()["CentreTopPanel/Content/EquipDollView/Doll"]
	assert_eq(doll.owner, window, "the doll is a node of store_window.tscn")
	assert_almost_eq(doll.global_position, Vector2(placed["position"][0], placed["position"][1]), Vector2(0.01, 0.01))
	assert_almost_eq(doll.scale, Vector2(placed["scale"][0], placed["scale"][1]), Vector2(0.0001, 0.0001))
	assert_lt(doll.scale.x, 0.0, "the doll is mirrored to face left")
	for i in 7:
		assert_lt(doll.get_index(), window.equip_view.get_node("Slot%d" % i).get_index())


func test_the_store_keeps_the_scene_doll_and_has_no_second_one():
	GameData.current_save = PlayerSave.new_game("StoreDoll", 0)
	var window = add_child_autofree(StoreWindowScene.instantiate())
	var dolls: Array[Node] = window.find_children("*", "CharacterVisual", true, false)
	assert_eq(dolls.size(), 1)
	assert_eq(window.find_children("*", "EquipDollView", true, false).size(), 1)
	window.refresh_store()
	assert_eq(window.find_children("*", "CharacterVisual", true, false), dolls)
	var doll: CharacterVisual = window.equip_view.get_node("Doll")
	assert_gt(doll.get_bounds().size.x, 0.0, "refresh dresses the doll")


func test_the_seven_equip_slots_are_scene_nodes_at_the_slot_scale_of_the_frame():
	var window = add_child_autofree(StoreWindowScene.instantiate())
	var slots: Array[Node] = window.equip_view.find_children("*", "ItemSlot", true, false)
	assert_eq(slots.size(), 7)
	for i in 7:
		var slot: ItemSlot = window.equip_view.get_node("Slot%d" % i)
		assert_eq(slot.owner, window)
		assert_eq(int(slot.get_meta("equip_index")), i)
		var rect: Array = _store_pieces()["CentreTopPanel/Content/EquipDollView/Slot%d" % i]["rect"]
		assert_almost_eq(slot.get_global_rect().size, Vector2(rect[2], rect[3]), Vector2(0.05, 0.05), "the slot draws at the record's size")
		assert_lt(slot.scale.x, 1.0, "the slot is scaled down from its 31 px art")


# A click on an equip slot of the Store unequips the item, and a click on an
# item of the right column equips it.
func test_equip_and_unequip_work_through_the_scene_slots():
	GameData.current_save = PlayerSave.new_game("StoreEquip", 0)
	var item: GameItem = null
	for candidate: GameItem in ItemManagerAuto.items_by_id.values():
		if candidate.required_level <= 1 and candidate.required_unit_id == 0 and Equipment.slot_for_item(candidate) != -1:
			item = candidate
			break
	assert_not_null(item)
	if item == null:
		return
	GameData.current_save.item_array[0] = item.id
	var window = add_child_autofree(StoreWindowScene.instantiate())
	window.refresh_store()
	var equip_index: int = Equipment.slot_for_item(item)
	var bag_slot: ItemSlot = window.right_column.slots[0]
	window.right_column.item_selected.emit(bag_slot)
	assert_eq(int(GameData.current_save.equip_array[equip_index]), item.id, "the click equipped it")
	assert_eq((window.equip_view.get_node("Slot%d" % equip_index) as ItemSlot).item, item, "the slot shows it")
	var slot: ItemSlot = window.equip_view.get_node("Slot%d" % equip_index)
	slot.slot_clicked.emit(slot)
	assert_eq(int(GameData.current_save.equip_array[equip_index]), 0, "the click unequipped it")
	assert_eq(int(GameData.current_save.item_array[0]), item.id)


# EquipDollView holds no second way to build a doll: its setup() takes no
# placement and finds the Doll that the scene places.
func test_equip_doll_view_setup_takes_no_arguments_and_needs_the_scene_doll():
	var view: EquipDollView = autofree(EquipDollView.new())
	for method: Dictionary in view.get_method_list():
		if method["name"] == "setup":
			assert_eq((method["args"] as Array).size(), 0, "setup() has no placement parameters")
	assert_eq(view.find_children("*", "CharacterVisual", true, false).size(), 0, "a bare view builds no doll")
