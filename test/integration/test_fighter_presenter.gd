# FighterPresenter on its own, with a hand-made unit and hand-made results and
# no battle scene or save behind it. Fades are stepped with custom_step(), the
# doll's swing with its own _process() and Floating numbers with their layer's
# advance(), so nothing here waits on real time.
extends GutTest

const FighterPresenterScene = preload("res://scenes/battle/fighter_presenter.tscn")
const HOME: Vector2 = Vector2(300, 250)
const ENEMY_SLOT: int = 2
const ALLY_SLOT: int = 3
const VOICE_HIT: Array = ["hit_a", "hit_b"]
const VOICE_DIE: String = "die"
const STUN: CharacterVisual.State = CharacterVisual.State.STUN
const HIT: CharacterVisual.State = CharacterVisual.State.HIT
const DEAD: CharacterVisual.State = CharacterVisual.State.DEAD
const ENEMY_COLOR: Color = FighterPresenter.RING_COLORS[FighterPresenter.Relation.ENEMY]
# The colors of the Result flash's two colored glows in each of BATTLEFLASH's
# labels, 16763904, 10092288 and 3407871 in frame_42/DoAction_3.as:117-130 and
# 162-168.
const HIT_FLASH: Color = Color("#ffcc00")
const HEAL_FLASH: Color = Color("#99ff00")
const FOCUS_FLASH: Color = Color("#33ffff")

var _presenter: FighterPresenter
var _doll: CharacterVisual
var _overlay: UnitOverlay
var _flash: ResultFlash
var _layer: FloatingNumberLayer
var _unit: CombatUnit
var _cues: Array = []


func before_each():
	_unit = _make_unit(CombatUnit.Team.TWO, ENEMY_SLOT)
	_present(_unit)


func _make_unit(team: CombatUnit.Team, slot: int) -> CombatUnit:
	var unit := CombatUnit.new()
	unit.player_id = slot
	unit.player_name = "Prison Guard"
	unit.plevel = 7
	unit.team_side = team
	unit.life_u = 100.0
	unit.life_n = 100.0
	unit.focus_u = 50.0
	unit.focus_n = 50.0
	unit.voice_hit = VOICE_HIT
	unit.voice_die = VOICE_DIE
	return unit


# Builds a presenter the way battle_scene.gd does, on a Floating number layer of
# its own that only steps when a test steps it, and records every cue it asks
# for in order in _cues.
func _present(unit: CombatUnit, items_by_id: Dictionary = {}, buffs_by_id: Dictionary = {}) -> void:
	_layer = add_child_autofree(FloatingNumberLayer.new())
	_layer.set_process(false)
	_presenter = add_child_autofree(FighterPresenterScene.instantiate())
	_presenter.setup(unit, HOME, items_by_id, buffs_by_id, _layer)
	_doll = _presenter.get_node("Doll")
	_overlay = _presenter.get_node("Overlay")
	# The tests step the Result flash themselves through advance().
	_flash = _presenter.get_node("ResultFlash")
	_flash.set_process(false)
	_cues = []
	_presenter.voice_cue.connect(func(cues): _cues.append(cues))
	_presenter.effect_cue.connect(func(cue): _cues.append(cue))


# What a hand-made event leaves on the unit: the unit as _make_unit builds it,
# at the given life, with no stun and no buffs.
func _state(life: float) -> UnitSnapshot:
	var state := UnitSnapshot.new()
	state.life = life
	state.life_max = 100.0
	state.focus = 50.0
	state.focus_max = 50.0
	return state


func _result(kind: MoveResult.Kind, direction: MoveResult.Direction, amount: float, life_after: float) -> MoveResult:
	var result := MoveResult.new()
	result.kind = kind
	result.direction = direction
	result.amount = amount
	result.target_after = _state(life_after)
	return result


func _damage(amount: float, life_after: float) -> MoveResult:
	return _result(MoveResult.Kind.DAMAGE, MoveResult.Direction.HARM, amount, life_after)


func _heal(amount: float, life_after: float) -> MoveResult:
	return _result(MoveResult.Kind.HEAL, MoveResult.Direction.HEAL, amount, life_after)


# Damage on a target under sswitch heals it.
func _damage_that_heals(amount: float, life_after: float) -> MoveResult:
	return _result(MoveResult.Kind.DAMAGE, MoveResult.Direction.HEAL, amount, life_after)


# A heal on a target under sswitch hurts it.
func _heal_that_hurts(amount: float, life_after: float) -> MoveResult:
	return _result(MoveResult.Kind.HEAL, MoveResult.Direction.HARM, amount, life_after)


func _critical(result: MoveResult) -> MoveResult:
	result.critical = true
	return result


func _killing(result: MoveResult) -> MoveResult:
	result.killed = true
	return result


func _stunned_at_hit(result: MoveResult) -> MoveResult:
	result.target_stunned = true
	result.target_after.stun = 1.0
	return result


func _stunning(result: MoveResult) -> MoveResult:
	result.target_after.stun = 1.0
	return result


func _fire_move() -> Ability:
	var move := Ability.new()
	move.damage_element_type = CombatUnit.Element.FIRE
	return move


func _numbers() -> Array[FloatingNumber]:
	return _layer.numbers()


# Shows `result` on a fresh fighter and returns the labels of the Floating
# numbers it draws, oldest first.
func _labels_drawn_by(result: MoveResult, move: Ability = null) -> Array:
	_present(_make_unit(CombatUnit.Team.TWO, ENEMY_SLOT))
	_presenter.show_result(result, move)
	return _numbers().map(func(number): return number.label)


# Where a Floating number's holder draws each of its glyphs, from the left, in
# the holder's own units.
func _glyph_offsets(number: FloatingNumber) -> Array:
	return number.flasher.get_children().map(func(glyph): return glyph.position.x)


# Every layer sprite of a Floating number, glyph by glyph from the left and
# bottom first within a glyph.
func _layer_sprites(number: FloatingNumber) -> Array:
	var sprites: Array = []
	for glyph in number.flasher.get_children():
		sprites.append_array(glyph.get_children())
	return sprites


# The shares of white a Floating number's layer sprites are drawn with, each
# share once.
func _whites(number: FloatingNumber) -> Array:
	var whites: Array = []
	for sprite in _layer_sprites(number):
		var white: float = (sprite.material as ShaderMaterial).get_shader_parameter("white")
		if not whites.has(white):
			whites.append(white)
	return whites


