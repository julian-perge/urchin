# The victory experience row's animation
# (DefineSprite_3142/frame_9/PlaceObject3_3002_*, onClipEvent(enterFrame)).
# Each test drives the row with step() and reads its counts from the same
# menu_math.json the row reads.
extends GutTest

const RowScene: PackedScene = preload("res://scenes/ui/menu/victory_exp_row.tscn")


func _math() -> Dictionary:
	return MenuMath.load_math()


func _fighter(experience: float, level: int, gained: float) -> BattleSettlement.FighterExperience:
	var fighter := BattleSettlement.FighterExperience.new()
	fighter.experience_before = experience
	fighter.level_before = level
	fighter.xp_gained = gained
	return fighter


func _row(fighter: BattleSettlement.FighterExperience, math: Dictionary = _math()) -> VictoryExpRow:
	var row: VictoryExpRow = RowScene.instantiate()
	add_child_autofree(row)
	row.setup("portraits/veradux.png", "Veradux", fighter, math)
	return row


func _full_width() -> float:
	return float(_math()["victory_rows"]["bar_width"])


func _frames() -> int:
	return int(_math()["victory_rows"]["frames"])


func test_after_every_frame_the_bar_shows_the_final_fraction() -> void:
	var row := _row(_fighter(20.0, 3, 45.0))
	for i in _frames():
		row.step()
	assert_almost_eq(row.bar.size.x, 0.65 * _full_width(), 0.001)
	assert_eq(row.percent_label.text, "65%")
	assert_true(row.is_finished())


func test_one_frame_short_of_the_end_the_bar_is_short_of_the_final_fraction() -> void:
	var row := _row(_fighter(20.0, 3, 45.0))
	for i in _frames() - 1:
		row.step()
	assert_lt(row.bar.size.x, 0.65 * _full_width() - 0.01)
	assert_false(row.is_finished())


func test_steps_past_the_end_change_nothing() -> void:
	var row := _row(_fighter(20.0, 3, 45.0))
	for i in _frames() + 5:
		row.step()
	assert_almost_eq(row.bar.size.x, 0.65 * _full_width(), 0.001)


func test_a_row_that_overflows_adds_one_level_shows_100_once_and_keeps_the_remainder() -> void:
	# 1.5 a frame from 81 reaches 99 and then 100.5, so no frame rounds to 100
	# before the one that overflows.
	var row := _row(_fighter(81.0, 4, 45.0))
	var hundreds: int = 0
	for i in _frames():
		row.step()
		if row.percent_label.text == "100%":
			hundreds += 1
	assert_eq(hundreds, 1, "the frame that crosses 100 shows 100%")
	assert_eq(row.level, 5)
	assert_true(row.leveled)
	assert_eq(row.level_label.text, Strings.menu(0) + "5")
	assert_eq(row.bar.texture.resource_path, VictoryExpRow.LEVEL_FILL.resource_path, "the bar keeps its level frame")
	assert_almost_eq(row.experience, 26.0, 0.001)
	assert_eq(row.percent_label.text, "26%")
	assert_almost_eq(row.bar.size.x, 0.26 * _full_width(), 0.001)


func test_a_row_that_does_not_overflow_keeps_the_normal_fill() -> void:
	var row := _row(_fighter(20.0, 3, 45.0))
	for i in _frames():
		row.step()
	assert_false(row.leveled)
	assert_eq(row.bar.texture.resource_path, VictoryExpRow.FILL.resource_path)


func test_a_fighter_at_the_level_cap_does_not_move() -> void:
	var cap: int = int(_math()["victory_rows"]["level_cap"])
	var row := _row(_fighter(40.0, cap, 45.0))
	var width_before: float = row.bar.size.x
	for i in _frames():
		row.step()
	assert_eq(row.bar.size.x, width_before)
	assert_almost_eq(row.experience, 40.0, 0.001)
	assert_eq(row.level, cap)


func test_a_row_ends_where_the_save_does() -> void:
	var save := PlayerSave.new_game("RowEndsLikeSave")
	save.level = 6
	save.experience = 70.0
	var row := _row(_fighter(save.experience, save.level, 95.0))
	Leveling.grant_experience(save, 95.0)
	for i in _frames():
		row.step()
	assert_eq(row.level, save.level)
	assert_almost_eq(row.experience, save.experience, 0.001)


# The row runs at the SWF's frame rate. Uneven frame times that add up to the
# whole animation end where the same number of step() calls does.
func test_uneven_frame_times_end_where_step_does() -> void:
	var stepped := _row(_fighter(80.0, 4, 45.0))
	for i in _frames():
		stepped.step()
	var timed := _row(_fighter(80.0, 4, 45.0))
	var duration: float = _frames() / float(_math()["victory_rows"]["frame_rate"])
	var deltas: Array[float] = [0.007, 0.05, 0.021, 0.1, 0.0333]
	var elapsed: float = 0.0
	var i: int = 0
	while elapsed < duration + 0.2:
		var delta: float = deltas[i % deltas.size()]
		timed.advance(delta)
		elapsed += delta
		i += 1
	assert_eq(timed.level, stepped.level)
	assert_almost_eq(timed.experience, stepped.experience, 0.001)
	assert_almost_eq(timed.bar.size.x, stepped.bar.size.x, 0.001)


func test_a_short_time_advances_no_frame() -> void:
	var row := _row(_fighter(20.0, 3, 45.0))
	var width_before: float = row.bar.size.x
	row.advance(0.5 / float(_math()["victory_rows"]["frame_rate"]))
	assert_eq(row.bar.size.x, width_before)


func test_setup_shows_the_values_from_before_the_win() -> void:
	var row := _row(_fighter(20.4, 3, 45.0))
	assert_eq(row.name_label.text, "Veradux")
	assert_eq(row.level_label.text, Strings.menu(0) + "3")
	assert_eq(row.percent_label.text, "20%")
	assert_almost_eq(row.bar.size.x, 0.204 * _full_width(), 0.001)


# The must-fail control: a copy of the extractor output with one more frame.
# The row then reads that count, so after the real count of steps it has not
# reached the final fraction, and the first test's check fails on it.
func test_control_a_changed_frame_count_fails_the_animation_check() -> void:
	var copy: Dictionary = _math().duplicate(true)
	copy["victory_rows"]["frames"] = _frames() + 1
	var row := _row(_fighter(20.0, 3, 45.0), copy)
	for i in _frames():
		row.step()
	assert_false(is_equal_approx(row.bar.size.x, 0.65 * _full_width()))
