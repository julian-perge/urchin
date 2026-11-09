# The original draws its menu text in DefineFont3 65, the device font _sans
# with fontFlagsBold set, and 190 of the 223 DefineEditText tags in
# sonny-2-2900.swf use it. Most of the rest use DefineFont3 295, the same
# _sans without the bold flag. The port draws _sans in TeX Gyre Heros: font 65
# text in its bold face, which the project theme sets once for every Control,
# and font 295 text in its regular face through the RegularLabel type
# variation. Two fonts the SWF embeds, Rockwell Bold (2738) and the pixel font
# "copy 10_65" (3307), come from the TTFs ffdec extracted. Each case pairs a
# port node with the edit text it stands in for and that edit text's font id.
extends GutTest

const BOLD_FONT_ID: int = 65
const HEROS_BOLD_PATH: String = "res://assets/fonts/texgyreheros-bold.otf"
const HEROS_REGULAR_PATH: String = "res://assets/fonts/texgyreheros-regular.otf"
const HEROS_BOLD_ITALIC_PATH: String = "res://assets/fonts/texgyreheros-bolditalic.otf"
const ROCKWELL_PATH: String = "res://assets/fonts/2738_Rockwell.ttf"
const PIXEL_FONT_PATH: String = "res://assets/fonts/3307_copy 10_65.ttf"
const EMBEDDED_FONTS: Dictionary = {2738: ROCKWELL_PATH, 3307: PIXEL_FONT_PATH}
const MainMenuScene = preload("res://scenes/main_menu.tscn")


func before_each():
	GameData.current_save = PlayerSave.new_game("FontTest", 0)


func after_each():
	GameData.current_save = null
	GameTooltip.hide_tooltip()


func _assert_font(control: Control, font_id: int, what: String) -> void:
	var font: Font = control.get_theme_font("font")
	if EMBEDDED_FONTS.has(font_id):
		assert_eq(font.resource_path, EMBEDDED_FONTS[font_id], "%s uses the font the SWF embeds as font %d" % [what, font_id])
		return
	if font_id == BOLD_FONT_ID:
		assert_eq(font.resource_path, HEROS_BOLD_PATH, "%s draws in the bold face like font 65" % what)
	else:
		assert_eq(font.resource_path, HEROS_REGULAR_PATH, "%s draws in the regular face like font %d" % [what, font_id])


# Each case maps a node path to [edit text id, font id].
func _assert_fonts(root: Node, cases: Dictionary) -> void:
	for path in cases:
		var case: Array = cases[path]
		_assert_font(root.get_node(path), case[1], "%s (edit text %d)" % [path, case[0]])


func test_the_project_theme_draws_sans_in_the_three_heros_faces():
	var theme: Theme = ThemeDB.get_project_theme()
	assert_not_null(theme, "project.godot sets a project theme")
	if theme == null:
		return
	var bold: Font = theme.default_font
	var regular: Font = theme.get_font("font", "RegularLabel")
	var bold_italic: Font = theme.get_font("font", "BoldItalicLabel")
	assert_eq(bold.resource_path, HEROS_BOLD_PATH, "the default font is the bold face")
	assert_eq(regular.resource_path, HEROS_REGULAR_PATH, "RegularLabel is the regular face")
	assert_eq(bold_italic.resource_path, HEROS_BOLD_ITALIC_PATH, "BoldItalicLabel is the bold italic face")
	assert_eq(bold.get_font_style(), TextServer.FONT_BOLD, "the bold file is a bold face")
	assert_eq(regular.get_font_style(), 0, "the regular file is an upright regular face")
	assert_eq(bold_italic.get_font_style(), TextServer.FONT_BOLD | TextServer.FONT_ITALIC, "the bold italic file is both")
	assert_eq(theme.get_type_variation_base("BoldItalicLabel"), &"Label", "BoldItalicLabel varies Label")
	var sample: String = "CLICK on the items that you wish to keep!"
	assert_gt(
		bold.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x,
		regular.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x,
		"bold sets wider"
	)
	# Native tooltips stand in for KrinToolTipper's body text, which is never
	# bold and is 12 px (DefineSprite_2717/frame_4/DoAction.as:40-45).
	assert_eq(theme.get_font("font", "TooltipLabel"), regular, "native tooltips stay regular")
	assert_eq(theme.get_font_size("font_size", "TooltipLabel"), 12, "native tooltips are 12 px")


func _text_files(directory: String) -> Array[String]:
	var found: Array[String] = []
	for file_name in DirAccess.get_files_at(directory):
		if file_name.get_extension() in ["gd", "tscn", "tres"]:
			found.append(directory.path_join(file_name))
	for child in DirAccess.get_directories_at(directory):
		found.append_array(_text_files(directory.path_join(child)))
	return found


