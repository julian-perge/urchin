# Ability.visual_effect_color - frame42/sonny2_moves.txt's colortobe value
# (11_visual_effect_color), tints the cast glow (both Missile and Shock)
# and the KrinTrail streak. docs/superpowers/specs/2026-08-18-missile-projectile-art-design.md.
extends GutTest


func test_visual_effect_color_parses_real_hex_value():
	var move: Ability = MoveManagerAuto.get_move(5)  # Nuke, Missile, "0xFF3366"
	assert_not_null(move, "move id 5 (Nuke) exists")
	assert_almost_eq(move.visual_effect_color.r, 1.0, 0.01)
	assert_almost_eq(move.visual_effect_color.g, 0.2, 0.01)
	assert_almost_eq(move.visual_effect_color.b, 0.4, 0.01)


func test_visual_effect_color_defaults_to_white_for_none_move():
	var move: Ability = MoveManagerAuto.get_move(0)  # "None" - Undefined sentinel
	assert_not_null(move)
	assert_eq(move.visual_effect_color, Color.WHITE)


func test_visual_effect_color_pads_a_short_hex_string():
	var move: Ability = MoveManagerAuto.get_move(261)  # Regulate, "0x066FF" - one digit short
	assert_not_null(move, "move id 261 (Regulate) exists")
	assert_almost_eq(move.visual_effect_color.r, 0.0, 0.01)
	assert_almost_eq(move.visual_effect_color.g, 0.4, 0.01)
	assert_almost_eq(move.visual_effect_color.b, 1.0, 0.01)
