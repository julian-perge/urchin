# menu_math.gd
# The inventory menu's element bar heights. The numbers come from
# dev/converted_json/menu_math.json, which uv run convert_menu_math reads out
# of DefineSprite_3142/frame_1/DoAction.as and the web SWF.
class_name MenuMath
extends RefCounted

const FILE: String = "res://dev/converted_json/menu_math.json"


static func load_math(path: String = FILE) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, "could not read %s" % path)
	return parsed


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


# x is the bar's value divided by the level's average. The heights are in px
# for the three layers the script sizes (DefineSprite_3142/frame_1/DoAction.as:108-125).
# xbar goes negative when x is below 1, as it does in the original.
static func layer_heights(x: float, math: Dictionary) -> Dictionary:
	var bars: Dictionary = math["element_bars"]
	var save_height: float = bars["save_height"]
	var quartic: float = 0.0
	for coefficient: float in bars["bar_quartic"]:
		quartic = quartic * (x + 1.0) + coefficient
	var heights: Dictionary = {
		"bar": save_height * quartic,
		"gbar": save_height / float(bars["gbar"]["divisor"]) * bars["gbar"]["factor"] * x,
		"xbar": save_height * bars["xbar"]["factor"] * (x + bars["xbar"]["offset"]),
	}
	for layer: String in bars["capped"]:
		heights[layer] = minf(heights[layer], save_height)
	return heights