func _stun() -> void:
	_unit.stun = 1.0
	_presenter.snap_to_unit()


# Steps the doll for two seconds, which outlasts its hit label.
func _play_out_the_hit() -> void:
	for frame in 60:
		_doll._process(1.0 / 30.0)


func test_setup_draws_the_unit():
	_unit.life_u = 250.0
	_unit.life_n = 180.0
	_unit.focus_n = 30.0
	_present(_unit)
	assert_eq(_overlay.name_label.text, "Prison Guard", "the name")
	assert_eq(_overlay.health_bar.max_value, 250.0, "the health bar's scale")
	assert_eq(_overlay.health_bar.value, 180.0, "the health bar")
	assert_eq(_overlay.health_value.text, "180", "the number beside it")
	assert_eq(_overlay.focus_bar.max_value, 50.0, "the focus bar's scale")
	assert_eq(_overlay.focus_bar.value, 30.0, "the focus bar")


func test_a_fighter_with_no_focus_keeps_a_valid_focus_bar():
	_unit.focus_u = 0.0
	_unit.focus_n = 0.0
	_present(_unit)
	assert_eq(_overlay.focus_bar.max_value, 1.0)


func test_setup_draws_the_hover_ring_through_the_presenter():
	assert_true(_overlay.ring.draw.is_connected(_presenter._draw_ring))


func test_a_unit_already_stunned_at_setup_plays_no_stun_animation():
	_unit.stun = 1.0
	_present(_unit)
	assert_ne(_doll._state, STUN)


func test_setup_mirrors_an_enemy_doll_and_leaves_its_overlay_readable():
	assert_eq(_doll.position, HOME, "the doll stands at its slot")
	assert_eq(_doll.scale.x, -1.0, "team 2 is mirrored to face left")
	assert_eq(_overlay.position, HOME, "the overlay sits at the doll")
	assert_eq(_overlay.scale.x, 1.0, "and is not mirrored")


func test_setup_leaves_a_team_one_doll_unmirrored():
	_present(_make_unit(CombatUnit.Team.ONE, ALLY_SLOT))
	assert_eq(_doll.scale.x, 1.0)


func test_setup_stands_a_model5_smaller_and_lower():
	var unit: CombatUnit = _make_unit(CombatUnit.Team.ONE, ALLY_SLOT)
	unit.model = ["MODEL5", "ONE", "ONE", "M"]
	_present(unit)
	assert_almost_eq(_doll.scale.x, 0.8, 0.001, "dressChar's 0.8x scale")
	assert_eq(_doll.position, HOME + Vector2(0, 10), "10 px lower")
	assert_eq(_overlay.position, _doll.position, "with the overlay on it")


func test_setup_dresses_the_doll_from_the_item_table():
	var unit: CombatUnit = _make_unit(CombatUnit.Team.ONE, ALLY_SLOT)
	unit.equipment_ids = [0, 7]
	var armor: GameItem = GameItem.new()
	armor.looks = "ARCTIC"
	_present(unit, {7: armor})
	assert_eq(_doll._parts["chest"].get_child_count(), 2, "the chest's skin plus the ARCTIC armor")


# The runner applies a whole half-turn before the replay starts, so the unit is
# already at 40 here while the hit that took it there has not been shown.
func test_the_bars_only_move_when_the_hit_lands():
	_unit.life_n = 40.0
	assert_eq(_overlay.health_bar.value, 100.0, "before the hit the bar is where it was")
	assert_eq(_overlay.health_value.text, "100", "and the number beside it")

	_presenter.show_result(_damage(60.0, 40.0), null)
	assert_eq(_overlay.health_bar.value, 40.0, "the bar drops when the hit lands")
	assert_eq(_overlay.health_value.text, "40", "and so does the number")
	assert_eq(_presenter.displayed.life, 40.0, "and the health it displays")


func test_each_hit_of_a_half_turn_shows_the_life_it_left():
	_unit.life_n = 40.0
	_presenter.show_result(_damage(25.0, 75.0), null)
	assert_eq(_overlay.health_bar.value, 75.0, "the first hit shows only itself")
	_presenter.show_result(_damage(35.0, 40.0), null)
	assert_eq(_overlay.health_bar.value, 40.0, "and the second reaches the unit's life")


# A result states the target's whole life, so the bar shows that life even when
# the unit also lost life to something the screen has not shown yet. Here that
# was 40, as a damage-over-time tick earlier in the half-turn can take, and the
# move moved 10 either way.
func test_a_result_shows_the_life_it_states_with_an_earlier_loss_in_it():
	for result in [
		_damage(10.0, 50.0),
		_damage_that_heals(10.0, 70.0),
		_heal_that_hurts(10.0, 50.0),
		_heal(10.0, 70.0),
	]:
		var label: String = "%s that pushed %s" % [MoveResult.Kind.find_key(result.kind), MoveResult.Direction.find_key(result.direction)]
		_present(_make_unit(CombatUnit.Team.TWO, ENEMY_SLOT))
		_presenter.show_result(result, null)
		assert_eq(_presenter.displayed.life, result.target_after.life, "a %s takes the earlier loss along with it" % label)
		assert_eq(_overlay.health_value.text, str(int(result.target_after.life)), "and so does the number beside the bar")


# A damage-over-time tick with no later event on the unit only reaches the bar
# when the half-turn ends.
func test_the_bars_snap_to_the_unit_at_half_turn_end():
	_unit.life_n = 63.0
	assert_eq(_overlay.health_bar.value, 100.0, "still held back before the snap")

	_presenter.snap_to_unit()
	assert_eq(_overlay.health_bar.value, 63.0, "the bar shows the unit's life")
	assert_eq(_overlay.health_value.text, "63", "and so does the number")
	assert_eq(_presenter.displayed.life, 63.0, "and the health it displays")


# A unit pays its move's costs as the move dispatches, and the original redraws
# its bars right there (the conductor, lines 357-359). The runner has already
# taken the unit to its Focus at the half-turn's end, so the bar waits for the
# move to start.
func test_a_focus_cost_shows_when_the_move_starts_and_not_before():
	_unit.life_n = 70.0
	_unit.focus_n = 12.0
	_presenter.show_result(_damage(10.0, 90.0), null)
	assert_eq(_overlay.focus_bar.value, 50.0, "a hit before the move leaves the Focus it states")

	var dispatched: UnitSnapshot = _state(80.0)
	dispatched.focus = 30.0
	_presenter.show_state(dispatched)
	assert_eq(_overlay.focus_bar.value, 30.0, "the move's start shows the Focus its cost left")
	assert_eq(_overlay.health_bar.value, 80.0, "and the life its cost left")


