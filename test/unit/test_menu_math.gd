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


# Each threshold of the defense-tip rules is pinned from the ActionScript
# (DefineSprite_3142/frame_1/DoAction.as:132-153). For every threshold there is
# a ratio just below it and one just above, passed as x = 1 / ratio, so moving
# a threshold in menu_math.json moves one of the two sides past the other and
# this test fails.
func test_a_ratio_on_either_side_of_each_threshold_picks_the_right_tip() -> void:
	# Pairs are the ratio (1 / x) and the tip it should pick. The thresholds
	# are 1, 0.81, 0.61, 0.41 and 0.31 in the ActionScript.
	var cases: Array[Array] = [
		# Around 1: above it picks tip 0, below it picks tip 2, at 1 it is the default 1.
		[1.02, 0], [0.98, 2],
		# Around 0.81: at or above it stays tip 2, below it is tip 3.
		[0.82, 2], [0.80, 3],
		# Around 0.61.
		[0.62, 3], [0.60, 4],
		# Around 0.41.
		[0.42, 4], [0.40, 5],
		# Around 0.31.
		[0.32, 5], [0.30, 6],
	]
	for case: Array in cases:
		assert_eq(
			MenuMath.defense_tip(1.0 / case[0], _math()),
			case[1],
			"ratio %s" % case[0],
		)


# At a "<" or ">" threshold the boundary itself belongs to the side the rule
# does not select, because the rule is exclusive. Sampling exactly on each
# threshold pins "<" against "<=" (and ">" against ">="): a rule flipped to an
# inclusive comparison would claim the boundary point and change the tip here.
# The thresholds are read from the extractor output, because they are not the
# round decimals the ActionScript types (0.61 is stored as 0.6100...1).
func test_a_ratio_exactly_on_a_threshold_stays_on_the_exclusive_side() -> void:
	var rules: Array = _math()["element_bars"]["defense_tips"]["rules"]
	# For each rule's tip, the tip that a ratio exactly on its threshold must
	# keep, under the ActionScript's exclusive comparisons. Tip 0's rule (">" 1)
	# and tip 2's rule ("<" 1) share the threshold 1, and both leave 1.0 on the
	# default tip 1. Each later "<" rule leaves its boundary on the tip above.
	var expected: Dictionary = {0: 1, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5}
	for rule: Dictionary in rules:
		var threshold: float = rule["threshold"]
		assert_eq(
			MenuMath.defense_tip(1.0 / threshold, _math()),
			expected[int(rule["tip"])],
			"ratio exactly the threshold of tip %s" % rule["tip"],
		)
