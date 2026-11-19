# test_ability_icon.gd
# AbilityIcon draws an ability icon over its disc in a colour
# (DefineSprite_2427/frame_15/PlaceObject2_2244_1).
extends GutTest

const DiscReader = preload("res://test/disc_reader.gd")
# The disc shows only on the anti-aliased rim of most icons, so the colour read
# back from 8-bit pixels is off by up to a few levels.
const TOLERANCE: float = 0.02


func _assert_color(actual: Color, expected: Color, text: String) -> void:
	for channel in 3:
		assert_almost_eq(actual[channel], expected[channel], TOLERANCE, "%s, channel %d" % [text, channel])


func test_the_disc_takes_the_colour_it_is_given() -> void:
	for element in [CombatUnit.Element.PHYSICAL, CombatUnit.Element.ICE, CombatUnit.Element.POISON]:
		var color: Color = MenuTheme.ELEMENT_COLORS[element]
		var drawn: Texture2D = AbilityIcon.texture("Leading_Strike", color)
		_assert_color(DiscReader.disc_color(drawn, "Leading_Strike"), color, "element %d" % element)


func test_the_disc_is_not_the_grey_ffdec_bakes_in() -> void:
	var grey: Color = Color8(38, 38, 38)
	var drawn: Texture2D = AbilityIcon.texture("Ghost_State", MenuTheme.ELEMENT_COLORS[CombatUnit.Element.SHADOW])
	var read: Color = DiscReader.disc_color(drawn, "Ghost_State")
	assert_gt(absf(read.r - grey.r) + absf(read.g - grey.g) + absf(read.b - grey.b), 0.1)


func test_an_icon_that_shows_no_disc_is_the_extracted_file() -> void:
	assert_false(AbilityIcon.shows_disc("Empty"), "Empty's grey disc has no script")
	assert_eq(AbilityIcon.texture("Empty", Color.RED).resource_path, "res://assets/ui/abilities/Empty.png")


func test_a_missing_icon_is_null() -> void:
	assert_null(AbilityIcon.texture("No_Such_Move", Color.RED))


func test_a_moves_icon_takes_its_elements_colour() -> void:
	var move: Ability = MoveManagerAuto.get_move(120)
	assert_eq(move.display_name, "Adrenaline", "sanity")
	assert_eq(AbilityIcon.element_color(move), MenuTheme.ELEMENT_COLORS[move.damage_element_type])
	_assert_color(DiscReader.disc_color(AbilityIcon.for_move(move), "Adrenaline"), MenuTheme.ELEMENT_COLORS[move.damage_element_type], "Adrenaline")


func test_the_key_is_the_extractors_file_name() -> void:
	assert_eq(AbilityIcon.key("Dead Man's Plea"), "Dead_Man_s_Plea")
	assert_eq(AbilityIcon.key("Re-Energize"), "Re_Energize")
