# element_bar.gd
# One element bar of the Inventory's piercing or defense block: a track and the
# four layers the original stacks on it, ybar, bar, gbar and xbar
# (spec/107-inventory.md, Centre panel: the element bars). The scene types the
# bar's rects, and test_screen_rects.gd checks them against the SWF. This script
# sets each layer's height and colour from the formulas in
# dev/converted_json/menu_math.json, as updateStatus does in
# DefineSprite_3142/frame_1/DoAction.as, and shows the bar's tooltip.
class_name ElementBar
extends Control

enum Kind { PIERCING, DEFENSE }

# Three passes of a 9 px box blur reach 13.5 px past the layer, and the glow
# node has 14 px of room on every side. _ready() checks the extracted blur
# against these.
const GLOW_REACH: float = 14.0
const GLOW_PASSES: int = 3
# The layers in the order the SWF stacks them over the track. Each gets a
# z_index in the scene, so a block draws every ybar, then every bar, and so on,
# as the SWF's depths do, and a Glow never lies over the next bar's layer.
const LAYERS: Array[String] = ["Ybar", "Bar", "Gbar", "Xbar"]

var _math: Dictionary = MenuMath.load_math()
var _element: int = 0
var _kind: Kind = Kind.PIERCING
var _tooltip: Dictionary = {}
# The bottom of the full bar. Every layer grows up from it, and a layer with a
# negative height hangs below it.
var _baseline: float = 0.0
var _full_height: float = 0.0
# The color the script gave the element's layers, or white while it has not.
var _element_color: Color = Color.WHITE

@onready var _layers: Dictionary[String, ColorRect] = {
	"Ybar": $Ybar, "Bar": $Bar, "Gbar": $Gbar, "Xbar": $Xbar,
}


func _ready() -> void:
	_baseline = _layers["Ybar"].offset_bottom
	_full_height = _layers["Ybar"].size.y
	for layer: String in ["Gbar", "Xbar"]:
		var glow: Dictionary = _math["element_bars"]["layers"][layer.to_lower()]["glow"]
		assert(glow["passes"] == GLOW_PASSES, "the glow shader draws three passes")
		assert(glow["composite_source"], "the glow shader draws the layer over its glow")
		assert(maxf(glow["blur_x"], glow["blur_y"]) * GLOW_PASSES / 2.0 <= GLOW_REACH, "the glow node has room for the blur")
		var material: ShaderMaterial = (get_node("%s/Glow" % layer) as ColorRect).material
		material.set_shader_parameter("blur", Vector2(glow["blur_x"], glow["blur_y"]))
		material.set_shader_parameter("strength", glow["strength"])
		material.set_shader_parameter("reach", GLOW_REACH)
	_color_layers()
	for layer: String in LAYERS:
		_fit_glow(layer)
	mouse_entered.connect(_show_tooltip)
	mouse_exited.connect(GameTooltip.hide_tooltip)


# `element` is a CombatUnit.Element, the index of MenuTheme.ELEMENT_COLORS and
# of ELEMENTS in strings.json.
func setup(element: int, kind: Kind) -> void:
	_element = element
	_kind = kind
	_element_color = MenuTheme.ELEMENT_COLORS[element]
	_color_layers()


# Sets the layers from one value. `allocation` is the save's per or def for the
# element, and the value the original shows is that plus the level's average.
func show_value(allocation: float, level: int) -> void:
	var x: float = MenuMath.x_for(allocation, level, _math)
	var average: float = _math["element_bars"]["average"]["base"] + _math["element_bars"]["average"]["per_level"] * level
	var value: float = allocation + ceilf(average)
	var heights: Dictionary = MenuMath.layer_heights(x, _math)
	_set_height("Bar", heights["bar"])
	_set_height("Gbar", heights["gbar"])
	_set_height("Xbar", heights["xbar"])
	_tooltip = tooltip_text(_kind, _element, value, x, _math)


# The tooltip of the bar the last show_value() set: {"title", "body"}.
func tooltip() -> Dictionary:
	return _tooltip


# The title is the element, the stat and the value, and the body is the text
# that updateStatus builds from the same x (DoAction.as:112-113 and 131-153).
static func tooltip_text(kind: Kind, element: int, value: float, x: float, math: Dictionary) -> Dictionary:
	var stat: String = Strings.system(5 if kind == Kind.PIERCING else 6)
	var title: String = "%s %s: %s" % [Strings.text("ELEMENTS", element), stat, _number_text(value)]
	if kind == Kind.DEFENSE:
		return {"title": title, "body": Strings.text("DEFTIP", MenuMath.defense_tip(x, math))}
	var terms: Dictionary = MenuMath.terms(x, math)
	var body: String = "%s %d%% %s %d%% %s %d%% %s" % [
		Strings.system(38), MenuMath.flash_round(terms["gbar"]),
		Strings.system(37), MenuMath.flash_round(terms["bar"] * 100.0),
		Strings.system(39), MenuMath.flash_round(terms["xbar"] * 100.0),
		Strings.system(40),
	]
	return {"title": title, "body": body}


# A number as ActionScript joins it into a string: a whole number has no ".0".
static func _number_text(value: float) -> String:
	return str(int(value)) if value == floorf(value) else String.num(value)


func _color_layers() -> void:
	for layer: String in LAYERS:
		var color: Color = MenuMath.layer_color(layer.to_lower(), _element_color, _math)
		_layers[layer].color = color
		var glow: ColorRect = get_node_or_null("%s/Glow" % layer)
		if glow != null:
			(glow.material as ShaderMaterial).set_shader_parameter("tint", color)


# A positive height grows up from the baseline. A negative one hangs below it,
# which is how Flash draws a clip whose _height is negative.
func _set_height(layer: String, height: float) -> void:
	var node: ColorRect = _layers[layer]
	if height >= 0.0:
		node.offset_top = _baseline - height
		node.offset_bottom = _baseline
	else:
		node.offset_top = _baseline
		node.offset_bottom = _baseline - height
	_fit_glow(layer)


# The glow sits behind its layer and is larger than it by GLOW_REACH.
func _fit_glow(layer: String) -> void:
	var glow: ColorRect = get_node_or_null("%s/Glow" % layer)
	if glow == null:
		return
	var node: ColorRect = _layers[layer]
	glow.position = Vector2(-GLOW_REACH, -GLOW_REACH)
	glow.size = node.size + Vector2(2.0 * GLOW_REACH, 2.0 * GLOW_REACH)
	(glow.material as ShaderMaterial).set_shader_parameter("node_size", glow.size)


func _show_tooltip() -> void:
	if _tooltip.is_empty():
		return
	GameTooltip.show_sections([
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": _tooltip["title"], "color": TooltipTheme.TEXT_TITLE}]},
		{"bg_color": TooltipTheme.BG_BODY, "lines": [{"text": _tooltip["body"], "color": TooltipTheme.TEXT_BODY}]},
	], self)