# Every string the port draws comes from one of these files or is built at
# runtime from them, which is why scanning the files covers the item, ability
# and buff text the converters brought in from KrinLang. The name a player
# types is the one exception, because any character can be typed there.
func test_every_character_the_port_can_show_exists_in_all_three_faces():
	var characters: Dictionary = {}
	for directory in ["res://resources", "res://scenes", "res://scripts"]:
		for path in _text_files(directory):
			for code in FileAccess.get_file_as_string(path).to_utf32_buffer().to_int32_array():
				if code >= 0x20 and code != 0x7f:
					characters[code] = true
	assert_gt(characters.size(), 90, "the scan found the port's text")
	for face_path in [HEROS_BOLD_PATH, HEROS_REGULAR_PATH, HEROS_BOLD_ITALIC_PATH]:
		var face: Font = load(face_path)
		var missing: Array = characters.keys().filter(func(code): return not face.has_char(code))
		assert_eq(missing, [], "%s has every character the port can show" % face_path.get_file())


# These nodes stand in for edit texts on root frames 64 (nameMenu), 74
# (dataMenu), 84 (classMenu) and 93 (optionsMenu). The class names under the
# cards are Rockwell Bold, font 2738.
func test_main_menu_text_is_bold_and_the_class_names_are_rockwell():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	_assert_fonts(menu, {
		"NamePanel/NameInput": [2712, 65],
		"NamePanel/OkLabel": [2711, 65],
		"NewGamePanel/ClassLabel": [2768, 65],
		"OptionsPanel/SettingsLabel": [2786, 65],
		"NewGamePanel/ClassPicker/PsychologicalName": [2739, 2738],
		"NewGamePanel/ClassPicker/BiologicalName": [2756, 2738],
		"NewGamePanel/ClassPicker/HydraulicName": [2747, 2738],
	})
	_assert_font(menu.slot_buttons.get_child(0), 65, "slot 1's button (edit text 2733)")


# Every edit text on root frame 104 (gameOverMenu) uses font 65.
func test_game_over_text_is_bold():
	var screen = add_child_autofree(load("res://scenes/battle/game_over_screen.tscn").instantiate())
	_assert_fonts(screen, {
		"DeadLabel": [2794, 65],
		"ReloadLabel": [2793, 65],
		"TipLabel": [2792, 65],
		"BackLabel": [2795, 65],
	})


# The hub panel's three lines are klt1, klt2 and klt3, which root frame 181
# (Navigation) fills in (frame_181/DoAction.as:12-14).
func test_hub_panel_text_is_bold():
	var hotbar = add_child_autofree(load("res://scenes/ui/hotbar.tscn").instantiate())
	_assert_fonts(hotbar, {
		"%ZoneTitle": [3144, 65],
		"%ZoneSubtitle": [3143, 65],
		"%StageLabel": [3145, 65],
	})


# The victory screen is frame 9 (win) of the menu clip, DefineSprite 3142. Its
# only font 295 lines are vb1 and vb7 (DefineSprite_3142/frame_9/DoAction.as:45
# and 50).
func test_victory_text_is_bold_except_the_two_font_295_lines():
	var victory = add_child_autofree(load("res://scenes/battle/victory_screen.tscn").instantiate())
	victory.setup(GameData.current_save, {}, [], [])
	_assert_fonts(victory, {
		"ExperienceLabel": [2996, 65],
		"ClickHintLabel": [3007, 65],
		"MoneyLabel": [3011, 65],
		"MoneyValue": [3010, 65],
		"ExpLabel": [3009, 65],
		"ProceedButton": [3014, 65],
		"DropsLabel": [3005, 295],
		"ProceedHintLabel": [3006, 295],
	})
	var rows: Array = victory.get_children().filter(func(child): return child is VictoryExperienceRow)
	assert_eq(rows.size(), 1, "the player's experience row")
	if rows.size() == 1:
		_assert_font(rows[0].name_label, 65, "the experience row's name (edit text 3000)")


