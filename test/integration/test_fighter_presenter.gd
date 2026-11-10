# FighterPresenter on its own, with a hand-made unit and hand-made results and
# no battle scene or save behind it. Fades are stepped with custom_step() and
# the doll's swing with its own _process(), so nothing here waits on real time.
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

var _presenter: FighterPresenter
var _doll: CharacterVisual
var _overlay: UnitOverlay
var _layer: Node2D
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


# Builds a presenter the way battle_scene.gd does, on a float layer of its own,
# and records every cue it asks for in order in _cues.
func _present(unit: CombatUnit, items_by_id: Dictionary = {}, buffs_by_id: Dictionary = {}) -> void:
	_layer = add_child_autofree(Node2D.new())
	_presenter = add_child_autofree(FighterPresenterScene.instantiate())
	_presenter.setup(unit, HOME, items_by_id, buffs_by_id, _layer)
	_doll = _presenter.get_node("Doll")
	_overlay = _presenter.get_node("Overlay")
	_cues = []
	_presenter.voice_cue.connect(func(cues): _cues.append(cues))
	_presenter.effect_cue.connect(func(cue): _cues.append(cue))


func _result(kind: MoveResult.Kind, direction: MoveResult.Direction, amount: float, life_after: float) -> MoveResult:
	var result := MoveResult.new()
	result.kind = kind
	result.direction = direction
	result.amount = amount
	result.life_after = life_after
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
	result.stun_after = 1.0
	return result


func _stunning(result: MoveResult) -> MoveResult:
	result.stun_after = 1.0
	return result


func _fire_move() -> Ability:
	var move := Ability.new()
	move.damage_element_type = CombatUnit.Element.FIRE
	return move


func _numbers() -> Array:
	return _layer.get_children().filter(func(child): return child is Label)


func _stun() -> void:
	_unit.stun = 1.0
	_presenter.snap_to_unit()


# Steps the doll for two seconds, which outlasts its hit label.
func _play_out_the_hit() -> void:
	for frame in 60:
		_doll._process(1.0 / 30.0)


# Steps the presenter and its doll by `count` frames at the original's 30 fps.
func _step_frames(count: int) -> void:
	for frame in count:
		_presenter._process(1.0 / 30.0)
		_doll._process(1.0 / 30.0)


func _present_with_a_buff() -> void:
	var buff := Buff.new()
	buff.internal_name = "FIRESAM"
	_unit.buff_slots = [{"cd": 3, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0}]
	_present(_unit, {}, {1: buff})


# What the overlay draws besides its two bars.
func _overlay_shows() -> Dictionary:
	var icons: Array = _overlay.buff_row.get_children().filter(func(icon): return not icon.is_queued_for_deletion())
	return {
		"icons": icons.size() if _overlay.buff_row.is_visible_in_tree() else 0,
		"name": _overlay.name_label.is_visible_in_tree(),
		"number": _overlay.health_value.is_visible_in_tree(),
	}


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
	_presenter.redraw()
	assert_eq(_overlay.health_bar.value, 100.0, "a redraw before the hit leaves the bar alone")
	assert_eq(_overlay.health_value.text, "100", "and the number beside it")

	_presenter.show_result(_damage(60.0, 40.0), null)
	assert_eq(_overlay.health_bar.value, 40.0, "the bar drops when the hit lands")
	assert_eq(_overlay.health_value.text, "40", "and so does the number")
	assert_eq(_presenter.displayed_hp, 40.0, "and the health it displays")


func test_each_hit_of_a_half_turn_shows_the_life_it_left():
	_unit.life_n = 40.0
	_presenter.show_result(_damage(25.0, 75.0), null)
	assert_eq(_overlay.health_bar.value, 75.0, "the first hit shows only itself")
	_presenter.show_result(_damage(35.0, 40.0), null)
	assert_eq(_overlay.health_bar.value, 40.0, "and the second reaches the unit's life")


