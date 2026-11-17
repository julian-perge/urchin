# ElementBar (scripts/ui/menu/element_bar.gd): one element bar of the
# Inventory's two blocks. The expected numbers are worked out by hand from
# DefineSprite_3142/frame_1/DoAction.as:103-153, so a changed number in
# dev/converted_json/menu_math.json fails a test.
extends GutTest

const SCENE: PackedScene = preload("res://scenes/ui/menu/element_bar.tscn")
const EPSILON: float = 0.001

# At level 1 the average is 100 + 15 * 1 = 115, so an allocation of 0 gives
# x = 1 and an allocation of 115 gives x = 2.
const LEVEL: int = 1


func _bar(kind: ElementBar.Kind = ElementBar.Kind.PIERCING, element: int = 3) -> ElementBar:
	var bar: ElementBar = add_child_autofree(SCENE.instantiate())
	bar.setup(element, kind)
	return bar


# The height a layer draws, signed: a layer below its baseline has a negative
# height, which is how Flash draws a clip with a negative _height.
func _signed_height(bar: ElementBar, layer: String) -> float:
	var node: ColorRect = bar.get_node(layer)
	var baseline: float = (bar.get_node("Ybar") as ColorRect).offset_bottom
	if is_equal_approx(node.offset_bottom, baseline):
		return node.size.y
	assert_almost_eq(node.offset_top, baseline, EPSILON, "%s grows from the baseline in one direction only" % layer)
	return -node.size.y


func test_with_no_value_each_layer_is_the_full_bar_the_swf_frame_draws() -> void:
	var bar: ElementBar = add_child_autofree(SCENE.instantiate())
	for layer: String in ["Ybar", "Bar", "Gbar", "Xbar"]:
		assert_almost_eq((bar.get_node(layer) as ColorRect).size.y, 68.0, EPSILON, layer)


func test_the_average_value_draws_30_percent_and_10_percent_and_no_xbar() -> void:
	var bar: ElementBar = _bar()
	bar.show_value(0.0, LEVEL)
	assert_almost_eq(_signed_height(bar, "Ybar"), 68.0, EPSILON, "the dim layer is never resized")
	assert_almost_eq(_signed_height(bar, "Bar"), 20.39991, EPSILON)
	assert_almost_eq(_signed_height(bar, "Gbar"), 10.2, EPSILON)
	assert_almost_eq(_signed_height(bar, "Xbar"), 0.0, EPSILON)


func test_double_the_average_value_gives_each_layer_its_own_height() -> void:
	var bar: ElementBar = _bar()
	bar.show_value(115.0, LEVEL)
	assert_almost_eq(_signed_height(bar, "Bar"), 61.2, EPSILON)
	assert_almost_eq(_signed_height(bar, "Gbar"), 20.4, EPSILON)
	assert_almost_eq(_signed_height(bar, "Xbar"), 4.76, EPSILON)


func test_a_value_far_over_the_average_caps_bar_and_gbar_but_not_xbar() -> void:
	var bar: ElementBar = _bar()
	bar.show_value(2000.0, LEVEL)
	assert_almost_eq(_signed_height(bar, "Bar"), 68.0, EPSILON)
	assert_almost_eq(_signed_height(bar, "Gbar"), 68.0, EPSILON)
	assert_gt(_signed_height(bar, "Xbar"), 68.0)


# The original sets _height of the xbar clip to a negative number when the
# value is under the average, which Flash draws flipped below the clip's
# origin. The port keeps that as a Quirk (docs/adr/0005).
func test_a_value_under_the_average_draws_xbar_below_the_baseline() -> void:
	var bar: ElementBar = _bar()
	bar.show_value(-57.5, LEVEL)
	# x = 0.5, so xbar is 68 * 0.07 * (0.5 - 1) = -2.38.
	assert_almost_eq(_signed_height(bar, "Xbar"), -2.38, EPSILON)
	var ybar: ColorRect = bar.get_node("Ybar")
	assert_almost_eq((bar.get_node("Xbar") as ColorRect).offset_top, ybar.offset_bottom, EPSILON)


func test_each_layer_keeps_the_baseline_of_the_full_bar_between_values() -> void:
	var bar: ElementBar = _bar()
	var baseline: float = (bar.get_node("Ybar") as ColorRect).offset_bottom
	for allocation: float in [0.0, 300.0, -57.5, 2000.0]:
		bar.show_value(allocation, LEVEL)
		assert_almost_eq((bar.get_node("Bar") as ColorRect).offset_bottom, baseline, EPSILON, "bar at %s" % allocation)
		assert_almost_eq((bar.get_node("Gbar") as ColorRect).offset_bottom, baseline, EPSILON, "gbar at %s" % allocation)


