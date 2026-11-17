# The status bar's buff icons (scenes/battle/status_bar.tscn), which the original
# draws on each bar (frame_42/DoAction_10.as:340-379).
extends GutTest

const StatusBarScene = preload("res://scenes/battle/status_bar.tscn")


func after_each():
	GameTooltip.hide_tooltip()


func _make_buff(internal_name: String, display_name: String, element: CombatUnit.Element) -> Buff:
	var buff := Buff.new()
	buff.internal_name = internal_name
	buff.display_name = display_name
	buff.tooltip_description = "test"
	buff.element_type = element
	return buff


func test_refresh_buffs_includes_buff_id_zero():
	# buff_id 0 is a real buff (TWINGUARDIANS, dev/converted_json/buffs.json) -
	# not an empty-slot sentinel (that's buff_id -1, see CombatUnit's slot
	# init) - so it must show up like any other active buff. The slots are in
	# the order apply_changes leaves them, most turns first.
	var bar: StatusBar = add_child_autofree(StatusBarScene.instantiate())
	var unit := CombatUnit.new()
	unit.buff_slots = [
		{"cd": 7, "buff_id": 0, "buff_value": 0.0, "shield_buff_value": 0.0},   # TWINGUARDIANS, longer
		{"cd": 3, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0},   # FIRESAM, shorter
		{"cd": 0, "buff_id": -1, "buff_value": 0.0, "shield_buff_value": 0.0},  # real empty-slot sentinel, skipped
	]
	var buff_twin: Buff = _make_buff("TWINGUARDIANS", "Twin Guardians", CombatUnit.Element.EARTH)
	var buff_fire: Buff = _make_buff("FIRESAM", "The Immortal Flame", CombatUnit.Element.FIRE)
	var buffs_by_id: Dictionary = {0: buff_twin, 1: buff_fire}

	bar.refresh_buffs(unit.buff_slots, buffs_by_id)

	assert_eq(bar.buff_row.get_child_count(), 2, "both real active buffs shown, the empty slot skipped")
	var first: Control = bar.buff_row.get_child(0)
	var second: Control = bar.buff_row.get_child(1)

	first.mouse_entered.emit()
	var first_title: Label = GameTooltip._sections.get_child(0).get_child(0).get_child(0)
	assert_string_contains(first_title.text, "Twin Guardians", "slot 0 shows first")
	first.mouse_exited.emit()

	second.mouse_entered.emit()
	var second_title: Label = GameTooltip._sections.get_child(0).get_child(0).get_child(0)
	assert_string_contains(second_title.text, "The Immortal Flame", "slot 1 shows second")
	second.mouse_exited.emit()


func test_refresh_buffs_caps_at_seven_icons():
	var bar: StatusBar = add_child_autofree(StatusBarScene.instantiate())
	var unit := CombatUnit.new()
	var buff_fire: Buff = _make_buff("FIRESAM", "The Immortal Flame", CombatUnit.Element.FIRE)
	unit.buff_slots = []
	for cd in range(1, 9):  # 8 active slots, one more than the 7-slot cap
		unit.buff_slots.append({"cd": cd, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0})

	bar.refresh_buffs(unit.buff_slots, {1: buff_fire})

	assert_eq(bar.buff_row.get_child_count(), 7, "8 active buffs capped at the record's 7 slots")