# These nodes stand in for edit texts on frames 1 (inventory), 16 (shop), 25
# (skills) and 45 (ach) of the menu clip. The shop frame adds two edit texts of
# its own, vb1 and vb2, and both use font 295
# (DefineSprite_3142/frame_16/DoAction.as:96-97).
func test_menu_screens_are_bold_except_the_shop_dialogue():
	var inventory = add_child_autofree(load("res://scenes/ui/menu/inventory_window.tscn").instantiate())
	_assert_fonts(inventory, {"NameLabel": [2891, 65], "ExperienceLabel": [2869, 65]})
	_assert_fonts(inventory.inventory_panel, {"TitleLabel": [2856, 65], "GoldLabel": [2862, 65]})
	var abilities = add_child_autofree(load("res://scenes/ui/menu/abilities_window.tscn").instantiate())
	_assert_fonts(abilities, {
		"TreeTitle": [3061, 65],
		"AttributesTitle": [3063, 65],
		"AbilityPointsLabel": [3081, 65],
		"VitalityLabel": [3089, 65],
	})
	var achievements = add_child_autofree(load("res://scenes/ui/menu/achievements_window.tscn").instantiate())
	_assert_fonts(achievements, {"TitleLabel": [3136, 65], "Plate0/NameLabel": [3138, 65]})
	var store = add_child_autofree(load("res://scenes/ui/store/store_window.tscn").instantiate())
	_assert_fonts(store, {"DescriptionLabel": [3019, 295], "PurchaseHintLabel": [3018, 295]})


# KrinToolTipper (DefineSprite 2717) builds its own text fields in _sans and
# sets bold only on the title field, my_txt2 (frame_4/DoAction.as:58-64). Its
# body field, my_txt, sets no bold (frame_4/DoAction.as:40-45), which is the
# face font 295 has.
func test_tooltips_bold_the_title_and_keep_the_body_regular():
	var anchor: Control = add_child_autofree(Control.new())
	GameTooltip.show_sections([
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": "Biological", "color": TooltipTheme.TEXT_TITLE}]},
		{"bg_color": TooltipTheme.BG_BODY, "lines": [{"text": "Wild and animalistic.", "color": TooltipTheme.TEXT_BODY}]},
	], anchor)
	var title: Label = GameTooltip._sections.get_child(0).get_child(0).get_child(0)
	var body: Label = GameTooltip._sections.get_child(1).get_child(0).get_child(0)
	_assert_font(title, 65, "the tooltip title, my_txt2")
	_assert_font(body, 295, "the tooltip body, my_txt")


# These nodes stand in for edit texts on root frame 217 (KRINBATTLESCENE). The
# unit bars and the battle speech use font 295, the member bar's name uses the
# pixel font 3307, and the buff counter uses font 65.
func test_battle_text_keeps_the_original_fonts():
	var overlay: UnitOverlay = add_child_autofree(load("res://scenes/battle/unit_overlay.tscn").instantiate())
	_assert_fonts(overlay, {"NameLabel": [3395, 295], "HealthValue": [3398, 295]})
	var unit := CombatUnit.new()
	unit.buff_slots = [{"cd": 3, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0}]
	var buff := Buff.new()
	buff.internal_name = "FIRESAM"
	buff.display_name = "The Immortal Flame"
	buff.element_type = CombatUnit.Element.FIRE
	overlay.refresh_buffs(unit, {1: buff})
	assert_eq(overlay.buff_row.get_child_count(), 1, "the buff shows")
	if overlay.buff_row.get_child_count() == 1:
		var counter: Label = overlay.buff_row.get_child(0).find_children("*", "Label", true, false)[0]
		_assert_font(counter, 65, "the buff counter (edit text 66)")
	var row = add_child_autofree(load("res://scenes/battle/stance_row.tscn").instantiate())
	_assert_fonts(row, {"NameLabel": [3308, 3307]})
	var battle = add_child_autofree(load("res://scenes/battle_scene.tscn").instantiate())
	_assert_fonts(battle, {"UI/SpeechLabel": [3361, 295]})


# The class names are edit texts 2739, 2747 and 2756 at 19 px. The member
# bar's name is edit text 3308, white at 6 px, which the pixel font's 1.625 em
# ascent makes about 10 px tall. Its CSMTextSettings ask for pixel grid
# fitting (gridFit 1), which the port's import gets from normal hinting and
# whole-pixel glyph positions.
func test_embedded_fonts_keep_their_edit_text_sizes():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	for card_name in ["PsychologicalName", "BiologicalName", "HydraulicName"]:
		var label: Label = menu.get_node("NewGamePanel/ClassPicker/" + card_name)
		assert_eq(label.get_theme_font_size("font_size"), 19, "%s is 19 px like its edit text" % card_name)
	var row = add_child_autofree(load("res://scenes/battle/stance_row.tscn").instantiate())
	var member_name: Label = row.get_node("NameLabel")
	assert_eq(member_name.get_theme_font_size("font_size"), 6, "the member bar's name is 6 px like edit text 3308")
	assert_eq(member_name.get_theme_color("font_color"), Color("ffffff"), "and white like it")
	var pixel_font: FontFile = load(PIXEL_FONT_PATH)
	assert_eq(pixel_font.hinting, TextServer.HINTING_NORMAL, "the pixel font's outlines snap to whole pixels")
	assert_eq(
		pixel_font.subpixel_positioning,
		TextServer.SUBPIXEL_POSITIONING_DISABLED,
		"and its glyphs sit on whole pixels"
	)