func test_the_layers_take_their_colors_from_the_element_and_the_layer_transforms() -> void:
	var bar: ElementBar = _bar(ElementBar.Kind.PIERCING, CombatUnit.Element.FIRE)
	var fire: Color = MenuTheme.ELEMENT_COLORS[CombatUnit.Element.FIRE]
	var math: Dictionary = MenuMath.load_math()
	# The script colours the shape inside ybar and bar, and the layers dim it
	# to 26/256 and 77/256. It colours the whole gbar clip. It never colours
	# xbar, which stays white.
	assert_eq((bar.get_node("Ybar") as ColorRect).color, Color(fire.r * 26.0 / 256.0, fire.g * 26.0 / 256.0, fire.b * 26.0 / 256.0))
	assert_eq((bar.get_node("Bar") as ColorRect).color, Color(fire.r * 77.0 / 256.0, fire.g * 77.0 / 256.0, fire.b * 77.0 / 256.0))
	assert_eq((bar.get_node("Gbar") as ColorRect).color, fire)
	assert_eq((bar.get_node("Xbar") as ColorRect).color, Color.WHITE)
	assert_eq(math["element_bars"]["layers"]["gbar"]["tint"], "clip", "the test and the extracted file agree")


func test_an_unset_bar_is_white_as_the_swf_frame_draws_it() -> void:
	var bar: ElementBar = add_child_autofree(SCENE.instantiate())
	assert_eq((bar.get_node("Gbar") as ColorRect).color, Color.WHITE)
	assert_almost_eq((bar.get_node("Ybar") as ColorRect).color.r, 26.0 / 256.0, EPSILON)


func test_gbar_and_xbar_draw_a_glow_behind_themselves_and_ybar_and_bar_do_not() -> void:
	var bar: ElementBar = _bar()
	for layer: String in ["Gbar", "Xbar"]:
		var glow: ColorRect = bar.get_node("%s/Glow" % layer)
		assert_true(glow.show_behind_parent, layer)
		assert_not_null(glow.material, layer)
	assert_null(bar.get_node_or_null("Ybar/Glow"))
	assert_null(bar.get_node_or_null("Bar/Glow"))


func test_the_glow_reaches_past_its_bar_by_the_blur_and_follows_the_height() -> void:
	var bar: ElementBar = _bar()
	bar.show_value(0.0, LEVEL)
	var layer: ColorRect = bar.get_node("Gbar")
	var glow: ColorRect = bar.get_node("Gbar/Glow")
	# Three passes of a 9 px box blur reach 13.5 px, so 14 px of room.
	assert_almost_eq(glow.size.x, layer.size.x + 28.0, EPSILON)
	assert_almost_eq(glow.size.y, layer.size.y + 28.0, EPSILON)
	assert_almost_eq(glow.position.x, -14.0, EPSILON)
	assert_almost_eq(glow.position.y, -14.0, EPSILON)
	assert_eq((glow.material as ShaderMaterial).get_shader_parameter("node_size"), glow.size)


func test_each_bars_glow_material_is_its_own() -> void:
	var first: ElementBar = _bar()
	var second: ElementBar = _bar()
	assert_ne(first.get_node("Gbar/Glow").material, second.get_node("Gbar/Glow").material)
	assert_ne(first.get_node("Gbar/Glow").material, first.get_node("Xbar/Glow").material)


func test_the_glow_takes_the_color_of_its_layer() -> void:
	var bar: ElementBar = _bar(ElementBar.Kind.PIERCING, CombatUnit.Element.ICE)
	assert_eq((bar.get_node("Gbar/Glow").material as ShaderMaterial).get_shader_parameter("tint"), MenuTheme.ELEMENT_COLORS[CombatUnit.Element.ICE])
	assert_eq((bar.get_node("Xbar/Glow").material as ShaderMaterial).get_shader_parameter("tint"), Color.WHITE)


func test_the_layers_stack_in_the_order_the_swf_draws_them() -> void:
	var bar: ElementBar = _bar()
	var order: Array[int] = []
	for layer: String in ["Track", "Ybar", "Bar", "Gbar", "Xbar"]:
		order.append((bar.get_node(layer) as CanvasItem).z_index)
	var sorted: Array[int] = order.duplicate()
	sorted.sort()
	assert_eq(order, sorted, "z_index rises from the track to xbar, so every bar of a block draws a layer before the next one")
	assert_eq(order.size(), 5)
	assert_eq(order.count(order[0]), 1)


