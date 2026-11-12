# The rect test (spec/107-ui-foundation.md, Part 4). It instantiates every
# scene in the record that extract_screen_rects writes
# (dev/urchin_dev/swf/extract/screen_rects.py) and checks where each piece
# lands after the containers lay it out. The control tests break one thing in a
# copy of the test scene each and expect the check to name it.
extends GutTest

const RECORD_PATH: String = "res://test/fixtures/screen_rects.json"
const TEST_SCENE: String = "res://test/fixtures/screen_rects/victory_left_panel.tscn"
const TOLERANCE: float = 0.5
const COLOR_TOLERANCE: float = 0.001


func _record() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(RECORD_PATH)
	return JSON.parse_string(text)


# A piece is a node that draws. Containers and slots only place pieces, so they
# are not pieces of their own.
func _draws(node: Node) -> bool:
	return node is Label or node is PanelContainer or node is TextureRect \
		or node is ColorRect or node is NinePatchRect


# A port only node is skipped with every node under it, so a piece the port
# builds from several nodes needs one name in port_only.
func _drawing_paths(root: Node, port_only: Array) -> Array[String]:
	var found: Array[String] = []
	var queue: Array[Node] = root.get_children()
	while queue:
		var node: Node = queue.pop_front()
		var path: String = str(root.get_path_to(node))
		if port_only.has(path):
			continue
		if _draws(node):
			found.append(path)
		queue.append_array(node.get_children())
	return found


func _close(a: float, b: float) -> bool:
	return absf(a - b) < TOLERANCE


func _same_color(actual: Color, expected: String) -> bool:
	return actual.is_equal_approx(Color.html(expected))


func _rect_problems(path: String, actual: Rect2, expected: Array, with_size: bool) -> Array[String]:
	var found: Array[String] = []
	var start := Vector2(expected[0], expected[1])
	var end := start + Vector2(expected[2], expected[3])
	if not (_close(actual.position.x, start.x) and _close(actual.position.y, start.y)):
		found.append("%s: top left %s, expected %s" % [path, actual.position, start])
	if with_size and not (_close(actual.end.x, end.x) and _close(actual.end.y, end.y)):
		found.append("%s: bottom right %s, expected %s" % [path, actual.end, end])
	return found


