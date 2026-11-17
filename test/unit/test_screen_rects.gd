# The rect test (spec/107-ui-foundation.md, Part 4). It instantiates every
# scene in the record that extract_screen_rects writes
# (dev/urchin_dev/swf/extract/screen_rects.py) and checks where each piece
# lands after the containers lay it out. The control tests break one thing in a
# copy of the test scene each and expect the check to name it.
extends GutTest

const RECORD_PATH: String = "res://test/fixtures/screen_rects.json"
const TEST_SCENE: String = "res://test/fixtures/screen_rects/victory_left_panel.tscn"
const TOLERANCE: float = 0.5

var _save_before: PlayerSave


# The record holds each scene as its .tscn places it. A scene that sizes a
# piece from the save, as the hotbar sizes the zone fill, only shows that state
# with no save, and an earlier test script can leave one behind.
func before_each() -> void:
	_save_before = GameData.current_save
	GameData.current_save = null


func after_each() -> void:
	GameData.current_save = _save_before


func _record() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(RECORD_PATH)
	return JSON.parse_string(text)


# A piece is a node that draws. Containers and plain Controls only place pieces,
# so they are not pieces of their own. Every other CanvasItem counts, so a class
# that nobody listed here, such as a Button or a RichTextLabel, still has to be in
# the record or port only. A script that extends Control keeps the class name
# "Control", so it is still a plain Control.
func _draws(node: Node) -> bool:
	return node is CanvasItem and not node is Container and node.get_class() != "Control"


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
		for problem: String in PanelRecipe.edge_problems(style):
			found.append("%s: %s" % [path, problem])
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


