# MenuMath (scripts/ui/menu/menu_math.gd) against numbers worked out by hand
# from DefineSprite_3142/frame_1/DoAction.as:103-153. The expected numbers do
# not come from menu_math.json, so a changed number in the file fails a test.
extends GutTest

const EPSILON: float = 0.0001


func _math() -> Dictionary:
	return MenuMath.load_math()


func _assert_heights(heights: Dictionary, bar: float, gbar: float, xbar: float) -> void:
	assert_almost_eq(heights["bar"], bar, EPSILON, "bar")
	assert_almost_eq(heights["gbar"], gbar, EPSILON, "gbar")
	assert_almost_eq(heights["xbar"], xbar, EPSILON, "xbar")


func test_a_value_below_the_average_gives_xbar_a_negative_height() -> void:
	_assert_heights(MenuMath.layer_heights(0.5, _math()), 4.462449, 5.1, -2.38)


func test_the_average_value_fills_thirty_percent_and_gives_no_xbar() -> void:
	_assert_heights(MenuMath.layer_heights(1.0, _math()), 20.399910, 10.2, 0.0)


func test_a_value_above_the_cap_stops_bar_and_gbar_at_save_height_but_not_xbar() -> void:
	_assert_heights(MenuMath.layer_heights(20.0, _math()), 68.0, 68.0, 90.44)


func test_no_allocation_gives_the_average_value() -> void:
	assert_almost_eq(MenuMath.x_for(0.0, 3, _math()), 1.0, EPSILON)


func test_an_allocation_adds_to_the_average_and_divides_by_it() -> void:
	# At level 2 the average is 100 + 15 * 2 = 130, so 65 gives 195 / 130.
	assert_almost_eq(MenuMath.x_for(65.0, 2, _math()), 1.5, EPSILON)


func test_the_added_average_is_rounded_up_but_the_divisor_is_not() -> void:
	# The file's average is always a whole number, so this copy changes it to
	# 100 + 0.5 * 1 = 100.5. The value is then 0 + 101, and x is 101 / 100.5.
	var math: Dictionary = _math().duplicate(true)
	math["element_bars"]["average"]["per_level"] = 0.5
	assert_almost_eq(MenuMath.x_for(0.0, 1, math), 101.0 / 100.5, EPSILON)


func test_each_defense_ratio_picks_its_tip() -> void:
	# The pairs are x, then the tip for 1 / x: 1 / 1 matches no rule, and each
	# smaller 1 / x passes one more threshold.
	var cases: Array[Array] = [[1.0, 1], [0.5, 0], [1.1, 2], [1.5, 3], [2.0, 4], [3.0, 5], [4.0, 6]]
	for case: Array in cases:
		assert_eq(MenuMath.defense_tip(case[0], _math()), case[1], "x %s" % case[0])