# A unit pays its own move's life cost when it acts, and the runner resolves the
# whole half-turn before the replay, so a result on the unit later in that
# half-turn starts from the life left after the cost. Here the cost was 40 and
# the move moved 10 either way. The bar shows the life each result states, so
# the cost reaches it at that result, where the original drew it when the cost
# was paid (the conductor, line 359).
func test_a_result_shows_the_life_it_states_with_an_earlier_cost_in_it():
	for result in [
		_damage(10.0, 50.0),
		_damage_that_heals(10.0, 70.0),
		_heal_that_hurts(10.0, 50.0),
		_heal(10.0, 70.0),
	]:
		var label: String = "%s that pushed %s" % [MoveResult.Kind.find_key(result.kind), MoveResult.Direction.find_key(result.direction)]
		_present(_make_unit(CombatUnit.Team.TWO, ENEMY_SLOT))
		_presenter.show_result(result, null)
		assert_eq(_presenter.displayed_hp, result.life_after, "a %s takes the cost along with it" % label)
		assert_eq(_overlay.health_value.text, str(int(result.life_after)), "and so does the number beside the bar")


# A damage-over-time tick or a life cost with no later result on the unit only
# reaches the bar when the half-turn ends.
func test_the_bars_snap_to_the_unit_at_half_turn_end():
	_unit.life_n = 63.0
	_presenter.redraw()
	assert_eq(_overlay.health_bar.value, 100.0, "still held back before the snap")

	_presenter.snap_to_unit()
	assert_eq(_overlay.health_bar.value, 63.0, "the bar shows the unit's life")
	assert_eq(_overlay.health_value.text, "63", "and so does the number")
	assert_eq(_presenter.displayed_hp, 63.0, "and the health it displays")


func test_focus_shows_the_unit_true_value_while_health_is_held_back():
	_unit.life_n = 40.0
	_unit.focus_n = 12.0
	_presenter.redraw()
	assert_eq(_overlay.focus_bar.value, 12.0, "focus is never held back")
	assert_eq(_overlay.health_bar.value, 100.0, "only health is")


func test_a_redraw_shows_the_units_buffs():
	var buff := Buff.new()
	buff.internal_name = "FIRESAM"
	_present(_unit, {}, {1: buff})
	assert_eq(_overlay.buff_row.get_child_count(), 0, "no buffs yet")
	_unit.buff_slots = [{"cd": 3, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0}]
	_presenter.redraw()
	assert_eq(_overlay.buff_row.get_child_count(), 1, "the buff table reaches the row")


func test_a_hit_bigger_than_the_displayed_health_stops_the_bar_at_empty():
	_presenter.show_result(_damage(250.0, 0.0), null)
	assert_eq(_presenter.displayed_hp, 0.0, "the displayed health stops at zero")
	assert_eq(_overlay.health_value.text, "0", "and so does the number")


func test_a_heal_raises_the_bar_with_a_plus_number_and_stops_at_full():
	_unit.life_n = 40.0
	_presenter.snap_to_unit()
	_presenter.show_result(_heal(10.0, 50.0), null)
	assert_eq(_overlay.health_bar.value, 50.0, "the bar rises by the heal")
	assert_eq(_numbers()[-1].text, "+10", "the number carries a plus")
	assert_eq(_numbers()[-1].modulate, MenuTheme.HEAL_COLOR, "in heal green")
	assert_eq(_cues, [], "a heal plays no voice")
	_presenter.show_result(_heal(500.0, 100.0), null)
	assert_eq(_presenter.displayed_hp, 100.0, "and it stops at full")


# KrinNumberShow colors a number by the move's element.
func test_a_damage_number_takes_the_moves_element_color():
	_presenter.show_result(_damage(12.0, 88.0), _fire_move())
	assert_eq(_numbers()[-1].text, "12")
	assert_eq(_numbers()[-1].modulate, MenuTheme.ELEMENT_COLORS[CombatUnit.Element.FIRE])


func test_a_damage_number_without_an_element_is_white():
	_presenter.show_result(_damage(5.0, 95.0), null)
	assert_eq(_numbers()[-1].modulate, Color.WHITE, "no move")
	var elementless := Ability.new()
	elementless.damage_element_type = -1 as CombatUnit.Element
	_presenter.show_result(_damage(5.0, 90.0), elementless)
	assert_eq(_numbers()[-1].modulate, Color.WHITE, "a move with no element")


func test_a_critical_number_is_bigger_and_outlined():
	for result in [
		_critical(_damage(12.0, 88.0)),
		_critical(_damage_that_heals(12.0, 100.0)),
		_critical(_heal_that_hurts(12.0, 88.0)),
	]:
		_presenter.show_result(result, null)
		assert_eq(_numbers()[-1].get_theme_font_size("font_size"), 24, "the critical size")
		assert_eq(_numbers()[-1].get_theme_constant("outline_size"), 4, "with an outline")