func _buff_icons() -> Array:
	return _overlay.buff_row.get_children().filter(func(icon): return not icon.is_queued_for_deletion())


# The runner resolves the whole half-turn before the replay, so a buff that a
# later hit lands is already on the unit when an earlier hit plays. The original
# draws a unit's buff icons in applyChangesKrin, which the conductor runs on the
# target after each strike that lands (line 103), so the icon waits for the hit
# that lands it.
func test_a_buff_landed_late_in_a_half_turn_shows_only_once_its_result_plays():
	var buff := Buff.new()
	buff.internal_name = "FIRESAM"
	_present(_unit, {}, {1: buff})
	var slot: Dictionary = {"cd": 3, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0}
	_unit.buff_slots[0] = slot.duplicate()

	_presenter.show_result(_damage(10.0, 90.0), null)
	assert_eq(_buff_icons().size(), 0, "a hit before the one that lands the buff shows no icon")

	var landing: MoveResult = _damage(10.0, 80.0)
	landing.target_after.buff_slots = [slot.duplicate()]
	_presenter.show_result(landing, null)
	assert_eq(_buff_icons().size(), 1, "the hit that lands it shows it, from the buff table")


# Shatter Bolt lands its stun as a buff, so its target shows the stun pose and
# the buff's icon. Both wait for the hit that lands them, where the original's
# applyChangesKrin draws them (the conductor, line 103).
func test_a_stun_icon_shows_only_at_the_hit_that_lands_it():
	var buff := Buff.new()
	buff.internal_name = "SHATTERBOLT"
	_present(_unit, {}, {1: buff})
	var slot: Dictionary = {"cd": 2, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0}
	_unit.buff_slots[0] = slot.duplicate()
	_unit.stun = 1.0

	_presenter.show_result(_damage(10.0, 90.0), null)
	_play_out_the_hit()
	assert_eq(_buff_icons().size(), 0, "a hit before the stun shows no icon")
	assert_ne(_doll._state, STUN, "and no stun")

	var stunning: MoveResult = _stunning(_result(MoveResult.Kind.STATUS_ONLY, MoveResult.Direction.NONE, 0.0, 90.0))
	stunning.target_after.buff_slots = [slot.duplicate()]
	_presenter.show_result(stunning, null)
	assert_eq(_buff_icons().size(), 1, "the hit that lands the stun shows its icon")
	assert_eq(_doll._state, STUN, "and starts the stun")


func test_a_hit_bigger_than_the_displayed_health_stops_the_bar_at_empty():
	_presenter.show_result(_damage(250.0, 0.0), null)
	assert_eq(_presenter.displayed.life, 0.0, "the displayed health stops at zero")
	assert_eq(_overlay.health_value.text, "0", "and so does the number")


# KrinNumberShow draws a heal in its HEAL color, 0x66FF00, with the same digits
# as any other number (frame_42/DoAction_7.as:10-13).
func test_a_heal_raises_the_bar_with_a_green_number_and_no_plus():
	_unit.life_n = 40.0
	_presenter.snap_to_unit()
	_presenter.show_result(_heal(12.0, 52.0), null)
	assert_eq(_overlay.health_bar.value, 52.0, "the bar rises by the heal")
	var number: FloatingNumber = _numbers()[-1]
	assert_eq(number.label, "normal", "the normal label")
	assert_eq(number.glyphs, ["1", "2"], "12 with no plus")
	assert_eq(number.tint, Color("66FF00"), "in heal green")
	assert_eq(_cues, [], "a heal plays no voice")
	_presenter.show_result(_heal(500.0, 100.0), null)
	assert_eq(_presenter.displayed.life, 100.0, "and it stops at full")


# The original's whole heal branch is inside DamageOutputKrinFinal > 0
# (frame_42/DoAction_8.as:172), so a heal of 0 draws nothing.
func test_a_heal_of_zero_draws_no_number():
	_presenter.show_result(_heal(0.0, 100.0), null)
	assert_eq(_numbers().size(), 0)


# KrinNumberShow colors a number by the move's element, from elementColorArray
# (frame_42/DoAction_7.as:14-22 and frame_41/DoAction_2.as:2).
func test_a_damage_number_takes_the_moves_element_color():
	assert_eq(_labels_drawn_by(_damage(12.0, 88.0), _fire_move()), ["normal"], "one number")
	assert_eq(_numbers()[0].glyphs, ["1", "2"], "12")
	assert_eq(_numbers()[0].tint, Color("FF6600"), "in the Fire color")


func test_a_damage_number_without_an_element_is_white():
	_presenter.show_result(_damage(5.0, 95.0), null)
	assert_eq(_numbers()[-1].tint, Color.WHITE, "no move")
	var elementless := Ability.new()
	elementless.damage_element_type = -1 as CombatUnit.Element
	_presenter.show_result(_damage(5.0, 90.0), elementless)
	assert_eq(_numbers()[-1].tint, Color.WHITE, "a move with no element")


# KrinNumberShow plays the critical label for any number while perKSuccess is
# set (frame_42/DoAction_7.as:42-49), so a crit heal plays it too. That label
# starts at 2.84x and flickers white every other frame over its frames 7 to 18
# (DefineSprite 53, frames 75-86).
func test_a_crit_plays_the_critical_label_for_a_heal_as_well_as_damage():
	for result in [
		_critical(_damage(12.0, 88.0)),
		_critical(_damage_that_heals(12.0, 100.0)),
		_critical(_heal_that_hurts(12.0, 88.0)),
		_critical(_heal(12.0, 100.0)),
	]:
		var kind: String = "%s that pushed %s" % [MoveResult.Kind.find_key(result.kind), MoveResult.Direction.find_key(result.direction)]
		assert_eq(_labels_drawn_by(result), ["critical"], "a crit %s" % kind)
	var heal: FloatingNumber = _numbers()[0]
	assert_almost_eq(heal.flasher.scale.x, 2.842, 0.001, "2.84x on its first frame")
	_step(6)
	assert_eq(_whites(heal), [1.0], "white on frame 7")
	_step(1)
	assert_eq(_whites(heal), [0.0], "in its own color on frame 8")


