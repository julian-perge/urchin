# menu_theme.gd
# Shared look + geometry for the rebuilt menu screens (inventory, store,
# abilities, achievements). Everything here is extracted from the original
# SWF's menu clip (DefineSprite 3142, placed on stage at 400.5, 222.4):
# panel art (assets/ui/menu/, exported at 2x zoom), slot grid geometry, and
# the piercing/defense bar math from the frame-1 DoAction.
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

# The element order every per/def array uses (CombatUnit.ELEMENT_ORDER) and
# the EXACT original colors (elementColorArray, frame_41/DoAction_2.as) -
# used by the menu bars AND the floating damage numbers.
const ELEMENT_COLORS: Array[Color] = [
	Color("C40000"),  # Physical
	Color("FB95C8"),  # Magic
	Color("68CBF4"),  # Ice
	Color("FF6600"),  # Fire
	Color("FFCC00"),  # Lightning
	Color("856B47"),  # Earth
	Color("664D80"),  # Shadow
	Color("508349"),  # Poison
]
# KrinNumberShow's HEAL color (0x66FF00).
const HEAL_COLOR: Color = Color("66FF00")

const STAT_LABELS: Array[String] = ["Vitality:", "Strength:", "Instinct:", "Speed:", "Focus:"]
const STAT_COLORS: Array[Color] = [
	Color(0.55, 0.85, 0.3),   # Vitality - green
	Color(0.9, 0.35, 0.3),    # Strength - red
	Color(0.95, 0.65, 0.2),   # Instinct - orange
	Color(0.75, 0.55, 0.9),   # Speed - purple
	Color(0.55, 0.65, 0.95),  # Focus - blue
]


# Menu bar fill fraction (frame-1 DoAction nT1/nT4): the crit-curve quartic
# of value / (100 + 15 * level), clamped to the bar. Base allocation fills
# 30% of the track.
static func bar_fill_fraction(value: float, level: int) -> float:
	var x: float = value / (100.0 + 15.0 * level) + 1.0
	var fraction: float = (
		0.016666667 * pow(x, 4) - 0.25 * pow(x, 3)
		+ 1.233333 * pow(x, 2) - 1.9 * x + 0.9
	)
	return clamp(fraction, 0.0, 1.0)


# Menu piercing/defense display value: allocation + ceil(100 + 15 * level).
static func element_display_value(allocation: float, level: int) -> int:
	return int(allocation) + int(ceil(100.0 + 15.0 * level))


static func texture(file: String) -> Texture2D:
	return load("%s/%s" % [ART, file])


static func add_texture_rect(parent: Node, file: String, rect: Rect2, stretch: bool = true) -> TextureRect:
	var node: TextureRect = TextureRect.new()
	node.texture = texture(file)
	# expand_mode must be set BEFORE size: with the default EXPAND_KEEP_SIZE
	# the texture's natural size acts as the minimum and wins over size.
	if stretch:
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		node.stretch_mode = TextureRect.STRETCH_SCALE
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


static func add_label(parent: Node, text: String, rect: Rect2, font_size: int, color: Color = Color.WHITE, align: int = HORIZONTAL_ALIGNMENT_LEFT, wrap_text: bool = false) -> Label:
	var label: Label = Label.new()
	# autowrap must be on BEFORE size: an unwrapped Label's minimum width is
	# the full text width, which overrides a narrower size.
	if wrap_text:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


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
