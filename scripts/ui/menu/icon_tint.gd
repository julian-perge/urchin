# icon_tint.gd
# Builds a ShaderMaterial that recolors an ability icon's silhouette to a
# flat element/passive color - `modulate` can't do this because the source
# art (DefineSprite 2427) is near-black, and black * any tint is still black.
class_name IconTint
extends RefCounted

const SHADER: Shader = preload("res://scenes/ui/menu/icon_tint.gdshader")


static func material(color: Color) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("tint_color", color)
	return mat