func _panel_problems(path: String, panel: PanelContainer, entry: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		found.append("%s: fill: the panel style is not a StyleBoxFlat" % path)
	else:
		if not _same_color(style.bg_color, entry["fill"]):
			found.append("%s: fill %s, expected %s" % [path, style.bg_color.to_html(), entry["fill"]])
		if not _same_color(style.border_color, entry["line"]):
			found.append("%s: stroke colour %s, expected %s" % [path, style.border_color.to_html(), entry["line"]])
		for side: Side in PanelRecipe.SIDES:
			if style.get_border_width(side) != int(entry["border"]):
				found.append("%s: stroke width %d on side %d, expected %d" % [
					path, style.get_border_width(side), side, int(entry["border"])])
	var material: ShaderMaterial = panel.material as ShaderMaterial
	if material != PanelRecipe.SHADOW_MATERIAL:
		found.append("%s: shadow material %s, expected %s" % [
			path, panel.material, PanelRecipe.SHADOW_MATERIAL.resource_path])
	else:
		var shadow: Dictionary = entry["shadow"]
		for parameter: String in shadow:
			var value: float = material.get_shader_parameter(parameter)
			if not is_equal_approx(value, float(shadow[parameter])):
				found.append("%s: shadow %s %s, expected %s" % [path, parameter, value, shadow[parameter]])
	return found


func _text_problems(path: String, label: Label, entry: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var size: int = label.get_theme_font_size("font_size")
	if not is_equal_approx(float(size), float(entry["font_size"])):
		found.append("%s: font size %d, expected %s" % [path, size, entry["font_size"]])
	var color: Color = label.get_theme_color("font_color")
	if not _same_color(color, entry["color"]):
		found.append("%s: font colour %s, expected %s" % [path, color.to_html(), entry["color"]])
	# A Label puts its lines one font height plus its line spacing apart.
	if entry.has("line_pitch"):
		var pitch: float = label.get_theme_font("font").get_height(size) \
			+ label.get_theme_constant("line_spacing")
		if not _close(pitch, float(entry["line_pitch"])):
			found.append("%s: line pitch %s, expected %s" % [path, pitch, entry["line_pitch"]])
	return found


# Returns one message for each way the laid-out scene under `root` differs from
# its record. A Label is checked at its top left only, because a Label is
# taller than the SWF's field (spec Part 2). A Panel is checked at both corners.
func _scene_problems(root: Control, scene: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var pieces: Dictionary = scene["pieces"]
	for path: String in pieces:
		var entry: Dictionary = pieces[path]
		var node: Control = root.get_node_or_null(path) as Control
		if node == null:
			found.append("%s: no such Control in the scene" % path)
			continue
		var actual := Rect2(node.global_position - root.global_position, node.size)
		match entry["kind"]:
			"panel":
				found.append_array(_rect_problems(path, actual, entry["rect"], true))
				if node is PanelContainer:
					found.append_array(_panel_problems(path, node, entry))
				else:
					found.append("%s: a panel piece that is not a PanelContainer" % path)
			"text":
				found.append_array(_rect_problems(path, actual, entry["rect"], false))
				if node is Label:
					found.append_array(_text_problems(path, node, entry))
				else:
					found.append("%s: a text piece that is not a Label" % path)
			"art":
				found.append_array(_rect_problems(path, actual, entry["rect"], true))
				if node is TextureRect:
					var texture: Texture2D = (node as TextureRect).texture
					var texture_path: String = texture.resource_path if texture else "no texture"
					if texture_path != entry["texture"]:
						found.append("%s: texture %s, expected %s" % [path, texture_path, entry["texture"]])
				else:
					found.append("%s: an art piece that is not a TextureRect" % path)
			"hit", "button":
				found.append_array(_rect_problems(path, actual, entry["rect"], true))
				if not node is BaseButton:
					found.append("%s: a %s piece that is not a button" % [path, entry["kind"]])
			_:
				found.append("%s: unknown kind %s" % [path, entry["kind"]])
	for path: String in _drawing_paths(root, scene["port_only"]):
		if not pieces.has(path):
			found.append("%s: draws but is neither in the record nor port only" % path)
	return found


func _laid_out(scene_path: String) -> Control:
	var root: Control = (load(scene_path) as PackedScene).instantiate()
	add_child_autofree(root)
	await wait_process_frames(2)
	return root


func _test_scene_record() -> Dictionary:
	return _record()["scenes"][TEST_SCENE]


# Each control breaks one thing, so exactly one message names it.
func _assert_one_problem(found: Array[String], words: String) -> void:
	assert_eq(found.size(), 1, str(found))
	assert_string_contains(found[0] if found else "", words)


func test_every_scene_in_the_record_lands_where_the_swf_puts_it() -> void:
	var scenes: Dictionary = _record()["scenes"]
	assert_gt(scenes.size(), 0, "the record holds no scene")
	for scene_path: String in scenes:
		var root: Control = await _laid_out(scene_path)
		assert_eq(_scene_problems(root, scenes[scene_path]), [] as Array[String], scene_path)


func test_control_a_panel_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(TEST_SCENE)
	(root.get_node("LeftPanel") as Control).position.x += 20.0
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _test_scene_record())
	assert_eq(found.size(), 3, str(found))
	assert_string_contains(found[0] if found else "", "LeftPanel: top left")


func test_control_a_label_moved_20_px_by_its_container_fails() -> void:
	var root: Control = await _laid_out(TEST_SCENE)
	var panel: PanelContainer = root.get_node("LeftPanel")
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate()
	style.content_margin_top += 20.0
	panel.add_theme_stylebox_override("panel", style)
	await wait_process_frames(2)
	_assert_one_problem(_scene_problems(root, _test_scene_record()), "LeftPanel/Heading: top left")


func _broken_style(root: Control) -> StyleBoxFlat:
	var panel: PanelContainer = root.get_node("LeftPanel")
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate()
	panel.add_theme_stylebox_override("panel", style)
	return style


func test_control_a_wrong_fill_fails() -> void:
	var root: Control = await _laid_out(TEST_SCENE)
	_broken_style(root).bg_color = Color(0.3, 0.3, 0.3)
	_assert_one_problem(_scene_problems(root, _test_scene_record()), "fill")


func test_control_a_wrong_stroke_colour_fails() -> void:
	var root: Control = await _laid_out(TEST_SCENE)
	_broken_style(root).border_color = Color.WHITE
	_assert_one_problem(_scene_problems(root, _test_scene_record()), "stroke colour")


func test_control_a_wrong_stroke_width_fails() -> void:
	var root: Control = await _laid_out(TEST_SCENE)
	_broken_style(root).border_width_left = 2
	_assert_one_problem(_scene_problems(root, _test_scene_record()), "stroke width")


func test_control_no_shadow_material_fails() -> void:
	var root: Control = await _laid_out(TEST_SCENE)
	(root.get_node("LeftPanel") as Control).material = null
	_assert_one_problem(_scene_problems(root, _test_scene_record()), "shadow material")


# The shared material is one resource for every Panel, so this control changes
# the record instead. It stands for a SWF Panel whose shadow differs from the
# shared material.
func test_control_a_shadow_other_than_the_shared_one_fails() -> void:
	var root: Control = await _laid_out(TEST_SCENE)
	var scene: Dictionary = _test_scene_record()
	scene["pieces"]["LeftPanel"]["shadow"]["blur"] = 4.0
	_assert_one_problem(_scene_problems(root, scene), "LeftPanel: shadow blur")


func test_control_a_wrong_font_size_fails() -> void:
	var root: Control = await _laid_out(TEST_SCENE)
	(root.get_node("LeftPanel/Heading") as Label).add_theme_font_size_override("font_size", 12)
	await wait_process_frames(2)
	_assert_one_problem(_scene_problems(root, _test_scene_record()), "font size")


func test_control_a_wrong_font_colour_fails() -> void:
	var root: Control = await _laid_out(TEST_SCENE)
	(root.get_node("LeftPanel/Heading") as Label).add_theme_color_override("font_color", Color.WHITE)
	_assert_one_problem(_scene_problems(root, _test_scene_record()), "font colour")


func test_control_an_unrecorded_piece_fails_and_a_port_only_one_passes() -> void:
	var root: Control = await _laid_out(TEST_SCENE)
	var extra := ColorRect.new()
	extra.name = "Extra"
	root.add_child(extra)
	var scene: Dictionary = _test_scene_record()
	_assert_one_problem(_scene_problems(root, scene), "Extra: draws")
	scene["port_only"] = ["Extra"]
	assert_eq(_scene_problems(root, scene), [] as Array[String])


const SHELL_SCENE: String = "res://scenes/ui/window/window_shell.tscn"


func _shell_record() -> Dictionary:
	return _record()["scenes"][SHELL_SCENE]


func test_control_a_shell_piece_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(SHELL_SCENE)
	(root.get_node("CloseArt") as Control).position.x += 20.0
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _shell_record())
	assert_eq(found.size(), 2, str(found))
	assert_string_contains(found[0] if found else "", "CloseArt: top left")


func test_control_a_hit_button_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(SHELL_SCENE)
	(root.get_node("CloseButton") as Control).position.y += 20.0
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _shell_record())
	assert_eq(found.size(), 2, str(found))
	assert_string_contains(found[0] if found else "", "CloseButton: top left")


