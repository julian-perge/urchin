# RadialMenu on its own, with hand-made units and moves and no battle scene or
# save behind it. Each test drives the clock and the mouse through advance(), so
# nothing here waits on real time.
extends GutTest

const RadialMenuScene = preload("res://scenes/battle/radial_menu.tscn")
const ENEMY_SLOT: int = 2
const CENTRE: Vector2 = Vector2(300, 300)
const FAR: Vector2 = Vector2(-1000, -1000)
const LEADING_STRIKE_ID: int = 1
const DESTROY_ID: int = 2

var _menu: RadialMenu
var _hold: Control
var _player: CombatUnit
var _enemy: CombatUnit
var _units: Dictionary
var _moves: Dictionary


func before_each():
	_player = _unit(CombatUnit.Team.ONE)
	_player.equipped_moves = [LEADING_STRIKE_ID, DESTROY_ID, 0, 0, 0, 0, 0, 0]
	_enemy = _unit(CombatUnit.Team.TWO)
	_units = {BattleRunner.PLAYER_SLOT: _player, ENEMY_SLOT: _enemy}
	_moves = {LEADING_STRIKE_ID: _move("Leading Strike"), DESTROY_ID: _move("Destroy")}
	_hold = add_child_autofree(Control.new())
	_hold.position = CENTRE + Vector2(-28, -52)
	_hold.size = Vector2(56, 100)
	_menu = add_child_autofree(RadialMenuScene.instantiate())
	_menu.set_process(false)
	_menu.setup(_units, _moves, {})
	_menu.decision_open = true


func after_each():
	GameTooltip.hide_tooltip()


func _unit(team: CombatUnit.Team) -> CombatUnit:
	var unit := CombatUnit.new()
	unit.team_side = team
	unit.life_u = 1000.0
	unit.life_n = 1000.0
	unit.ability_cooldowns = [0, 0, 0, 0, 0, 0, 0, 0]
	return unit


func _move(display_name: String) -> Ability:
	var move := Ability.new()
	move.display_name = display_name
	move.can_target_self = true
	move.can_target_others = true
	move.targets_allies = true
	return move


func _open() -> void:
	_menu.open(ENEMY_SLOT, CENTRE, _hold)


func _hold_centre() -> Vector2:
	return _hold.get_global_rect().get_center()


func _orb_centre(bar_index: int) -> Vector2:
	return _menu.orbs[bar_index].get_global_rect().get_center()


func _tooltip_lines() -> Array:
	var texts: Array = []
	for section in GameTooltip._sections.get_children():
		for label in section.get_child(0).get_children():
			texts.append(label.text)
	return texts


func test_opening_centres_the_menu_and_shows_each_equipped_slot():
	_open()
	assert_true(_menu.visible)
	assert_eq(_menu.position, CENTRE)
	assert_eq(_menu.modulate.a, 1.0)
	var shown: Array = _menu.orbs.map(func(orb): return orb.visible)
	assert_eq(shown, [true, true, false, false, false, false, false, false])


# Bar slot 0 locked on cooldown used to vanish from the menu, shifting bar slot
# 1's move into slot 0's arc position. The source only hides a truly empty
# ("None") slot and never renumbers around a temporarily-unusable one.
func test_an_orb_sits_at_its_own_bar_slots_offset():
	_player.ability_cooldowns[0] = 5
	_open()
	var orb: Button = _menu.orbs[1]
	assert_eq(orb.position, RadialMenu.ORB_OFFSETS[1] - orb.size / 2.0)


func test_a_refused_orb_is_shown_darkened_and_the_rest_stay_usable():
	_player.ability_cooldowns[0] = 5
	_open()
	assert_true(_menu.orbs[0].visible, "a refused orb is still shown")
	assert_true(_menu.orbs[0].disabled, "and cannot be clicked")
	assert_false(_menu.orbs[1].disabled, "the other slot is untouched")


