# ShellPanel (scripts/ui/window/shell_panel.gd). test_screen_rects.gd checks
# each fill, border and shadow against the SWF through
# test/fixtures/screen_rects/shell_panel_fills.tscn. These tests check what a
# host sets: the fill, the border width and the content margins.
extends GutTest

const PANEL: PackedScene = preload("res://scenes/ui/window/shell_panel.tscn")


func _panel() -> ShellPanel:
	var panel: ShellPanel = PANEL.instantiate()
	add_child_autofree(panel)
	return panel


func _style(panel: ShellPanel) -> StyleBoxFlat:
	return panel.get_theme_stylebox("panel") as StyleBoxFlat


func test_the_default_panel_follows_the_recipe() -> void:
	var panel: ShellPanel = _panel()
	var fill_rect: Rect2 = Rect2(panel.position, panel.size).grow(-0.5)
	assert_eq(PanelRecipe.problems(panel, fill_rect, Vector2.ONE), [] as Array[String])
	assert_eq(_style(panel).border_color, Color.BLACK)


func test_each_fill_sets_a_different_colour() -> void:
	var panel: ShellPanel = _panel()
	var colours: Array[Color] = []
	for fill: ShellPanel.Fill in [ShellPanel.Fill.TALL, ShellPanel.Fill.BAR, ShellPanel.Fill.CENTRE]:
		panel.fill = fill
		colours.append(_style(panel).bg_color)
	assert_ne(colours[0], colours[1])
	assert_ne(colours[1], colours[2])
	assert_ne(colours[0], colours[2])


func test_border_sets_every_side() -> void:
	var panel: ShellPanel = _panel()
	panel.border = 2
	for side: Side in PanelRecipe.SIDES:
		assert_eq(_style(panel).get_border_width(side), 2)


func test_content_margins_are_left_top_right_bottom() -> void:
	var panel: ShellPanel = _panel()
	panel.content_margins = Vector4(1.5, 2.5, 3.5, 4.5)
	var style: StyleBoxFlat = _style(panel)
	assert_eq(style.content_margin_left, 1.5)
	assert_eq(style.content_margin_top, 2.5)
	assert_eq(style.content_margin_right, 3.5)
	assert_eq(style.content_margin_bottom, 4.5)


# Two Panels of one scene must not share a StyleBoxFlat, or a host that sets
# one Panel's fill would change the other's.
func test_two_panels_do_not_share_a_style() -> void:
	var first: ShellPanel = _panel()
	var second: ShellPanel = _panel()
	first.fill = ShellPanel.Fill.CENTRE
	second.fill = ShellPanel.Fill.BAR
	assert_ne(_style(first).bg_color, _style(second).bg_color)