# The original draws a unit's buff row inside applyChangesKrin, right after its
# sort (frame_42/DoAction_10.as:344-379): one KrinBuffShower for each of slots
# 0 to 6 whose CD isn't 0, in slot order, with no sort of its own. Here 17
# buffs hold 3 turns each in the order they landed, which is the order
# apply_changes leaves them in, since sorting tied slots that are already in
# order moves nothing. The row shows the first 7 of them.
func test_refresh_buffs_shows_the_first_seven_slots_in_slot_order():
	var bar: StatusBar = add_child_autofree(StatusBarScene.instantiate())
	var unit := CombatUnit.new()
	var names: Array = [
		"AGGRAVATE", "AMEND", "ANALYSIS", "APPLETHROW", "APPREHEND", "ARTERY", "AUXILLARY", "AVENGERFORM",
		"BADSMELL", "BADTRIP", "BANANALURE", "BEGGINGTACTICS", "BESEATED", "BLADESHIELD", "BLEED", "BLOCK",
		"BLOCKDAMAGE",
	]
	var buffs_by_id: Dictionary = {}
	unit.buff_slots = []
	for i in names.size():
		buffs_by_id[i] = _make_buff(names[i], names[i], CombatUnit.Element.PHYSICAL)
		unit.buff_slots.append({"cd": 3, "buff_id": i, "buff_value": 0.0, "shield_buff_value": 0.0})
	for i in CombatUnit.MAX_BUFF_LIMIT - names.size():
		unit.buff_slots.append({"cd": 0, "buff_id": -1, "buff_value": 0.0, "shield_buff_value": 0.0})

	bar.refresh_buffs(unit.buff_slots, buffs_by_id)

	var shown: Array = []
	for shower in bar.buff_row.get_children():
		var icon: TextureRect = shower.get_node("Icon")
		shown.append(icon.texture.resource_path.get_file().get_basename())
	assert_eq(shown, names.slice(0, 7), "the row shows slots 0 to 6 in slot order")


func test_refresh_buffs_skips_rebuild_when_state_is_unchanged():
	# Called after every combat event, not only when buffs actually change -
	# rebuilding an identical row would flicker and drop an open tooltip out
	# from under a hovering player for no reason.
	var bar: StatusBar = add_child_autofree(StatusBarScene.instantiate())
	var unit := CombatUnit.new()
	var buff_fire: Buff = _make_buff("FIRESAM", "The Immortal Flame", CombatUnit.Element.FIRE)
	unit.buff_slots = [{"cd": 3, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0}]

	bar.refresh_buffs(unit.buff_slots, {1: buff_fire})
	var icon_id: int = bar.buff_row.get_child(0).get_instance_id()

	bar.refresh_buffs(unit.buff_slots, {1: buff_fire})  # identical state

	assert_eq(bar.buff_row.get_child_count(), 1, "row still shows the one buff")
	assert_eq(bar.buff_row.get_child(0).get_instance_id(), icon_id, "same node - no rebuild happened")


func test_refresh_buffs_clears_expired_buffs():
	var bar: StatusBar = add_child_autofree(StatusBarScene.instantiate())
	var unit := CombatUnit.new()
	var buff_a := Buff.new()
	buff_a.internal_name = "FIRESAM"
	buff_a.element_type = CombatUnit.Element.FIRE
	unit.buff_slots = [{"cd": 1, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0}]
	bar.refresh_buffs(unit.buff_slots, {1: buff_a})
	assert_eq(bar.buff_row.get_child_count(), 1)

	unit.buff_slots = []  # buff expired
	bar.refresh_buffs(unit.buff_slots, {1: buff_a})
	await wait_process_frames(1)  # queue_free() defers actual removal to the next frame
	assert_eq(bar.buff_row.get_child_count(), 0, "cleared once the buff is gone")