func test_a_hit_flinches_the_doll_and_plays_the_hit_voice():
	_presenter.show_result(_damage(10.0, 90.0), null)
	assert_eq(_doll._state, HIT, "the flinch")
	assert_eq(_cues, [VOICE_HIT], "and the unit's hit voices")


# A move-caused death used to play only when the queued DEATH event was reached,
# which for a melee hit is after the caster has run back.
func test_a_killing_blow_plays_the_death_at_the_impact():
	_presenter.show_result(_killing(_damage(100.0, 0.0)), null)
	assert_eq(_doll._state, DEAD, "the doll plays its death at the impact")


# The original plays the hit voice only when the target survives, in the else
# of IDKT.LIFEN == 0 (frame_42/DoAction_8.as:104-131).
func test_a_killing_blow_plays_the_death_voice_and_not_the_hit_voice():
	_presenter.show_result(_killing(_damage(500.0, 0.0)), null)
	assert_eq(_cues, [VOICE_DIE])


# The original attaches LifeBarSmoother to the bar at the death, and the clip's
# frame 18, 17 frames later, removes the buff icons and sends the bar's inner
# clip to its empty "third" frame, which takes the name and the numbers away
# (DefineSprite_57_LifeBarSmoother/frame_18/DoAction.as).
func test_the_buff_icons_name_and_number_clear_17_frames_after_a_killing_impact():
	_present_with_a_buff()
	_presenter.show_result(_killing(_damage(100.0, 0.0)), null)
	_step_frames(16)
	var before_the_clear: Dictionary = _overlay_shows()
	_step_frames(1)
	assert_eq([before_the_clear, _overlay_shows()], [
		{"icons": 1, "name": true, "number": true},
		{"icons": 0, "name": false, "number": false},
	])


# The alpha the overlay is drawn at, which is 0 once it is hidden.
func _overlay_alpha() -> float:
	return _overlay.modulate.a if _overlay.is_visible_in_tree() else 0.0


# From the frame after the clear, LifeBarSmoother takes 5 off the bar's alpha
# every frame (DefineSprite_57_LifeBarSmoother/frame_38/DoAction.as).
func test_the_bar_fades_5_alpha_a_frame_after_the_clear():
	_presenter.show_result(_killing(_damage(100.0, 0.0)), null)
	var alphas: Array = [_overlay_alpha()]
	for frame in 37:
		_step_frames(1)
		alphas.append(_overlay_alpha())
	for expected in [[16, 1.0], [17, 1.0], [18, 0.95], [27, 0.5], [37, 0.0]]:
		assert_almost_eq(alphas[expected[0]], expected[1], 0.001, "frame %d after the impact" % expected[0])


# The scene redraws every fighter after every event and snaps them all at the
# half-turn's end, and the bar's name, number and icons stay cleared through it.
func test_a_redraw_after_the_clear_leaves_the_overlay_cleared():
	_present_with_a_buff()
	_presenter.show_result(_killing(_damage(100.0, 0.0)), null)
	_step_frames(20)
	_presenter.redraw()
	_presenter.snap_to_unit()
	assert_eq(_overlay_shows(), {"icons": 0, "name": false, "number": false})


# LifeBarSmoother hides the bar the frame after its alpha reaches 0
# (DefineSprite_57_LifeBarSmoother/frame_38/DoAction.as), and the doll removes
# itself when its dead label ends.
func test_a_dead_units_slot_shows_nothing_for_the_rest_of_the_battle():
	_present_with_a_buff()
	_presenter.show_result(_killing(_damage(100.0, 0.0)), null)
	_step_frames(90)
	_presenter.redraw()
	_presenter.snap_to_unit()
	var drawn: Array = _presenter.get_children().filter(func(child): return child is CanvasItem and child.is_visible_in_tree())
	assert_eq(drawn.map(func(child): return child.name), [])


# lifeBarUpdate plays the death voice and starts the fade only when the bar's
# rounded percent changes (frame_42/DoAction_8.as:295-298 and 345-347), so the
# original kills a unit from under 0.5% life with neither. ADR 0005 counts that
# as an Original bug, and the port plays both on every death.
func test_a_unit_killed_from_under_half_a_percent_life_still_plays_its_death_voice_and_fade():
	_unit.life_u = 1000.0
	_unit.life_n = 4.0
	_present(_unit)
	_presenter.show_result(_killing(_damage(4.0, 0.0)), null)
	_step_frames(27)
	assert_eq(_cues, [VOICE_DIE], "the death voice")
	assert_almost_eq(_overlay_alpha(), 0.5, 0.001, "and the bar halfway through its fade")


