# test_game_tooltip.gd
# NOTE: If running this test fails with "Identifier 'TooltipTheme' not declared
# in the current scope" after adding the tooltip_theme.gd file, the Godot
# global_script_class_cache.cfg is stale. Run:
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --import .
# from the project root to regenerate the class cache, then retry.
extends GutTest


func after_each():
	GameTooltip.hide_tooltip()


func _sections_fixture() -> Array:
	return [
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": "Title", "color": TooltipTheme.TEXT_TITLE}]},
		{"bg_color": TooltipTheme.BG_BODY, "lines": [
			{"text": "Line one", "color": TooltipTheme.TEXT_BODY},
			{"text": "Line two", "color": TooltipTheme.TEXT_STAT},
		]},
	]


func test_show_sections_builds_one_panel_per_section_with_right_colors_and_lines():
	var anchor: Control = add_child_autofree(Control.new())
	anchor.position = Vector2(100, 100)
	anchor.size = Vector2(30, 30)

	GameTooltip.show_sections(_sections_fixture(), anchor)

	assert_eq(GameTooltip._sections.get_child_count(), 2, "one PanelContainer per section")
	var header_panel: PanelContainer = GameTooltip._sections.get_child(0)
	var header_style: StyleBoxFlat = header_panel.get_theme_stylebox("panel")
	assert_eq(header_style.bg_color, TooltipTheme.BG_HEADER)
	var header_label: Label = header_panel.get_child(0).get_child(0)
	assert_eq(header_label.text, "Title")
	assert_eq(header_label.get_theme_color("font_color"), TooltipTheme.TEXT_TITLE)

	var body_panel: PanelContainer = GameTooltip._sections.get_child(1)
	var body_style: StyleBoxFlat = body_panel.get_theme_stylebox("panel")
	assert_eq(body_style.bg_color, TooltipTheme.BG_BODY)
	var body_lines: VBoxContainer = body_panel.get_child(0)
	assert_eq(body_lines.get_child_count(), 2)
	assert_eq(body_lines.get_child(0).text, "Line one")
	assert_eq(body_lines.get_child(1).get_theme_color("font_color"), TooltipTheme.TEXT_STAT)


func test_show_sections_clears_previous_sections_on_a_second_call():
	var anchor: Control = add_child_autofree(Control.new())
	GameTooltip.show_sections(_sections_fixture(), anchor)
	GameTooltip.show_sections(
		[{"bg_color": TooltipTheme.BG_BODY, "lines": [{"text": "Only", "color": TooltipTheme.TEXT_BODY}]}], anchor
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


func test_position_lands_beside_the_anchor_when_there_is_room():
	var anchor: Control = add_child_autofree(Control.new())
	anchor.position = Vector2(100, 100)
	anchor.size = Vector2(30, 30)
	GameTooltip.show_sections(_sections_fixture(), anchor)
	await wait_process_frames(1)
	assert_eq(
		GameTooltip._root.position,
		anchor.global_position + Vector2(anchor.size.x + GameTooltip.ANCHOR_GAP, 0.0)
	)


func test_position_flips_to_the_left_instead_of_covering_its_anchor():
	var anchor: Control = add_child_autofree(Control.new())
	# Far enough right that the tooltip cannot fit beside it, but with room to
	# spare on the left - the rightmost class-select card's situation.
	anchor.position = Vector2(600, 100)
	anchor.size = Vector2(180, 300)
	GameTooltip.show_sections(_sections_fixture(), anchor)
	await wait_process_frames(1)
	var tooltip_right: float = GameTooltip._root.position.x + GameTooltip._root.size.x
	assert_almost_eq(
		GameTooltip._root.position.x,
		anchor.global_position.x - GameTooltip._root.size.x - GameTooltip.ANCHOR_GAP,
		0.01,
		"sits just left of the anchor"
	)
	assert_lt(tooltip_right, anchor.global_position.x, "clears the anchor entirely")


func test_position_clamps_at_the_right_and_bottom_edges():
	var anchor: Control = add_child_autofree(Control.new())
	anchor.position = Vector2(790, 590)
	anchor.size = Vector2(30, 30)
	GameTooltip.show_sections(_sections_fixture(), anchor)
	await wait_process_frames(1)
	var viewport_size: Vector2 = GameTooltip.get_viewport().get_visible_rect().size
	assert_true(
		GameTooltip._root.position.x + GameTooltip._root.size.x <= viewport_size.x,
		"tooltip stays inside the viewport's right edge"
	)
	assert_true(
		GameTooltip._root.position.y + GameTooltip._root.size.y <= viewport_size.y,
		"tooltip stays inside the viewport's bottom edge"
	)


# A Flash text field keeps 2 px between its edges and its text, and each line
# stands in for one of KrinToolTipper's text fields, so every line pads its
# text by 2 px and the box is its layout's text width plus 4. The containers
# round that width up to a whole pixel, which is the width the text wraps at.
func test_lines_keep_the_flash_text_field_gutter():
	var anchor: Control = add_child_autofree(Control.new())
	GameTooltip.show_sections(_sections_fixture(), anchor, null, Color.WHITE, TooltipTheme.TEXT_WIDTH_ITEM)
	await wait_process_frames(2)
	for panel in GameTooltip._sections.get_children():
		for label in panel.get_child(0).get_children():
			var gutter: StyleBox = label.get_theme_stylebox("normal")
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				assert_eq(gutter.get_content_margin(side), 2.0, "%s has a 2 px gutter on side %d" % [label.text, side])
	assert_eq(GameTooltip._sections.size.x, ceilf(TooltipTheme.TEXT_WIDTH_ITEM + 4.0), "the box is the text width plus both gutters")
	var title: Label = GameTooltip._sections.get_child(0).get_child(0).get_child(0)
	assert_eq(title.size.x - 4.0, ceilf(TooltipTheme.TEXT_WIDTH_ITEM), "the text still wraps at the layout's width")


# KrinToolTipper starts each text field 2 px below the one above it
# (DefineSprite_2717/frame_13/DoAction.as:48 and frame_17/DoAction.as:38), so
# the lines sit 2 px apart whether or not they share a section.
func test_fields_stack_2_px_apart():
	var anchor: Control = add_child_autofree(Control.new())
	GameTooltip.show_sections(_sections_fixture(), anchor)
	await wait_process_frames(2)
	var title: Control = GameTooltip._sections.get_child(0)
	var body: Control = GameTooltip._sections.get_child(1)
	assert_eq(body.position.y - title.position.y - title.size.y, 2.0, "2 px between sections")
	assert_eq(body.get_child(0).position.y, 0.0, "a section adds nothing above its first line")
	var lines: Array = body.get_child(0).get_children()
	assert_eq(lines[1].position.y - lines[0].position.y - lines[0].size.y, 2.0, "2 px between the lines of a section")


func test_position_clamps_at_the_left_and_top_edges():
	var anchor: Control = add_child_autofree(Control.new())
	anchor.position = Vector2(-50, -50)
	anchor.size = Vector2(10, 10)
	GameTooltip.show_sections(_sections_fixture(), anchor)
	await wait_process_frames(1)
	assert_true(GameTooltip._root.position.x >= 0.0, "never positioned off the left edge")
	assert_true(GameTooltip._root.position.y >= 0.0, "never positioned off the top edge")
