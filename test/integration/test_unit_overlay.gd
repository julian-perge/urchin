# UnitOverlay's buff-icon row (scenes/battle/unit_overlay.tscn) -
# .claude/plan_battle_screen_niceties.md Task 4.
extends GutTest

const UnitOverlayScene = preload("res://scenes/battle/unit_overlay.tscn")


func _make_buff(internal_name: String, display_name: String, element: CombatUnit.Element) -> Buff:
	var buff := Buff.new()
	buff.internal_name = internal_name
	buff.display_name = display_name
	buff.tooltip_description = "test"
	buff.element_type = element
	return buff


func test_refresh_buffs_includes_buff_id_zero_and_sorts_by_duration_descending():
	# buff_id 0 is a real buff (TWINGUARDIANS, dev/converted_json/buffs.json) -
	# not an empty-slot sentinel (that's buff_id -1, see CombatUnit's slot
	# init) - so it must show up like any other active buff.
	var overlay: UnitOverlay = add_child_autofree(UnitOverlayScene.instantiate())
	var unit := CombatUnit.new()
	unit.buff_slots = [
		{"cd": 3, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0},   # FIRESAM, shorter
		{"cd": 7, "buff_id": 0, "buff_value": 0.0, "shield_buff_value": 0.0},   # TWINGUARDIANS, longer
		{"cd": 0, "buff_id": -1, "buff_value": 0.0, "shield_buff_value": 0.0},  # real empty-slot sentinel, skipped
	]
	var buff_twin: Buff = _make_buff("TWINGUARDIANS", "Twin Guardians", CombatUnit.Element.EARTH)
	var buff_fire: Buff = _make_buff("FIRESAM", "The Immortal Flame", CombatUnit.Element.FIRE)
	var buffs_by_id: Dictionary = {0: buff_twin, 1: buff_fire}

	overlay.refresh_buffs(unit, buffs_by_id)

	assert_eq(overlay.buff_row.get_child_count(), 2, "both real active buffs shown, the empty slot skipped")
	var first: TextureRect = overlay.buff_row.get_child(0)
	var second: TextureRect = overlay.buff_row.get_child(1)
	assert_string_contains(first.tooltip_text, "Twin Guardians", "higher cd (7) sorts first")
	assert_string_contains(second.tooltip_text, "The Immortal Flame", "lower cd (3) sorts second")


func test_refresh_buffs_caps_at_seven_icons():
	var overlay: UnitOverlay = add_child_autofree(UnitOverlayScene.instantiate())
	var unit := CombatUnit.new()
	var buff_fire: Buff = _make_buff("FIRESAM", "The Immortal Flame", CombatUnit.Element.FIRE)
	unit.buff_slots = []
	for cd in range(1, 9):  # 8 active slots, one more than the 7-slot cap
		unit.buff_slots.append({"cd": cd, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0})

	overlay.refresh_buffs(unit, {1: buff_fire})

	assert_eq(overlay.buff_row.get_child_count(), 7, "8 active buffs capped at MAX_BUFF_ICONS (7)")


func test_refresh_buffs_skips_rebuild_when_state_is_unchanged():
	# Called after every combat event, not only when buffs actually change -
	# rebuilding an identical row would flicker and drop an open tooltip out
	# from under a hovering player for no reason.
	var overlay: UnitOverlay = add_child_autofree(UnitOverlayScene.instantiate())
	var unit := CombatUnit.new()
	var buff_fire: Buff = _make_buff("FIRESAM", "The Immortal Flame", CombatUnit.Element.FIRE)
	unit.buff_slots = [{"cd": 3, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0}]

	overlay.refresh_buffs(unit, {1: buff_fire})
	var icon_id: int = overlay.buff_row.get_child(0).get_instance_id()

	overlay.refresh_buffs(unit, {1: buff_fire})  # identical state

	assert_eq(overlay.buff_row.get_child_count(), 1, "row still shows the one buff")
	assert_eq(overlay.buff_row.get_child(0).get_instance_id(), icon_id, "same node - no rebuild happened")


func test_refresh_buffs_clears_expired_buffs():
	var overlay: UnitOverlay = add_child_autofree(UnitOverlayScene.instantiate())
	var unit := CombatUnit.new()
	var buff_a := Buff.new()
	buff_a.internal_name = "FIRESAM"
	buff_a.element_type = CombatUnit.Element.FIRE
	unit.buff_slots = [{"cd": 1, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0}]
	overlay.refresh_buffs(unit, {1: buff_a})
	assert_eq(overlay.buff_row.get_child_count(), 1)

	unit.buff_slots = []  # buff expired
	overlay.refresh_buffs(unit, {1: buff_a})
	await wait_process_frames(1)  # queue_free() defers actual removal to the next frame
	assert_eq(overlay.buff_row.get_child_count(), 0, "cleared once the buff is gone")
