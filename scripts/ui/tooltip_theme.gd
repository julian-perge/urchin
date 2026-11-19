# tooltip_theme.gd
# Shared tooltip look, recovered from the original's own KrinToolTipper clip
# (DefineSprite 2717). Its backers are two clips that every section reuses: a
# black body (2716) and a white, grey and white gradient (2715) for the title
# and sub-header bars, each recolored by a ColorTransform. The backers'
# fills and transforms come from dev/converted_json/tooltip_look.json, which
# dev/urchin_dev/swf/extract/tooltip_look.py writes from the SWF and the AS.
# Text sizes, colors and widths are the TextFormat and createTextField values
# the clip's frame scripts give each text field they build.
class_name TooltipTheme
extends RefCounted

const LOOK_FILE := "res://dev/converted_json/tooltip_look.json"

# The original's names for the rarities, which key rarity_add in LOOK_FILE. An
# item slot passes the item's KRINITEM[2] (DefineButton2_2985 on(rollOver).as:3).
# No item in items.json is EPIC or LEGENDARY, so they have no name.
const RARITY_NAMES: Dictionary = {
	GameItem.Rarity.COMMON: "Common",
	GameItem.Rarity.UNCOMMON: "Uncommon",
	GameItem.Rarity.RARE: "Rare",
}

static var _look: Dictionary = {}

# The four backer colors are static vars and not consts, because they come
# from LOOK_FILE. They keep the names callers already pass as a section's
# bg_color. GameTooltip draws a BG_HEADER or BG_COST section as the 2715
# gradient, so those two only name the bar: each is the gradient's grey stop,
# with the GO2 sub-header's add terms for BG_COST. BG_BODY is the body fill, and
# BG_NEXT_RANK is that fill through fontBacker4's transform in GO7.
static var BG_HEADER: Color = _grey_stop([0, 0, 0])
static var BG_COST: Color = _grey_stop(look()["subheader_add"]["GO2"])
static var BG_BODY: Color = color_of(look()["body_fill"])
static var BG_NEXT_RANK: Color = _transformed(look()["body_fill"], look()["next_rank"])

# Every field the clip builds is 12 px (DefineSprite_2717/frame_4/DoAction.as:43).
const FONT_SIZE: int = 12

# The title is black in every layout (DefineSprite_2717/frame_4/DoAction.as:60).
# An ability's cost line is 0x000033, its description white and its next tier
# 0xFFCC00 (DefineSprite_2717/frame_17/DoAction.as:30, 47 and 71). An item's
# level line is 0x333333, its stat lines 0xF8D754 and its flavor text 0xB8FE4E
# (DefineSprite_2717/frame_13/DoAction.as:34, 58 and 77).
const TEXT_TITLE: Color = Color("000000")
const TEXT_SUBHEADER: Color = Color("000033")
const TEXT_BODY: Color = Color("ffffff")
const TEXT_NEXT_RANK: Color = Color("ffcc00")
const TEXT_REQUIREMENT: Color = Color("333333")
const TEXT_STAT: Color = Color("f8d754")
const TEXT_FLAVOR: Color = Color("b8fe4e")

# The clip builds every field of a layout at one width: 170 px for a plain
# tooltip (DefineSprite_2717/frame_4/DoAction.as:33), 150 for an ability
# (DefineSprite_2717/frame_17/DoAction.as:21) and 200 for an item
# (DefineSprite_2717/frame_13/DoAction.as:25),
# and Flash keeps a 2 px gutter on each side of the text. Each width below is
# that field width less both gutters, plus the 3.34 px of one 12 px space,
# because Godot counts the space after a line's last word when it wraps and the
# reference captures wrap as if Flash does not. The sum is rounded down to a
# whole pixel, because a Label only wraps at whole pixels and GameTooltip's
# containers would round a fraction up. Measured over the 3596 different
# tooltip fields the port can show, 3562 then wrap onto as many lines as a wrap
# that ignores trailing spaces at the field's own width less both gutters, and
# the other 34 are one line off.
const TEXT_WIDTH_PLAIN: float = 169.0
const TEXT_WIDTH_ABILITY: float = 149.0
const TEXT_WIDTH_ITEM: float = 199.0

# -> the parsed LOOK_FILE, read once.
static func look() -> Dictionary:
	if _look.is_empty():
		_look = JSON.parse_string(FileAccess.get_file_as_string(LOOK_FILE))
	return _look


# -> the layout record of LOOK_FILE that a GameTooltip text width stands for:
# GO for a plain tooltip, GO4 for an item and GO7 for an ability. GO2 and GO3,
# the ability icon's other layouts, have GO7's width and offsets.
static func layout_for_width(text_width: float) -> Dictionary:
	var label: String = "GO"
	if text_width == TEXT_WIDTH_ITEM:
		label = "GO4"
	elif text_width == TEXT_WIDTH_ABILITY:
		label = "GO7"
	return look()["layouts"][label]


# -> a Color from 0..255 channel values, with alpha 255 when there are three.
static func color_of(channels: Array) -> Color:
	var alpha: float = float(channels[3]) if channels.size() > 3 else 255.0
	return Color(float(channels[0]) / 255.0, float(channels[1]) / 255.0, float(channels[2]) / 255.0, alpha / 255.0)


# -> the gradient's stops as [ratio 0..1, Color], each with the red, green and
# blue add terms in add (0..255 units) applied and clamped, as Flash applies a
# ColorTransform. Every tooltip transform adds nothing to alpha.
static func gloss_stops(add: Array = [0, 0, 0]) -> Array:
	var stops: Array = []
	for stop: Dictionary in look()["gloss_stops"]:
		var channels: Array = stop["color"]
		var tinted: Array = []
		for i in 3:
			tinted.append(clampi(int(channels[i]) + int(add[i]), 0, 255))
		tinted.append(int(channels[3]))
		stops.append([float(stop["ratio"]) / 255.0, color_of(tinted)])
	return stops


static func _grey_stop(add: Array) -> Color:
	var darkest: Array = gloss_stops(add)[0]
	for stop: Array in gloss_stops(add):
		if stop[1].r < darkest[1].r:
			darkest = stop
	return darkest[1]


static func _transformed(channels: Array, transform: Dictionary) -> Color:
	var out: Array = []
	for i in 4:
		var value: float = float(channels[i]) * float(transform["multiply"][i]) / 256.0 + float(transform["add"][i])
		out.append(clampf(value, 0.0, 255.0))
	return color_of(out)
