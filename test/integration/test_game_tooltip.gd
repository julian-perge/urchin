# test_game_tooltip.gd
extends GutTest


func after_each():
	GameTooltip.hide_tooltip()


func _get_tooltip_theme() -> Script:
	return load("res://scripts/ui/tooltip_theme.gd")


func _sections_fixture() -> Array:
	var theme: Script = _get_tooltip_theme()
	return [
		{"bg_color": theme.BG_HEADER, "lines": [{"text": "Title", "color": theme.TEXT_TITLE}]},
		{"bg_color": theme.BG_BODY, "lines": [
			{"text": "Line one", "color": theme.TEXT_BODY},
			{"text": "Line two", "color": theme.TEXT_STAT},
		]},
	]


func test_show_sections_builds_one_panel_per_section_with_right_colors_and_lines():
	var theme: Script = _get_tooltip_theme()
	var anchor: Control = add_child_autofree(Control.new())
	anchor.position = Vector2(100, 100)
	anchor.size = Vector2(30, 30)

	GameTooltip.show_sections(_sections_fixture(), anchor)

	assert_eq(GameTooltip._sections.get_child_count(), 2, "one PanelContainer per section")
	var header_panel: PanelContainer = GameTooltip._sections.get_child(0)
	var header_style: StyleBoxFlat = header_panel.get_theme_stylebox("panel")
	assert_eq(header_style.bg_color, theme.BG_HEADER)
	var header_label: Label = header_panel.get_child(0).get_child(0)
	assert_eq(header_label.text, "Title")
	assert_eq(header_label.get_theme_color("font_color"), theme.TEXT_TITLE)

	var body_panel: PanelContainer = GameTooltip._sections.get_child(1)
	var body_style: StyleBoxFlat = body_panel.get_theme_stylebox("panel")
	assert_eq(body_style.bg_color, theme.BG_BODY)
	var body_lines: VBoxContainer = body_panel.get_child(0)
	assert_eq(body_lines.get_child_count(), 2)
	assert_eq(body_lines.get_child(0).text, "Line one")
	assert_eq(body_lines.get_child(1).get_theme_color("font_color"), theme.TEXT_STAT)


func test_show_sections_clears_previous_sections_on_a_second_call():
	var theme: Script = _get_tooltip_theme()
	var anchor: Control = add_child_autofree(Control.new())
	GameTooltip.show_sections(_sections_fixture(), anchor)
	GameTooltip.show_sections(
		[{"bg_color": theme.BG_BODY, "lines": [{"text": "Only", "color": theme.TEXT_BODY}]}], anchor
	)
	assert_eq(GameTooltip._sections.get_child_count(), 1, "old sections cleared, not accumulated")


func test_icon_shows_only_when_provided():
	var anchor: Control = add_child_autofree(Control.new())
	var texture: Texture2D = load("res://assets/ui/abilities/Leading_Strike.png")

	GameTooltip.show_sections(_sections_fixture(), anchor, texture, Color.RED)
	assert_true(GameTooltip._icon_backing.visible, "icon shown when provided")
	assert_eq(GameTooltip._icon.texture, texture)
	assert_eq(GameTooltip._icon_backing.color, Color.RED)

	GameTooltip.show_sections(_sections_fixture(), anchor)
	assert_false(GameTooltip._icon_backing.visible, "icon hidden when omitted")


func test_show_sections_makes_the_tooltip_visible_and_hide_tooltip_hides_it():
	var anchor: Control = add_child_autofree(Control.new())
	GameTooltip.show_sections(_sections_fixture(), anchor)
	assert_true(GameTooltip._root.visible)
	GameTooltip.hide_tooltip()
	assert_false(GameTooltip._root.visible)


func test_position_clamps_at_the_right_and_bottom_edges():
	var anchor: Control = add_child_autofree(Control.new())
	anchor.position = Vector2(790, 590)
	anchor.size = Vector2(30, 30)
	GameTooltip.show_sections(_sections_fixture(), anchor)
	var viewport_size: Vector2 = GameTooltip.get_viewport().get_visible_rect().size
	assert_true(
		GameTooltip._root.position.x + GameTooltip._root.size.x <= viewport_size.x,
		"tooltip stays inside the viewport's right edge"
	)
	assert_true(
		GameTooltip._root.position.y + GameTooltip._root.size.y <= viewport_size.y,
		"tooltip stays inside the viewport's bottom edge"
	)


func test_position_clamps_at_the_left_and_top_edges():
	var anchor: Control = add_child_autofree(Control.new())
	anchor.position = Vector2(-50, -50)
	anchor.size = Vector2(10, 10)
	GameTooltip.show_sections(_sections_fixture(), anchor)
	assert_true(GameTooltip._root.position.x >= 0.0, "never positioned off the left edge")
	assert_true(GameTooltip._root.position.y >= 0.0, "never positioned off the top edge")
