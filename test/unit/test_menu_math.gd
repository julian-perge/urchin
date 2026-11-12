# MenuMath (scripts/ui/menu/menu_math.gd) against heights worked out by hand
# from DefineSprite_3142/frame_1/DoAction.as:108-125. The expected numbers do
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


func test_a_changed_coefficient_changes_the_heights() -> void:
	var changed: Dictionary = _math().duplicate(true)
	changed["element_bars"]["bar_quartic"][4] = 0.95
	var heights: Dictionary = MenuMath.layer_heights(1.0, changed)
	assert_true(absf(heights["bar"] - 20.399910) > 1.0, "the test sees the file's numbers")
