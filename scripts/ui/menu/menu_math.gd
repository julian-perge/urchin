# menu_math.gd
# The inventory menu's element bar heights. The numbers come from
# dev/converted_json/menu_math.json, which uv run convert_menu_math reads out
# of DefineSprite_3142/frame_1/DoAction.as and the web SWF.
class_name MenuMath
extends RefCounted

const FILE: String = "res://dev/converted_json/menu_math.json"


# Each path is parsed once, because every ElementBar asks for the numbers. The
# caller must not change the dictionary it gets.
static var _cache: Dictionary[String, Dictionary] = {}


static func load_math(path: String = FILE) -> Dictionary:
	if not _cache.has(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert(parsed is Dictionary, "could not read %s" % path)
		_cache[path] = parsed
	return _cache[path]


# The x that the bar formulas take, for one element's allocation at a level
# (DefineSprite_3142/frame_1/DoAction.as:103-107). The script adds the rounded
# average to the allocation and then divides by the average without rounding.
static func x_for(allocation: float, level: int, math: Dictionary) -> float:
	var bars: Dictionary = math["element_bars"]
	var average: float = bars["average"]["base"] + bars["average"]["per_level"] * level
	assert(bars["value"]["average_rounding"] == "ceil", "MenuMath only rounds the average up")
	return (allocation + ceilf(average)) / average


# The DEFTIP index for a defense bar's x (DoAction.as:128-153). The script
# tests 1 / x against each rule in order, and the last rule that matches wins.
static func defense_tip(x: float, math: Dictionary) -> int:
	var tips: Dictionary = math["element_bars"]["defense_tips"]
	var ratio: float = 1.0 / x
	var tip: int = tips["default"]
	for rule: Dictionary in tips["rules"]:
		var threshold: float = rule["threshold"]
		var matches: bool = ratio > threshold if rule["compare"] == ">" else ratio < threshold
		if matches:
			tip = rule["tip"]
	return tip


# The three formulas before the heights are capped: nT1 and nT4, nT2 and nT5,
# nT3 and nT6 (DefineSprite_3142/frame_1/DoAction.as:108-110 and 146-148). The
# tooltips round these and the bars cap them.
static func terms(x: float, math: Dictionary) -> Dictionary:
	var bars: Dictionary = math["element_bars"]
	var quartic: float = 0.0
	for coefficient: float in bars["bar_quartic"]:
		quartic = quartic * (x + 1.0) + coefficient
	return {
		"bar": quartic,
		"gbar": bars["gbar"]["factor"] * x,
		"xbar": bars["xbar"]["factor"] * (x + bars["xbar"]["offset"]),
	}


# x is the bar's value divided by the level's average. The heights are in px
# for the three layers the script sizes (DefineSprite_3142/frame_1/DoAction.as:108-125).
# xbar goes negative when x is below 1, as it does in the original. The bar
# draws no xbar then (ElementBar._set_height).
static func layer_heights(x: float, math: Dictionary) -> Dictionary:
	var bars: Dictionary = math["element_bars"]
	var save_height: float = bars["save_height"]
	var terms_of_x: Dictionary = terms(x, math)
	var heights: Dictionary = {
		"bar": save_height * terms_of_x["bar"],
		"gbar": save_height / float(bars["gbar"]["divisor"]) * terms_of_x["gbar"],
		"xbar": save_height * terms_of_x["xbar"],
	}
	for layer: String in bars["capped"]:
		heights[layer] = minf(heights[layer], save_height)
	return heights


# What a layer's colour is on screen, from the element's colour. The script
# colours the shape inside a layer ("inner") or the whole clip ("clip") with
# the element colour, or neither. A layer's own colour transform then
# multiplies the colour and adds to it, which brightens or dims the shape
# inside. A colour set on the clip replaces that transform
# (DefineSprite_3142/frame_1/DoAction.as:196-220).
static func layer_color(layer: String, element: Color, math: Dictionary) -> Color:
	var look: Dictionary = math["element_bars"]["layers"][layer]
	if look["tint"] == "clip":
		return Color(element.r, element.g, element.b)
	var base: Color = element if look["tint"] == "inner" else Color.WHITE
	var multiplier: float = look["multiplier"]
	var added: float = look["add"]
	return Color(
		clampf(base.r * multiplier + added, 0.0, 1.0),
		clampf(base.g * multiplier + added, 0.0, 1.0),
		clampf(base.b * multiplier + added, 0.0, 1.0),
	)


# Math.round: a half goes up, below zero too.
static func flash_round(value: float) -> int:
	return floori(value + 0.5)
