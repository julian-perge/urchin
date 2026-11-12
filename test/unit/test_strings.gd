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
