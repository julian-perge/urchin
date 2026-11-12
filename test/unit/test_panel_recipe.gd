# PanelRecipe (scripts/ui/panel_recipe.gd) builds and checks one flat Panel.
# The inputs are chosen to test the formulas, not taken from the SWF. The rect
# test (julian-perge/urchin#208) checks the real Panels against extracted values.
extends GutTest

const EPSILON: float = 0.0001
const FILL: Color = Color(0.2, 0.2, 0.2)
const LINE: Color = Color.BLACK
const FILL_RECT: Rect2 = Rect2(100.25, 50.5, 200.0, 120.0)

# The mean scale stroke is sqrt((0.6^2 + 2.1^2) / 2) = 1.54, which rounds to 2.
# The arithmetic mean of the two scales is 1.35 and would round to 1.
const SCALE: Vector2 = Vector2(0.6, 2.1)
const BORDER: int = 2


func _panel() -> PanelContainer:
	var panel: PanelContainer = PanelRecipe.build(FILL, LINE, FILL_RECT, SCALE)
	add_child_autofree(panel)
	return panel


func test_border_width_is_the_rounded_mean_scale_stroke() -> void:
	assert_eq(PanelRecipe.border_width(SCALE), BORDER)
	assert_eq(PanelRecipe.border_width(Vector2.ONE), 1)


func test_panel_rect_grows_the_fill_rect_by_half_the_border() -> void:
	var grown: Rect2 = PanelRecipe.panel_rect(FILL_RECT, BORDER)
	assert_almost_eq(grown.position, Vector2(99.25, 49.5), Vector2(EPSILON, EPSILON))
	assert_almost_eq(grown.size, Vector2(202.0, 122.0), Vector2(EPSILON, EPSILON))


func test_built_panel_has_one_border_width_on_all_sides() -> void:
	var style: StyleBoxFlat = _panel().get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(style)
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		assert_eq(style.get_border_width(side), BORDER)
	assert_eq(style.bg_color, FILL)
	assert_eq(style.border_color, LINE)


func test_built_panel_has_sharp_corners() -> void:
	var style: StyleBoxFlat = _panel().get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(style)
	for corner: Corner in [CORNER_TOP_LEFT, CORNER_TOP_RIGHT, CORNER_BOTTOM_RIGHT, CORNER_BOTTOM_LEFT]:
		assert_eq(style.get_corner_radius(corner), 0)


func test_built_panel_sits_on_the_grown_rect() -> void:
	var panel: PanelContainer = _panel()
	assert_almost_eq(panel.position, Vector2(99.25, 49.5), Vector2(EPSILON, EPSILON))
	assert_almost_eq(panel.size, Vector2(202.0, 122.0), Vector2(EPSILON, EPSILON))


func test_built_panel_uses_the_shared_shadow_material() -> void:
	assert_same(_panel().material, PanelRecipe.SHADOW_MATERIAL)


func test_shadow_material_holds_the_swf_filter_values() -> void:
	var material: ShaderMaterial = PanelRecipe.SHADOW_MATERIAL
	assert_eq(material.shader.resource_path, "res://scenes/ui/panel_inner_shadow.gdshader")
	assert_eq(material.get_shader_parameter("blur"), 5.0)
	assert_eq(material.get_shader_parameter("distance"), 5.0)
	assert_eq(material.get_shader_parameter("angle"), 45.0)


func test_built_panel_has_no_problems() -> void:
	assert_eq(PanelRecipe.problems(_panel(), FILL_RECT, SCALE), [] as Array[String])


func test_problems_reports_a_wrong_border_width() -> void:
	var panel: PanelContainer = _panel()
	(panel.get_theme_stylebox("panel") as StyleBoxFlat).border_width_top = BORDER + 1
	var found: Array[String] = PanelRecipe.problems(panel, FILL_RECT, SCALE)
	assert_eq(found.size(), 1, str(found))
	assert_string_contains(found[0] if found else "", "border")


func test_problems_reports_a_rect_without_growth() -> void:
	var panel: PanelContainer = _panel()
	panel.position = FILL_RECT.position
	panel.size = FILL_RECT.size
	var found: Array[String] = PanelRecipe.problems(panel, FILL_RECT, SCALE)
	assert_eq(found.size(), 1, str(found))
	assert_string_contains(found[0] if found else "", "rect")


func test_problems_reports_a_missing_material() -> void:
	var panel: PanelContainer = _panel()
	panel.material = null
	var found: Array[String] = PanelRecipe.problems(panel, FILL_RECT, SCALE)
	assert_eq(found.size(), 1, str(found))
	assert_string_contains(found[0] if found else "", "material")