func _outline_problems(path: String, panel: Panel, entry: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return ["%s: outline is not a StyleBoxFlat" % path]
	if style.draw_center:
		found.append("%s: outline has a fill" % path)
	if style.shadow_size != 0 or panel.material != null:
		found.append("%s: outline has a shadow" % path)
	if not _same_color(style.border_color, entry["line"]):
		found.append("%s: outline stroke colour" % path)
	for side: Side in PanelRecipe.SIDES:
		if style.get_border_width(side) != int(entry["border"]):
			found.append("%s: outline stroke width" % path)
	for problem: String in PanelRecipe.edge_problems(style):
		found.append("%s: %s" % [path, problem])
	return found


# CODING_STANDARDS.md names `rect * zoom == PNG pixel size` as the invariant that
# holds across all the extracted art. The record holds the PNG's size and zoom, so
# this checks the rect against them and the texture against the size.
func _art_size_problems(path: String, texture: Texture2D, entry: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var size := Vector2(entry["size"][0], entry["size"][1])
	var zoomed := Vector2(entry["rect"][2], entry["rect"][3]) * float(entry["zoom"])
	if not zoomed.is_equal_approx(size):
		found.append("%s: rect times zoom %s, expected the PNG size %s" % [path, zoomed, size])
	var actual: Vector2 = texture.get_size() if texture else Vector2.ZERO
	if not actual.is_equal_approx(size):
		found.append("%s: texture size %s, expected %s" % [path, actual, size])
	return found


const ALIGNMENTS: Dictionary = {
	"left": HORIZONTAL_ALIGNMENT_LEFT,
	"center": HORIZONTAL_ALIGNMENT_CENTER,
	"right": HORIZONTAL_ALIGNMENT_RIGHT,
	"justify": HORIZONTAL_ALIGNMENT_FILL,
}


func _text_problems(path: String, label: Label, entry: Dictionary) -> Array[String]:
	var found: Array[String] = []
	if label.horizontal_alignment != ALIGNMENTS[entry["align"]]:
		found.append("%s: alignment %d, expected %s" % [path, label.horizontal_alignment, entry["align"]])
	# Only a field of static text has a text in the record. The game fills the rest.
	if entry.has("text") and label.text != entry["text"]:
		found.append("%s: text '%s', expected '%s'" % [path, label.text, entry["text"]])
	var size: int = label.get_theme_font_size("font_size")
	if not is_equal_approx(float(size), float(entry["font_size"])):
		found.append("%s: font size %d, expected %s" % [path, size, entry["font_size"]])
	var color: Color = label.get_theme_color("font_color")
	if not _same_color(color, entry["color"]):
		found.append("%s: font colour %s, expected %s" % [path, color.to_html(), entry["color"]])
	# A centred or right-aligned Label places its text from its right edge too,
	# so a wrong width moves the text. A Label also grows past its offsets when
	# its text is wider than the field.
	if label.horizontal_alignment != HORIZONTAL_ALIGNMENT_LEFT:
		var right: float = label.global_position.x + label.size.x
		var expected_right: float = float(entry["rect"][0]) + float(entry["rect"][2])
		if not _close(right, expected_right):
			found.append("%s: right edge %s, expected %s" % [path, right, expected_right])
	# A Label puts its lines one font height plus its line spacing apart.
	if entry.has("line_pitch"):
		var pitch: float = label.get_theme_font("font").get_height(size) \
			+ label.get_theme_constant("line_spacing")
		if not _close(pitch, float(entry["line_pitch"])):
			found.append("%s: line pitch %s, expected %s" % [path, pitch, entry["line_pitch"]])
	# A Label's shadow offsets are whole px and it can't blur its shadow, so the
	# offsets are the SWF's rounded and the blur is not checked.
	if entry.has("shadow"):
		var shadow: Dictionary = entry["shadow"]
		var shadow_color: Color = label.get_theme_color("font_shadow_color")
		if not _same_color(shadow_color, shadow["color"]):
			found.append("%s: shadow colour %s, expected %s" % [path, shadow_color.to_html(), shadow["color"]])
		var offset := Vector2i(label.get_theme_constant("shadow_offset_x"), label.get_theme_constant("shadow_offset_y"))
		var expected := Vector2i(roundi(shadow["offset"][0]), roundi(shadow["offset"][1]))
		if offset != expected:
			found.append("%s: shadow offset %s, expected %s" % [path, offset, expected])
	return found


# A doll is a CharacterVisual, whose art is a set of rotated and scaled parts, so
# no rect holds it. The record holds the position and scale that put it where the
# SWF's 31 part clips sit, and the union rect of the art of the unequipped male
# doll. The union rect is held to 1 px and not 0.5. The record's rect is the art
# under the SWF's placements, and the port draws the rig's REST_POSE, which has
# the same part origins as the SWF's pose but not every part's scale and
# rotation, so its art reaches 0.9 to 1 px less far on the left and on the right.
const DOLL_TOLERANCE: float = 1.0


func _doll_problems(root: Control, path: String, entry: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var doll: CharacterVisual = root.get_node_or_null(path) as CharacterVisual
	if doll == null:
		return ["%s: no such CharacterVisual in the scene" % path]
	var position := Vector2(entry["position"][0], entry["position"][1])
	if not (_close(doll.global_position.x, position.x) and _close(doll.global_position.y, position.y)):
		found.append("%s: position %s, expected %s" % [path, doll.global_position, position])
	var scale := Vector2(entry["scale"][0], entry["scale"][1])
	if not doll.scale.is_equal_approx(scale):
		found.append("%s: scale %s, expected %s" % [path, doll.scale, scale])
	var look: Dictionary = entry["look"]
	doll.dress(look["gender"], look["skin"], look["hair"], ["", "", "", "", "", "", ""])
	var bounds: Rect2 = (doll.get_parent() as CanvasItem).get_global_transform() * doll.get_bounds()
	var rect: Array = entry["rect"]
	var expected := Rect2(rect[0], rect[1], rect[2], rect[3])
	var corners: Array[float] = [
		bounds.position.x - expected.position.x, bounds.position.y - expected.position.y,
		bounds.end.x - expected.end.x, bounds.end.y - expected.end.y]
	for off: float in corners:
		if absf(off) > DOLL_TOLERANCE:
			found.append("%s: union rect %s, expected %s" % [path, bounds, expected])
			break
	return found


# Returns one message for each way the laid-out scene under `root` differs from
# its record. A Label is checked at its top left, and at its right edge when its
# text is not left-aligned. Its bottom is not checked, because a Label is taller
# than the SWF's field (spec Part 2). A Panel is checked at both corners.
func _scene_problems(root: Control, scene: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var pieces: Dictionary = scene["pieces"]
	for path: String in pieces:
		var entry: Dictionary = pieces[path]
		if entry["kind"] == "doll":
			found.append_array(_doll_problems(root, path, entry))
			continue
		if entry["kind"] == "point":
			var point: Node2D = root.get_node_or_null(path) as Node2D
			if point == null:
				found.append("%s: no such Node2D" % path)
			else:
				var expected := Vector2(entry["position"][0], entry["position"][1])
				if not (_close(point.global_position.x, expected.x) and _close(point.global_position.y, expected.y)):
					found.append("%s: position %s, expected %s" % [path, point.global_position, expected])
				if not point.scale.is_equal_approx(Vector2(entry["scale"][0], entry["scale"][1])):
					found.append("%s: scale differs" % path)
			continue
		var node: Control = root.get_node_or_null(path) as Control
		if node == null:
			found.append("%s: no such Control in the scene" % path)
			continue
		# The record holds Stage positions. A scene such as right_column.tscn
		# puts its root where the SWF puts the piece, so the root's own
		# position counts.
		var actual := node.get_global_rect()
		match entry["kind"]:
			"outline":
				found.append_array(_rect_problems(path, actual, entry["rect"], true))
				if node is Panel:
					found.append_array(_outline_problems(path, node, entry))
				else:
					found.append("%s: an outline piece that is not a Panel" % path)
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
					found.append_array(_art_size_problems(path, texture, entry))
				else:
					found.append("%s: an art piece that is not a TextureRect" % path)
			"art_set":
				# The piece shows one PNG of the set at a time, all of one size.
				found.append_array(_rect_problems(path, actual, entry["rect"], true))
				if node is TextureRect:
					var texture: Texture2D = (node as TextureRect).texture
					var texture_path: String = texture.resource_path if texture else "no texture"
					if not entry["textures"].has(texture_path):
						found.append("%s: texture %s, expected one of %s" % [path, texture_path, entry["textures"]])
					found.append_array(_art_size_problems(path, texture, entry))
				else:
					found.append("%s: an art_set piece that is not a TextureRect" % path)
			"face":
				# A face shows a different PNG for each fighter, so there is no
				# texture to compare.
				found.append_array(_rect_problems(path, actual, entry["rect"], true))
				if not node is TextureRect:
					found.append("%s: a face piece that is not a TextureRect" % path)
			"box":
				found.append_array(_rect_problems(path, actual, entry["rect"], true))
				if node is ColorRect:
					if not _same_color((node as ColorRect).color, entry["fill"]):
						found.append("%s: fill %s, expected %s" % [path, (node as ColorRect).color.to_html(), entry["fill"]])
				else:
					found.append("%s: a box piece that is not a ColorRect" % path)
			"shape":
				found.append_array(_rect_problems(path, actual, entry["rect"], true))
			"hit", "button":
				found.append_array(_rect_problems(path, actual, entry["rect"], true))
				# An orb takes its clicks through a plain Control (orb_base.gd), so
				# its hit piece is the one that does not have to be a button.
				if not (node is BaseButton or node.get_parent() is OrbBase):
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
	# The Panel fails at both corners. The centred Heading fails at its top left
	# and at its right edge.
	var found: Array[String] = _scene_problems(root, _test_scene_record())
	assert_eq(found.size(), 4, str(found))
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


func test_control_a_rounded_corner_fails() -> void:
	var root: Control = await _laid_out(TEST_SCENE)
	_broken_style(root).corner_radius_top_left = 4
	_assert_one_problem(_scene_problems(root, _test_scene_record()), "LeftPanel: corners")


func test_control_anti_aliasing_on_fails() -> void:
	var root: Control = await _laid_out(TEST_SCENE)
	_broken_style(root).anti_aliasing = true
	_assert_one_problem(_scene_problems(root, _test_scene_record()), "LeftPanel: anti_aliasing")


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


# The Heading is edit text 2996, align 2, so it is centred in the SWF.
func test_control_a_centred_field_drawn_left_aligned_fails() -> void:
	var root: Control = await _laid_out(TEST_SCENE)
	var heading: Label = root.get_node("LeftPanel/Heading")
	assert_eq(heading.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "the scene centres its Heading")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _test_scene_record())
	assert_gt(found.size(), 0, "a left-aligned Heading passed")
	assert_string_contains(found[0] if found else "", "LeftPanel/Heading: alignment")


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


func test_control_a_hit_piece_that_is_a_plain_control_fails() -> void:
	var root: Control = await _laid_out(SHELL_SCENE)
	var button: Control = root.get_node("CloseButton")
	var plain := Control.new()
	plain.position = button.position
	plain.size = button.size
	var parent: Node = button.get_parent()
	var index: int = button.get_index()
	parent.remove_child(button)
	button.free()
	plain.name = "CloseButton"
	parent.add_child(plain)
	parent.move_child(plain, index)
	_assert_one_problem(_scene_problems(root, _shell_record()), "CloseButton: a hit piece that is not a button")


func test_control_the_wrong_art_fails() -> void:
	var root: Control = await _laid_out(SHELL_SCENE)
	(root.get_node("CloseArt") as TextureRect).texture = (root.get_node("Backdrop") as TextureRect).texture
	# The backdrop is also not the close button's size, so the size check fails too.
	var found: Array[String] = _scene_problems(root, _shell_record())
	assert_eq(found.size(), 2, str(found))
	assert_string_contains(found[0] if found else "", "CloseArt: texture res://")
	assert_string_contains(found[1] if found else "", "CloseArt: texture size")


# _draws once knew only five classes, so a probe that added each of these to the
# test scene got no problem back (#271, from the re-review of #208).
func test_control_an_unrecorded_node_of_any_drawing_class_fails() -> void:
	var drawing: Array[Control] = [
		Button.new(), TextureButton.new(), Panel.new(), RichTextLabel.new(), LineEdit.new(),
	]
	for extra: Control in drawing:
		var root: Control = await _laid_out(TEST_SCENE)
		extra.name = "Extra"
		root.add_child(extra)
		_assert_one_problem(_scene_problems(root, _test_scene_record()), "Extra: draws")


func test_control_a_container_and_a_plain_control_are_not_drawing_nodes() -> void:
	var root: Control = await _laid_out(TEST_SCENE)
	root.add_child(Control.new())
	root.add_child(FloatBox.new())
	root.add_child(MarginContainer.new())
	assert_eq(_scene_problems(root, _test_scene_record()), [] as Array[String])


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


const RIGHT_COLUMN_SCENE: String = "res://scenes/ui/window/right_column.tscn"


# A slot in row 2 that is 20 px wider pushes the five slots after it 20 px
# right along the row's FloatBox. The wide slot fails at its bottom right, and
# each of the five fails at both corners, so there are 11 problems, all in row 2.
func test_control_a_right_column_slot_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(RIGHT_COLUMN_SCENE)
	(root.get_node("Grid/Row2/Slot0") as Control).custom_minimum_size.x += 20.0
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _record()["scenes"][RIGHT_COLUMN_SCENE])
	assert_eq(found.size(), 11, str(found))
	for problem: String in found:
		assert_string_starts_with(problem, "Grid/Row2/Slot")
	assert_string_starts_with(found[0] if found else "", "Grid/Row2/Slot0: bottom right")


# The Title is centred, so a field 20 px too wide moves its text 10 px right
# while its top left stays where the SWF puts it.
func test_control_a_centred_label_20_px_too_wide_fails() -> void:
	var root: Control = await _laid_out(RIGHT_COLUMN_SCENE)
	(root.get_node("Title") as Label).offset_right += 20.0
	await wait_process_frames(2)
	_assert_one_problem(_scene_problems(root, _record()["scenes"][RIGHT_COLUMN_SCENE]), "Title: right edge")


func test_control_a_left_aligned_label_20_px_too_wide_passes() -> void:
	var root: Control = await _laid_out(RIGHT_COLUMN_SCENE)
	(root.get_node("Amount") as Label).offset_right += 20.0
	await wait_process_frames(2)
	assert_eq(_scene_problems(root, _record()["scenes"][RIGHT_COLUMN_SCENE]), [] as Array[String])


const VICTORY_SCENE: String = "res://scenes/battle/victory_screen.tscn"


# The Face's rect comes from where extract_faces cuts its portraits in clip 2978
# and where the row places that clip, not from numbers typed in the scene (#271,
# from the re-review of #239).
func test_control_a_victory_row_face_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(VICTORY_SCENE)
	(root.get_node("ExpRows/PlayerSlot/Row/Face") as Control).position.x += 20.0
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _record()["scenes"][VICTORY_SCENE])
	assert_eq(found.size(), 2, str(found))
	assert_string_contains(found[0] if found else "", "PlayerSlot/Row/Face: top left")


func test_the_victory_row_face_is_not_port_only() -> void:
	var scene: Dictionary = _record()["scenes"][VICTORY_SCENE]
	assert_does_not_have(scene["port_only"], "ExpRows/PlayerSlot/Row/Face")
	assert_eq(scene["pieces"]["ExpRows/PlayerSlot/Row/Face"]["kind"], "face")


# The record says the CloseArt PNG is 148 by 146 at zoom 4, so its rect is 37 by
# 36.5. A rect 5 px wider no longer matches the PNG.
func test_control_an_art_rect_that_is_not_the_png_size_over_the_zoom_fails() -> void:
	var root: Control = await _laid_out(SHELL_SCENE)
	var scene: Dictionary = _shell_record()
	scene["pieces"]["CloseArt"]["rect"][2] += 5.0
	var found: Array[String] = _scene_problems(root, scene)
	assert_eq(found.size(), 2, str(found))
	assert_string_contains(found[0] if found else "", "CloseArt: bottom right")
	assert_string_contains(found[1] if found else "", "CloseArt: rect times zoom")


# The record's rect and size agree with each other here, so only the PNG on disk
# is wrong: it stands for an art file that a run of the extractor left at another
# size.
func test_control_a_png_that_is_not_the_recorded_size_fails() -> void:
	var root: Control = await _laid_out(SHELL_SCENE)
	var scene: Dictionary = _shell_record()
	var piece: Dictionary = scene["pieces"]["CloseArt"]
	piece["size"] = [152, 146]
	piece["rect"][2] = 152.0 / float(piece["zoom"])
	var found: Array[String] = _scene_problems(root, scene)
	assert_eq(found.size(), 2, str(found))
	assert_string_contains(found[0] if found else "", "CloseArt: bottom right")
	assert_string_contains(found[1] if found else "", "CloseArt: texture size")


# The euro sign is static text in the SWF (edit text 2861), so the record holds
# its character and the Label has to show it.
func test_control_a_label_with_other_text_than_the_static_field_fails() -> void:
	var root: Control = await _laid_out(RIGHT_COLUMN_SCENE)
	(root.get_node("EuroSign") as Label).text = "$"
	_assert_one_problem(_scene_problems(root, _record()["scenes"][RIGHT_COLUMN_SCENE]), "EuroSign: text")


func test_the_record_holds_the_text_of_static_fields_only() -> void:
	var pieces: Dictionary = _record()["scenes"][RIGHT_COLUMN_SCENE]["pieces"]
	assert_true(pieces["EuroSign"].has("text"), "the euro sign is static text")
	assert_false(pieces["Amount"].has("text"), "the game fills the amount")


const TITLE_SCENE: String = "res://scenes/ui/menu/title_panel.tscn"


# A menu hit button draws nothing, so only this test can see one move.
func test_control_a_title_hit_button_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(TITLE_SCENE)
	(root.get_node("Captions/PlaySlot/HitButton") as Control).position.x += 20.0
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _record()["scenes"][TITLE_SCENE])
	assert_eq(found.size(), 2, str(found))
	assert_string_contains(found[0] if found else "", "Captions/PlaySlot/HitButton: top left")


