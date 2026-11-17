# The top status bar's entries. Each case reads the widths, colors and rects from
# top_bar.json, which extract_top_bar writes, so a test never types a SWF value.
extends GutTest

const StatusBarScene = preload("res://scenes/battle/status_bar.tscn")
const TopStatusBarScene = preload("res://scenes/battle/top_status_bar.tscn")


func _bar(slot: int) -> StatusBar:
	var bar: StatusBar = StatusBarScene.instantiate()
	bar.slot = slot
	add_child_autofree(bar)
	return bar


func _state(life: float, life_max: float, focus: float = 0.0, focus_max: float = 0.0) -> UnitSnapshot:
	var state := UnitSnapshot.new()
	state.life = life
	state.life_max = life_max
	state.focus = focus
	state.focus_max = focus_max
	return state


# The width a fill has at full, which is the art's width times the scale that
# the bar clip is placed with.
func _full_width(which: String) -> float:
	var bar: Dictionary = StatusBar.record()["bars"][which]
	return float(StatusBar.record()["art"][bar["art"]]["rect"][2]) * float(bar["scale_x"])


func _life_color(frame: int) -> Color:
	return Color.html(StatusBar.record()["life_colors"][frame])


func test_a_bar_at_rest_shows_both_fills_at_full_width() -> void:
	var bar: StatusBar = _bar(1)
	assert_almost_eq(bar.life_fill.size.x, _full_width("life"), 0.001)
	assert_almost_eq(bar.focus_fill.size.x, _full_width("focus"), 0.001)


func test_full_life_fills_the_bar_in_the_last_color_frame_and_shows_the_numbers() -> void:
	var bar: StatusBar = _bar(1)
	bar.show_status(_state(250.0, 250.0, 30.0, 50.0))
	assert_almost_eq(bar.life_fill.size.x, _full_width("life"), 0.001, "the life fill")
	assert_eq(bar.life_fill.modulate, _life_color(100), "in the color of frame 101")
	assert_eq(bar.life_back.modulate, _life_color(100), "and so is the fill behind it")
	assert_almost_eq(bar.focus_fill.size.x, _full_width("focus") * 0.6, 0.001, "the focus fill is 30 of 50")
	assert_eq([bar.life_now_label.text, bar.life_max_label.text], ["250", "250"])
	assert_eq([bar.focus_now_label.text, bar.focus_max_label.text], ["30", "50"])


func test_half_life_gives_half_the_width_and_the_color_of_frame_51() -> void:
	var bar: StatusBar = _bar(1)
	bar.show_status(_state(125.0, 250.0))
	assert_almost_eq(bar.life_fill.size.x, _full_width("life") * 0.5, 0.001)
	assert_eq(bar.life_fill.modulate, _life_color(50))


func test_a_share_picks_the_color_frame_of_its_rounded_percent() -> void:
	var bar: StatusBar = _bar(1)
	bar.show_status(_state(1.0, 3.0))
	assert_eq(bar.life_fill.modulate, _life_color(33), "33.3 percent is frame 34")
	bar.show_status(_state(2.0, 3.0))
	assert_eq(bar.life_fill.modulate, _life_color(67), "66.7 percent is frame 68")


func test_zero_life_empties_the_fill() -> void:
	var bar: StatusBar = _bar(1)
	bar.show_status(_state(0.0, 250.0))
	assert_eq(bar.life_fill.size.x, 0.0)
	assert_eq(bar.life_fill.modulate, _life_color(0), "in the color of frame 1")
	assert_eq(bar.life_now_label.text, "0")


func test_a_bar_with_no_max_shows_an_empty_fill() -> void:
	var bar: StatusBar = _bar(1)
	bar.show_status(_state(0.0, 0.0))
	assert_eq(bar.life_fill.size.x, 0.0)
	assert_eq(bar.focus_fill.size.x, 0.0)


func test_a_right_hand_bar_mirrors_inner2_and_takes_the_second_frame_of_inner() -> void:
	var record: Dictionary = StatusBar.record()
	for slot in [1, 3, 5]:
		var left: StatusBar = _bar(slot)
		assert_eq(left.inner2.scale.x, 1.0, "slot %d keeps inner2 as it is" % slot)
		assert_almost_eq(left.name_label.position.x, float(record["inner"]["frames"]["first"]["fields"].filter(func(f): return f["variable"] == "playerName")[0]["rect"][0]), 0.001, "slot %d lays its text out from the first frame" % slot)
	for slot in [2, 4, 6]:
		var right: StatusBar = _bar(slot)
		assert_eq(right.inner2.scale.x, -1.0, "slot %d mirrors inner2" % slot)
		assert_almost_eq(right.name_label.position.x, float(record["inner"]["frames"]["second"]["fields"].filter(func(f): return f["variable"] == "playerName")[0]["rect"][0]), 0.001, "slot %d lays its text out from the second frame" % slot)


func test_a_bar_sits_where_the_battle_frame_places_its_slot() -> void:
	var placements: Dictionary = StatusBar.record()["placements"]
	for slot in range(1, 7):
		var bar: StatusBar = _bar(slot)
		var placed: Dictionary = placements["p%dBAR" % slot]
		assert_eq(bar.position, Vector2(placed["x"], placed["y"]), "slot %d" % slot)
		assert_eq(bar.scale, Vector2(placed["scale"][0], placed["scale"][1]), "slot %d" % slot)


func test_the_death_clear_takes_the_name_and_the_numbers_away_and_leaves_the_fills() -> void:
	var bar: StatusBar = _bar(1)
	bar.setup("Veradux")
	bar.show_status(_state(0.0, 250.0))
	assert_true(bar.name_label.is_visible_in_tree())
	bar.clear_for_death()
	assert_false(bar.name_label.is_visible_in_tree(), "the name goes")
	assert_false(bar.life_now_label.is_visible_in_tree(), "and the numbers")
	assert_true(bar.life_back.is_visible_in_tree(), "the bars stay")
	bar.show_status(_state(0.0, 250.0))
	assert_false(bar.name_label.is_visible_in_tree(), "a later redraw leaves them cleared")


func _unit(active: bool) -> CombatUnit:
	var unit := CombatUnit.new()
	unit.active = active
	return unit


# The original hides the bar of a slot whose unit is not active
# (frame_217/PlaceObject2_3389_480 onClipEvent(load)), and the other bars stay
# where they are.
func test_a_slot_with_no_active_unit_has_its_bar_hidden_and_the_others_do_not_move() -> void:
	var top: TopStatusBar = add_child_autofree(TopStatusBarScene.instantiate())
	var before: Dictionary = {}
	for slot in range(1, 7):
		before[slot] = top.bar_for_slot(slot).position
	top.show_active({1: _unit(true), 2: _unit(true), 3: _unit(false), 5: _unit(true)})
	for slot in [1, 2, 5]:
		assert_true(top.bar_for_slot(slot).visible, "slot %d fights" % slot)
	for slot in [3, 4, 6]:
		assert_false(top.bar_for_slot(slot).visible, "slot %d has no active unit" % slot)
	for slot in range(1, 7):
		assert_eq(top.bar_for_slot(slot).position, before[slot], "slot %d did not move" % slot)