func test_a_hit_flinches_the_doll_and_plays_the_hit_voice():
	_presenter.show_result(_damage(10.0, 90.0), null)
	assert_eq(_doll._state, HIT, "the flinch")
	assert_eq(_cues, [VOICE_HIT], "and the unit's hit voices")


# A move-caused death used to play only when the queued DEATH event was reached,
# which for a melee hit is after the caster has run back.
func test_a_killing_blow_plays_the_death_at_the_impact():
	_presenter.show_result(_killing(_damage(100.0, 0.0)), null)
	assert_eq(_doll._state, DEAD, "the doll plays its death at the impact")
	assert_false(_overlay.visible, "the overlay goes the same moment")
	assert_eq(_cues, [VOICE_DIE, VOICE_HIT], "the death cry, then the hit voice")


func test_die_plays_the_death_with_no_hit():
	_presenter.die()
	assert_eq(_doll._state, DEAD, "the doll plays its death")
	assert_false(_overlay.visible, "the overlay goes with it")
	assert_eq(_cues, [VOICE_DIE], "with the death cry alone")


# Damage on a target under an sswitch buff heals it. The original raises life
# capped at max and plays no hit animation (frame_42/DoAction_8.as:133-149). It
# leaves a heal green number on top (line 137), and the port draws only that
# one (ADR 0005).
func test_damage_on_a_sswitch_target_shows_as_a_heal():
	_unit.life_n = 50.0
	_presenter.snap_to_unit()
	_presenter.show_result(_damage_that_heals(15.0, 65.0), _fire_move())
	assert_eq(_overlay.health_bar.value, 65.0, "the bar rises, because the damage healed the target")
	assert_eq(_numbers().size(), 1, "one number")
	assert_eq(_numbers()[0].glyphs, ["1", "5"], "the amount the damage healed")
	assert_eq(_numbers()[0].tint, Color("66FF00"), "drawn in heal green")
	assert_ne(_doll._state, HIT, "no hit animation")
	assert_eq(_cues, [], "and no hit voice")


func test_damage_on_a_sswitch_target_stops_the_bar_at_full():
	_presenter.show_result(_damage_that_heals(15.0, 100.0), null)
	assert_eq(_presenter.displayed.life, 100.0)


# A heal on a target under an sswitch buff hurts it. The original draws the
# number in the Shadow color, lowers life and plays the hit animation
# (frame_42/DoAction_8.as:189-207).
func test_heal_on_a_sswitch_target_shows_as_damage():
	_presenter.show_result(_heal_that_hurts(20.0, 80.0), null)
	assert_eq(_overlay.health_bar.value, 80.0, "the bar falls, because the heal hurt the target")
	assert_eq(_numbers()[-1].glyphs, ["2", "0"], "the amount the heal took")
	assert_eq(_numbers()[-1].tint, Color("664D80"), "drawn in the Shadow color")
	assert_eq(_doll._state, HIT, "the hit animation plays")
	assert_eq(_cues, [], "but no hit voice")


# A heal bigger than an sswitch target's life kills it, and the original plays
# the death at that impact (frame_42/DoAction_8.as:208-228).
func test_heal_that_kills_a_sswitch_target_plays_the_death():
	_presenter.show_result(_killing(_heal_that_hurts(150.0, 0.0)), null)
	assert_eq(_doll._state, DEAD, "the doll plays its death")
	assert_false(_overlay.visible, "its overlay is hidden with it")
	assert_eq(_presenter.displayed.life, 0.0, "the bar drops to empty")
	assert_eq(_cues, [VOICE_DIE], "with the death cry and no hit voice")


# The original skips the hit animation on a stunned target for plain damage
# (frame_42/DoAction_8.as:101-104), so a hit that doesn't kill leaves the doll
# in its stun. The hit voice still plays.
func test_damage_on_a_stunned_target_keeps_it_stunned():
	_stun()
	_presenter.show_result(_stunned_at_hit(_damage(10.0, 90.0)), null)
	assert_eq(_doll._state, STUN, "no hit animation on a stunned target")
	assert_eq(_cues, [VOICE_HIT], "the hit voice still plays")


# The same skip applies to a heal that hurts a stunned target
# (frame_42/DoAction_8.as:204-207).
func test_heal_on_a_stunned_sswitch_target_keeps_it_stunned():
	_stun()
	_presenter.show_result(_stunned_at_hit(_heal_that_hurts(10.0, 90.0)), null)
	assert_eq(_doll._state, STUN, "no hit animation on a stunned target")


# The runner resolves the whole half-turn before the replay, so the unit's stun
# is already the one it ends the half-turn with when an earlier event plays. The
# original reads the stun when a hit lands to decide the flinch
# (frame_42/DoAction_8.as:100-103), and starts the stun pose at the strike that
# lands the stun (the conductor, line 103), so the doll goes by the stun each
# result states.
func test_a_stun_from_later_in_the_half_turn_waits_for_the_hit_that_lands_it():
	_unit.stun = 1.0
	assert_ne(_doll._state, STUN, "the unit's stun doesn't show before the hit that lands it")
	_presenter.show_result(_damage(10.0, 90.0), null)
	assert_eq(_doll._state, HIT, "a hit before it flinches")
	_play_out_the_hit()
	_presenter.show_result(_stunning(_damage(10.0, 80.0)), null)
	assert_eq(_doll._state, STUN, "and the hit that lands it starts the stun")

	_present(_make_unit(CombatUnit.Team.TWO, ENEMY_SLOT))
	_presenter.show_result(_stunned_at_hit(_damage(10.0, 90.0)), null)
	assert_ne(_doll._state, HIT, "a stun that has worn off by the half-turn's end still stops the flinch")


# The original plays a hit's flinch and starts the stun it lands at the same
# strike, so the doll ends up stunned.
func test_a_hit_that_lands_a_stun_leaves_the_doll_stunned():
	_presenter.show_result(_stunning(_damage(10.0, 90.0)), null)
	_play_out_the_hit()
	assert_eq(_doll._state, STUN)


# The original's Focus branch draws no number, only the focus flash
# (frame_42/DoAction_8.as:232-249).
func test_a_focus_result_draws_no_number():
	_presenter.show_result(_result(MoveResult.Kind.FOCUS, MoveResult.Direction.NONE, 8.0, 100.0), null)
	assert_eq(_numbers().size(), 0)