# A taller Play slot pushes the two slots after it 20 px down the FloatBox
# column, so the caption and the hit button of each fail at their top left, and
# each hit button at its bottom right too.
func test_control_a_title_slot_20_px_taller_fails() -> void:
	var root: Control = await _laid_out(TITLE_SCENE)
	(root.get_node("Captions/PlaySlot") as Control).custom_minimum_size.y += 20.0
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _record()["scenes"][TITLE_SCENE])
	assert_eq(found.size(), 6, str(found))
	for problem: String in found:
		assert_false(problem.contains("PlaySlot"), problem)


const HOTBAR_SCENE: String = "res://scenes/ui/hotbar.tscn"


func test_control_each_zone_text_slot_moved_20_px_fails() -> void:
	for slot: String in ["ZoneTitleSlot", "ZoneSubtitleSlot", "StageSlot"]:
		var root: Control = await _laid_out(HOTBAR_SCENE)
		(root.get_node(slot) as Control).position.y += 20.0
		await wait_process_frames(2)
		var found: Array[String] = _scene_problems(root, _record()["scenes"][HOTBAR_SCENE])
		_assert_one_problem(found, slot + "/")
		assert_string_contains(found[0] if found else "", "top left")


# A slot holds its square, its icon and its hit button, so each of the three
# fails at both corners. The slot's Glow is port only.
func test_control_a_hotbar_slot_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(HOTBAR_SCENE)
	(root.get_node("SaveSlot") as Control).position.x += 20.0
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _record()["scenes"][HOTBAR_SCENE])
	assert_eq(found.size(), 6, str(found))
	for problem: String in found:
		assert_string_starts_with(problem, "SaveSlot/")


