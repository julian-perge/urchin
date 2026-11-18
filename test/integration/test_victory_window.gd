# The Victory Window (spec/107-victory.md): the drops, the strings, the
# experience rows' pitch and the lock on Proceed. test_screen_rects.gd checks
# where each piece sits. test_battle_scene.gd checks the battle's hand-off.
extends GutTest

const VictoryWindowScene: PackedScene = preload("res://scenes/ui/menu/victory_window.tscn")
const STRINGS_PATH: String = "res://dev/converted_json/strings.json"

var _save: PlayerSave


func before_each() -> void:
	_save = PlayerSave.new_game("Victory", 0)
	GameData.current_save = _save


func after_each() -> void:
	GameData.current_save = null


func _settlement(drops: Array[int]) -> BattleSettlement:
	var settlement := BattleSettlement.new()
	var player := BattleSettlement.FighterExperience.new()
	player.experience_before = 10.0
	player.level_before = 2
	player.xp_gained = 30.0
	settlement.fighters[0] = player
	settlement.money_gained = 12
	settlement.xp_gained = 30.0
	settlement.drops = drops
	return settlement


func _window(drops: Array[int]) -> VictoryWindow:
	var window: VictoryWindow = add_child_autofree(VictoryWindowScene.instantiate())
	window.setup(_save, _settlement(drops))
	return window


func _finish_player_row(window: VictoryWindow) -> void:
	var row: VictoryExpRow = window.get_node("ExpRows/PlayerSlot/Row")
	while not row.is_finished():
		row.step()


func _strings() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(STRINGS_PATH))


# The rows of the player and the two Companions are 92.50 px apart.
func test_the_experience_rows_are_92_50_px_apart() -> void:
	var window: VictoryWindow = _window([])
	await wait_process_frames(2)
	var tops: Array[float] = []
	for slot in ["PlayerSlot", "CompanionSlot0", "CompanionSlot1"]:
		tops.append((window.get_node("ExpRows/%s" % slot) as Control).global_position.y)
	assert_almost_eq(tops[1] - tops[0], 92.5, 0.01)
	assert_almost_eq(tops[2] - tops[1], 92.5, 0.01)


func test_the_drop_slots_sit_on_five_columns_and_three_rows() -> void:
	var window: VictoryWindow = _window([])
	await wait_process_frames(2)
	assert_eq(window._drop_slots.size(), 15)
	var columns: Dictionary = {}
	var rows: Dictionary = {}
	for slot: ItemSlot in window._drop_slots:
		columns[snappedf(slot.global_position.x, 0.01)] = true
		rows[snappedf(slot.global_position.y, 0.01)] = true
	assert_eq(columns.size(), 5)
	assert_eq(rows.size(), 3)


# An empty slot is hidden and keeps its place, so a shorter list does not shift
# the slots after it.
func test_an_empty_drop_slot_is_hidden_and_keeps_its_place() -> void:
	var window: VictoryWindow = _window([300, 301])
	await wait_process_frames(2)
	var empty_x: float = window._drop_slots[2].global_position.x
	for i in window._drop_slots.size():
		var slot: ItemSlot = window._drop_slots[i]
		assert_eq(slot.modulate.a, 1.0 if i < 2 else 0.0, "slot %d" % i)
		assert_eq(slot.mouse_filter, Control.MOUSE_FILTER_STOP if i < 2 else Control.MOUSE_FILTER_IGNORE)
	var full: VictoryWindow = _window([300, 301, 302])
	await wait_process_frames(2)
	assert_almost_eq(full._drop_slots[2].global_position.x, empty_x, 0.01)


func test_no_items_found_shows_with_no_drops() -> void:
	var window: VictoryWindow = _window([])
	assert_eq(window.get_node("NoItemsLabel").text, _strings()["MENU"][12])
	assert_eq(window.get_node("ClickHintLabel").text, "")


func test_the_click_hint_shows_with_drops() -> void:
	var window: VictoryWindow = _window([300])
	assert_eq(window.get_node("NoItemsLabel").text, "")
	assert_eq(window.get_node("ClickHintLabel").text, _strings()["VICTORY"][1])


func test_every_label_reads_from_strings_json() -> void:
	var strings: Dictionary = _strings()
	var window: VictoryWindow = _window([300])
	assert_eq(window.get_node("Heading").text, strings["MENU"][15])
	assert_eq(window.get_node("DropsLabel").text, strings["VICTORY"][0])
	assert_eq(window.get_node("ClickHintLabel").text, strings["VICTORY"][1])
	assert_eq(window.get_node("MoneyLabel").text, strings["VICTORY"][2])
	assert_eq(window.get_node("ExpLabel").text, strings["VICTORY"][3])
	assert_eq(window.get_node("ProceedHintLabel").text, strings["VICTORY"][4])
	assert_eq(window.get_node("ProceedLabel").text, strings["MENU"][13])
	assert_eq(window.right_column.get_node("Title").text, strings["MENU"][14])
	var gain := _window([])
	assert_eq(gain.get_node("MoneyValue").text, String.chr(0x20ac) + "12")
	assert_eq(gain.get_node("ExpValue").text, "30%")


func test_a_click_on_a_drop_moves_it_into_the_first_free_cell() -> void:
	_save.item_array[0] = 304
	var window: VictoryWindow = _window([300, 301])
	var drop: ItemSlot = window._drop_slots[1]
	window._on_drop_clicked(drop)
	assert_eq(_save.item_array[1], 301)
	assert_null(drop.item)
	assert_eq(drop.modulate.a, 0.0, "the claimed slot is hidden")
	assert_eq(window._drop_slots[0].item.id, 300, "the other drop stays")
	assert_eq(window.right_column.slots[1].item.id, 301, "the column shows it")


func test_a_full_inventory_leaves_the_drop_claimable() -> void:
	_save.item_array.fill(304)
	var window: VictoryWindow = _window([300])
	var drop: ItemSlot = window._drop_slots[0]
	window._on_drop_clicked(drop)
	assert_eq(drop.item.id, 300)
	assert_eq(drop.modulate.a, 1.0)
	assert_does_not_have(_save.item_array, 300)


func test_proceed_does_nothing_before_the_players_row_finishes() -> void:
	var window: VictoryWindow = _window([])
	watch_signals(window)
	window._on_proceed_pressed()
	assert_signal_not_emitted(window, "proceed_pressed")
	assert_false((window.get_node("ProceedButton") as Button).disabled)
	_finish_player_row(window)
	window._on_proceed_pressed()
	assert_signal_emit_count(window, "proceed_pressed", 1)


func test_proceed_works_once() -> void:
	var window: VictoryWindow = _window([])
	_finish_player_row(window)
	watch_signals(window)
	window._on_proceed_pressed()
	window._on_proceed_pressed()
	assert_signal_emit_count(window, "proceed_pressed", 1)