# A focus move can dispel a buff that holds up max life, and the recompute after
# it then moves life. The original redraws the bar after every strike that lands
# (the conductor, line 103) and runs nothing on a miss, so every result but a
# miss moves the bar to the life it states.
func test_every_result_but_a_miss_moves_the_bar_to_the_life_it_states():
	for kind in [MoveResult.Kind.FOCUS, MoveResult.Kind.STATUS_ONLY]:
		_present(_make_unit(CombatUnit.Team.TWO, ENEMY_SLOT))
		_presenter.show_result(_result(kind, MoveResult.Direction.NONE, 0.0, 25.0), null)
		assert_eq(_overlay.health_bar.value, 25.0, "a %s result moves the bar" % MoveResult.Kind.find_key(kind))

	_present(_make_unit(CombatUnit.Team.TWO, ENEMY_SLOT))
	_presenter.show_result(_result(MoveResult.Kind.MISS, MoveResult.Direction.NONE, 0.0, 25.0), null)
	assert_eq(_overlay.health_bar.value, 100.0, "a miss leaves it")


# The conductor passes a miss the move's element (line 108), and KrinNumberShow
# gives the MISS word's KN fill that element's color (frame_42/DoAction_7.as:63-68).
func test_a_miss_shows_the_miss_word_in_the_moves_element_color():
	var miss: MoveResult = _result(MoveResult.Kind.MISS, MoveResult.Direction.NONE, 0.0, 100.0)
	assert_eq(_labels_drawn_by(miss, _fire_move()), ["miss"], "the miss label")
	var number: FloatingNumber = _numbers()[0]
	assert_eq(number.glyphs, ["miss"], "the MISS word")
	assert_eq(number.tint, Color("FF6600"), "in the Fire color")
	assert_eq(_cues, ["sfx_magicmiss"], "the miss sound")
	assert_ne(_doll._state, HIT, "and no flinch")


# Shatter Bolt only applies a status effect, and at its impact the original
# draws no number and plays no hit flinch. The target's stun animation still
# starts there, because the conductor runs applyChangesKrin on the target right
# after the status lands (conductor line 103).
func test_a_status_only_result_starts_the_stun_and_draws_no_number():
	_unit.stun = 1.0
	_presenter.show_result(_stunning(_result(MoveResult.Kind.STATUS_ONLY, MoveResult.Direction.NONE, 0.0, 100.0)), null)
	assert_eq(_numbers().size(), 0, "no number floats up")
	assert_eq(_doll._state, STUN, "the target's stun animation starts at the impact")
	assert_eq(_cues, [], "and nothing plays")


func test_any_rise_in_stun_replays_the_stun_animation():
	_stun()
	assert_eq(_doll._state, STUN, "the first stun")
	_doll._process(0.1)
	assert_gt(_doll._label_time, 0.0, "sanity: the animation has moved on")
	_unit.stun = 2.0
	_presenter.snap_to_unit()
	assert_eq(_doll._label, "stun", "a second stun plays the stun-in label")
	assert_eq(_doll._label_time, 0.0, "from its start")


func test_a_result_with_no_change_in_stun_leaves_the_animation_alone():
	_stun()
	_doll._process(0.1)
	var time_into_label: float = _doll._label_time
	_presenter.show_result(_stunned_at_hit(_damage(10.0, 90.0)), null)
	assert_eq(_doll._label_time, time_into_label)


func test_any_fall_in_stun_plays_the_wake_up_even_while_still_stunned():
	_unit.stun = 2.0
	_presenter.snap_to_unit()
	_unit.stun = 1.0
	_presenter.snap_to_unit()
	assert_eq(_doll._label, "outofstun", "a partial fall still plays the wake-up")


# A unit stunned when its half-turn starts can fall to a later hit in it, so the
# runner has it inactive before the replay reaches that hit. The original keeps
# it in its stun until the hit that kills it, and changes no dead unit's stun
# pose (frame_42/DoAction_10.as:468).
func test_a_stunned_unit_stays_stunned_until_its_death_plays():
	_stun()
	_unit.active = false
	assert_eq(_doll._state, STUN, "the doll is still stunned")
	assert_ne(_doll._label, "outofstun", "and doesn't wake up first")
	var killing_stun: MoveResult = _stunned_at_hit(_killing(_damage(100.0, 0.0)))
	killing_stun.target_after.stun = 2.0
	_presenter.show_result(killing_stun, null)
	assert_eq(_doll._state, DEAD, "the hit that kills it plays the death, though it lands another stun")
	_unit.stun = 2.0
	_presenter.snap_to_unit()
	assert_eq(_doll._state, DEAD, "and the half-turn's end leaves the death alone")


# The ring fades in at +20 a frame at the original's 30 fps
# (frame_217/PlaceObject3_3394_450).
func test_the_ring_fades_in_over_its_fade_in_time():
	var ring: Control = _overlay.ring
	assert_eq(ring.modulate.a, 0.0, "starts invisible")
	_presenter.show_hover(true)
	var fade: Tween = _presenter._ring_fade
	fade.pause()
	fade.custom_step(FighterPresenter.RING_FADE_IN_TIME * 0.5)
	assert_almost_eq(ring.modulate.a, 0.5, 0.01, "half faded in at the halfway point")
	fade.custom_step(FighterPresenter.RING_FADE_IN_TIME * 0.5)
	assert_almost_eq(ring.modulate.a, 1.0, 0.001, "and fully in at the end")


# It fades out at -5 a frame, four times slower than it fades in.
func test_the_ring_fades_out_over_its_fade_out_time():
	var ring: Control = _overlay.ring
	ring.modulate.a = 1.0
	_presenter.show_hover(false)
	var fade: Tween = _presenter._ring_fade
	fade.pause()
	fade.custom_step(FighterPresenter.RING_FADE_OUT_TIME * 0.5)
	assert_almost_eq(ring.modulate.a, 0.5, 0.01, "half faded out at the halfway point")
	fade.custom_step(FighterPresenter.RING_FADE_OUT_TIME * 0.5)
	assert_almost_eq(ring.modulate.a, 0.0, 0.001, "and gone at the end")


func test_a_new_hover_replaces_the_running_fade():
	_presenter.show_hover(true)
	var interrupted: Tween = _presenter._ring_fade
	_presenter.show_hover(false)
	assert_false(interrupted.is_valid(), "the running fade is killed, not left to fight the new one")