# The hit button is smaller than the square's art, which holds the Glows around
# the square, so only this test can see the hit button move.
func test_control_a_hotbar_hit_button_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(HOTBAR_SCENE)
	(root.get_node("%ZoneMapButton") as Control).position.y += 20.0
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _record()["scenes"][HOTBAR_SCENE])
	assert_eq(found.size(), 2, str(found))
	assert_string_contains(found[0] if found else "", "ZoneMapSlot/ZoneMapButton: top left")


# The zone fill is a plain Control on the fill's shape with the fill's art
# under it, so the shape and the art each fail at both corners.
func test_control_the_zone_fill_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(HOTBAR_SCENE)
	(root.get_node("ZoneFill") as Control).position.x += 20.0
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _record()["scenes"][HOTBAR_SCENE])
	assert_eq(found.size(), 4, str(found))
	for problem: String in found:
		assert_string_starts_with(problem, "ZoneFill")


const MODE_SCENE: String = "res://scenes/ui/menu/mode_panel.tscn"


# A New Game slot 20 px taller breaks the 60 px pitch of the choice, so Load
# Game's caption fails at its top left and its hit button at both corners.
func test_control_a_choice_slot_20_px_taller_fails() -> void:
	var root: Control = await _laid_out(MODE_SCENE)
	(root.get_node("Captions/NewGameSlot") as Control).custom_minimum_size.y += 20.0
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _record()["scenes"][MODE_SCENE])
	assert_eq(found.size(), 3, str(found))
	for problem: String in found:
		assert_string_contains(problem, "Captions/LoadGameSlot")


