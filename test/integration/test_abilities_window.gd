# The Abilities window's text, hint box and flows (spec/107-abilities.md).
# test_screen_rects.gd checks where each piece lands. This file checks what the
# pieces say and what clicking them does.
extends GutTest

const SCENE: String = "res://scenes/ui/menu/abilities_window.tscn"
const ROWS: Array[String] = ["Vitality", "Strength", "Instinct", "Speed"]
const DiscReader = preload("res://test/disc_reader.gd")
const ADRENALINE_ID: int = 120
const LEADING_STRIKE_ID: int = 1


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
	for section: Node in GameTooltip.sections():
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
	assert_true(GameTooltip.is_showing(), "the tooltip shows")
	assert_eq(_tooltip_texts(), expected)
	assert_eq(socket.tooltip_text, "", "no native tooltip shows over the rich one")


# A pool row shows its title, then toolTip3 (the cost), then toolTip: the
# description followed by SKILLTHRS1, the action bar limit and SKILLTHRS2
# (DefineSprite_3142/frame_25/DoAction.as:48-50).
func test_a_pool_row_tooltip_ends_the_description_with_the_action_bar_limit() -> void:
	var save: PlayerSave = GameData.current_save
	save.move_matrix2.clear()
	save.move_matrix2.append(LEADING_STRIKE_ID)
	var window: Control = _window()
	(window.get_node("Pool/Mask/Rows/PoolRow0") as Button).mouse_entered.emit()
	var move: Ability = MoveManagerAuto.get_move(LEADING_STRIKE_ID)
	var expected: Array[String] = [
		move.display_name,
		move.tooltip_cost,
		move.tooltip_description + Strings.text("SKILLTHRS1") + str(move.hotbar_slot_limit) + Strings.text("SKILLTHRS2"),
	]
	assert_true(GameTooltip.is_showing(), "the tooltip shows")
	assert_eq(_tooltip_texts(), expected)


# -> the ability that the first pool row shows in a new game. The pool walks
# move_matrix2 from the end, so that is the last owned ability. The tests below
# read its copy limit, KRINABILITY[8], from the move data.
func _first_row_move() -> int:
	var owned: Array = GameData.current_save.move_matrix2.filter(func(move_id): return int(move_id) != 0)
	assert_gt(owned.size(), 0, "a new game owns an ability")
	return int(owned[-1])


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
	var move_id: int = _first_row_move()
	save.move_matrix.fill(0)
	var window: Control = _window()
	_hold_first_row(window)
	var icon: TextureRect = window.get_node("HeldIcon")
	assert_true(icon.visible, "the held icon shows")
	assert_eq(icon.texture, AbilityIcon.for_move(MoveManagerAuto.get_move(move_id)))
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
	var move_id: int = _first_row_move()
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
	var move_id: int = _first_row_move()
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
	var move_id: int = _first_row_move()
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
	save.move_matrix[2] = _first_row_move()
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
	assert_eq(int(save.move_matrix[1]), _first_row_move())
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
	var move_id: int = _first_row_move()
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


# KrinCreateAbilityMatrix walks the push-built moveMatrix2 with for..in, which
# goes from the last index down (DefineSprite_3142/frame_25/DoAction.as:37,
# DECODED_ALGORITHMS.md "for..in order over arrays"). The learn button builds
# moveMatrix2 as the two starting moves, then the learned nodes from node 37
# down (DefineButton2_3096 on(release) lines 48-58), so the rows read the low
# node, the high node, then the starting moves in reverse.
func test_the_pool_rows_walk_move_matrix2_from_the_end() -> void:
	var save: PlayerSave = GameData.current_save
	save.skill_points = 2
	var window: Control = _window()
	for node_index: int in [0, 2]:
		assert_false(TalentTree.is_passive(TalentTree.TREES[save.player_class][node_index]), "node %d is active" % node_index)
		(window.get_node("TreeNodes/Node%d" % node_index) as Button).pressed.emit()
	var starting: Array = TalentTree.STARTING_MOVES[save.player_class]
	var expected: Array = [
		int(save.skill_adder_matrix[0]), int(save.skill_adder_matrix[2]), int(starting[1]), int(starting[0]),
	]
	assert_does_not_have(expected, 0, "both nodes are learned")
	for i in expected.size():
		var row: AbilityPoolRow = window.get_node("Pool/Mask/Rows/PoolRow%d" % i)
		assert_eq(row.name_label.text, MoveManagerAuto.get_move(expected[i]).display_name, "row %d" % i)
	assert_false((window.get_node("Pool/Mask/Rows/PoolRow4") as AbilityPoolRow).visible, "row 4 is empty")


