# The tutorial steps of the hint box (#387). extract_hint_steps reads the
# labels, their MENU indices, their fields, their click areas and their art
# from the clip `reader` (DefineSprite 3059) into hint_steps.json. These tests
# check that the window follows that file: when the steps start, that a click
# moves to the next label, and what each label shows and where.
extends GutTest

const SCENE: String = "res://scenes/ui/menu/abilities_window.tscn"
const LAYOUT_PATH: String = "res://assets/ui/menu/hint_steps/hint_steps.json"
const TOLERANCE: float = 0.5

var _layout: Dictionary


func before_all() -> void:
	_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))


func before_each() -> void:
	GameData.current_save = PlayerSave.new_game("HintStepsTest", 0)
	GameData.current_save.skill_points = 0
	GameData.current_save.stat_points = 0


func after_each() -> void:
	GameData.current_save = null
	GameTooltip.hide_tooltip()


func _window() -> Control:
	var window: Control = add_child_autofree(load(SCENE).instantiate())
	window.refresh()
	(window.get_node("HintSteps") as HintSteps).set_process(false)
	return window


func _steps(window: Control) -> HintSteps:
	return window.get_node("HintSteps")


# The labels from the first step to the one whose click goes back to the tip.
func _chain() -> Array[String]:
	var chain: Array[String] = []
	var state: String = _layout["start"]
	while state != _layout["rest"]:
		assert_false(chain.has(state), "the steps do not loop back on %s" % state)
		if chain.has(state):
			break
		chain.append(state)
		state = _layout["steps"][state]["next"]
	return chain


func _close_rect(actual: Rect2, expected: Array) -> bool:
	return absf(actual.position.x - float(expected[0])) < TOLERANCE \
		and absf(actual.position.y - float(expected[1])) < TOLERANCE \
		and absf(actual.size.x - float(expected[2])) < TOLERANCE \
		and absf(actual.size.y - float(expected[3])) < TOLERANCE


func _strip_rect(strip_name: String) -> Array:
	var rect: Dictionary = _layout["strips"][strip_name]["rect"]
	return [rect["x"], rect["y"], rect["w"], rect["h"]]


func _assert_field(label: Label, field: Dictionary, text: String, what: String) -> void:
	assert_true(label.visible, "%s shows" % what)
	assert_eq(label.text, text, "%s text" % what)
	assert_true(_close_rect(label.get_global_rect(), field["rect"]), "%s sits at %s, not %s" % [what, field["rect"], label.get_global_rect()])
	var size: int = label.get_theme_font_size("font_size")
	assert_almost_eq(float(size), float(field["font_size"]), 0.01, "%s font size" % what)
	assert_true(label.get_theme_color("font_color").is_equal_approx(Color.html(field["color"])), "%s colour" % what)
	var pitch: float = label.get_theme_font("font").get_height(size) + label.get_theme_constant("line_spacing")
	assert_almost_eq(pitch, float(field["line_pitch"]), TOLERANCE, "%s line pitch" % what)
	var regular: Font = ThemeDB.get_project_theme().get_font("font", "RegularLabel")
	assert_eq(label.get_theme_font("font") != regular, bool(field["bold"]), "%s is bold like its SWF font" % what)


# DefineSprite_3142/frame_25/PlaceObject2_3059_675: onClipEvent(load) goes to
# `level` when skillPoints + statPoints > 0.
func test_the_steps_start_when_the_window_opens_with_points() -> void:
	var cases: Array[Array] = [[0, 0, _layout["rest"]], [1, 0, _layout["start"]], [0, 1, _layout["start"]], [2, 3, _layout["start"]]]
	for case: Array in cases:
		GameData.current_save.skill_points = case[0]
		GameData.current_save.stat_points = case[1]
		var window: Control = _window()
		assert_eq(_steps(window).state, case[2], "%d ability and %d attribute points" % [case[0], case[1]])
		assert_eq((window.get_node("HintLabel") as Label).visible, case[2] == _layout["rest"], "the tip shows only at rest")
		window.free()


func test_the_steps_are_the_prompt_then_three_steps_then_a_last_tip() -> void:
	assert_eq(_layout["start"], "level")
	assert_eq(_chain(), ["level", "part1", "part2", "part3", "part4"] as Array[String])


func test_each_step_shows_its_strings_json_text_where_the_swf_places_it() -> void:
	GameData.current_save.skill_points = 1
	var window: Control = _window()
	var steps: HintSteps = _steps(window)
	for state: String in _chain():
		assert_eq(steps.state, state)
		var step: Dictionary = _layout["steps"][state]
		_assert_field(window.get_node("HintSteps/StepLabel"), step["reader_field"], Strings.menu(int(step["reader"])), "%s reader" % state)
		_assert_field(window.get_node("HintSteps/ClickLabel"), step["clicker_field"], Strings.menu(int(step["clicker"])), "%s clicker" % state)
		assert_false((window.get_node("HintLabel") as Label).visible, "%s hides the tip" % state)
		steps.click()


