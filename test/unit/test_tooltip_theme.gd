extends GutTest
# TooltipTheme's backer colors against dev/converted_json/tooltip_look.json,
# which this test reads itself, so a value typed into the theme fails here.

var _look: Dictionary


func before_all() -> void:
	_look = JSON.parse_string(FileAccess.get_file_as_string("res://dev/converted_json/tooltip_look.json"))


func _rgba(channels: Array) -> Color:
	return Color8(int(channels[0]), int(channels[1]), int(channels[2]), int(channels[3]))


func _grey_stop() -> Array:
	var darkest: Array = _look["gloss_stops"][0]["color"]
	for stop: Dictionary in _look["gloss_stops"]:
		if int(stop["color"][0]) < int(darkest[0]):
			darkest = stop["color"]
	return darkest


func test_the_header_is_the_gradients_grey_stop() -> void:
	assert_eq(TooltipTheme.BG_HEADER, _rgba(_grey_stop()))


func test_the_cost_bar_is_the_grey_stop_with_the_go2_add_terms() -> void:
	var grey: Array = _grey_stop()
	var add: Array = _look["subheader_add"]["GO2"]
	var expected: Array = []
	for i in 3:
		expected.append(clampi(int(grey[i]) + int(add[i]), 0, 255))
	expected.append(grey[3])
	assert_eq(TooltipTheme.BG_COST, _rgba(expected))


func test_the_body_is_the_body_backers_fill() -> void:
	assert_eq(TooltipTheme.BG_BODY, _rgba(_look["body_fill"]))


func test_the_next_rank_bar_is_the_body_fill_through_fontbacker4s_transform() -> void:
	var fill: Array = _look["body_fill"]
	var transform: Dictionary = _look["next_rank"]
	var expected: Array = []
	for i in 4:
		expected.append(int(fill[i]) * int(transform["multiply"][i]) / 256 + int(transform["add"][i]))
	assert_eq(TooltipTheme.BG_NEXT_RANK, _rgba(expected))


func test_gloss_stops_apply_and_clamp_the_add_terms() -> void:
	var stops: Array = TooltipTheme.gloss_stops([86, 0, -164])
	var first: Array = _look["gloss_stops"][0]["color"]
	assert_eq(stops[0][1], _rgba([mini(int(first[0]) + 86, 255), int(first[1]), maxi(int(first[2]) - 164, 0), int(first[3])]))
	assert_eq(stops.size(), _look["gloss_stops"].size())