func test_the_menu_opens_when_every_equipped_move_is_refused():
	_player.ability_cooldowns[0] = 5
	_player.ability_cooldowns[1] = 5
	_open()
	assert_true(_menu.visible, "the source only hides empty slots")
	assert_true(_menu.orbs[0].disabled)
	assert_true(_menu.orbs[1].disabled)


func test_an_empty_or_unknown_slot_shows_no_orb():
	_moves[0] = _move("None")  # the shipped data has a real move 0
	_player.equipped_moves = [0, 99, DESTROY_ID, 0, 0, 0, 0, 0]
	_open()
	assert_false(_menu.orbs[0].visible, "move id 0 is an empty slot")
	assert_false(_menu.orbs[1].visible, "an id with no move")
	assert_true(_menu.orbs[2].visible)


func test_a_bar_past_the_eight_orbs_is_ignored():
	_player.equipped_moves = [LEADING_STRIKE_ID, 0, 0, 0, 0, 0, 0, 0, DESTROY_ID]
	_open()
	assert_true(_menu.visible)
	assert_true(_menu.orbs[0].visible)


func test_a_bar_with_no_orb_at_all_opens_nothing():
	_player.equipped_moves = [0, 0, 0, 0, 0, 0, 0, 0]
	_open()
	assert_false(_menu.visible)


func test_reopening_dresses_the_orbs_for_the_current_bar():
	_player.ability_cooldowns[0] = 5
	_open()
	assert_true(_menu.orbs[0].disabled)
	_player.ability_cooldowns[0] = 0
	_player.equipped_moves[1] = 0
	_open()
	assert_false(_menu.orbs[0].disabled, "the cooldown ended")
	assert_false(_menu.orbs[1].visible, "the slot was emptied")


func test_no_menu_opens_while_the_decision_is_closed():
	_menu.decision_open = false
	_open()
	assert_false(_menu.visible)


func test_closing_the_decision_closes_the_menu():
	_open()
	_menu.decision_open = false
	assert_false(_menu.visible)


func test_clicking_a_dead_or_missing_unit_leaves_an_open_menu_up():
	_open()
	_enemy.active = false
	_menu.open(ENEMY_SLOT, CENTRE + Vector2(50, 0), _hold)
	assert_true(_menu.visible, "dead target")
	assert_eq(_menu.position, CENTRE, "the open menu was not moved")
	_menu.open(4, CENTRE + Vector2(50, 0), _hold)
	assert_true(_menu.visible, "empty slot")
	assert_eq(_menu.position, CENTRE, "the open menu was not moved")


func test_a_missing_player_closes_the_menu_and_opens_nothing():
	_open()
	_units.erase(BattleRunner.PLAYER_SLOT)
	_open()
	assert_false(_menu.visible)


func test_a_pick_reports_the_slot_move_and_target_after_the_menu_has_closed():
	_open()
	var picks: Array = []
	_menu.move_picked.connect(func(bar_index, move_id, target_slot): picks.append([bar_index, move_id, target_slot, _menu.visible]))
	_menu.orbs[1].pressed.emit()
	assert_eq(picks, [[1, DESTROY_ID, ENEMY_SLOT, false]])


func test_the_menu_is_whole_through_the_grace_period():
	_open()
	_menu.advance(RadialMenu.LEAVE_GRACE, FAR)
	assert_eq(_menu.modulate.a, 1.0)


func test_the_menu_fades_after_the_grace_and_closes_when_the_fade_is_spent():
	_open()
	_menu.advance(RadialMenu.LEAVE_GRACE + RadialMenu.FADE_TIME * 0.5, FAR)
	assert_almost_eq(_menu.modulate.a, 0.5, 0.001, "halfway through the fade")
	assert_true(_menu.visible)
	_menu.advance(RadialMenu.FADE_TIME * 0.5, FAR)
	assert_false(_menu.visible)


# The orbs fan out well outside the unit's hit area, so checking the unit alone
# would close the menu as the player moved toward an orb.
func test_the_hold_area_and_every_shown_orb_keep_the_menu_open():
	_open()
	var spent: float = RadialMenu.LEAVE_GRACE + RadialMenu.FADE_TIME
	assert_false(_hold.get_global_rect().has_point(_orb_centre(1)), "sanity: orb 1 is outside the hold area")
	_menu.advance(spent, _hold_centre())
	assert_true(_menu.visible, "over the hold area")
	_menu.advance(spent, _orb_centre(1))
	assert_true(_menu.visible, "over an orb")