func _disc(texture: Texture2D, move_id: int) -> Color:
	return DiscReader.disc_color(texture, AbilityIcon.key(MoveManagerAuto.get_move(move_id).display_name))


func _element(move_id: int) -> Color:
	return MenuTheme.ELEMENT_COLORS[MoveManagerAuto.get_move(move_id).damage_element_type]


func _assert_color(actual: Color, expected: Color, text: String) -> void:
	for channel in 3:
		assert_almost_eq(actual[channel], expected[channel], 0.02, "%s, channel %d" % [text, channel])


# KrinCreateAbilityMatrix gives each pool icon and each ring socket the
# element colour of its move (DefineSprite_3142/frame_25/DoAction.as:51-57 and
# 75-81), and DefineButton2_2437 gives the held icon its colour.
func test_the_pool_the_ring_and_the_held_icon_tint_the_disc_with_the_moves_element() -> void:
	var save: PlayerSave = GameData.current_save
	save.move_matrix2.clear()
	save.move_matrix2.append(LEADING_STRIKE_ID)
	save.move_matrix2.append(ADRENALINE_ID)
	save.move_matrix.fill(0)
	save.move_matrix[2] = ADRENALINE_ID
	var window: Control = _window()
	var row: AbilityPoolRow = window.get_node("Pool/Mask/Rows/PoolRow0")
	assert_eq(row.name_label.text, "Adrenaline", "sanity: the pool lists the last owned first")
	_assert_color(_disc(row.icon_rect.texture, ADRENALINE_ID), _element(ADRENALINE_ID), "pool row")
	_assert_color(_disc(_socket(window, 2).icon, ADRENALINE_ID), _element(ADRENALINE_ID), "socket")
	_hold_first_row(window)
	var held: TextureRect = window.get_node("HeldIcon")
	_assert_color(_disc(held.texture, ADRENALINE_ID), _element(ADRENALINE_ID), "held icon")
	row.mouse_entered.emit()
	_assert_color(_disc(GameTooltip.icon_texture(), ADRENALINE_ID), _element(ADRENALINE_ID), "pool tooltip")


func _talent_cover(window: Control, node_index: int) -> TextureRect:
	return window.get_node("TreeNodes/Node%d/IconRect/Cover" % node_index)


# krinRemakeTree shows the icon's black "bfilter" disc at an alpha of its own on
# a node with no point in it, and hides it on a node with one
# (DefineSprite_3142/frame_25/PlaceObject3_3100_153 load, lines 59-67).
# extract_fade_steps writes that alpha to talent_cover.json. Flash stores it in
# 1/256 steps.
func test_a_tree_node_with_no_point_is_covered_until_it_takes_one() -> void:
	var save: PlayerSave = GameData.current_save
	save.skill_points = 1
	var window: Control = _window()
	assert_eq(TalentTree.get_rank(save, 0), 0, "sanity: node 0 has no point")
	var cover: TextureRect = _talent_cover(window, 0)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/abilities/talent_cover.json"))
	assert_true(cover.visible, "a node with no point is covered")
	assert_eq(cover.modulate.a, FlashAlpha.from_percent(float(layout["cover_percent"])) / 256.0, "at the alpha krinRemakeTree gives it")
	(window.get_node("TreeNodes/Node0") as Button).pressed.emit()
	assert_eq(TalentTree.get_rank(save, 0), 1, "sanity: the click learned the talent")
	assert_false(cover.visible, "a node with a point shows its icon uncovered")