# A damage-over-time death has no result to move the bar. The original empties
# the bar on the tick that kills (frame_42/DoAction_10.as:108-114 and 135, and
# applyChangesKrin's lifeBarUpdate at 342), so the bar fades from empty.
func test_a_death_with_no_result_empties_the_bar_before_it_fades():
	_unit.life_n = 0.0
	_presenter.die()
	assert_eq(_overlay.health_bar.value, 0.0)


func test_die_plays_the_death_with_no_hit():
	_presenter.die()
	assert_eq(_doll._state, DEAD, "the doll plays its death")
	assert_eq(_cues, [VOICE_DIE], "with the death cry alone")


# Damage on a target under an sswitch buff heals it. The original draws the
# number in heal green, raises life capped at max, and plays no hit animation
# (frame_42/DoAction_8.as:133-149).
func test_damage_on_a_sswitch_target_shows_as_a_heal():
	_unit.life_n = 50.0
	_presenter.snap_to_unit()
	_presenter.show_result(_damage_that_heals(15.0, 65.0), _fire_move())
	assert_eq(_overlay.health_bar.value, 65.0, "the bar rises, because the damage healed the target")
	assert_eq(_numbers()[-1].text, "15", "the number is the amount the damage healed")
	assert_eq(_numbers()[-1].modulate, MenuTheme.HEAL_COLOR, "drawn in heal green")
	assert_ne(_doll._state, HIT, "no hit animation")
	assert_eq(_cues, [], "and no hit voice")


func test_damage_on_a_sswitch_target_stops_the_bar_at_full():
	_presenter.show_result(_damage_that_heals(15.0, 100.0), null)
	assert_eq(_presenter.displayed_hp, 100.0)


# A heal on a target under an sswitch buff hurts it. The original draws the
# number in the Shadow color, lowers life and plays the hit animation
# (frame_42/DoAction_8.as:189-207).
func test_heal_on_a_sswitch_target_shows_as_damage():
	_presenter.show_result(_heal_that_hurts(20.0, 80.0), null)
	assert_eq(_overlay.health_bar.value, 80.0, "the bar falls, because the heal hurt the target")
	assert_eq(_numbers()[-1].text, "20", "no plus sign")
	assert_eq(_numbers()[-1].modulate, MenuTheme.ELEMENT_COLORS[CombatUnit.Element.SHADOW], "drawn in the Shadow color")
	assert_eq(_doll._state, HIT, "the hit animation plays")
	assert_eq(_cues, [], "but no hit voice")


# A heal bigger than an sswitch target's life kills it, and the original plays
# the death at that impact (frame_42/DoAction_8.as:208-228).
func test_heal_that_kills_a_sswitch_target_plays_the_death():
	_presenter.show_result(_killing(_heal_that_hurts(150.0, 0.0)), null)
	assert_eq(_doll._state, DEAD, "the doll plays its death")
	assert_eq(_presenter.displayed_hp, 0.0, "the bar drops to empty")
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
	_presenter.redraw()
	assert_ne(_doll._state, STUN, "a redraw before the stun lands doesn't start it")
	_presenter.show_result(_damage(10.0, 90.0), null)
	assert_eq(_doll._state, HIT, "a hit before it flinches")
	_play_out_the_hit()
	_presenter.show_result(_stunning(_damage(10.0, 80.0)), null)
	assert_eq(_doll._state, STUN, "and the hit that lands it starts the stun")

	_present(_make_unit(CombatUnit.Team.TWO, ENEMY_SLOT))
	_presenter.show_result(_stunned_at_hit(_damage(10.0, 90.0)), null)
	assert_ne(_doll._state, HIT, "a stun that has worn off by the half-turn's end still stops the flinch")


# Every event redraws every fighter, so a redraw comes between the start of a
# half-turn and the hit that lands a stun. The original plays that hit's flinch
# and starts the stun at the same strike, so the doll ends up stunned.
func test_a_hit_that_lands_a_stun_leaves_the_doll_stunned():
	_unit.stun = 1.0
	_presenter.redraw()
	_presenter.show_result(_stunning(_damage(10.0, 90.0)), null)
	_play_out_the_hit()
	assert_eq(_doll._state, STUN)