# The piercing tooltip (DefineSprite_3142/frame_1/DoAction.as:112-113): the title
# is ELEMENTS[k], SYSTEM[5], ": " and the value, and the body is SYSTEM[38], the
# rounded nT2, "%", SYSTEM[37], nT1, "%", SYSTEM[39], nT3, "%" and SYSTEM[40].
func test_the_piercing_tooltip_is_built_from_the_strings_and_the_rounded_percentages() -> void:
	var bar: ElementBar = _bar(ElementBar.Kind.PIERCING, 2)
	bar.show_value(115.0, LEVEL)
	# Value 115 + 115 = 230, x = 2. nT2 = 30, nT1 = 90 (the quartic at x + 1 = 3
	# is 0.9) and nT3 = 7.
	var tip: Dictionary = bar.tooltip()
	assert_eq(tip["title"], "%s %s: 230" % [Strings.text("ELEMENTS", 2), Strings.system(5)])
	assert_eq(tip["body"], "%s 30%% %s 90%% %s 7%% %s" % [Strings.system(38), Strings.system(37), Strings.system(39), Strings.system(40)])


func test_the_piercing_tooltip_percentages_are_not_capped_like_the_bars() -> void:
	var bar: ElementBar = _bar(ElementBar.Kind.PIERCING, 0)
	bar.show_value(2000.0, LEVEL)
	# x = 2115 / 115 = 18.391, so nT2 = 15 * x = 275.87, over the cap of the gbar.
	assert_string_contains(bar.tooltip()["body"], "276%")


func test_the_piercing_tooltip_rounds_the_percentages_like_math_round() -> void:
	var bar: ElementBar = _bar(ElementBar.Kind.PIERCING, 0)
	# x = 1.5 gives nT3 * 100 = 3.5000000000000004, which Math.round makes 4.
	bar.show_value(57.5, LEVEL)
	assert_string_contains(bar.tooltip()["body"], "%s 4%% %s" % [Strings.system(39), Strings.system(40)])
	# x = 0.5 gives -3.5000000000000004, which Math.round makes -4.
	bar.show_value(-57.5, LEVEL)
	assert_string_contains(bar.tooltip()["body"], "%s -4%% %s" % [Strings.system(39), Strings.system(40)])


func test_the_defense_tooltip_is_the_value_title_and_the_deftip_for_its_factor() -> void:
	var bar: ElementBar = _bar(ElementBar.Kind.DEFENSE, 5)
	bar.show_value(0.0, LEVEL)
	var tip: Dictionary = bar.tooltip()
	assert_eq(tip["title"], "%s %s: 115" % [Strings.text("ELEMENTS", 5), Strings.system(6)])
	assert_eq(tip["body"], Strings.text("DEFTIP", 1))


# Each pair is an allocation at level 1 (average 115) and the DEFTIP the
# original picks for its 1 / x (DoAction.as:128-153): x = 1 is the default 1,
# and a bigger x is a smaller 1 / x. The x values are 0.5, 1, 1.1, 1.5, 2, 3
# and 4, the same ones test_menu_math.gd uses.
func test_each_of_the_seven_deftip_factors_is_reachable_from_an_allocation() -> void:
	var cases: Array[Array] = [
		[-57.5, 0], [0.0, 1], [11.5, 2], [57.5, 3], [115.0, 4], [230.0, 5], [345.0, 6],
	]
	for case: Array in cases:
		var bar: ElementBar = _bar(ElementBar.Kind.DEFENSE, 0)
		bar.show_value(case[0], LEVEL)
		assert_eq(bar.tooltip()["body"], Strings.text("DEFTIP", case[1]), "allocation %s" % case[0])


func test_hovering_a_bar_shows_its_title_and_body_in_the_shared_tooltip_and_leaving_hides_them() -> void:
	GameTooltip.hide_tooltip()
	var bar: ElementBar = _bar(ElementBar.Kind.PIERCING, 2)
	bar.show_value(115.0, LEVEL)
	bar.mouse_entered.emit()
	assert_true(GameTooltip._root.visible)
	assert_eq(GameTooltip._sections.get_child_count(), 2, "a title section and a body section")
	var title: Label = GameTooltip._sections.get_child(0).get_child(0).get_child(0)
	var body: Label = GameTooltip._sections.get_child(1).get_child(0).get_child(0)
	assert_eq(title.text, bar.tooltip()["title"])
	assert_eq(body.text, bar.tooltip()["body"])
	bar.mouse_exited.emit()
	assert_false(GameTooltip._root.visible)


func test_hovering_a_bar_with_no_value_shows_no_tooltip() -> void:
	GameTooltip.hide_tooltip()
	var bar: ElementBar = _bar()
	bar.mouse_entered.emit()
	assert_false(GameTooltip._root.visible)


func test_a_whole_value_prints_without_a_fraction_and_a_fractional_one_keeps_it() -> void:
	var bar: ElementBar = _bar(ElementBar.Kind.PIERCING, 0)
	bar.show_value(0.5, LEVEL)
	assert_string_contains(bar.tooltip()["title"], ": 115.5")
