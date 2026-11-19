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
const BATTLE_LAYOUT_PATH: String = "res://assets/backgrounds/battle/battle_layout.json"

var _layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BATTLE_LAYOUT_PATH))
var _menu: RadialMenu
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
	_menu.open(ENEMY_SLOT, CENTRE)


# Steps the menu by whole SWF frames with the mouse at point. extract_battle_screen
# writes the SWF's frame rate into battle_layout.json.
func _step(point: Vector2, frames: int = 1) -> void:
	for i in frames:
		_menu.advance(_frame_time(), point)


func _frame_time() -> float:
	return 1.0 / float(_layout["fade"]["fps"])


# Opens the menu and plays the three frames its fade-in takes, after which the
# mouse counts.
func _open_and_settle() -> void:
	_open()
	_step(CENTRE, 3)


func _ring_scale() -> float:
	return float(_layout["radial_menu"]["scale"])


# Where orb bar_index sits on the stage: its button's rect from
# battle_layout.json, scaled, around the menu's centre.
func _orb_rect(bar_index: int) -> Rect2:
	var rect: Dictionary = _layout["radial_menu"]["orb_rects"][bar_index]
	return Rect2(CENTRE + Vector2(rect["x"], rect["y"]) * _ring_scale(), Vector2(rect["w"], rect["h"]) * _ring_scale())


# The Radial menu clip's box on the stage, from battle_layout.json.
func _box() -> Rect2:
	var box: Dictionary = _layout["radial_menu"]["box"]
	return Rect2(CENTRE + Vector2(box["x"], box["y"]) * _ring_scale(), Vector2(box["w"], box["h"]) * _ring_scale())


func _gap_between_orbs(first: int, second: int) -> Vector2:
	return (_orb_rect(first).get_center() + _orb_rect(second).get_center()) / 2.0


func _on_any_orb(point: Vector2) -> bool:
	return _menu.orbs.any(func(orb): return orb.get_global_rect().has_point(point))


func _orb_centre(bar_index: int) -> Vector2:
	return _menu.orbs[bar_index].get_global_rect().get_center()


# The black disc the original lays over a darkened orb, its "bfilter".
func _cover(bar_index: int) -> TextureRect:
	return _menu.orbs[bar_index].get_node("Cover")


# The turns left on a cooldown, the original's "ACD" field.
func _count(bar_index: int) -> Label:
	return _menu.orbs[bar_index].get_node("Count")


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
	var shown: Array = _menu.orbs.map(func(orb): return orb.visible)
	assert_eq(shown, [true, true, false, false, false, false, false, false])


# Bar slot 0 locked on cooldown used to vanish from the menu, shifting bar slot
# 1's move into slot 0's arc position. The source only hides a truly empty
# ("None") slot and never renumbers around a temporarily-unusable one.
func test_an_orb_sits_at_its_own_bar_slots_offset():
	_player.ability_cooldowns[0] = 5
	_open()
	assert_almost_eq(_orb_centre(1), _orb_rect(1).get_center(), Vector2(0.01, 0.01))


# Each orb is its thingo button's rect, scaled by the Radial menu clip's scale,
# which moves every orb out from the unit and grows it by that scale.
func test_every_orb_is_its_buttons_rect_times_the_clips_scale():
	assert_gt(_ring_scale(), 1.0, "sanity: the clip is scaled up")
	_open()
	for bar_index in _menu.orbs.size():
		var orb_rect: Rect2 = _menu.orbs[bar_index].get_global_rect()
		var want: Rect2 = _orb_rect(bar_index)
		assert_almost_eq(orb_rect.position, want.position, Vector2(0.01, 0.01), "orb %d's corner" % bar_index)
		assert_almost_eq(orb_rect.size, want.size, Vector2(0.01, 0.01), "orb %d's size" % bar_index)


# The box hitTest uses holds every button, so the mouse on any part of a shown
# orb keeps the menu open.
func test_every_orb_lies_inside_the_clips_box():
	_open()
	for bar_index in _menu.orbs.size():
		assert_true(_box().grow(0.01).encloses(_menu.orbs[bar_index].get_global_rect()), "orb %d" % bar_index)