func test_a_focus_result_floats_its_amount():
	_presenter.show_result(_result(MoveResult.Kind.FOCUS, MoveResult.Direction.NONE, 8.0, 100.0), null)
	assert_eq(_numbers()[-1].text, "+8 FOCUS")
	assert_eq(_numbers()[-1].modulate, Color.SKY_BLUE)


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


# The miss sound depends on the move's type, so battle_scene.gd plays it and
# test_battle_scene.gd checks it.
func test_a_miss_floats_miss_and_plays_nothing():
	_presenter.show_result(_result(MoveResult.Kind.MISS, MoveResult.Direction.NONE, 0.0, 100.0), null)
	assert_eq(_numbers()[-1].text, "MISS")
	assert_eq(_numbers()[-1].modulate, Color.GRAY)
	assert_eq(_cues, [], "no sound and no voice")
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


func test_a_redraw_with_no_change_in_stun_leaves_the_animation_alone():
	_stun()
	_doll._process(0.1)
	var time_into_label: float = _doll._label_time
	_presenter.redraw()
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
	_presenter.redraw()
	assert_eq(_doll._state, STUN, "the doll is still stunned")
	assert_ne(_doll._label, "outofstun", "and doesn't wake up first")
	var killing_stun: MoveResult = _stunned_at_hit(_killing(_damage(100.0, 0.0)))
	killing_stun.stun_after = 2.0
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


func test_floating_text_goes_on_the_float_layer_above_the_doll():
	_presenter.float_text("DISPEL", Color.CYAN)
	var label: Label = _numbers()[-1]
	assert_eq(label.get_parent(), _layer, "on the layer, so it draws over every fighter")
	assert_eq(label.text, "DISPEL", "the text")
	assert_eq(label.modulate, Color.CYAN, "the color")
	assert_eq(label.position, HOME + FighterPresenter.FLOAT_OFFSET, "above the doll")


func test_floating_text_rises_fades_and_frees_itself():
	var running: Array = get_tree().get_processed_tweens()
	_presenter.float_text("12", Color.WHITE)
	var rise: Tween = get_tree().get_processed_tweens().filter(func(tween): return not running.has(tween))[0]
	var label: Label = _numbers()[-1]
	var start_y: float = label.position.y
	rise.pause()
	rise.custom_step(0.4)
	assert_almost_eq(label.position.y, start_y - 20.0, 0.01, "halfway up after 0.4 s")
	assert_almost_eq(label.modulate.a, 0.5, 0.01, "and half faded")
	rise.custom_step(0.5)
	assert_true(label.is_queued_for_deletion(), "and gone once the 0.8 s are up")


# Starts a melee at an ally 200 px to the left, whose swing the test steps by
# hand. The returned array holds true once melee() has returned.
func _start_melee(on_blow: Callable) -> Array:
	_doll.set_process(false)
	var target: FighterPresenter = _fighter_at(_make_unit(CombatUnit.Team.ONE, ALLY_SLOT), HOME - Vector2(200, 0))
	var returned: Array = []
	var run: Callable = func():
		await _presenter.melee(target, "Attack", on_blow)
		returned.append(true)
	run.call()
	return returned


# krinMelee hands the battle back at Impact and runs the fighter home on its
# own afterwards (frame_42/DoAction_4.as:73-135), so melee() returns at the
# blow, with the doll still where it struck.
func test_melee_lands_the_blow_once_and_returns_at_it():
	var blows: Array = []
	var returned: Array = _start_melee(func(): blows.append(_doll.position))
	assert_eq(blows.size(), 0, "nothing lands as the run starts")
	for frame in 600:
		if not returned.is_empty():
			break
		_doll._process(1.0 / 30.0)
	assert_eq(blows.size(), 1, "the blow lands once")
	if blows.size() == 1:
		assert_lt(blows[0].x, HOME.x - 100.0, "after a run toward the target")
		assert_eq(_doll.position, blows[0], "while the doll still stands where it struck")
	assert_eq(returned, [true], "melee returns at the blow")
	for frame in 120:
		_doll._process(1.0 / 30.0)
	assert_eq(_doll.position, HOME, "and the doll then runs home on its own")
	assert_eq(blows.size(), 1, "with no second blow")


func test_melee_without_waiting_lands_the_blow_at_once():
	var blows: Array = []
	var target: FighterPresenter = _fighter_at(_make_unit(CombatUnit.Team.ONE, ALLY_SLOT), HOME - Vector2(200, 0))
	await _presenter.melee(target, "Attack", func(): blows.append(true), false)
	assert_eq(blows.size(), 1, "the blow lands without the swing being played")


