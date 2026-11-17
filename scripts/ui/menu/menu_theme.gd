# menu_theme.gd
# Shared look + geometry for the rebuilt menu screens (inventory, store,
# abilities, achievements). Everything here is extracted from the original
# SWF's menu clip (DefineSprite 3142, placed on stage at 400.5, 222.4):
# panel art (assets/ui/menu/, exported at 2x zoom) and slot grid geometry. The
# piercing/defense bar math is MenuMath's.
class_name MenuTheme
extends RefCounted

const ART: String = "res://assets/ui/menu"

# KRINMENU's stage placement - all extracted coordinates below are stage px.
const ORIGIN: Vector2 = Vector2(400.5, 222.4)

# The red cracked backdrop (shape 2993 via sprite 2994 at (-2.1, 0.1)).
const BACKDROP_RECT: Rect2 = Rect2(14.2, 14.9, 768.5, 425.1)
# Close X (sprite 2855, art shape 2854) centered at (752.9, 48.0) at its
# extracted size.
const CLOSE_RECT: Rect2 = Rect2(734.5, 29.8, 36.7, 36.4)

# 31x31 item/equip slots (buttons 2985/2981/3012 share frame art 2982),
# laid out on a 38 px pitch everywhere.
const SLOT_SIZE: Vector2 = Vector2(31, 31)
const SLOT_STEP: float = 38.0

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


static func format_money(value: int) -> String:
	var text: String = str(absi(value))
	var out: String = ""
	var count: int = 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out