func test_the_menu_opens_when_every_equipped_move_is_refused():
	_player.ability_cooldowns[0] = 5
	_player.ability_cooldowns[1] = 5
	_open()
	assert_true(_menu.visible, "the source only hides empty slots")
	assert_true(_cover(0).visible)
	assert_true(_cover(1).visible)


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
	assert_true(_cover(0).visible)
	assert_eq(_count(0).text, "5")
	_player.ability_cooldowns[0] = 0
	_player.equipped_moves[1] = 0
	_open()
	assert_false(_cover(0).visible, "the cooldown ended")
	assert_eq(_count(0).text, "", "and its count is cleared")
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
	_menu.open(ENEMY_SLOT, CENTRE + Vector2(50, 0))
	assert_true(_menu.visible, "dead target")
	assert_eq(_menu.position, CENTRE, "the open menu was not moved")
	_menu.open(4, CENTRE + Vector2(50, 0))
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


# Clicks the orb and returns what the menu said back: every pick_refused
# message and every move_picked bar slot, in the order they came.
func _click_orb(bar_index: int) -> Dictionary:
	var said: Dictionary = {"refused": [], "picked": []}
	_menu.pick_refused.connect(func(message): said["refused"].append(message))
	_menu.move_picked.connect(func(picked_bar_index, _move_id, _target_slot): said["picked"].append(picked_bar_index))
	_menu.orbs[bar_index].pressed.emit()
	return said


# The original's orb buttons call addMoveForPlayer with no gate of their own, so
# every orb takes the click. A pick that fails a check shows that check's
# message in the Combat text banner, and only a pick that passes closes the
# menu (frame_42/DoAction_11.as:60-104). Only a bad target or a cooldown
# darkens the orb (frame_217/PlaceObject3_3382_500 enterFrame, lines 15-29).
func _assert_lit_and_refused(bar_index: int, message: String) -> void:
	assert_false(_cover(bar_index).visible, "the orb is not darkened")
	assert_eq(_count(bar_index).text, "", "and shows no count")
	var said: Dictionary = _click_orb(bar_index)
	assert_eq(said["refused"], [message], "the click says why")
	assert_eq(said["picked"], [], "nothing is picked")
	assert_true(_menu.visible, "and the menu stays open")


func _assert_darkened_and_refused(bar_index: int, count: String, message: String) -> void:
	assert_true(_cover(bar_index).visible, "the orb is darkened")
	assert_eq(_count(bar_index).text, count, "the count is the turns left")
	var said: Dictionary = _click_orb(bar_index)
	assert_eq(said["refused"], [message], "the click says why")
	assert_eq(said["picked"], [], "nothing is picked")
	assert_true(_menu.visible, "and the menu stays open")


func test_an_orb_short_of_focus_stays_lit_and_says_why_when_clicked():
	_moves[LEADING_STRIKE_ID].focus_cost = 10.0
	_open()
	_assert_lit_and_refused(0, "You cannot use this move because you don't have enough Focus.")


func test_a_silenced_orb_stays_lit_and_says_why_when_clicked():
	_player.focus_n = 100.0
	_player.silenced = 1.0
	_moves[LEADING_STRIKE_ID].focus_cost = 10.0
	_open()
	_assert_lit_and_refused(0, "You cannot use moves that require Focus this turn.")


func test_an_orb_short_of_life_stays_lit_and_says_why_when_clicked():
	_moves[LEADING_STRIKE_ID].flat_life_cost = 1000.0
	_open()
	_assert_lit_and_refused(0, "You cannot use this move because you don't have enough Health.")


func test_an_orb_whose_target_lacks_its_buffs_stays_lit_and_says_why_when_clicked():
	_moves[LEADING_STRIKE_ID].required_buff_count = 1
	_open()
	_assert_lit_and_refused(0, "The target's status does not meet the requirements of this move.")


func test_an_orb_for_a_bad_target_is_darkened_and_says_why_when_clicked():
	_moves[LEADING_STRIKE_ID].can_target_others = false
	_open()
	_assert_darkened_and_refused(0, "", "You cannot use this move on that target.")


func test_an_orb_on_cooldown_is_darkened_shows_its_turns_left_and_says_why_when_clicked():
	_player.ability_cooldowns[0] = 3
	_open()
	_assert_darkened_and_refused(0, "3", "This move is not ready yet.")
	assert_false(_cover(1).visible, "the other slot is untouched")
	assert_eq(_count(1).text, "")


