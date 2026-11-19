# The Abilities window's text, hint box and flows (spec/107-abilities.md).
# test_screen_rects.gd checks where each piece lands. This file checks what the
# pieces say and what clicking them does.
extends GutTest

const SCENE: String = "res://scenes/ui/menu/abilities_window.tscn"
const ROWS: Array[String] = ["Vitality", "Strength", "Instinct", "Speed"]


func before_each() -> void:
	GameData.current_save = PlayerSave.new_game("AbilitiesTest", 0)


func after_each() -> void:
	GameData.current_save = null
	GameTooltip.hide_tooltip()


func _window() -> Control:
	var window: Control = add_child_autofree(load(SCENE).instantiate())
	window.refresh()
	return window


func _text(window: Control, path: String) -> String:
	return (window.get_node(path) as Label).text


func _spend_all_points() -> void:
	GameData.current_save.skill_points = 0
	GameData.current_save.stat_points = 0


func _tips() -> Array[String]:
	var tips: Array[String] = []
	for index in range(43, 47):
		tips.append(Strings.menu(index))
	return tips


# The reader clip's first frame shows MENU[43 + random(4)]
# (DefineSprite_3059/frame_1/DoAction.as) when the player has no points.
func test_the_hint_box_shows_one_of_the_four_tips() -> void:
	_spend_all_points()
	var window: Control = _window()
	assert_has(_tips(), _text(window, "HintLabel"))
	assert_true((window.get_node("HintLabel") as Label).visible, "the tip shows")
	assert_false((window.get_node("HintSteps/StepLabel") as Label).visible, "no step shows")


func test_the_hint_box_picks_a_tip_each_time_the_window_opens() -> void:
	_spend_all_points()
	seed(236)
	var window: Control = _window()
	var shown: Dictionary = {}
	for i in 20:
		window.hide()
		window.show()
		shown[_text(window, "HintLabel")] = true
	randomize()
	assert_gt(shown.size(), 1, "20 openings showed only %s" % [shown.keys()])
	for tip: String in shown:
		assert_has(_tips(), tip)


# DefineSprite_3142/frame_25/DoAction.as:10-15.
func test_the_titles_and_points_labels_read_strings_json() -> void:
	var window: Control = _window()
	assert_eq(_text(window, "TreeTitle"), Strings.text("K_TITLE1"))
	assert_eq(_text(window, "AttributesTitle"), Strings.text("K_TITLE2"))
	assert_eq(_text(window, "ActionBarTitle"), Strings.text("K_TITLE3"))
	assert_eq(_text(window, "PoolTitle"), Strings.menu(16))
	assert_eq(_text(window, "AbilityPointsLabel"), Strings.text("SKLOAD") + ":")
	assert_eq(_text(window, "AttributePointsLabel"), Strings.text("SPLOAD") + ":")


# DefineSprite_3142/frame_25/DoAction.as:2-5.
func test_the_attribute_names_read_system_0_to_3() -> void:
	var window: Control = _window()
	for i in ROWS.size():
		var path: String = "AttributeRows/%sRow/%sLabel" % [ROWS[i], ROWS[i]]
		assert_eq(_text(window, path), Strings.system(i) + ":", path)


# DefineSprite_3142/frame_25/DoAction.as:17. ClassStats counts from 1, and
# PlayerClass counts from 0.
func test_the_level_line_reads_menu_0_the_level_and_the_class() -> void:
	var save: PlayerSave = GameData.current_save
	var window: Control = _window()
	for player_class: int in PlayerSave.PlayerClass.values():
		save.player_class = player_class
		window.refresh()
		var expected: String = "%s%d %s" % [Strings.menu(0), save.level, PlayerSave.CLASS_NAMES[player_class]]
		assert_eq(_text(window, "LevelLabel"), expected, PlayerSave.CLASS_NAMES[player_class])


