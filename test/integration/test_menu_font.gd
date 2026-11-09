# The original draws its menu text in DefineFont3 65, the device font _sans
# with fontFlagsBold set, and 190 of the 223 DefineEditText tags in
# sonny-2-2900.swf use it. Most of the rest use DefineFont3 295, the same
# _sans without the bold flag. The port draws font 65 text in a bold face of
# its own default font, which the project theme sets once for every Control,
# and gives everything the original draws in another font the RegularLabel
# type variation. Each case pairs a port node with the edit text it stands in
# for and that edit text's font id.
extends GutTest

const BOLD_FONT_ID: int = 65
const MainMenuScene = preload("res://scenes/main_menu.tscn")


func before_each():
	GameData.current_save = PlayerSave.new_game("FontTest", 0)


func after_each():
	GameData.current_save = null
	GameTooltip.hide_tooltip()


# Godot's own default theme bolds its default font for RichTextLabel's [b] by
# wrapping it in a FontVariation, so that is the bold the menu text uses too.
func _engine_bold() -> float:
	var bold: FontVariation = ThemeDB.get_default_theme().get_font("bold_font", "RichTextLabel")
	return bold.variation_embolden


func _assert_font(control: Control, font_id: int, what: String) -> void:
	var font: Font = control.get_theme_font("font")
	var embolden: float = font.variation_embolden if font is FontVariation else 0.0
	if font_id == BOLD_FONT_ID:
		assert_eq(embolden, _engine_bold(), "%s is bold like font 65" % what)
	else:
		assert_eq(embolden, 0.0, "%s stays regular like font %d" % [what, font_id])


# Each case maps a node path to [edit text id, font id].
func _assert_fonts(root: Node, cases: Dictionary) -> void:
	for path in cases:
		var case: Array = cases[path]
		_assert_font(root.get_node(path), case[1], "%s (edit text %d)" % [path, case[0]])


func test_the_project_theme_bolds_the_default_font_the_way_the_engine_does():
	var theme: Theme = ThemeDB.get_project_theme()
	assert_not_null(theme, "project.godot sets a project theme")
	if theme == null:
		return
	var bold: Font = theme.default_font
	assert_true(bold is FontVariation, "the bold face is a variation of a font, not a font file")
	if not bold is FontVariation:
		return
	assert_eq(bold.variation_embolden, _engine_bold(), "as bold as the engine's own bold")
	assert_eq(bold.get_font_name(), ThemeDB.fallback_font.get_font_name(), "of the port's default font")
	var sample: String = "CLICK on the items that you wish to keep!"
	var plain: float = ThemeDB.fallback_font.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	assert_gt(bold.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, plain, "bold sets wider")
	var regular: Font = theme.get_font("font", "RegularLabel")
	assert_eq(
		regular.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x,
		plain,
		"RegularLabel sets exactly as the default font did"
	)
	# Native tooltips stand in for KrinToolTipper's body text, which is never
	# bold (DefineSprite_2717/frame_4/DoAction.as:40-45).
	assert_eq(theme.get_font("font", "TooltipLabel"), regular, "native tooltips stay regular")


# These nodes stand in for edit texts on root frames 64 (nameMenu), 74
# (dataMenu), 84 (classMenu) and 93 (optionsMenu). The class names under the
# cards are Rockwell Bold, font 2738, so they keep the regular face.
func test_main_menu_text_is_bold_except_the_rockwell_class_names():
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
		_assert_font(overlay.buff_row.get_child(0).get_child(0), 65, "the buff counter (edit text 66)")
	var row = add_child_autofree(load("res://scenes/battle/stance_row.tscn").instantiate())
	_assert_fonts(row, {"NameLabel": [3308, 3307]})
	var battle = add_child_autofree(load("res://scenes/battle_scene.tscn").instantiate())
	_assert_fonts(battle, {"UI/SpeechLabel": [3361, 295]})
