# test_hub_card.gd - the Hub's Info card (scenes/ui/hub_card.tscn): what it
# shows, that it takes every click while it shows, its close prompt, and the
# Save button that opens it. Where the card's pieces sit is checked by
# test_screen_rects.gd.
extends GutTest

const CardScene = preload("res://scenes/ui/hub_card.tscn")
const HotbarScene = preload("res://scenes/ui/hotbar.tscn")

const TEST_SAVE_DIR := "user://test_hub_card_saves/"

var _save_before: PlayerSave
var _slot_before: int


# The Save button writes the current slot, so these tests write into a folder of
# their own and never into the player's real saves.
func before_each() -> void:
	_save_before = GameData.current_save
	_slot_before = GameData.current_slot
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)
	GameData.save_dir = TEST_SAVE_DIR


func after_each() -> void:
	GameData.current_save = _save_before
	GameData.current_slot = _slot_before
	GameData.save_dir = GameData.SAVE_DIR
	for file: String in DirAccess.get_files_at(TEST_SAVE_DIR):
		DirAccess.remove_absolute(TEST_SAVE_DIR + file)
	DirAccess.remove_absolute(TEST_SAVE_DIR)
	GameTooltip.hide_tooltip()


# A viewport of the Stage's size for a test that clicks. In the test runner's
# own viewport, GUT's panel covers part of the hotbar and takes the click.
func _stage() -> SubViewport:
	var stage := SubViewport.new()
	stage.size = Vector2i(800, 575)
	add_child_autofree(stage)
	return stage


# One left button event at `point`, pushed through the viewport's GUI input.
func _button_at(viewport: Viewport, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)


# A left click at `point`: a press, then a release.
func _click_at(viewport: Viewport, point: Vector2) -> void:
	for pressed: bool in [true, false]:
		_button_at(viewport, point, pressed)


func _click(control: Control) -> void:
	_click_at(control.get_viewport(), control.get_global_rect().get_center())


# The hotbar with the card over it, as scenes/game.tscn stacks them.
func _hub() -> Dictionary:
	var stage: SubViewport = _stage()
	var hotbar: Control = HotbarScene.instantiate()
	stage.add_child(hotbar)
	var card: HubCard = CardScene.instantiate()
	stage.add_child(card)
	await wait_process_frames(2)
	return {"stage": stage, "hotbar": hotbar, "card": card}


func test_the_card_is_hidden_until_it_is_shown():
	var card: HubCard = add_child_autofree(CardScene.instantiate())
	assert_false(card.visible)


func test_show_card_fills_the_title_and_the_text_and_shows_the_card():
	var card: HubCard = add_child_autofree(CardScene.instantiate())
	card.show_card("A title", "Some text\nover two lines")
	assert_true(card.visible)
	assert_eq((card.get_node("%Title") as Label).text, "A title")
	assert_eq((card.get_node("%Body") as Label).text, "Some text\nover two lines")


func test_hide_card_hides_the_card():
	var card: HubCard = add_child_autofree(CardScene.instantiate())
	card.show_card("A title", "Some text")
	card.hide_card()
	assert_false(card.visible)


func test_the_close_prompt_reads_system_8():
	var card: HubCard = add_child_autofree(CardScene.instantiate())
	assert_eq((card.get_node("%Prompt") as Label).text, Strings.system(8))


func test_the_card_is_in_the_hub_card_group():
	var card: HubCard = add_child_autofree(CardScene.instantiate())
	assert_eq(get_tree().get_first_node_in_group(HubCard.GROUP), card)


func test_the_card_blocks_a_click_on_a_hotbar_button_while_it_shows():
	var hub: Dictionary = await _hub()
	var button: BaseButton = hub["hotbar"].get_node("%InventoryButton")
	var card: HubCard = hub["card"]
	watch_signals(button)
	card.show_card("A title", "Some text")
	_click(button)
	assert_signal_not_emitted(button, "pressed", "the card takes the click")
	card.hide_card()
	_click(button)
	assert_signal_emitted(button, "pressed", "the hotbar takes it again after")