func test_hover_shows_the_level_in_the_relation_color():
	_presenter.show_hover(true)
	var info: Label = _level_labels()[0]
	assert_eq(info.text, "Lvl. 7", "the unit's level")
	assert_eq(info.get_theme_color("font_color"), ENEMY_COLOR, "in the ring's color")


func test_the_ring_color_follows_the_units_relation_to_the_player():
	for case in [
		[BattleRunner.PLAYER_SLOT, CombatUnit.Team.ONE, FighterPresenter.Relation.PLAYER],
		[ALLY_SLOT, CombatUnit.Team.ONE, FighterPresenter.Relation.ALLY],
		[ENEMY_SLOT, CombatUnit.Team.TWO, FighterPresenter.Relation.ENEMY],
	]:
		_present(_make_unit(case[1], case[0]))
		_presenter.show_hover(true)
		assert_eq(_level_labels()[0].get_theme_color("font_color"), FighterPresenter.RING_COLORS[case[2]], "slot %d" % case[0])


# A label that is queued for deletion stays in the tree until the frame ends.
func _level_labels() -> Array:
	return _overlay.get_children().filter(func(child):
		return child is Label and child.text.begins_with("Lvl.") and not child.is_queued_for_deletion()
	)


func test_leaving_takes_the_level_away():
	_presenter.show_hover(true)
	assert_eq(_level_labels().size(), 1, "the level shows")
	_presenter.show_hover(false)
	assert_eq(_level_labels().size(), 0, "and goes without another taking its place")


func test_hovering_again_shows_one_level_at_a_time():
	_presenter.show_hover(true)
	_presenter.show_hover(true)
	assert_eq(_level_labels().size(), 1, "a second hover replaces the label")
	_presenter.show_hover(false)
	assert_eq(_level_labels().size(), 0, "and leaving takes it away")
	await wait_process_frames(1)
	_presenter.show_hover(true)
	assert_eq(_level_labels().size(), 1, "it comes back once the old one is gone")


func test_hovering_a_dead_fighter_does_nothing():
	_unit.active = false
	_presenter.show_hover(true)
	assert_null(_presenter._ring_fade, "no fade starts")
	assert_eq(_level_labels().size(), 0, "and no level shows")


# KrinNumberShow puts a number on the target rig's own spot with no offset
# (frame_42/DoAction_7.as:38-39). It sets the digits 19 apart along the holder,
# the first at -19 * (digits - 2) / 2 - 10 (lines 3, 34-35 and 56), so three
# digits sit at -19.5, -0.5 and 18.5: around the rig's origin, half a unit to the
# left because half a spacing is 9.5.
func test_a_three_digit_number_draws_three_digits_19_apart_around_the_rig():
	_presenter.show_result(_damage(123.0, 0.0), null)
	var number: FloatingNumber = _numbers()[-1]
	assert_eq(number.position, HOME, "on the target rig's origin")
	assert_eq(number.glyphs, ["1", "2", "3"], "the digits from the left")
	assert_eq(_glyph_offsets(number), [-19.5, -0.5, 18.5], "19 apart around the origin")


# dressChar lowers only a MODEL5 unit's doll inside its rig
# (frame_217/DoAction_2.as:19-24), and KrinNumberShow puts the number on the
# rig itself.
func test_a_model5_units_number_stays_on_the_rig_above_its_lowered_doll():
	var unit: CombatUnit = _make_unit(CombatUnit.Team.ONE, ALLY_SLOT)
	unit.model = ["MODEL5", "ONE", "ONE", "M"]
	_present(unit)
	_presenter.show_result(_damage(5.0, 95.0), null)
	assert_eq(_numbers()[-1].position, HOME)


# KrinNumberShow attaches each number one depth above the last and goes from
# depth 1639 back to 1620 (frame_42/DoAction_7.as:4 and 75-79), and a clip
# attached at a depth that is in use replaces the clip there.
func test_a_21st_live_number_replaces_the_oldest():
	_presenter.show_result(_damage(1.0, 99.0), null)
	var oldest: FloatingNumber = _numbers()[0]
	for amount in range(2, 22):
		_presenter.show_result(_damage(amount, 100.0 - amount), null)
	var shown: Array = _numbers().map(func(number): return "".join(number.glyphs))
	assert_eq(shown.size(), 20, "20 numbers at most")
	assert_eq([shown[0], shown[-1]], ["2", "21"], "from the second number to the 21st")
	assert_true(oldest.is_queued_for_deletion(), "and the first one is freed")


# A shield can leave less than 1 of a hit. KrinNumberShow still attaches a
# number for anything above 0, but its digit loop starts below the ones digit
# and draws no digit (frame_42/DoAction_7.as:8 and 26-61).
func test_a_hit_under_one_plays_a_number_with_no_digits():
	assert_eq(_labels_drawn_by(_damage(0.5, 99.5)), ["normal"], "a number")
	assert_eq(_numbers()[0].glyphs, [], "with no digits")


# Steps every Floating number on by `frames` frames of the SWF's 30 fps.
func _step(frames: int) -> void:
	for frame in frames:
		_layer.advance(1.0 / 30.0)


# The color each layer sprite of a Floating number replaces its own with, or
# null for a sprite that keeps its own.
func _layer_tints(number: FloatingNumber) -> Array:
	return _layer_sprites(number).map(func(sprite):
		var material: ShaderMaterial = sprite.material
		return material.get_shader_parameter("tint") if material.get_shader_parameter("tinted") else null
	)


# KrinNumberShow's setRGB colors only the KN fill of each digit, the middle of
# its three layers, and leaves the outline and the shine alone
# (frame_42/DoAction_7.as:58-59).
func test_only_each_digits_kn_fill_takes_the_numbers_color():
	_presenter.show_result(_damage(12.0, 88.0), _fire_move())
	var fire: Color = Color("FF6600")
	assert_eq(_layer_tints(_numbers()[-1]), [null, fire, null, null, fire, null])


# SHIELDED (DefineSprite 52) is one layer with no KN child, so it takes no color.
func test_shielded_takes_no_color():
	_layer.show_shield(HOME)
	assert_eq(_layer_tints(_numbers()[-1]), [null])