func test_a_hidden_orb_does_not_keep_the_menu_open():
	_open()
	var hidden_orb_centre: Vector2 = _orb_centre(7)
	assert_false(_hold.get_global_rect().has_point(hidden_orb_centre), "sanity: outside the hold area")
	_menu.advance(RadialMenu.LEAVE_GRACE + RadialMenu.FADE_TIME, hidden_orb_centre)
	assert_false(_menu.visible)


func test_the_mouse_returning_mid_fade_snaps_back_and_restarts_the_grace():
	_open()
	_menu.advance(RadialMenu.LEAVE_GRACE + RadialMenu.FADE_TIME * 0.5, FAR)
	_menu.advance(0.0, _hold_centre())
	assert_eq(_menu.modulate.a, 1.0, "snapped back to whole")
	_menu.advance(RadialMenu.LEAVE_GRACE, FAR)
	assert_eq(_menu.modulate.a, 1.0, "the mouse leaving again gets a full grace")


# A Tween that outlived its menu once closed the next menu a moment later
# (08dc6a7).
func test_opening_on_another_unit_replaces_a_fading_menu():
	_open()
	_menu.advance(RadialMenu.LEAVE_GRACE + RadialMenu.FADE_TIME * 0.5, FAR)
	assert_lt(_menu.modulate.a, 1.0, "the first menu is fading")

	_menu.open(BattleRunner.PLAYER_SLOT, CENTRE + Vector2(100, 0), _hold)
	assert_eq(_menu.modulate.a, 1.0, "the new menu starts whole")
	_menu.advance(RadialMenu.LEAVE_GRACE, FAR)
	assert_eq(_menu.modulate.a, 1.0, "with a full grace of its own")
	_menu.advance(RadialMenu.FADE_TIME, _orb_centre(0))
	assert_true(_menu.visible, "well past where the first fade would have ended")

	var picks: Array = []
	_menu.move_picked.connect(func(_bar_index, _move_id, target_slot): picks.append(target_slot))
	_menu.orbs[0].pressed.emit()
	assert_eq(picks, [BattleRunner.PLAYER_SLOT], "and it belongs to the newly clicked unit")


func test_an_orbs_tooltip_carries_the_moves_description():
	_moves[LEADING_STRIKE_ID].tooltip_description = "Attack the enemy."
	_moves[LEADING_STRIKE_ID].cooldown_turns = 3
	_open()
	_menu.orbs[0].mouse_entered.emit()
	assert_eq(_tooltip_lines(), ["Leading Strike", "This move costs nothing", "Attack the enemy.", "Cooldown: 3 turns"])
	_menu.orbs[0].mouse_exited.emit()
	assert_false(GameTooltip._root.visible, "leaving the orb hides it")


func test_an_orb_shows_the_moves_icon_art_not_initials():
	_open()
	var orb: Button = _menu.orbs[0]
	assert_not_null(orb.icon, "loaded the move's real extracted icon art")
	assert_eq(orb.icon.resource_path, "res://assets/ui/abilities/Leading_Strike.png")
	assert_eq(orb.text, "", "no 2-letter initials now that real art is shown")


func test_closing_drops_the_tooltip_an_orb_raised():
	_open()
	_menu.orbs[0].mouse_entered.emit()
	assert_true(GameTooltip._root.visible, "the orb raised it")
	_menu.decision_open = false
	assert_false(GameTooltip._root.visible)


func test_closing_leaves_a_tooltip_the_menu_did_not_raise():
	_open()
	GameTooltip.show_sections([{"bg_color": Color.BLACK, "lines": [{"text": "Quit", "color": Color.WHITE}]}], _hold)
	_menu.decision_open = false
	assert_true(GameTooltip._root.visible)
