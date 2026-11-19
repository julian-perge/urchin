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


func _tips() -> Array[String]:
	var tips: Array[String] = []
	for index in range(43, 47):
		tips.append(Strings.menu(index))
	return tips


# The reader clip's first frame shows MENU[43 + random(4)]
# (DefineSprite_3059/frame_1/DoAction.as).
func test_the_hint_box_shows_one_of_the_four_tips() -> void:
	var window: Control = _window()
	assert_has(_tips(), _text(window, "HintLabel"))


func test_the_hint_box_picks_a_tip_each_time_the_window_opens() -> void:
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


# -> the first ability a new game owns. The tests below read its copy limit,
# KRINABILITY[8], from the move data.
func _first_owned() -> int:
	var owned: Array = GameData.current_save.move_matrix2.filter(func(move_id): return int(move_id) != 0)
	assert_gt(owned.size(), 0, "a new game owns an ability")
	return int(owned[0])


func _limit(move_id: int) -> int:
	return MoveManagerAuto.get_move(move_id).hotbar_slot_limit


func _banner() -> CombatTextBanner:
	var banner: CombatTextBanner = add_child_autofree(load("res://scenes/battle/combat_text_banner.tscn").instantiate())
	banner.placement = "hub"
	banner.add_to_group(&"combat_text_banner")
	banner.set_process(false)
	return banner


func _socket(window: Control, index: int) -> Button:
	return window.get_node("Socket%d" % index)


func _hold_first_row(window: Control) -> void:
	(window.get_node("Pool/Mask/Rows/PoolRow0") as Button).button_down.emit()


func _mouse_down() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


# A press on a pool ability holds it and shows its icon at the mouse
# (DefineButton2_2437 on(press)). A release on a ring socket puts it there
# (DefineButton2_3101 to 3108 on(release), frame_42/DoAction_11.as:11-32).
func test_a_held_pool_ability_goes_to_the_socket_it_is_released_on() -> void:
	var save: PlayerSave = GameData.current_save
	var move_id: int = _first_owned()
	save.move_matrix.fill(0)
	var window: Control = _window()
	_hold_first_row(window)
	var icon: TextureRect = window.get_node("HeldIcon")
	assert_true(icon.visible, "the held icon shows")
	assert_eq(icon.texture, RadialMenu.icon_texture(MoveManagerAuto.get_move(move_id)))
	assert_eq(int(save.move_matrix[5]), 0, "a press places nothing")
	_socket(window, 5).pressed.emit()
	var expected: Array = [0, 0, 0, 0, 0, move_id, 0, 0]
	assert_eq(save.move_matrix.map(func(id): return int(id)), expected, "only socket 5 holds it")
	assert_false(icon.visible, "the hold ends")


# addMoveForPlayer counts the copies on the ring, the one in the target socket
# included, and refuses a copy past KRINABILITY[8] with SKILLERROR. The hold ends
# either way (frame_42/DoAction_11.as:14-32).
func test_a_copy_past_the_limit_shows_skillerror_and_leaves_the_ring() -> void:
	var save: PlayerSave = GameData.current_save
	var move_id: int = _first_owned()
	var limit: int = _limit(move_id)
	assert_between(limit, 1, 7, "the limit leaves a free socket")
	save.move_matrix.fill(0)
	for i in limit:
		save.move_matrix[i] = move_id
	var before: Array = save.move_matrix.duplicate()
	var banner: CombatTextBanner = _banner()
	var window: Control = _window()
	_hold_first_row(window)
	_socket(window, limit).pressed.emit()
	assert_eq(save.move_matrix, before, "the free socket stays empty")
	assert_true(banner.is_up(), "the banner shows")
	assert_eq(banner.label.text, Strings.text("SKILLERROR"))
	assert_false((window.get_node("HeldIcon") as TextureRect).visible, "the hold ends")


func test_a_copy_under_the_limit_goes_on_the_ring() -> void:
	var save: PlayerSave = GameData.current_save
	var move_id: int = _first_owned()
	var limit: int = _limit(move_id)
	save.move_matrix.fill(0)
	for i in limit - 1:
		save.move_matrix[i] = move_id
	var banner: CombatTextBanner = _banner()
	var window: Control = _window()
	_hold_first_row(window)
	_socket(window, 7).pressed.emit()
	assert_eq(int(save.move_matrix[7]), move_id)
	assert_false(banner.is_up(), "no refusal")