# NumberFixer's normal label pops the number in all white at 1.78x, settles it
# at 1x in its own color by frame 6, lifts it 27.5 px by frame 45 and fades it
# out over frames 53 to 67 (DefineSprite 53).
func test_a_normal_number_pops_in_white_settles_rises_and_fades():
	_presenter.show_result(_damage(12.0, 88.0), _fire_move())
	var number: FloatingNumber = _numbers()[-1]
	assert_almost_eq(number.flasher.scale.x, 1.776, 0.001, "1.78x on frame 1")
	assert_eq(_whites(number), [1.0], "all white on frame 1")
	_step(5)
	assert_eq(number.flasher.scale, Vector2.ONE, "1x on frame 6")
	assert_eq(_whites(number), [0.0], "in its own color on frame 6")
	_step(39)
	assert_eq(number.flasher.position.y, -27.5, "27.5 px up on frame 45")
	assert_eq(number.flasher.modulate.a, 1.0, "and not faded yet")
	_step(22)
	assert_eq(number.flasher.modulate.a, 0.0, "faded out on frame 67")


# NumberFixer's labels run frames 1-67, 69-129, 131-181 and 183-233, and the
# frame after each one runs removeMovieClip(this) (DefineSprite 53).
func test_each_label_runs_its_swf_frame_count_and_frees_itself():
	for case in [
		["normal", 67, func(): _layer.show_number(HOME, 12.0, Color.WHITE, false)],
		["critical", 61, func(): _layer.show_number(HOME, 12.0, Color.WHITE, true)],
		["miss", 51, func(): _layer.show_miss(HOME, Color.WHITE)],
		["shield", 51, func(): _layer.show_shield(HOME)],
	]:
		case[2].call()
		var number: FloatingNumber = _numbers()[-1]
		assert_eq(number.label, case[0], "the label")
		_step(case[1] - 1)
		assert_true(_numbers().has(number), "%s still shows on frame %d" % [case[0], case[1]])
		_step(1)
		assert_false(_numbers().has(number), "%s is gone after frame %d" % [case[0], case[1]])
		assert_true(number.is_queued_for_deletion(), "and %s has freed itself" % case[0])


# Starts a melee whose swing the test steps by hand. The returned array holds
# what melee() returned once it has returned.
func _start_melee(on_blow: Callable) -> Array:
	_doll.set_process(false)
	var returned: Array = []
	var run: Callable = func():
		returned.append(await _presenter.melee(Vector2(100, 0), "Attack", on_blow))
	run.call()
	return returned


func test_melee_lands_the_blow_once_and_returns_when_the_doll_is_home():
	var blows: Array = []
	var returned: Array = _start_melee(func(): blows.append(_doll.position))
	assert_eq(blows.size(), 0, "nothing lands as the run starts")
	for frame in 600:
		if not returned.is_empty():
			break
		_doll._process(1.0 / 30.0)
	assert_eq(blows.size(), 1, "the blow lands once")
	if blows.size() == 1:
		assert_almost_eq(blows[0].x, HOME.x + 100.0, 0.01, "at the target, before the run back")
	assert_eq(_doll.position, HOME, "the doll is home")
	assert_eq(returned, [false], "and nothing was landed late")


func test_an_interrupted_melee_still_lands_the_blow():
	var blows: Array = []
	var returned: Array = _start_melee(func(): blows.append(true))
	_doll.set_state(CharacterVisual.State.DEAD)
	assert_eq(blows.size(), 1, "the blow never fired, so it lands late")
	assert_eq(returned, [true], "and melee says so")


func test_melee_without_waiting_lands_the_blow_at_once():
	var blows: Array = []
	var landed_late: bool = await _presenter.melee(Vector2(100, 0), "Attack", func(): blows.append(true), false)
	assert_eq(blows.size(), 1, "the blow lands without the swing being played")
	assert_true(landed_late)


func test_a_melee_whose_presenter_left_the_tree_lands_nothing():
	var blows: Array = []
	var returned: Array = _start_melee(func(): blows.append(true))
	remove_child(_presenter)
	_doll.melee_finished.emit()
	assert_eq(blows.size(), 0, "no blow on a fighter that is gone")
	assert_eq(returned, [false])


# The real colortobe glow tint (frame217/onClipEvent(enterFrame).as: 417,450).
func test_cast_plays_the_cast_state_tinted_with_the_moves_color():
	var move := Ability.new()
	move.visual_effect_color = Color(0.2, 1.0, 0.0)
	_presenter.cast(move)
	assert_eq(_doll._state, CharacterVisual.State.CAST, "the cast state")
	var expected: Color = move.visual_effect_color.lerp(Color.WHITE, 0.4)
	assert_almost_eq(_doll.modulate.r, expected.r, 0.01, "tinted red")
	assert_almost_eq(_doll.modulate.g, expected.g, 0.01, "tinted green")
	assert_almost_eq(_doll.modulate.b, expected.b, 0.01, "tinted blue")


# The color of the Result flash the doll shows, or null while it shows none. The
# flash is a filter in the shader that draws the doll's body, so this reads
# whether that filter is on and the color it draws.
func _flash_color_on(doll: CharacterVisual) -> Variant:
	var body_shader: ShaderMaterial = doll.get_node("Body").material
	if not body_shader.get_shader_parameter("result_flash"):
		return null
	return body_shader.get_shader_parameter("color")


func _flash_color() -> Variant:
	return _flash_color_on(_doll)


func _advance_flash(frames: int) -> void:
	for frame in frames:
		_flash.advance(1.0 / 30.0)


# executeMove plays BATTLEFLASH's `hit` label on a hit
# (frame_42/DoAction_8.as:95-99) and on a heal that hurts under sswitch
# (199-203), its `heal` label on damage that heals under sswitch (144-148) and on
# a heal (182-186), and its `focus` label on every focus result, a drain
# included (232-249).
func test_each_result_starts_the_result_flash_in_its_color():
	for case in [
		[_damage(10.0, 90.0), HIT_FLASH, "a hit"],
		[_heal_that_hurts(10.0, 90.0), HIT_FLASH, "a heal that hurts under sswitch"],
		[_damage_that_heals(10.0, 100.0), HEAL_FLASH, "damage that heals under sswitch"],
		[_heal(10.0, 100.0), HEAL_FLASH, "a heal"],
		[_result(MoveResult.Kind.FOCUS, MoveResult.Direction.NONE, 8.0, 100.0), FOCUS_FLASH, "a focus result"],
		[_result(MoveResult.Kind.FOCUS, MoveResult.Direction.NONE, -8.0, 100.0), FOCUS_FLASH, "a focus drain"],
	]:
		_present(_make_unit(CombatUnit.Team.TWO, ENEMY_SLOT))
		_presenter.show_result(case[0], null)
		assert_eq(_flash_color(), case[1], case[2])