const SLOT_SCENE: String = "res://scenes/ui/menu/slot_panel.tscn"


# A menu hit button draws nothing, so only this test can see one move.
func test_control_a_slot_hit_button_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(SLOT_SCENE)
	(root.get_node("Rows/Row2/HitButton") as Control).position.x += 20.0
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _record()["scenes"][SLOT_SCENE])
	assert_eq(found.size(), 2, str(found))
	for problem: String in found:
		assert_string_contains(problem, "Rows/Row2/HitButton")


# The row pitches are 54, 57 and 54 px. A first row as tall as the second
# moves the three rows under it 3 px down, so each of their four pieces fails
# at its top left, each hit button at its bottom right too.
func test_control_a_slot_row_with_the_wrong_pitch_fails() -> void:
	var root: Control = await _laid_out(SLOT_SCENE)
	var rows: Control = root.get_node("Rows")
	(rows.get_node("Row1") as Control).custom_minimum_size.y = (rows.get_node("Row2") as Control).custom_minimum_size.y
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _record()["scenes"][SLOT_SCENE])
	assert_eq(found.size(), 15, str(found))
	for problem: String in found:
		assert_false(problem.contains("Row1"), problem)


const INVENTORY_SCENE: String = "res://scenes/ui/menu/inventory_window.tscn"


