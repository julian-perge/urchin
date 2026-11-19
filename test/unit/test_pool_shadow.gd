# The ability pool's inner shadow overlay, scenes/ui/menu/pool_shadow.tscn
# (julian-perge/urchin#190). A headless run draws nothing, so these tests check
# what decides the drawing: the overlay's place among the pool's nodes, its rect
# and its mouse filter, and that its shader takes the ramp from the same include
# as the Panels' shader, with the same numbers. test_screen_rects.gd checks the
# overlay's rect and numbers against the SWF.
extends GutTest

const ABILITIES_SCENE: String = "res://scenes/ui/menu/abilities_window.tscn"
const OVERLAY_SHADER: String = "res://scenes/ui/menu/pool_shadow.gdshader"
const INCLUDE_PATH: String = "res://scenes/ui/panel_shadow.gdshaderinc"
const RAMP_CALL: String = "shadow_ramp(local, blur, distance, angle)"
const PARAMETERS: Array[String] = ["blur", "distance", "angle"]
const RAMP_MATH: Array[String] = ["clamp(", "smoothstep(", "min(", "max(", "step(", "radians(", "cos(", "sin("]


func _window() -> Control:
	var root: Control = (load(ABILITIES_SCENE) as PackedScene).instantiate()
	add_child_autofree(root)
	await wait_process_frames(2)
	return root


func _overlay_material() -> ShaderMaterial:
	var overlay: Control = (load("res://scenes/ui/menu/pool_shadow.tscn") as PackedScene).instantiate()
	var material: ShaderMaterial = overlay.material as ShaderMaterial
	overlay.free()
	return material


# Returns one message for each way the overlay breaks #190: it has to be the
# last child of the pool, so it draws above the backing, the rows, the frame and
# the scroll buttons, it has to let every click through, and it has to cover
# the pool's rect and nothing more.
func _overlay_problems(window: Control) -> Array[String]:
	var pool: Control = window.get_node("Pool")
	var overlay: Control = pool.get_node_or_null("Shadow") as Control
	if overlay == null:
		return ["the pool has no Shadow overlay"]
	var found: Array[String] = []
	for path: String in ["Mask/Backing", "Mask/Rows", "Frame"]:
		if pool.get_node_or_null(path) == null:
			found.append("the pool has no %s under the overlay" % path)
	if overlay.get_index() != pool.get_child_count() - 1:
		found.append("the overlay is child %d of %d, not the last" % [overlay.get_index(), pool.get_child_count()])
	if overlay.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		found.append("the overlay's mouse filter is %d, not ignore" % overlay.mouse_filter)
	if not overlay.get_global_rect().is_equal_approx(pool.get_global_rect()):
		found.append("the overlay covers %s, not the pool's %s" % [overlay.get_global_rect(), pool.get_global_rect()])
	var material: ShaderMaterial = overlay.material as ShaderMaterial
	if material == null or material.shader.resource_path != OVERLAY_SHADER:
		found.append("the overlay's material is not %s" % OVERLAY_SHADER)
	return found


func test_the_overlay_lies_over_the_pool_and_lets_clicks_through() -> void:
	var window: Control = await _window()
	assert_eq(_overlay_problems(window), [] as Array[String])


func test_control_a_copy_with_no_overlay_fails() -> void:
	var window: Control = await _window()
	window.get_node("Pool/Shadow").free()
	assert_eq(_overlay_problems(window), ["the pool has no Shadow overlay"] as Array[String])


func test_control_rows_moved_above_the_overlay_fail() -> void:
	var window: Control = await _window()
	var pool: Control = window.get_node("Pool")
	pool.get_node("Mask").move_child(pool.get_node("Mask/Rows"), -1)
	pool.move_child(pool.get_node("Frame"), -1)
	var found: Array[String] = _overlay_problems(window)
	assert_eq(found.size(), 1, str(found))
	assert_string_contains(found[0] if found else "", "not the last")


func test_control_an_overlay_that_takes_clicks_fails() -> void:
	var window: Control = await _window()
	(window.get_node("Pool/Shadow") as Control).mouse_filter = Control.MOUSE_FILTER_STOP
	var found: Array[String] = _overlay_problems(window)
	assert_eq(found.size(), 1, str(found))
	assert_string_contains(found[0] if found else "", "mouse filter")


func test_control_an_overlay_wider_than_the_pool_fails() -> void:
	var window: Control = await _window()
	(window.get_node("Pool/Shadow") as Control).size.x += 20.0
	var found: Array[String] = _overlay_problems(window)
	assert_eq(found.size(), 1, str(found))
	assert_string_contains(found[0] if found else "", "covers")


func test_a_pool_row_lies_under_the_overlay_and_stops_the_mouse() -> void:
	var window: Control = await _window()
	var row: Control = window.get_node("Pool/Mask/Rows/PoolRow0")
	var overlay: Control = window.get_node("Pool/Shadow")
	assert_true(overlay.get_global_rect().encloses(row.get_global_rect()))
	assert_eq(row.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_eq(overlay.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_the_include_holds_the_one_ramp() -> void:
	var include: String = FileAccess.get_file_as_string(INCLUDE_PATH)
	assert_string_contains(include, "float shadow_ramp(vec2 local, float blur, float distance, float angle)")


# The overlay's ramp equals the Panels' on the same inputs when both shaders
# call the one function of the include with the same arguments and neither
# computes a ramp of its own. RAMP_MATH lists the calls that a ramp written
# in a shader itself would need.
func test_the_overlay_and_the_panels_call_the_same_ramp() -> void:
	var shaders: Array[Shader] = [PanelRecipe.SHADOW_MATERIAL.shader, _overlay_material().shader]
	for shader: Shader in shaders:
		assert_string_contains(shader.code, '#include "%s"' % INCLUDE_PATH)
		assert_string_contains(shader.code, RAMP_CALL)
		for call: String in RAMP_MATH:
			assert_false(shader.code.contains(call), "%s computes a ramp of its own with %s" % [shader.resource_path, call])


func test_the_overlay_multiplies_what_is_under_it() -> void:
	var code: String = _overlay_material().shader.code
	assert_string_contains(code, "render_mode blend_mul;")
	assert_string_contains(code, "COLOR = vec4(vec3(%s), 1.0);" % RAMP_CALL)


func test_the_overlay_takes_the_panels_shadow_numbers() -> void:
	var overlay: ShaderMaterial = _overlay_material()
	for parameter: String in PARAMETERS:
		assert_almost_eq(
			float(overlay.get_shader_parameter(parameter)),
			float(PanelRecipe.SHADOW_MATERIAL.get_shader_parameter(parameter)),
			0.0001,
			parameter,
		)