func _shield_block() -> MoveResult:
	var result: MoveResult = _damage(0.0, 100.0)
	result.shield_took_all = true
	return result


# A Shield block stops short of executeMove's call to BATTLEFLASH
# (frame_42/DoAction_8.as:70-76). A hit exactly as big as the shield is not a
# Shield block, and ADR 0005 keeps it as a Quirk: it plays the hit's flash with
# no number (79-99).
func test_a_shield_block_plays_no_flash_but_a_hit_the_shield_soaks_exactly_does():
	_presenter.show_result(_shield_block(), null)
	assert_null(_flash_color(), "a Shield block")
	_presenter.show_result(_damage(0.0, 100.0), null)
	assert_eq(_flash_color(), HIT_FLASH, "a hit the shield soaked exactly")


# The original's whole heal branch, its calls to BATTLEFLASH included, is inside
# DamageOutputKrinFinal > 0 (frame_42/DoAction_8.as:172), so a heal of 0 plays
# no flash, under sswitch too.
func test_a_heal_of_0_plays_no_flash():
	_presenter.show_result(_heal(0.0, 100.0), null)
	assert_null(_flash_color())


# The conductor runs executeMove only on a strike that lands, and a miss takes
# its else branch (lines 19 and 105-109). Shatter Bolt's "Attack" category has
# no branch in executeMove.
func test_a_miss_and_a_status_only_result_play_no_flash():
	_presenter.show_result(_result(MoveResult.Kind.MISS, MoveResult.Direction.NONE, 0.0, 100.0), null)
	assert_null(_flash_color(), "a miss")
	_presenter.show_result(_result(MoveResult.Kind.STATUS_ONLY, MoveResult.Direction.NONE, 0.0, 100.0), null)
	assert_null(_flash_color(), "a status-only result")


# Only executeMove calls BATTLEFLASH, so buffTicker draws a Buff tick with no
# flash (frame_42/DoAction_10.as:14-136). A tick reaches the fighter through
# show_state(), or through snap_to_unit() at the half-turn's end.
func test_a_buff_tick_plays_no_flash():
	_presenter.show_state(_state(80.0))
	assert_null(_flash_color(), "a tick shown when it happens")
	_unit.life_n = 70.0
	_presenter.snap_to_unit()
	assert_null(_flash_color(), "a tick shown at the half-turn's end")


# Each of BATTLEFLASH's labels puts its filter on at its first frame and on the
# 4th, 8th and 12th frames after it, takes it off 2 frames after each, and takes
# it off for good and stops on the 14th frame after it (DefineSprite_3416/frame_2
# to frame_46). The doll shows that filter from the frame the result lands on.
func test_the_flash_pulses_4_times_over_14_frames_then_stops():
	for case in [
		[_damage(10.0, 90.0), HIT_FLASH],
		[_heal(10.0, 100.0), HEAL_FLASH],
		[_result(MoveResult.Kind.FOCUS, MoveResult.Direction.NONE, 8.0, 100.0), FOCUS_FLASH],
	]:
		_present(_make_unit(CombatUnit.Team.TWO, ENEMY_SLOT))
		_presenter.show_result(case[0], null)
		var shown: Array = [_flash_color()]
		for frame in 15:
			_advance_flash(1)
			shown.append(_flash_color())
		var on: Color = case[1]
		assert_eq(shown, [on, on, null, null, on, on, null, null, on, on, null, null, on, on, null, null], str(on))


# The flash only puts its filter on the doll's body and takes it off, so the doll
# ends it looking the way it did before. A caster that heals itself keeps the
# cast tint it had when its heal landed, and a stunned doll keeps its stun pose.
func test_the_doll_looks_the_same_after_the_flash():
	var heal_move := Ability.new()
	heal_move.visual_effect_color = Color(0.2, 1.0, 0.0)
	_presenter.cast(heal_move)
	var tint: Color = _doll.modulate
	_presenter.show_result(_heal(10.0, 100.0), heal_move)
	assert_eq(_flash_color(), HEAL_FLASH, "a heal flashes the caster it lands on")
	_advance_flash(14)
	assert_null(_flash_color(), "the flash is over")
	assert_eq(_doll.modulate, tint, "and the cast tint is still on")

	_present(_make_unit(CombatUnit.Team.TWO, ENEMY_SLOT))
	_stun()
	_presenter.show_result(_stunned_at_hit(_damage(10.0, 90.0)), null)
	assert_eq(_flash_color(), HIT_FLASH, "a hit flashes a stunned doll")
	_advance_flash(14)
	assert_null(_flash_color(), "the flash is over")
	assert_eq(_doll._state, STUN, "and the doll is still in its stun")
	assert_eq(_doll._label, "stun", "on the same label")


# executeMove's gotoAndPlay() starts BATTLEFLASH's label over, so a result that
# lands during a flash starts a new one in its own color, which runs all 14
# frames.
func test_a_result_during_a_flash_starts_it_over_in_its_own_color():
	_presenter.show_result(_damage(10.0, 90.0), null)
	_advance_flash(2)
	_presenter.show_result(_heal(10.0, 100.0), null)
	assert_eq(_flash_color(), HEAL_FLASH, "the new flash shows at once")
	_advance_flash(13)
	assert_eq(_flash_color(), HEAL_FLASH, "it still pulses 13 frames later")
	_advance_flash(1)
	assert_null(_flash_color(), "and stops 14 frames after it started")


# The original has one BATTLEFLASH for the whole battle, so a move that hits
# several units flashes only the last one, an Original bug that ADR 0005 has the
# port fix. Each Fighter presenter runs its own Result flash.
func test_every_target_of_a_move_flashes():
	var first_target: FighterPresenter = _presenter
	var first_doll: CharacterVisual = _doll
	_present(_make_unit(CombatUnit.Team.TWO, ENEMY_SLOT + 2))
	first_target.show_result(_damage(10.0, 90.0), null)
	_presenter.show_result(_damage(10.0, 90.0), null)
	assert_eq(_flash_color_on(first_doll), HIT_FLASH, "the first target")
	assert_eq(_flash_color(), HIT_FLASH, "the second target")