func test_a_melee_whose_presenter_left_the_tree_lands_nothing():
	var blows: Array = []
	var returned: Array = _start_melee(func(): blows.append(true))
	remove_child(_presenter)
	_doll.attack_connected.emit()
	assert_eq(blows.size(), 0, "no blow on a fighter that is gone")
	assert_eq(returned, [true], "and melee returns")


# Builds a second presenter for `unit` at `home`, on the same float layer, and
# stops its doll's own processing so that the test steps the doll itself.
func _fighter_at(unit: CombatUnit, home: Vector2, items_by_id: Dictionary = {}) -> FighterPresenter:
	var presenter: FighterPresenter = add_child_autofree(FighterPresenterScene.instantiate())
	presenter.setup(unit, home, items_by_id, {}, _layer)
	presenter.get_node("Doll").set_process(false)
	return presenter


# Puts a weapon whose art is `looks` in both of `unit`'s hands, and returns the
# item table that holds it. Empty looks leave the unit bare.
func _armed(unit: CombatUnit, looks: String) -> Dictionary:
	var weapon := GameItem.new()
	weapon.looks = looks
	unit.equipment_ids = [0, 0, 0, 0, 0, 7, 7]
	return {7: weapon}


# Swings `caster` at `target`, steps the caster's doll until the blow lands,
# and returns where the caster's doll stands then.
func _blow_spot(caster: FighterPresenter, target: FighterPresenter) -> Vector2:
	var doll: CharacterVisual = caster.get_node("Doll")
	var spots: Array = []
	caster.melee(target, "Attack", func(): spots.append(doll.position))  # not awaited, because the test steps the swing
	for frame in 60:
		if not spots.is_empty():
			break
		doll._process(1.0 / 30.0)
	return spots[0] if not spots.is_empty() else Vector2.INF


# krinMelee stops the caster at the target's x less half of each fighter's
# width, the caster's in its run pose and the target's as it stands
# (frame_42/DoAction_4.as:46-56). A wide weapon widens a fighter, so two
# fighters with wide weapons stop further apart than two bare fighters.
func test_two_fighters_in_wide_gear_stop_further_apart_than_two_bare_fighters():
	var gaps: Dictionary = {}
	for looks in ["", "UBER1"]:
		var caster_unit: CombatUnit = _make_unit(CombatUnit.Team.ONE, ALLY_SLOT)
		var target_unit: CombatUnit = _make_unit(CombatUnit.Team.TWO, ENEMY_SLOT)
		var caster: FighterPresenter = _fighter_at(caster_unit, Vector2(160, 300), _armed(caster_unit, looks))
		var target: FighterPresenter = _fighter_at(target_unit, Vector2(640, 300), _armed(target_unit, looks))
		gaps[looks] = target.get_node("Doll").position.x - _blow_spot(caster, target).x
	assert_gt(gaps[""], 0.0, "sanity: two bare fighters stop short of each other")
	assert_gt(gaps["UBER1"], gaps[""], "two fighters with UBER1 in both hands stop further apart")


# dressChar draws a MODEL5 doll 10 px lower inside its rig, and krinMelee runs
# the rig toward the target's rig (frame_217/DoAction_2.as:19-24 and
# frame_42/DoAction_4.as:112-116). So a MODEL5 fighter runs level at a target
# whose rig stands level with its own.
func test_a_model5_fighter_runs_level_at_a_target_level_with_it():
	var caster_unit: CombatUnit = _make_unit(CombatUnit.Team.ONE, ALLY_SLOT)
	caster_unit.model = ["MODEL5", "ONE", "ONE", "M"]
	var caster: FighterPresenter = _fighter_at(caster_unit, Vector2(160, 300))
	var target: FighterPresenter = _fighter_at(_make_unit(CombatUnit.Team.TWO, ENEMY_SLOT), Vector2(640, 300))
	var doll: CharacterVisual = caster.get_node("Doll")
	var start: Vector2 = doll.position
	assert_eq(start.y, 310.0, "sanity: the MODEL5 doll stands 10 px lower")
	var blow: Vector2 = _blow_spot(caster, target)
	assert_gt(blow.x, start.x + 300.0, "sanity: the doll ran most of the way")
	assert_eq(blow.y, start.y, "and stayed level")


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