# The prompt and the three steps read MENU[7] to MENU[10], each with
# MENU[11], "< Click Here >", and the last label shows the first tip,
# MENU[43] (DefineSprite_3059/frame_7/DoAction.as,
# DefineSprite_3059/frame_12/DoAction.as, DefineSprite_3059/frame_56/DoAction.as,
# DefineSprite_3059/frame_107/DoAction.as and
# DefineSprite_3059/frame_151/DoAction.as).
func test_the_steps_read_menu_7_to_10_and_the_last_reads_menu_43() -> void:
	var readers: Array[int] = []
	for state: String in _chain():
		readers.append(int(_layout["steps"][state]["reader"]))
		assert_eq(int(_layout["steps"][state]["clicker"]), 11, "%s clicker" % state)
	assert_eq(readers, [7, 8, 9, 10, 43] as Array[int])
	assert_eq(Strings.menu(11), "< Click Here >")


func test_a_click_on_the_box_moves_to_the_next_step_and_the_last_goes_back_to_a_tip() -> void:
	GameData.current_save.skill_points = 1
	var window: Control = _window()
	var steps: HintSteps = _steps(window)
	var button: Button = window.get_node("HintSteps/ClickButton")
	for state: String in _chain():
		assert_eq(steps.state, state)
		assert_true(button.visible, "%s takes clicks" % state)
		assert_true(_close_rect(button.get_global_rect(), _layout["steps"][state]["button"]), "%s click area" % state)
		button.pressed.emit()
		assert_eq(steps.state, _layout["steps"][state]["next"], "a click on %s" % state)
	assert_eq(steps.state, _layout["rest"])
	assert_false(button.visible, "the tip takes no clicks")
	assert_true((window.get_node("HintLabel") as Label).visible, "the tip shows again")
	assert_has([43, 44, 45, 46].map(func(i: int) -> String: return Strings.menu(i)), (window.get_node("HintLabel") as Label).text)


func test_reopening_the_window_starts_the_steps_again() -> void:
	GameData.current_save.skill_points = 1
	var window: Control = _window()
	var steps: HintSteps = _steps(window)
	steps.click()
	steps.click()
	window.hide()
	window.show()
	assert_eq(steps.state, _layout["start"], "the clip loads again on its first step")


# The original places the clip again each time the menu enters the Abilities
# frame, so the box starts again from its first frame even when the window
# closed on a step.
func test_reopening_the_window_on_a_step_starts_the_box_again() -> void:
	GameData.current_save.skill_points = 1
	var window: Control = _window()
	var steps: HintSteps = _steps(window)
	for i in 5:
		steps.advance(1.0 / float(_layout["fps"]))
	assert_eq(steps.box_frame, 6)
	window.hide()
	window.show()
	assert_eq(steps.state, _layout["start"])
	assert_eq(steps.box_frame, 1, "the box starts again from its first frame")


func test_each_step_draws_its_glow_art_at_the_rendered_rect() -> void:
	GameData.current_save.skill_points = 1
	var window: Control = _window()
	var steps: HintSteps = _steps(window)
	var box: TextureRect = window.get_node("HintSteps/BoxArt")
	var pointer: TextureRect = window.get_node("HintSteps/PointerArt")
	for state: String in _chain():
		var step: Dictionary = _layout["steps"][state]
		assert_true(box.visible and box.texture != null, "%s draws the box" % state)
		assert_true(_close_rect(box.get_global_rect(), _strip_rect(step["box"])), "%s box rect" % state)
		if step["pointer"] == null:
			assert_null(pointer.texture, "%s draws no pointer" % state)
		else:
			assert_not_null(pointer.texture, "%s draws the pointer" % state)
			assert_true(_close_rect(pointer.get_global_rect(), _strip_rect(step["pointer"])), "%s pointer rect" % state)
		steps.click()
	assert_false(box.visible, "the tip draws no box")


func test_the_box_plays_on_across_steps_and_the_pointer_loops_its_label() -> void:
	GameData.current_save.skill_points = 1
	var window: Control = _window()
	var steps: HintSteps = _steps(window)
	var frame_time: float = 1.0 / float(_layout["fps"])
	var box_count: int = _layout["strips"][_layout["steps"]["level"]["box"]]["frames"].size()
	assert_eq(steps.box_frame, 1)
	for i in 5:
		steps.advance(frame_time)
	assert_eq(steps.box_frame, 6, "the box steps once a frame")
	steps.click()
	assert_eq(steps.state, "part1")
	assert_eq(steps.box_frame, 6, "the box plays on into the next step")
	assert_eq(steps.pointer_frame, 1, "the pointer starts its loop")
	var pointer_count: int = _layout["strips"][_layout["steps"]["part1"]["pointer"]]["frames"].size()
	for i in pointer_count:
		steps.advance(frame_time)
	assert_eq(steps.pointer_frame, 1, "the pointer loops after its %d frames" % pointer_count)
	assert_eq(steps.box_frame, (5 + pointer_count) % box_count + 1, "the box loops after its %d frames" % box_count)
	var textures: Array = _layout["strips"][_layout["steps"]["part1"]["box"]]["frames"]
	assert_eq((window.get_node("HintSteps/BoxArt") as TextureRect).texture.resource_path, "res://assets/ui/menu/hint_steps/" + textures[steps.box_frame - 1])


func test_the_hint_box_draws_over_the_tree_and_the_ring() -> void:
	var window: Control = _window()
	var index: int = window.get_node("HintSteps").get_index()
	assert_gt(index, window.get_node("TreeNodes").get_index(), "over the tree")
	assert_gt(index, window.get_node("Socket7").get_index(), "over the ring")
	assert_eq(window.get_node("HeldIcon").get_index(), index + 1, "under the held icon only")