func _find(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	for child in node.get_children():
		var found: Node = _find(child, type)
		if found != null:
			return found
	return null


# KrinBuffShower, DefineSprite 104, places buffColor, the icon and the
# counter, edit text 66, as siblings, and tints only buffColor
# (frame_42/DoAction_10.as:373-374), so the counter keeps its own white. Edit
# text 66 is placed where the record says from the icon's center.
func test_buff_counter_is_untinted_and_centered_over_the_icon():
	var bar: StatusBar = add_child_autofree(StatusBarScene.instantiate())
	var unit := CombatUnit.new()
	unit.buff_slots = [{"cd": 3, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0}]
	bar.refresh_buffs(unit.buff_slots, {1: _make_buff("FIRESAM", "The Immortal Flame", CombatUnit.Element.FIRE)})
	await wait_process_frames(2)
	var buff: Node = bar.buff_row.get_child(0)
	var counter: Label = _find(buff, "Label")
	var icon: TextureRect = _find(buff, "TextureRect")
	var tint: Color = counter.self_modulate
	var node: Node = counter
	while node != bar.buff_row:
		tint *= node.modulate
		node = node.get_parent()
	assert_eq(tint, Color.WHITE, "no element tint reaches the counter")
	assert_eq(icon.modulate, MenuTheme.ELEMENT_COLORS[CombatUnit.Element.FIRE], "the icon carries the tint")
	# The bar scales everything in it, so this reads the offset in the icon's own
	# space.
	var from_icon_center: Vector2 = counter.position - (icon.position + icon.size / 2.0)
	var field: Dictionary = StatusBar.record()["buff_row"]["counter"]
	assert_almost_eq(from_icon_center.x, float(field["rect"][0]), 0.01, "edit text 66's x from the icon's center")
	assert_almost_eq(from_icon_center.y, float(field["rect"][1]), 0.01, "and its y")
	assert_almost_eq(counter.size.x, float(field["rect"][2]), 0.01, "its text width")
	assert_eq(counter.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "and its centered text")


# The counter is edit text 66: the record gives its size and color, and its face is bold _sans.
func test_buff_counter_matches_edit_text_66():
	var bar: StatusBar = add_child_autofree(StatusBarScene.instantiate())
	var unit := CombatUnit.new()
	unit.buff_slots = [{"cd": 3, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0}]
	bar.refresh_buffs(unit.buff_slots, {1: _make_buff("FIRESAM", "The Immortal Flame", CombatUnit.Element.FIRE)})
	var counter: Label = _find(bar.buff_row.get_child(0), "Label")
	var field: Dictionary = StatusBar.record()["buff_row"]["counter"]
	assert_eq(counter.get_theme_font_size("font_size"), roundi(float(field["font_size"])), "the field's size")
	assert_eq((counter.get_theme_font("font") as FontVariation).base_font.resource_path, "res://assets/fonts/texgyreheros-bold.otf", "bold")
	assert_eq(counter.get_theme_color("font_color"), Color.html(field["color"]), "the field's color")


# The original's buff icon tooltip takes its title from the buff's name alone
# (frame_42/DoAction_10.as:375), and the icon's own counter, edit text 66,
# shows the turns left (line 364). With no turn count after it, a name like
# "Seek and Destroy" fits the title on one line.
func test_buff_tooltip_title_is_the_name_alone_and_the_icon_counts_the_turns():
	var bar: StatusBar = add_child_autofree(StatusBarScene.instantiate())
	var unit := CombatUnit.new()
	unit.buff_slots = [{"cd": 3, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0}]
	bar.refresh_buffs(unit.buff_slots, {1: _make_buff("FIRESAM", "Seek and Destroy", CombatUnit.Element.FIRE)})
	var buff: Control = bar.buff_row.get_child(0)
	assert_eq(_find(buff, "Label").text, "3", "the icon's counter shows the turns left")
	buff.mouse_entered.emit()
	await wait_process_frames(2)
	var title: Label = GameTooltip._sections.get_child(0).get_child(0).get_child(0)
	assert_eq(title.text, "Seek and Destroy", "the title is the name alone")
	assert_eq(title.get_line_count(), 1, "and fits on one line")


func _slot(cd: int, buff_id: int) -> Dictionary:
	return {"cd": cd, "buff_id": buff_id, "buff_value": 0.0, "shield_buff_value": 0.0}


func _bar(slot: int) -> StatusBar:
	var bar: StatusBar = StatusBarScene.instantiate()
	bar.slot = slot
	return add_child_autofree(bar)


# Returns the x of the center of each icon in the bar's space.
func _icon_centers(bar: StatusBar) -> Array:
	return bar.buff_row.get_children().map(func(shower: Control): return shower.position.x + shower.size.x / 2.0)


# The icon for slot h sits at (offset + space * h) * side, with the offset and the
# space from the extractor. An empty slot leaves its place empty, so the icons do
# not close up. The player's bars are on the left and take side 1.
func test_an_icon_sits_at_its_slots_place_on_the_players_side():
	var row: Dictionary = StatusBar.record()["buff_row"]
	var bar: StatusBar = _bar(1)
	var buff: Buff = _make_buff("FIRESAM", "The Immortal Flame", CombatUnit.Element.FIRE)
	bar.refresh_buffs([_slot(3, 1), _slot(0, -1), _slot(2, 1)], {1: buff})
	assert_eq(_icon_centers(bar), [
		(row["offset"] + row["space"] * 0) * row["player_side"],
		(row["offset"] + row["space"] * 2) * row["player_side"],
	], "slot 0 and slot 2, with slot 1's place empty")


func test_an_icon_on_a_right_hand_bar_takes_the_enemy_side():
	var row: Dictionary = StatusBar.record()["buff_row"]
	var bar: StatusBar = _bar(2)
	bar.refresh_buffs([_slot(3, 1)], {1: _make_buff("FIRESAM", "The Immortal Flame", CombatUnit.Element.FIRE)})
	assert_eq(_icon_centers(bar), [row["offset"] * row["enemy_side"]])
	assert_lt(_icon_centers(bar)[0], 0.0, "to the left of the bar's origin")


func test_icons_sit_on_the_line_between_the_two_fills():
	var bar: StatusBar = _bar(1)
	bar.refresh_buffs([_slot(3, 1)], {1: _make_buff("FIRESAM", "The Immortal Flame", CombatUnit.Element.FIRE)})
	var shower: Control = bar.buff_row.get_child(0)
	assert_almost_eq(shower.position.y + shower.size.y / 2.0, 0.0, 0.001)


func test_the_death_clear_takes_the_buff_icons_away():
	var bar: StatusBar = _bar(1)
	bar.refresh_buffs([_slot(3, 1)], {1: _make_buff("FIRESAM", "The Immortal Flame", CombatUnit.Element.FIRE)})
	assert_true(bar.buff_row.is_visible_in_tree())
	bar.clear_for_death()
	assert_false(bar.buff_row.is_visible_in_tree())


# Every one of the seven slots has its own place on each side, so a slot's place
# does not depend on how many icons come before it.
func test_seven_icons_sit_at_their_places_on_each_side():
	var row: Dictionary = StatusBar.record()["buff_row"]
	var buff: Buff = _make_buff("FIRESAM", "The Immortal Flame", CombatUnit.Element.FIRE)
	var slots: Array = []
	for index in int(row["slots"]):
		slots.append(_slot(3, 1))
	for case in [[1, row["player_side"]], [2, row["enemy_side"]]]:
		var bar: StatusBar = _bar(case[0])
		bar.refresh_buffs(slots, {1: buff})
		var expected: Array = []
		for index in int(row["slots"]):
			expected.append((row["offset"] + row["space"] * index) * case[1])
		assert_eq(_icon_centers(bar), expected, "slot %d's bar" % case[0])


# The original draws a slot only when its CD is not 0 (frame_42/DoAction_10.as:353).
# The slot here still names a real buff, so only its CD keeps it off the bar.
func test_a_slot_at_duration_0_shows_no_icon_even_with_a_real_buff_in_it():
	var bar: StatusBar = _bar(1)
	bar.refresh_buffs([_slot(3, 1), _slot(0, 1)], {1: _make_buff("FIRESAM", "The Immortal Flame", CombatUnit.Element.FIRE)})
	assert_eq(bar.buff_row.get_child_count(), 1)
