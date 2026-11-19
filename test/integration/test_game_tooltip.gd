# test_game_tooltip.gd
# NOTE: If running this test fails with "Identifier 'TooltipTheme' not declared
# in the current scope" after adding the tooltip_theme.gd file, the Godot
# global_script_class_cache.cfg is stale. Run:
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --import .
# from the project root to regenerate the class cache, then retry.
extends GutTest


var _default_mouse_source: Callable


func before_all():
	_default_mouse_source = GameTooltip.mouse_source


func after_each():
	GameTooltip.hide_tooltip()
	GameTooltip.mouse_source = _default_mouse_source


func _put_mouse_at(point: Vector2) -> void:
	GameTooltip.mouse_source = func() -> Vector2: return point


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
	assert_eq(_gloss_colors(header_panel), _expected_gloss([0, 0, 0]), "the title draws the untinted 2715 gradient")
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


# A Flash text field keeps 2 px between its edges and its text, and each line
# stands in for one of KrinToolTipper's text fields, so every line pads its
# text by 2 px and the box is its layout's text width plus 4.
func test_lines_keep_the_flash_text_field_gutter():
	var anchor: Control = add_child_autofree(Control.new())
	GameTooltip.show_sections(_sections_fixture(), anchor, null, Color.WHITE, TooltipTheme.TEXT_WIDTH_ITEM)
	await wait_process_frames(2)
	for panel in GameTooltip._sections.get_children():
		for label in panel.get_child(0).get_children():
			var gutter: StyleBox = label.get_theme_stylebox("normal")
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				assert_eq(gutter.get_content_margin(side), 2.0, "%s has a 2 px gutter on side %d" % [label.text, side])
	assert_eq(GameTooltip._sections.size.x, TooltipTheme.TEXT_WIDTH_ITEM + 4.0, "the box is the text width plus both gutters")
	var title: Label = GameTooltip._sections.get_child(0).get_child(0).get_child(0)
	assert_eq(title.size.x - 4.0, TooltipTheme.TEXT_WIDTH_ITEM, "the text still wraps at the layout's width")


# KrinToolTipper starts each text field 2 px below the one above it
# (DefineSprite_2717/frame_13/DoAction.as:48 and
# DefineSprite_2717/frame_17/DoAction.as:38), so the lines sit 2 px apart
# whether or not they share a section.
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

var _look: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://dev/converted_json/tooltip_look.json"))


# -> the gradient stops of tooltip_look.json with add applied and clamped, read
# by this test itself so a value typed into the port fails it.
func _expected_gloss(add: Array) -> PackedColorArray:
	var colors: PackedColorArray = PackedColorArray()
	for stop: Dictionary in _look["gloss_stops"]:
		var c: Array = stop["color"]
		colors.append(Color8(
			clampi(int(c[0]) + int(add[0]), 0, 255),
			clampi(int(c[1]) + int(add[1]), 0, 255),
			clampi(int(c[2]) + int(add[2]), 0, 255),
			int(c[3])
		))
	return colors


func _gloss_colors(panel: Control) -> PackedColorArray:
	var gloss: TextureRect = panel.get_node_or_null("Gloss")
	if gloss == null:
		return PackedColorArray()
	return (gloss.texture as GradientTexture2D).gradient.colors


func _rare_item() -> GameItem:
	for item: GameItem in ItemManagerAuto.items_by_id.values():
		if item.rarity == GameItem.Rarity.RARE and item.item_type >= GameItem.ItemType.HEAD:
			return item
	return null


func test_a_rare_items_title_bar_carries_the_rare_add_terms():
	var slot: ItemSlot = add_child_autofree(preload("res://scenes/ui/item_slot.tscn").instantiate())
	var item: GameItem = _rare_item()
	assert_not_null(item, "items.json holds a Rare item")
	slot.set_item(item)
	slot.mouse_entered.emit()
	var title: Control = GameTooltip._sections.get_child(0)
	assert_eq(_gloss_colors(title), _expected_gloss(_look["rarity_add"]["Rare"]))
	var level_line: Control = GameTooltip._sections.get_child(1)
	assert_eq(_gloss_colors(level_line), _expected_gloss([0, 0, 0]), "only the title takes the rarity")


