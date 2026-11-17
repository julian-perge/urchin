# test_strings.gd
extends GutTest


func test_system_reads_the_as_index():
	assert_eq(Strings.system(0), "Vitality")
	assert_eq(Strings.system(1), "Strength")


func test_text_reads_an_array_entry_by_name():
	assert_eq(Strings.text("SYSTEM", 6), "Defense")


func test_text_reads_a_scalar_by_name():
	assert_eq(Strings.text("SKILLNONE"), "None")


func test_text_returns_empty_for_an_unknown_name():
	assert_eq(Strings.text("NOT_A_NAME"), "")
	assert_push_error("NOT_A_NAME")


func test_has_is_true_for_an_array_entry():
	assert_true(Strings.has("SYSTEM", 6))


# NAVTITLE2 has the six entries 0 to 5.
func test_has_is_false_past_the_end_of_an_array():
	assert_true(Strings.has("NAVTITLE2", 5))
	assert_false(Strings.has("NAVTITLE2", 6))
	assert_false(Strings.has("SYSTEM", -1))


func test_has_is_false_for_an_unknown_name_and_for_a_scalar():
	assert_false(Strings.has("NOT_A_NAME", 0))
	assert_false(Strings.has("SKILLNONE", 0))