func test_control_the_wrong_art_fails() -> void:
	var root: Control = await _laid_out(SHELL_SCENE)
	(root.get_node("CloseArt") as TextureRect).texture = (root.get_node("Backdrop") as TextureRect).texture
	_assert_one_problem(_scene_problems(root, _shell_record()), "CloseArt: texture")


func test_control_a_port_only_node_also_skips_the_nodes_under_it() -> void:
	var root: Control = await _laid_out(TEST_SCENE)
	var extra := Control.new()
	extra.name = "Extra"
	var inner := ColorRect.new()
	inner.name = "Inner"
	extra.add_child(inner)
	root.add_child(extra)
	var scene: Dictionary = _test_scene_record()
	_assert_one_problem(_scene_problems(root, scene), "Extra/Inner: draws")
	scene["port_only"] = ["Extra"]
	assert_eq(_scene_problems(root, scene), [] as Array[String])


const ABILITIES_SCENE: String = "res://scenes/ui/menu/abilities_window.tscn"


# A taller Instinct slot pushes the Speed row 20 px down its FloatBox column, so
# the row's name and value both fail.
func test_control_an_attribute_row_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(ABILITIES_SCENE)
	var slot: Control = root.get_node("AttributeRows/InstinctRow")
	slot.custom_minimum_size.y += 20.0
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _record()["scenes"][ABILITIES_SCENE])
	assert_eq(found.size(), 2, str(found))
	for problem: String in found:
		assert_string_contains(problem, "AttributeRows/SpeedRow/")
		assert_string_contains(problem, "top left")


func test_control_a_wrapping_label_with_the_wrong_line_pitch_fails() -> void:
	var root: Control = await _laid_out(ABILITIES_SCENE)
	var hint: Label = root.get_node("HintLabel")
	hint.add_theme_constant_override("line_spacing", hint.get_theme_constant("line_spacing") + 3)
	_assert_one_problem(_scene_problems(root, _record()["scenes"][ABILITIES_SCENE]), "HintLabel: line pitch")