func test_control_an_inventory_header_row_20_px_taller_fails() -> void:
	var root: Control = await _laid_out(INVENTORY_SCENE)
	(root.get_node("LeftPanel/Content/Header/NameRow") as Control).custom_minimum_size.y += 20.0
	await wait_process_frames(2)
	_assert_one_problem(_scene_problems(root, _record()["scenes"][INVENTORY_SCENE]), "InfoRow/LevelLabel: top left")


func test_control_an_inventory_outline_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(INVENTORY_SCENE)
	(root.get_node("CenterPanel/Content/StatsOutline") as Control).position.x += 20.0
	var found: Array[String] = _scene_problems(root, _record()["scenes"][INVENTORY_SCENE])
	assert_eq(found.size(), 2, str(found))
	for problem: String in found:
		assert_string_starts_with(problem, "CenterPanel/Content/StatsOutline:")


func test_control_an_inventory_defense_outline_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(INVENTORY_SCENE)
	(root.get_node("CenterPanel/Content/DefenseOutline") as Control).position.y += 20.0
	var found: Array[String] = _scene_problems(root, _record()["scenes"][INVENTORY_SCENE])
	assert_eq(found.size(), 2, str(found))
	for problem: String in found:
		assert_string_starts_with(problem, "CenterPanel/Content/DefenseOutline:")


func test_control_an_inventory_element_bar_layer_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(INVENTORY_SCENE)
	(root.get_node("PerBars/Bars/Bar3/Gbar") as Control).position.x += 20.0
	var found: Array[String] = _scene_problems(root, _record()["scenes"][INVENTORY_SCENE])
	assert_eq(found.size(), 2, str(found))
	for problem: String in found:
		assert_string_starts_with(problem, "PerBars/Bars/Bar3/Gbar:")


func test_control_a_defense_bar_row_with_the_wrong_pitch_fails() -> void:
	var root: Control = await _laid_out(INVENTORY_SCENE)
	(root.get_node("DefBars/Bars") as FloatBox).separation += 2.0
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _record()["scenes"][INVENTORY_SCENE])
	assert_gt(found.size(), 0, "a pitch of 20 instead of 18 moves the bars after the first")
	for problem: String in found:
		assert_string_starts_with(problem, "DefBars/Bars/Bar")


