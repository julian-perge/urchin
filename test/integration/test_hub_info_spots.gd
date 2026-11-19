# test_hub_info_spots.gd - the 20 info spots of zones 1 to 5 (#224): which zone
# holds which spot, that a press on a spot opens the Info card with the spot's
# own NAVTITLE and NAVTEXT, and that a spot is a hit area that draws nothing.
# Where each spot sits is checked by test_screen_rects.gd.
extends GutTest

const CardScene = preload("res://scenes/ui/hub_card.tscn")
const HotbarScene = preload("res://scenes/ui/hotbar.tscn")

const RECORD_PATH: String = "res://test/fixtures/screen_rects.json"
const ZONES: Array[int] = [1, 2, 3, 4, 5, 6, 7]
const SPOT_COUNT: int = 20


# A viewport of the Stage's size for a test that clicks. In the test runner's
# own viewport, GUT's panel covers part of the hotbar and takes the click.
func _stage() -> SubViewport:
	var stage := SubViewport.new()
	stage.size = Vector2i(800, 575)
	add_child_autofree(stage)
	return stage


func _button_at(viewport: Viewport, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)


func _press(control: Control) -> void:
	_button_at(control.get_viewport(), control.get_global_rect().get_center(), true)


# The zone with the hotbar and the card over it, as scenes/game.tscn stacks them.
func _hub(zone: int) -> Dictionary:
	var stage: SubViewport = _stage()
	var scene: Control = load(str(ZoneManager.ZONES[zone]["scene"])).instantiate()
	stage.add_child(scene)
	var hotbar: Control = HotbarScene.instantiate()
	stage.add_child(hotbar)
	var card: HubCard = CardScene.instantiate()
	stage.add_child(card)
	await wait_process_frames(2)
	return {"stage": stage, "scene": scene, "hotbar": hotbar, "card": card}


# The zone's info spots, by number.
func _spots(scene: Node) -> Dictionary:
	var found: Dictionary = {}
	for child: Node in scene.get_children():
		if child.name.begins_with("InfoSpot"):
			found[int(child.get("spot"))] = child
	return found


# The numbers of the spots that the rect record places in a zone's scene. The
# record reads them from the SWF: each is the n that the press script of the
# button at the spot's depth passes to krinNavHideUI (dev/tests/test_screen_rects.py).
func _recorded_numbers(zone: int) -> Array:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECORD_PATH))
	var scene: Dictionary = record["scenes"][str(ZoneManager.ZONES[zone]["scene"])]
	var numbers: Array = []
	for piece: String in scene["pieces"]:
		if piece.begins_with("InfoSpot"):
			numbers.append(int(piece.trim_prefix("InfoSpot")))
	numbers.sort()
	return numbers


func test_each_zone_holds_the_spots_the_record_places_there_by_number():
	var total: int = 0
	for zone: int in ZONES:
		var scene: Control = load(str(ZoneManager.ZONES[zone]["scene"])).instantiate()
		add_child_autofree(scene)
		var spots: Dictionary = _spots(scene)
		var numbers: Array = spots.keys()
		numbers.sort()
		assert_eq(numbers, _recorded_numbers(zone), "zone %d" % zone)
		for n: int in numbers:
			assert_eq(String(spots[n].name), "InfoSpot%d" % n, "zone %d" % zone)
		total += numbers.size()
		if zone > 5:
			assert_eq(numbers, [], "zone %d has no spot" % zone)
	assert_eq(total, SPOT_COUNT)


func test_a_press_on_each_spot_opens_the_card_with_its_own_title_and_text():
	var pressed: int = 0
	for zone: int in ZONES:
		var hub: Dictionary = await _hub(zone)
		var card: HubCard = hub["card"]
		var spots: Dictionary = _spots(hub["scene"])
		for n: int in spots:
			card.hide_card()
			_press(spots[n])
			pressed += 1
			assert_true(card.visible, "zone %d spot %d opens the card" % [zone, n])
			assert_eq((card.get_node("%Title") as Label).text, Strings.text("NAVTITLE", n), "spot %d title" % n)
			assert_eq((card.get_node("%Body") as Label).text, Strings.text("NAVTEXT", n), "spot %d text" % n)
		# A spot finds the first card in the group, so the next zone's hub
		# must not share the tree with this one's.
		(hub["stage"] as SubViewport).free()
	assert_eq(pressed, SPOT_COUNT)


func test_the_close_button_hides_a_card_that_a_spot_opened():
	var hub: Dictionary = await _hub(1)
	var card: HubCard = hub["card"]
	_press(_spots(hub["scene"])[4])
	assert_true(card.visible)
	var close: Control = card.get_node("CloseButton")
	_button_at(close.get_viewport(), close.get_global_rect().get_center(), true)
	assert_false(card.visible)


func test_a_spot_does_nothing_while_the_hub_is_inert():
	var hub: Dictionary = await _hub(1)
	var card: HubCard = hub["card"]
	hub["hotbar"].set_inert(true)
	_press(_spots(hub["scene"])[4])
	assert_false(card.visible, "an inert hub ignores the spot")
	hub["hotbar"].set_inert(false)
	_press(_spots(hub["scene"])[4])
	assert_true(card.visible, "the spot works again after")


# The buttons have only a hit state in the SWF, so a spot shows no art, no hover
# look and no tooltip, and the hand cursor is the only sign that it can be pressed.
func test_a_spot_draws_nothing_and_shows_no_tooltip():
	var hub: Dictionary = await _hub(1)
	var spots: Dictionary = _spots(hub["scene"])
	assert_eq(spots.size(), 4, "zone 1 holds four spots")
	for spot: TextureButton in spots.values():
		assert_null(spot.texture_normal, "%s draws no art" % spot.name)
		assert_null(spot.texture_hover, "%s has no hover look" % spot.name)
		assert_null(spot.texture_pressed, "%s has no pressed look" % spot.name)
		assert_eq(spot.tooltip_text, "", "%s has no native tooltip" % spot.name)
		spot.mouse_entered.emit()
		assert_false(GameTooltip.is_showing(), "%s shows no tooltip" % spot.name)
		spot.mouse_exited.emit()
		assert_eq(spot.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND, "%s" % spot.name)
