# One member row's two frames. The original's member bar 3311 has `active`, with
# the name and five buttons, and `inactive`, with the text of MENU[52]. The scene
# tests cover which slot shows which.
extends GutTest

const StanceRowScene = preload("res://scenes/battle/stance_row.tscn")


func _row() -> StanceRow:
	var row: StanceRow = add_child_autofree(StanceRowScene.instantiate())
	row.setup("Veradux")
	return row


func test_a_row_starts_on_its_active_frame():
	var row: StanceRow = _row()
	assert_true(row.name_label.visible)
	assert_eq(row.buttons.filter(func(button): return button.visible).size(), 5, "five buttons")
	assert_false(row.inactive_label.visible)


func test_the_inactive_frame_shows_the_text_of_menu_52_and_nothing_else():
	var row: StanceRow = _row()
	row.show_inactive()
	assert_true(row.inactive_label.visible)
	assert_eq(row.inactive_label.text, Strings.menu(52))
	assert_eq(row.inactive_label.text, "< Team Member Inactive >")
	assert_false(row.name_label.visible, "the name goes")
	assert_eq(row.buttons.filter(func(button): return button.visible), [], "and the buttons")
	assert_true(row.panel.visible, "the panel stays")


func test_the_active_frame_comes_back():
	var row: StanceRow = _row()
	row.show_inactive()
	row.show_active()
	assert_true(row.name_label.visible)
	assert_eq(row.buttons.filter(func(button): return button.visible).size(), 5)
	assert_false(row.inactive_label.visible)


# The text sits where edit text 3310 does, read from member_rows.json, in the
# colour and size of the field.
func test_the_inactive_text_is_laid_out_from_the_record():
	var row: StanceRow = _row()
	var entry: Dictionary = StanceRow.member_rows()["inactive"]
	assert_almost_eq(row.inactive_label.position, Vector2(entry["rect"][0], entry["rect"][1]), Vector2(0.001, 0.001))
	assert_almost_eq(row.inactive_label.size.x, float(entry["rect"][2]), 0.001)
	assert_eq(row.inactive_label.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER)
	assert_eq(row.inactive_label.get_theme_color("font_color"), Color.html(entry["color"]))
	assert_eq(row.inactive_label.get_theme_font_size("font_size"), int(entry["font_size"]))