# The original keeps the last item's rarity for a tooltip whose caller sets
# none, because its frame 1 resets colorChage. ADR 0005 fixes that.
func test_a_tooltip_with_no_rarity_after_a_rare_item_is_untinted():
	var slot: ItemSlot = add_child_autofree(preload("res://scenes/ui/item_slot.tscn").instantiate())
	slot.set_item(_rare_item())
	slot.mouse_entered.emit()
	var anchor: Control = add_child_autofree(Control.new())
	GameTooltip.show_sections(_sections_fixture(), anchor)
	assert_eq(_gloss_colors(GameTooltip._sections.get_child(0)), _expected_gloss([0, 0, 0]))


func test_the_cost_bar_draws_the_gradient_with_the_go2_add_terms():
	var anchor: Control = add_child_autofree(Control.new())
	GameTooltip.show_sections([
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": "Title", "color": TooltipTheme.TEXT_TITLE}]},
		{"bg_color": TooltipTheme.BG_COST, "lines": [{"text": "Cost", "color": TooltipTheme.TEXT_SUBHEADER}]},
	], anchor)
	assert_eq(_gloss_colors(GameTooltip._sections.get_child(1)), _expected_gloss(_look["subheader_add"]["GO2"]))


func test_a_flat_section_has_no_gradient():
	var anchor: Control = add_child_autofree(Control.new())
	GameTooltip.show_sections(_sections_fixture(), anchor)
	assert_null(GameTooltip._sections.get_child(1).get_node_or_null("Gloss"))


func _assert_every_section_has_a_black_1_px_border() -> void:
	assert_gt(GameTooltip._sections.get_child_count(), 0)
	for panel: Control in GameTooltip._sections.get_children():
		var border: Panel = panel.get_node_or_null("Border")
		assert_not_null(border, "%s has a border" % panel.name)
		if border == null:
			continue
		var style: StyleBoxFlat = border.get_theme_stylebox("panel")
		assert_false(style.draw_center)
		assert_eq(style.border_color, Color.BLACK)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			assert_eq(style.get_border_width(side), 1)


func test_every_section_of_an_item_tooltip_has_its_border():
	var slot: ItemSlot = add_child_autofree(preload("res://scenes/ui/item_slot.tscn").instantiate())
	slot.set_item(_rare_item())
	slot.mouse_entered.emit()
	_assert_every_section_has_a_black_1_px_border()


func test_every_section_of_an_ability_tooltip_has_its_border():
	var anchor: Control = add_child_autofree(Control.new())
	GameTooltip.show_sections([
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": "Title", "color": TooltipTheme.TEXT_TITLE}]},
		{"bg_color": TooltipTheme.BG_COST, "lines": [{"text": "Cost", "color": TooltipTheme.TEXT_SUBHEADER}]},
		{"bg_color": TooltipTheme.BG_BODY, "lines": [{"text": "Body", "color": TooltipTheme.TEXT_BODY}]},
		{"bg_color": TooltipTheme.BG_NEXT_RANK, "lines": [{"text": "Next", "color": TooltipTheme.TEXT_NEXT_RANK}]},
	], anchor, null, Color.WHITE, TooltipTheme.TEXT_WIDTH_ABILITY)
	assert_eq(GameTooltip._sections.get_child_count(), 4)
	_assert_every_section_has_a_black_1_px_border()


# -> where the sections' left edge and the title's top land for a mouse at
# point, after two frames so the containers have sorted the new Labels.
func _placed_at(point: Vector2) -> Vector2:
	_put_mouse_at(point)
	await wait_process_frames(2)
	return Vector2(GameTooltip._sections.global_position.x, GameTooltip._root.position.y)


func test_the_tooltip_moves_with_the_mouse():
	var anchor: Control = add_child_autofree(Control.new())
	var layout: Dictionary = _look["layouts"]["GO"]
	_put_mouse_at(Vector2(100, 100))
	GameTooltip.show_sections(_sections_fixture(), anchor)
	var first: Vector2 = await _placed_at(Vector2(100, 100))
	assert_eq(first, Vector2(100 + float(layout["near_x"]), 100))
	var second: Vector2 = await _placed_at(Vector2(220, 160))
	assert_eq(second, Vector2(220 + float(layout["near_x"]), 160), "the tooltip follows a moved mouse")