# addMoveForPlayer writes a message for every check that fails and shows the
# last one written, so a cooldown outranks Focus and life outranks a cooldown.
# The orb darkens for its cooldown whichever message wins, because the ring's
# enterFrame tests the cooldown on its own.
func test_when_two_checks_fail_the_click_says_the_one_the_original_shows():
	_moves[LEADING_STRIKE_ID].focus_cost = 10.0
	_player.ability_cooldowns[0] = 2
	_moves[DESTROY_ID].flat_life_cost = 1000.0
	_player.ability_cooldowns[1] = 4
	_open()
	_assert_darkened_and_refused(0, "2", "This move is not ready yet.")
	_assert_darkened_and_refused(1, "4", "You cannot use this move because you don't have enough Health.")


func test_a_refused_pick_leaves_the_next_orb_free_to_pick_the_move_and_close_the_menu():
	_moves[LEADING_STRIKE_ID].focus_cost = 10.0
	_open()
	_click_orb(0)
	var said: Dictionary = _click_orb(1)
	assert_eq(said["refused"], [], "a pick with no Refusal is not refused")
	assert_eq(said["picked"], [1], "it picks the move")
	assert_false(_menu.visible, "and closes the menu")


# The cover is DefineSprite 2241, a black disc 23 px across on the orb's centre,
# which the ring's enterFrame sets to 75% alpha while it fades in and 85% once
# it has (lines 16 and 42).
# The count is edit text 2245, 12 px grey and centred, laid out 2 px inside
# bounds that the orb places 17.2 px left of and 8.65 px above its centre.
func test_a_darkened_orb_takes_the_originals_cover_and_count():
	_player.ability_cooldowns[0] = 3
	_open()
	var centre: Vector2 = _orb_centre(0)
	var cover: TextureRect = _cover(0)
	assert_almost_eq(cover.get_global_rect().position - centre, Vector2(-11.5, -11.5), Vector2(0.5, 0.5), "the disc sits on the centre")
	assert_almost_eq(cover.size, Vector2(23, 23), Vector2(0.5, 0.5), "23 px across")
	assert_almost_eq(cover.modulate.a, 0.75, 0.001, "at 75% alpha while the ring fades in")
	_step(CENTRE, 3)
	assert_almost_eq(cover.modulate.a, 0.85, 0.001, "and 85% once it has")
	var count: Label = _count(0)
	assert_almost_eq(count.get_global_rect().position - centre, Vector2(-15.2, -6.65), Vector2(0.001, 0.001), "where the count starts")
	assert_almost_eq(count.size.x, 30.35, 0.001, "how wide it is")
	assert_eq(count.get_theme_font_size("font_size"), 12, "12 px")
	assert_eq(count.get_theme_color("font_color"), Color8(153, 153, 153), "grey")
	assert_eq(count.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "centred")


# The original's ring adds 50 alpha a frame from the 0 a click shows it at, and
# only tests the mouse once that is done (frame_217/DoAction_3.as:46-48,
# frame_217/PlaceObject3_3382_500 enterFrame, lines 32-46).
func test_a_new_menu_fades_in_over_two_frames_and_ignores_the_mouse_meanwhile():
	_open()
	assert_eq(_menu.modulate.a, 0.0, "a click shows the clip at alpha 0")
	_step(FAR)
	assert_almost_eq(_menu.modulate.a, 0.5, 0.001, "half after one frame")
	_step(FAR)
	assert_almost_eq(_menu.modulate.a, 1.0, 0.001, "full after two")
	_step(FAR)
	assert_almost_eq(_menu.modulate.a, 1.0, 0.001, "the third frame ends the fade-in")
	_step(FAR)
	assert_almost_eq(_menu.modulate.a, 0.9, 0.001, "and from the fourth the mouse counts")


# hitTest with no shape flag tests the clip's bounding box, so the gaps between
# orbs and the unit inside the ring count as over it (enterFrame line 48).
func test_a_gap_between_two_orbs_and_the_unit_inside_the_ring_hold_the_menu():
	_open_and_settle()
	var gap: Vector2 = _gap_between_orbs(0, 1)
	assert_false(_on_any_orb(gap), "sanity: the gap is on no orb")
	assert_false(_on_any_orb(CENTRE), "sanity: the unit is on no orb")
	_step(gap, 30)
	assert_almost_eq(_menu.modulate.a, 1.0, 0.001, "the gap holds it at full alpha")
	_step(CENTRE, 30)
	assert_almost_eq(_menu.modulate.a, 1.0, 0.001, "and so does the unit")
	assert_true(_menu.visible)


