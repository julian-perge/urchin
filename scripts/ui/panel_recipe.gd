# panel_recipe.gd
# The recipe for the 16 flat KRINMENU Panels (spec/107-ui-foundation.md,
# Part 3). Each Panel is a PanelContainer with its own StyleBoxFlat and the
# shared inner shadow material. A Theme cannot hold a material, so every Panel
# sets it itself.
class_name PanelRecipe
extends RefCounted

const SHADOW_MATERIAL: ShaderMaterial = preload("res://resources/ui/panel_inner_shadow.tres")


const SIDES: Array[Side] = [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]
const CORNERS: Array[Corner] = [CORNER_TOP_LEFT, CORNER_TOP_RIGHT, CORNER_BOTTOM_RIGHT, CORNER_BOTTOM_LEFT]
const RECT_TOLERANCE: float = 0.001


# The SWF scales one stroke with the placement matrix. One whole-pixel width on
# all four sides keeps the StyleBoxFlat sharp, so the width is the mean scale.
static func border_width(placement_scale: Vector2) -> int:
	return roundi(sqrt((placement_scale.x ** 2 + placement_scale.y ** 2) / 2.0))


# The SWF's fill rect ends at the middle of its stroke, and a StyleBoxFlat draws
# its border inside its rect, so the Panel's rect is half a border larger.
static func panel_rect(fill_rect: Rect2, border: int) -> Rect2:
	return fill_rect.grow(border / 2.0)


static func build(fill: Color, line: Color, fill_rect: Rect2, placement_scale: Vector2) -> PanelContainer:
	var border: int = border_width(placement_scale)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = line
	style.anti_aliasing = false
	for side: Side in SIDES:
		style.set_border_width(side, border)
	for corner: Corner in CORNERS:
		style.set_corner_radius(corner, 0)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.material = SHADOW_MATERIAL
	var rect: Rect2 = panel_rect(fill_rect, border)
	panel.position = rect.position
	panel.size = rect.size
	return panel


# Returns one message for each part of the recipe the Panel breaks: its border
# width, its rect, or its material. An empty list means the Panel follows it.
static func problems(panel: PanelContainer, fill_rect: Rect2, placement_scale: Vector2) -> Array[String]:
	var found: Array[String] = []
	var border: int = border_width(placement_scale)
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		found.append("border: the panel style is not a StyleBoxFlat")
	else:
		var widths: Array[int] = []
		for side: Side in SIDES:
			widths.append(style.get_border_width(side))
		if widths != [border, border, border, border]:
			found.append("border: widths %s, expected %d on every side" % [widths, border])
	var rect: Rect2 = panel_rect(fill_rect, border)
	var actual: Rect2 = Rect2(panel.position, panel.size)
	if not (
		actual.position.distance_to(rect.position) < RECT_TOLERANCE
		and actual.size.distance_to(rect.size) < RECT_TOLERANCE
	):
		found.append("rect: %s, expected %s" % [actual, rect])
	if panel.material != SHADOW_MATERIAL:
		found.append("material: %s, expected %s" % [panel.material, SHADOW_MATERIAL.resource_path])
	return found