func test_control_an_inventory_bar_shade_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(INVENTORY_SCENE)
	(root.get_node("PerBars/Shade") as Control).position.y += 20.0
	var found: Array[String] = _scene_problems(root, _record()["scenes"][INVENTORY_SCENE])
	assert_eq(found.size(), 2, str(found))
	for problem: String in found:
		assert_string_starts_with(problem, "PerBars/Shade:")


func test_control_a_party_face_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(INVENTORY_SCENE)
	(root.get_node("PartyFaces/Face2/Parts/Face") as Control).position.y += 20.0
	var found: Array[String] = _scene_problems(root, _record()["scenes"][INVENTORY_SCENE])
	assert_eq(found.size(), 2, str(found))
	for problem: String in found:
		assert_string_starts_with(problem, "PartyFaces/Face2/Parts/Face:")


func test_control_a_party_bar_with_the_wrong_pitch_fails() -> void:
	var root: Control = await _laid_out(INVENTORY_SCENE)
	(root.get_node("PartyFaces") as FloatBox).separation += 2.0
	await wait_process_frames(2)
	var found: Array[String] = _scene_problems(root, _record()["scenes"][INVENTORY_SCENE])
	assert_gt(found.size(), 0, "a pitch of 42 instead of 40 moves the faces after the first")
	for problem: String in found:
		assert_string_starts_with(problem, "PartyFaces/Face")
		assert_false(problem.begins_with("PartyFaces/Face0/"), problem)


func test_the_inventory_has_six_party_faces_with_five_parts_each() -> void:
	var pieces: Dictionary = _record()["scenes"][INVENTORY_SCENE]["pieces"]
	for n in 6:
		for node: String in ["Backing", "Face", "Blacker", "HitButton", "Frame"]:
			assert_true(pieces.has("PartyFaces/Face%d/Parts/%s" % [n, node]), "face %d %s" % [n, node])


func test_the_inventory_has_sixteen_bars_with_a_track_and_four_layers_each() -> void:
	var pieces: Dictionary = _record()["scenes"][INVENTORY_SCENE]["pieces"]
	for block: String in ["PerBars", "DefBars"]:
		for k in 8:
			for node: String in ["Track", "Ybar", "Bar", "Gbar", "Xbar"]:
				assert_true(pieces.has("%s/Bars/Bar%d/%s" % [block, k, node]), "%s bar %d %s" % [block, k, node])
		assert_true(pieces.has("%s/Shade" % block))


func test_the_inventory_centre_column_has_three_outline_boxes_one_above_the_other() -> void:
	var pieces: Dictionary = _record()["scenes"][INVENTORY_SCENE]["pieces"]
	var tops: Array[float] = []
	for path: String in pieces:
		if path.begins_with("CenterPanel/Content/") and pieces[path]["kind"] == "outline":
			tops.append(pieces[path]["rect"][1])
	tops.sort()
	assert_eq(tops.size(), 3, "stats, Piercing and Defense")
	if tops.size() == 3:
		assert_lt(tops[0], tops[1])
		assert_lt(tops[1], tops[2])


func test_control_an_inventory_equip_slot_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(INVENTORY_SCENE)
	(root.get_node("LeftPanel/Content/EquipDollView/Slot0") as Control).position.x += 20.0
	var found: Array[String] = _scene_problems(root, _record()["scenes"][INVENTORY_SCENE])
	assert_eq(found.size(), 2, str(found))
	for problem: String in found:
		assert_string_starts_with(problem, "LeftPanel/Content/EquipDollView/Slot0:")


const INVENTORY_DOLL: String = "LeftPanel/Content/EquipDollView/Doll"


func test_control_an_inventory_doll_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(INVENTORY_SCENE)
	(root.get_node(INVENTORY_DOLL) as Node2D).position.x += 20.0
	var found: Array[String] = _scene_problems(root, _record()["scenes"][INVENTORY_SCENE])
	assert_eq(found.size(), 2, str(found))
	for problem: String in found:
		assert_string_starts_with(problem, INVENTORY_DOLL + ":")


func test_control_an_inventory_doll_facing_the_other_way_fails() -> void:
	var root: Control = await _laid_out(INVENTORY_SCENE)
	(root.get_node(INVENTORY_DOLL) as Node2D).scale.x *= -1.0
	var found: Array[String] = _scene_problems(root, _record()["scenes"][INVENTORY_SCENE])
	assert_gt(found.size(), 0)
	assert_string_contains(found[0] if found else "", "scale")