func _tooltip_labels() -> Array:
	var labels: Array = []
	for section in GameTooltip._sections.get_children():
		for label in section.get_child(0).get_children():
			labels.append(label)
	return labels


func _assert_tooltip_fields(colors: Array, what: String) -> void:
	var labels: Array = _tooltip_labels()
	assert_eq(labels.size(), colors.size(), "%s: one label per field" % what)
	for i in mini(labels.size(), colors.size()):
		assert_eq(labels[i].get_theme_color("font_color"), colors[i], "%s field %d color" % [what, i])
		assert_eq(labels[i].get_theme_font_size("font_size"), 12, "%s field %d is 12 px" % [what, i])


# The lowest id equipment item with both stat lines and flavor text, so its
# tooltip has every kind of item field.
func _equipment_with_flavor() -> GameItem:
	var ids: Array = ItemManagerAuto.items_by_id.keys()
	ids.sort()
	for id in ids:
		var item: GameItem = ItemManagerAuto.items_by_id[id]
		if item.item_type >= GameItem.ItemType.HEAD and not item.tooltipAlt.is_empty() and not item.tooltip.is_empty():
			return item
	return null


# KrinToolTipper builds every field in 12 px _sans with one color per kind of
# field. An ability's title is black, its cost line 0x000033, its description
# white and its next tier 0xFFCC00 (DefineSprite_2717/frame_17/DoAction.as:89,
# 30, 47 and 71). An item's title is black, its level line 0x333333, its stat
# lines 0xF8D754 and its flavor text 0xB8FE4E (frame_13/DoAction.as:104, 34,
# 58 and 77).
func test_tooltips_use_the_original_text_size_and_colors():
	var abilities = add_child_autofree(load("res://scenes/ui/menu/abilities_window.tscn").instantiate())
	abilities.refresh()
	abilities._on_tree_node_hovered(0)
	_assert_tooltip_fields(
		[Color("000000"), Color("000033"), Color("ffffff"), Color("ffcc00")], "an ability tree node"
	)
	var item: GameItem = _equipment_with_flavor()
	assert_not_null(item, "an equipment item with stat lines and flavor text exists")
	if item == null:
		return
	var slot = add_child_autofree(load("res://scenes/ui/item_slot.tscn").instantiate())
	slot.set_item(item)
	slot.mouse_entered.emit()
	var colors: Array = [Color("000000"), Color("333333")]
	for _i in item.tooltipAlt.size():
		colors.append(Color("f8d754"))
	colors.append(Color("b8fe4e"))
	_assert_tooltip_fields(colors, item.display_name)


# The reference captures show the original wrapping three tooltips: the
# Biological blurb onto 11 lines and the New Game warning onto 5 in a plain
# tooltip (references/2026_07_18_flashpoint/7_start_screen_on_class_hover and
# 5_start_screen_on_slot_hover), and Leading Strike's description onto 3 in an
# ability tooltip (13_inbattle_after_player_click_on_hover_ability).
func test_tooltips_wrap_onto_as_many_lines_as_the_reference_captures():
	var menu = add_child_autofree(MainMenuScene.instantiate())
	await get_tree().process_frame
	menu.class_picker.get_node("Biological").mouse_entered.emit()
	await wait_process_frames(2)
	assert_eq(_tooltip_labels()[1].get_line_count(), 11, "the Biological blurb")
	menu.class_picker.get_node("Biological").mouse_exited.emit()
	menu.get_node("ModePanel/NewGameButton").pressed.emit()
	menu.get_node("NamePanel/OkButton").pressed.emit()
	menu.slot_buttons.get_child(0).mouse_entered.emit()
	await wait_process_frames(2)
	assert_eq(_tooltip_labels()[1].get_line_count(), 5, "the New Game warning")
	var abilities = add_child_autofree(load("res://scenes/ui/menu/abilities_window.tscn").instantiate())
	abilities.refresh()
	abilities._on_socket_hovered(0)
	await wait_process_frames(2)
	var description: Label = _tooltip_labels()[2]
	assert_string_starts_with(description.text, "Attack the enemy for 170% of your Strength", "socket 0 holds Leading Strike")
	assert_eq(description.get_line_count(), 3, "Leading Strike's description")
