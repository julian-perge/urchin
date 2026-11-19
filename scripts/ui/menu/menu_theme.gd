# menu_theme.gd
# The element colors and the heal color that the menu bars and the battle
# numbers share, and a loader for the art in assets/ui/menu/. The piercing and
# defense bar math is in MenuMath.
class_name MenuTheme
extends RefCounted

const ART: String = "res://assets/ui/menu"

# The color of each element, in the order every per/def array uses
# (CombatUnit.ELEMENT_ORDER). The original sets it once as elementColorArray
# (frame_41/DoAction_2.as), and the menu bars and the floating damage numbers
# both draw with it. uv run convert_menu_math reads it into menu_math.json.
static var ELEMENT_COLORS: Array[Color] = _read_element_colors()

# KrinNumberShow's HEAL color (0x66FF00).
const HEAL_COLOR: Color = Color("66FF00")


static func _read_element_colors() -> Array[Color]:
	var colors: Array[Color] = []
	for hex: String in MenuMath.load_math()["element_colors"]["colors"]:
		colors.append(Color(hex))
	return colors


static func texture(file: String) -> Texture2D:
	return load("%s/%s" % [ART, file])