func test_control_an_inventory_doll_10_percent_too_wide_fails() -> void:
	var root: Control = await _laid_out(INVENTORY_SCENE)
	(root.get_node(INVENTORY_DOLL) as Node2D).scale.x *= 1.1
	var found: Array[String] = _scene_problems(root, _record()["scenes"][INVENTORY_SCENE])
	assert_gt(found.size(), 0)


func test_control_an_inventory_experience_fill_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(INVENTORY_SCENE)
	(root.get_node("ExpFill") as Control).position.x += 20.0
	var found: Array[String] = _scene_problems(root, _record()["scenes"][INVENTORY_SCENE])
	assert_eq(found.size(), 2, str(found))
	for problem: String in found:
		assert_string_starts_with(problem, "ExpFill:")


func test_control_an_inventory_stat_row_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(INVENTORY_SCENE)
	(root.get_node("CenterPanel/Content/StatNames/Row2/Label") as Control).position.y += 20.0
	var found: Array[String] = _scene_problems(root, _record()["scenes"][INVENTORY_SCENE])
	assert_eq(found.size(), 1, str(found))
	for problem: String in found:
		assert_string_starts_with(problem, "CenterPanel/Content/StatNames/Row2/Label:")


func test_control_an_inventory_outline_with_fill_or_shadow_fails() -> void:
	var root: Control = await _laid_out(INVENTORY_SCENE)
	var panel: Panel = root.get_node("CenterPanel/Content/StatsOutline")
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate()
	panel.add_theme_stylebox_override("panel", style)
	style.draw_center = true
	_assert_one_problem(_scene_problems(root, _record()["scenes"][INVENTORY_SCENE]), "outline has a fill")
	style.draw_center = false
	style.shadow_size = 5
	_assert_one_problem(_scene_problems(root, _record()["scenes"][INVENTORY_SCENE]), "outline has a shadow")


func test_control_a_zone_orb_moved_20_px_fails() -> void:
	var path: String = "res://scenes/zones/zone1_prison.tscn"
	var scenes: Dictionary = _record()["scenes"]
	assert_has(scenes, path)
	if not scenes.has(path):
		return
	var root: Control = await _laid_out(path)
	(root.get_node("StoryFight") as Node2D).position.x += 20.0
	var found: Array[String] = _scene_problems(root, scenes[path])
	assert_gt(found.size(), 0)
	assert_string_contains(found[0] if found else "", "StoryFight")


# An info spot is a hit area on the zone art, so a spot moved 20 px fails at both
# of its corners.
func test_control_an_info_spot_moved_20_px_fails() -> void:
	var path: String = "res://scenes/zones/zone1_prison.tscn"
	var root: Control = await _laid_out(path)
	(root.get_node("InfoSpot4") as Control).position.x += 20.0
	var found: Array[String] = _scene_problems(root, _record()["scenes"][path])
	assert_eq(found.size(), 2, str(found))
	for problem: String in found:
		assert_string_starts_with(problem, "InfoSpot4: ")


const STORE_SCENE: String = "res://scenes/ui/store/store_window.tscn"


func _store_record() -> Dictionary:
	return _record()["scenes"][STORE_SCENE]


# A ware slot is a TextureRect in a FloatBox row. Moving it 20 px fails its
# top left and its bottom right (spec/107-store.md, Testing strategy).
func test_control_a_ware_slot_moved_20_px_fails() -> void:
	var root: Control = await _laid_out(STORE_SCENE)
	assert_eq(_scene_problems(root, _store_record()), [] as Array[String], "the unchanged Store passes")
	(root.get_node("CentreBottomPanel/Content/Wares/Row1/Slot2") as Control).position.x += 20.0
	var found: Array[String] = _scene_problems(root, _store_record())
	assert_eq(found.size(), 2, str(found))
	assert_string_contains(found[0] if found else "", "Row1/Slot2: top left")


# The keeper's PNG changes with the shop, so the record lists all seven and
# the check is that the node shows one of them at the recorded size.
func test_control_a_keeper_art_from_another_folder_fails() -> void:
	var root: Control = await _laid_out(STORE_SCENE)
	(root.get_node("LeftPanel/Content/KeeperArt") as TextureRect).texture = load("res://assets/ui/window/backdrop.png")
	var found: Array[String] = _scene_problems(root, _store_record())
	assert_eq(found.size(), 2, str(found))
	assert_string_contains(found[0] if found else "", "KeeperArt: texture res://")
	assert_string_contains(found[1] if found else "", "KeeperArt: texture size")