func test_each_plus_button_is_filled_with_its_rows_colour() -> void:
	var window: Control = _window()
	for row: String in ROWS:
		var button: Button = window.get_node("PlusColumn/%sSlot/%sPlus" % [row, row])
		var label: Label = window.get_node("AttributeRows/%sRow/%sLabel" % [row, row])
		var style: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
		assert_not_null(style, "%s: the normal style is a StyleBoxFlat" % row)
		if style != null:
			assert_eq(style.bg_color.to_html(), label.get_theme_color("font_color").to_html(), row)


# Godot draws the focus style over the state style, and a click gives a button
# focus, so a focus style that draws would hide the hover and pressed fills.
func test_a_plus_button_draws_no_focus_style() -> void:
	var window: Control = _window()
	for row: String in ROWS:
		var button: Button = window.get_node("PlusColumn/%sSlot/%sPlus" % [row, row])
		assert_is(button.get_theme_stylebox("focus"), StyleBoxEmpty, row)


func test_a_plus_button_spends_an_attribute_point() -> void:
	var save: PlayerSave = GameData.current_save
	save.stat_points = 1
	var life_before: float = save.life
	var window: Control = _window()
	(window.get_node("PlusColumn/VitalitySlot/VitalityPlus") as Button).pressed.emit()
	assert_eq(save.stat_points, 0)
	assert_eq(save.life, life_before + 1)
	assert_eq(_text(window, "AttributePointsValue"), "0")
	assert_eq(_text(window, "AttributeRows/VitalityRow/VitalityValue"), str(int(save.life)))


func test_a_tree_node_click_learns_the_talent() -> void:
	var save: PlayerSave = GameData.current_save
	save.skill_points = 1
	var window: Control = _window()
	(window.get_node("TreeNodes/Node0") as Button).pressed.emit()
	assert_eq(TalentTree.get_rank(save, 0), 1)
	assert_eq(_text(window, "AbilityPointsValue"), "0")


func _tooltip_texts() -> Array[String]:
	var texts: Array[String] = []
	for section: Node in GameTooltip._sections.get_children():
		for label: Node in section.get_child(0).get_children():
			texts.append((label as Label).text)
	return texts


# DefineSprite_3142/frame_25/DoAction.as:85-88 sets the title to SKILLNONE,
# toolTip to SKILLTUT and toolTip3 to SKILLTUT2. The tooltip clip draws
# toolTip3 under the title and toolTip below that
# (DefineSprite_2717/frame_7/DoAction.as:21-38).
func test_an_empty_socket_tooltip_reads_strings_json() -> void:
	GameData.current_save.move_matrix[3] = 0
	var window: Control = _window()
	var socket: Button = window.get_node("Socket3")
	socket.mouse_entered.emit()
	var expected: Array[String] = [
		Strings.text("SKILLNONE"), Strings.text("SKILLTUT2"), Strings.text("SKILLTUT"),
	]
	assert_true(GameTooltip._root.visible, "the tooltip shows")
	assert_eq(_tooltip_texts(), expected)
	assert_eq(socket.tooltip_text, "", "no native tooltip shows over the rich one")


func test_a_pool_row_places_its_ability_and_a_socket_click_sends_it_back() -> void:
	var save: PlayerSave = GameData.current_save
	var owned: Array = save.move_matrix2.filter(func(move_id): return int(move_id) != 0)
	assert_gt(owned.size(), 0, "a new game owns an ability")
	save.move_matrix.fill(0)
	var window: Control = _window()
	(window.get_node("Pool/Mask/Rows/PoolRow0") as Button).pressed.emit()
	assert_eq(int(save.move_matrix[0]), int(owned[0]), "the first free socket holds it")
	(window.get_node("Socket0") as Button).pressed.emit()
	assert_eq(int(save.move_matrix[0]), 0, "the socket is empty again")


func test_the_close_button_hides_the_window() -> void:
	var window: Control = _window()
	(window.get_node("WindowShell") as WindowShell).close_pressed.emit()
	assert_false(window.visible)
