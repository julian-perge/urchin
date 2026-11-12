# panel_recipe.gd
# The recipe for the 16 flat KRINMENU Panels (spec/107-ui-foundation.md,
# Part 3). Each Panel is a PanelContainer with its own StyleBoxFlat and the
# shared inner shadow material. A Theme cannot hold a material, so every Panel
# sets it itself.
class_name PanelRecipe
extends RefCounted

const SHADOW_MATERIAL: ShaderMaterial = preload("res://resources/ui/panel_inner_shadow.tres")


static func border_width(_placement_scale: Vector2) -> int:
	return 0


static func panel_rect(fill_rect: Rect2, _border: int) -> Rect2:
	return fill_rect


static func build(_fill: Color, _line: Color, _fill_rect: Rect2, _placement_scale: Vector2) -> PanelContainer:
	return PanelContainer.new()


static func problems(_panel: PanelContainer, _fill_rect: Rect2, _placement_scale: Vector2) -> Array[String]:
	return []
