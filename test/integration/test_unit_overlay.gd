# UnitOverlay's buff-icon row (scenes/battle/unit_overlay.tscn) -
# .claude/plan_battle_screen_niceties.md Task 4.
extends GutTest

const UnitOverlayScene = preload("res://scenes/battle/unit_overlay.tscn")


func test_refresh_buffs_populates_sorted_by_duration_capped_at_seven():
	var overlay: UnitOverlay = add_child_autofree(UnitOverlayScene.instantiate())
	var unit := CombatUnit.new()
	unit.buff_slots = [
		{"cd": 3, "buff_id": 1, "buff_value": 0.0, "shield_buff_value": 0.0},   # FIRESAM
		{"cd": 10, "buff_id": 0, "buff_value": 0.0, "shield_buff_value": 0.0},  # 0 = empty slot, skipped
	]
	var buff_a := Buff.new()
	buff_a.internal_name = "FIRESAM"
	buff_a.display_name = "The Immortal Flame"
	buff_a.tooltip_description = "test"
	buff_a.element_type = CombatUnit.Element.FIRE
	var buffs_by_id: Dictionary = {1: buff_a}

	overlay.refresh_buffs(unit, buffs_by_id)
	assert_eq(overlay.buff_row.get_child_count(), 1, "one real active buff shown, the empty slot skipped")


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