func test_the_fields_flip_to_the_mouses_left_at_the_limit():
	var anchor: Control = add_child_autofree(Control.new())
	var layout: Dictionary = _look["layouts"]["GO4"]
	var x: float = float(layout["mouse_x_limit"])
	_put_mouse_at(Vector2(x, 100))
	GameTooltip.show_sections(_sections_fixture(), anchor, null, Color.WHITE, TooltipTheme.TEXT_WIDTH_ITEM)
	var placed: Vector2 = await _placed_at(Vector2(x, 100))
	assert_eq(placed.x, x + float(layout["far_x"]))
	var left_of_limit: Vector2 = await _placed_at(Vector2(x - 1, 100))
	assert_eq(left_of_limit.x, x - 1 + float(layout["near_x"]))


func test_the_plain_layout_moves_up_low_on_the_stage_and_the_item_layout_does_not():
	var anchor: Control = add_child_autofree(Control.new())
	var plain: Dictionary = _look["layouts"]["GO"]
	var y: float = float(plain["mouse_y_limit"]) + 1
	_put_mouse_at(Vector2(100, y))
	GameTooltip.show_sections(_sections_fixture(), anchor)
	assert_eq((await _placed_at(Vector2(100, y))).y, y + float(plain["low_shift_y"]))
	assert_false(_look["layouts"]["GO4"].has("low_shift_y"), "the item layout has no move up")
	GameTooltip.show_sections(_sections_fixture(), anchor, null, Color.WHITE, TooltipTheme.TEXT_WIDTH_ITEM)
	assert_eq((await _placed_at(Vector2(100, 400))).y, 400.0)


# ADR 0012: a tooltip that would run past the Stage's bottom edge slides up.
func test_a_tooltip_that_does_not_fit_stays_on_the_stage():
	var anchor: Control = add_child_autofree(Control.new())
	_put_mouse_at(Vector2(100, 560))
	GameTooltip.show_sections(_sections_fixture(), anchor, null, Color.WHITE, TooltipTheme.TEXT_WIDTH_ITEM)
	await _placed_at(Vector2(100, 560))
	var stage: Vector2 = GameTooltip.get_viewport().get_visible_rect().size
	assert_almost_eq(GameTooltip._root.position.y + GameTooltip._root.size.y, stage.y, 0.01)
	await _placed_at(Vector2(-40, -40))
	assert_eq(GameTooltip._root.position, Vector2.ZERO, "and stays inside the top left corner")


func test_the_tooltip_hides_when_its_anchor_leaves_the_tree():
	var anchor: Control = Control.new()
	add_child(anchor)
	GameTooltip.show_sections(_sections_fixture(), anchor)
	anchor.free()
	await wait_process_frames(1)
	assert_false(GameTooltip._root.visible)


func test_an_ability_icons_tooltip_shows_the_title_alone_first():
	var anchor: Control = add_child_autofree(Control.new())
	var sections: Array = _sections_fixture()
	GameTooltip.show_sections(sections, anchor, null, Color.WHITE, TooltipTheme.TEXT_WIDTH_ABILITY, "", true)
	var delay: float = float(_look["detail_delay_frames"]) / float(_look["frame_rate"])
	assert_true(GameTooltip._sections.get_child(0).visible, "the title shows at once")
	assert_false(GameTooltip._sections.get_child(1).visible, "the body waits")
	GameTooltip._process(delay * 0.9)
	assert_false(GameTooltip._sections.get_child(1).visible, "still waiting just before the delay ends")
	GameTooltip._process(delay * 0.2)
	assert_true(GameTooltip._sections.get_child(1).visible, "the body shows after the delay")


func test_a_tooltip_without_the_delay_shows_every_section_at_once():
	var anchor: Control = add_child_autofree(Control.new())
	GameTooltip.show_sections(_sections_fixture(), anchor)
	assert_true(GameTooltip._sections.get_child(1).visible)