# The count includes the copy in the target socket, so a release on the socket
# that already holds the last allowed copy is refused too.
func test_the_count_includes_the_copy_in_the_target_socket() -> void:
	var save: PlayerSave = GameData.current_save
	var move_id: int = _first_owned()
	save.move_matrix.fill(0)
	for i in _limit(move_id):
		save.move_matrix[i] = move_id
	var banner: CombatTextBanner = _banner()
	var window: Control = _window()
	_hold_first_row(window)
	_socket(window, 0).pressed.emit()
	assert_eq(int(save.move_matrix[0]), move_id)
	assert_eq(banner.label.text, Strings.text("SKILLERROR"))


# A release with nothing held empties the socket (frame_42/DoAction_11.as:7-10).
func test_a_release_with_nothing_held_empties_the_socket() -> void:
	var save: PlayerSave = GameData.current_save
	save.move_matrix[2] = _first_owned()
	var window: Control = _window()
	_socket(window, 2).pressed.emit()
	assert_eq(int(save.move_matrix[2]), 0)


# The menu frame's onMouseDown drops a held ability unless the mouse is over a
# ring socket, whose rollOver sets UITdrop (frame_181/DoAction_2.as:10-14).
func test_a_mouse_down_off_the_ring_drops_the_held_ability() -> void:
	var save: PlayerSave = GameData.current_save
	save.move_matrix.fill(0)
	var window: Control = _window()
	_hold_first_row(window)
	window._input(_mouse_down())
	assert_false((window.get_node("HeldIcon") as TextureRect).visible, "the hold ends")
	_socket(window, 1).pressed.emit()
	assert_eq(int(save.move_matrix[1]), 0, "a release with nothing held places nothing")


func test_a_mouse_down_on_a_socket_keeps_the_held_ability() -> void:
	var save: PlayerSave = GameData.current_save
	save.move_matrix.fill(0)
	var window: Control = _window()
	_hold_first_row(window)
	_socket(window, 1).mouse_entered.emit()
	window._input(_mouse_down())
	_socket(window, 1).pressed.emit()
	assert_eq(int(save.move_matrix[1]), _first_owned())
	_socket(window, 1).mouse_exited.emit()


# The frame's script sets UITmouseHold to 0 as the window opens
# (DefineSprite_3142/frame_25/DoAction.as:1).
func test_reopening_the_window_drops_the_held_ability() -> void:
	var window: Control = _window()
	_hold_first_row(window)
	window.hide()
	window.show()
	assert_false((window.get_node("HeldIcon") as TextureRect).visible)


# KrinCreateAbilityMatrix lists every ability in moveMatrix2, the ones on the
# ring too, so a second copy can be taken from the pool
# (DefineSprite_3142/frame_25/DoAction.as:35-44).
func test_the_pool_lists_the_abilities_on_the_ring_too() -> void:
	var save: PlayerSave = GameData.current_save
	var move_id: int = _first_owned()
	save.move_matrix.fill(0)
	save.move_matrix[0] = move_id
	var window: Control = _window()
	var row: AbilityPoolRow = window.get_node("Pool/Mask/Rows/PoolRow0")
	assert_true(row.visible)
	assert_eq(row.name_label.text, MoveManagerAuto.get_move(move_id).display_name)


# The tooltip clip follows the mouse and places inner2, the icon sheet, at its
# origin, so the icon's rect from the mouse is the one extract_tooltip_look
# writes.
func test_the_held_icon_sits_on_the_mouse_as_the_tooltip_clip_places_it() -> void:
	var rect: Dictionary = TooltipTheme.look()["held_icon"]
	var window: Control = _window()
	_hold_first_row(window)
	var mouse := Vector2(400, 300)
	window._place_held_icon(mouse)
	var icon: TextureRect = window.get_node("HeldIcon")
	assert_eq(icon.global_position, mouse + Vector2(rect["x"], rect["y"]))
	assert_eq(icon.size, Vector2(rect["w"], rect["h"]))


func test_the_close_button_hides_the_window() -> void:
	var window: Control = _window()
	(window.get_node("WindowShell") as WindowShell).close_pressed.emit()
	assert_false(window.visible)