func test_the_close_button_hides_the_card_and_emits_closed():
	var hub: Dictionary = await _hub()
	var card: HubCard = hub["card"]
	watch_signals(card)
	card.show_card("A title", "Some text")
	_click(card.get_node("CloseButton"))
	assert_false(card.visible)
	assert_signal_emitted(card, "closed")


# The original's hit button closes the card on press, with no release needed
# (DefineButton2_2841/BUTTONCONDACTION on(press).as:2).
func test_the_close_button_closes_the_card_on_mouse_down():
	var hub: Dictionary = await _hub()
	var card: HubCard = hub["card"]
	watch_signals(card)
	card.show_card("A title", "Some text")
	var button: Control = card.get_node("CloseButton")
	_button_at(button.get_viewport(), button.get_global_rect().get_center(), true)
	assert_false(card.visible)
	assert_signal_emitted(card, "closed")


func test_a_click_on_the_card_away_from_the_close_button_does_nothing():
	var hub: Dictionary = await _hub()
	var card: HubCard = hub["card"]
	watch_signals(card)
	card.show_card("A title", "Some text")
	for point: Vector2 in [Vector2(400, 200), Vector2(10, 10), Vector2(400, 345)]:
		_click_at(hub["stage"], point)
		assert_true(card.visible, "a click at %s" % point)
	assert_signal_not_emitted(card, "closed")


func test_the_save_button_shows_the_information_card():
	GameData.current_save = PlayerSave.new_game("Saver", 0)
	GameData.current_slot = 3
	var hub: Dictionary = await _hub()
	var card: HubCard = hub["card"]
	var strings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Strings.STRINGS_FILE))
	_click(hub["hotbar"].get_node("%SaveButton"))
	assert_true(card.visible)
	assert_eq((card.get_node("%Title") as Label).text, strings["NAVTITLE"][0])
	assert_eq((card.get_node("%Title") as Label).text, "Information")
	assert_eq((card.get_node("%Body") as Label).text, strings["NAVTEXT"][0])


func test_the_save_button_leaves_the_zone_subtitle_alone():
	GameData.current_save = PlayerSave.new_game("Saver", 0)
	GameData.current_slot = 3
	var hub: Dictionary = await _hub()
	var hotbar: Control = hub["hotbar"]
	var before: String = hotbar.zone_subtitle.text
	_click(hotbar.get_node("%SaveButton"))
	assert_eq(hotbar.zone_subtitle.text, before)


func test_a_save_that_fails_shows_no_card():
	GameData.current_save = null
	var hub: Dictionary = await _hub()
	_click(hub["hotbar"].get_node("%SaveButton"))
	assert_false((hub["card"] as HubCard).visible)


# The tests above stack a hotbar and a card by hand. This one uses the real
# scene, so it fails when scenes/game.tscn loses the card or puts it under the
# Hotbar.
func test_the_game_scene_opens_the_card_from_save_and_the_card_covers_the_hotbar():
	GameData.current_save = PlayerSave.new_game("Saver", 0)
	GameData.current_slot = 3
	var stage: SubViewport = _stage()
	var game: Control = load("res://scenes/game.tscn").instantiate()
	stage.add_child(game)
	await wait_process_frames(2)
	var hotbar: Control = game.get_node("Hotbar")
	var card: HubCard = game.get_node_or_null("HubCard")
	assert_not_null(card, "scenes/game.tscn has the Info card")
	if card == null:
		return
	assert_false(card.visible)
	_click(hotbar.get_node("%SaveButton"))
	assert_true(card.visible, "Save shows the card in the game scene")
	var inventory: BaseButton = hotbar.get_node("%InventoryButton")
	watch_signals(inventory)
	_click(inventory)
	assert_signal_not_emitted(inventory, "pressed", "the card covers the hotbar")
	_click(card.get_node("CloseButton"))
	assert_false(card.visible)