func test_the_clips_box_holds_the_menu_to_its_edge():
	_open_and_settle()
	var box: Rect2 = _box()
	var inside: Vector2 = box.position + Vector2(0.5, 0.5)
	assert_false(_on_any_orb(inside), "sanity: the corner is on no orb")
	_step(inside, 30)
	assert_almost_eq(_menu.modulate.a, 1.0, 0.001, "just inside the corner")
	_step(box.position - Vector2(0.5, 0.5))
	assert_almost_eq(_menu.modulate.a, 0.9, 0.001, "just outside it")


# Off the clip the original takes 10 alpha a frame and hides the clip at 0, with
# no grace (enterFrame lines 48-61).
func test_off_the_clip_alpha_falls_a_tenth_a_frame_and_the_menu_closes_after_ten():
	_open_and_settle()
	for frame in range(1, 10):
		_step(FAR)
		assert_almost_eq(_menu.modulate.a, 1.0 - frame * 0.1, 0.001, "frame %d" % frame)
		assert_true(_menu.visible, "still up on frame %d" % frame)
	_step(FAR)
	assert_false(_menu.visible, "closed on the tenth frame")


# Back over the clip the original sets alpha straight to 100 (enterFrame line 64).
func test_coming_back_mid_fade_puts_alpha_straight_back_to_full():
	_open_and_settle()
	_step(FAR, 5)
	assert_almost_eq(_menu.modulate.a, 0.5, 0.001, "halfway through the fade")
	_step(_gap_between_orbs(2, 3))
	assert_almost_eq(_menu.modulate.a, 1.0, 0.001, "straight back to full")
	_step(FAR)
	assert_almost_eq(_menu.modulate.a, 0.9, 0.001, "and leaving again gets no grace")


# _process() hands advance() each rendered frame's delta, which is not the
# SWF's frame, so the menu steps only once a whole SWF frame has passed.
func test_the_menu_steps_once_per_swf_frame_whatever_the_delta():
	_open_and_settle()
	_menu.advance(_frame_time() * 0.5, FAR)
	assert_almost_eq(_menu.modulate.a, 1.0, 0.001, "half a frame changes nothing")
	_menu.advance(_frame_time() * 0.5, FAR)
	assert_almost_eq(_menu.modulate.a, 0.9, 0.001, "the second half completes the frame")
	_menu.advance(_frame_time() * 3.0, FAR)
	assert_almost_eq(_menu.modulate.a, 0.6, 0.001, "a long delta steps every frame it covers")


# An empty slot's thingo is hidden, but the bounding box hitTest uses is the
# whole clip's box, so the empty slot's place still holds the menu.
func test_an_empty_slots_place_still_holds_the_menu():
	_open_and_settle()
	var empty_slot: Vector2 = _orb_centre(7)
	assert_false(_menu.orbs[7].visible, "sanity: slot 7 is empty")
	_step(empty_slot, 30)
	assert_true(_menu.visible)
	assert_almost_eq(_menu.modulate.a, 1.0, 0.001)


# _process() runs while the menu is closed too, and that time must not play the
# next menu's frames the moment it opens.
func test_time_while_closed_does_not_carry_into_the_next_menu():
	_open_and_settle()
	_menu.decision_open = false
	_menu.advance(10.0, FAR)
	_menu.decision_open = true
	_open()
	_step(FAR)
	assert_almost_eq(_menu.modulate.a, 0.5, 0.001, "one frame into the fade-in")


# A Tween that outlived its menu once closed the next menu a moment later
# (08dc6a7).
func test_opening_on_another_unit_replaces_a_fading_menu():
	_open_and_settle()
	_step(FAR, 5)
	assert_lt(_menu.modulate.a, 1.0, "the first menu is fading")

	_menu.open(BattleRunner.PLAYER_SLOT, CENTRE + Vector2(100, 0))
	assert_eq(_menu.modulate.a, 0.0, "the new menu starts clear")
	_step(FAR, 3)
	assert_almost_eq(_menu.modulate.a, 1.0, 0.001, "and fades in whole")
	_step(FAR, 9)
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
	var anchor: Control = add_child_autofree(Control.new())
	GameTooltip.show_sections([{"bg_color": Color.BLACK, "lines": [{"text": "Quit", "color": Color.WHITE}]}], anchor)
	_menu.decision_open = false
	assert_true(GameTooltip._root.visible)