# The tree places each icon, thing2, at its own size, so the disc covers the
# same part of the icon as it does on a Radial menu orb. The port draws the
# tree's icons smaller, and the disc shrinks with them. extract_ability_icons
# renders the disc and cuts every icon to the box of disc.png at one zoom, so
# the disc is as wide against the icon as cooldown_cover.png is against
# disc.png.
func test_the_talent_cover_sits_on_the_icons_centre_at_the_icons_scale() -> void:
	var window: Control = _window()
	var icon_rect: TextureRect = window.get_node("TreeNodes/Node0/IconRect")
	var cover: TextureRect = _talent_cover(window, 0)
	var rect: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/abilities/cooldown.json"))["cover"]
	var cover_texture: Texture2D = load("res://assets/ui/abilities/cooldown_cover.png")
	var icon_texture: Texture2D = load(AbilityIcon.DISC_PATH)
	assert_eq(cover.texture, cover_texture, "the black disc that the Radial menu shows")
	assert_almost_eq(cover.size.x / icon_rect.size.x, float(cover_texture.get_width()) / icon_texture.get_width(), 0.0001, "as wide against the icon as in the art")
	assert_almost_eq(cover.size.y / cover.size.x, float(rect["h"]) / float(rect["w"]), 0.0001, "and as tall against its width")
	var px_per_stage_px: float = cover.size.x / float(rect["w"])
	var rect_centre: Vector2 = Vector2(rect["x"] + rect["w"] / 2.0, rect["y"] + rect["h"] / 2.0)
	assert_almost_eq(cover.get_global_rect().get_center(), icon_rect.get_global_rect().get_center() + rect_centre * px_per_stage_px, Vector2(0.01, 0.01), "on the icon's centre")


# krinRemakeTree gives a node the element of its ID's move, and a passive
# node's ID is 0, whose move is Physical
# (DefineSprite_3142/frame_25/PlaceObject3_3100_153 load, lines 51-57).
func test_a_tree_nodes_disc_takes_the_element_of_its_moves_row() -> void:
	var window: Control = _window()
	var tree: Array = TalentTree.TREES[PlayerSave.PlayerClass.BIOLOGICAL]
	assert_eq(tree[1]["buff_family"], "INTEGRITY", "sanity: node 1 is a passive")
	assert_eq(int(tree[5]["move_id"]), ADRENALINE_ID, "sanity: node 5 grants Adrenaline")
	var passive: TextureRect = window.find_child("Node1", true, false).get_node("IconRect")
	_assert_color(DiscReader.disc_color(passive.texture, "INTEGRITY"), MenuTheme.ELEMENT_COLORS[MoveManagerAuto.get_move(0).damage_element_type], "passive")
	var active: TextureRect = window.find_child("Node5", true, false).get_node("IconRect")
	_assert_color(_disc(active.texture, ADRENALINE_ID), _element(ADRENALINE_ID), "active")
	window._on_tree_node_hovered(5)
	_assert_color(_disc(GameTooltip.icon_texture(), ADRENALINE_ID), _element(ADRENALINE_ID), "tree tooltip")


# A socket that goes from one ability straight to another stays on a frame
# that holds the disc, so Flash keeps the disc and its load script does not run
# again. The disc keeps the first ability's colour until the socket empties
# ("Empty" holds no tinted disc) or the window opens again. A throwaway Probe
# measured this in the Flash debug player for #439.
func test_a_socket_keeps_its_discs_colour_until_it_empties_or_the_window_reopens() -> void:
	var save: PlayerSave = GameData.current_save
	assert_ne(_element(LEADING_STRIKE_ID), _element(ADRENALINE_ID), "sanity: two elements")
	save.move_matrix2.clear()
	save.move_matrix2.append(LEADING_STRIKE_ID)
	save.move_matrix2.append(ADRENALINE_ID)
	save.move_matrix.fill(0)
	save.move_matrix[0] = LEADING_STRIKE_ID
	var window: Control = _window()
	_hold_first_row(window)
	_socket(window, 0).pressed.emit()
	assert_eq(int(save.move_matrix[0]), ADRENALINE_ID, "sanity: the socket took Adrenaline")
	_assert_color(_disc(_socket(window, 0).icon, ADRENALINE_ID), _element(LEADING_STRIKE_ID), "the first colour stays")
	_socket(window, 0).pressed.emit()
	assert_eq(int(save.move_matrix[0]), 0, "sanity: an empty-handed click empties it")
	_hold_first_row(window)
	_socket(window, 0).pressed.emit()
	_assert_color(_disc(_socket(window, 0).icon, ADRENALINE_ID), _element(ADRENALINE_ID), "a new disc after the empty socket")
	save.move_matrix[0] = LEADING_STRIKE_ID
	window.refresh()
	_assert_color(_disc(_socket(window, 0).icon, LEADING_STRIKE_ID), _element(ADRENALINE_ID), "sanity: still the old colour")
	window.visible = false
	window.visible = true
	_assert_color(_disc(_socket(window, 0).icon, LEADING_STRIKE_ID), _element(LEADING_STRIKE_ID), "reopening makes the ring again")
