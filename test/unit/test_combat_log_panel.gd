# CombatLogPanel's event->text formatter - mirrors battle_scene.gd's
# _play_events() match structure so every animated event type also gets
# a readable log line. .claude/plan_battle_screen_niceties.md Task 5.
extends GutTest

const CombatLogPanelScene = preload("res://scenes/battle/combat_log_panel.tscn")

var units: Dictionary


func before_each():
	var caster := CombatUnit.new()
	caster.player_name = "Veradux"
	var target := CombatUnit.new()
	target.player_name = "Grulnak"
	units = {1: caster, 2: target}


func test_format_damage_move_line():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
		"move_name": "Acid Slash",
		"result": {"type": BattleManager.ResultType.DAMAGE, "amount": 42.0, "did_crit": false, "target_died": false},
	}
	assert_eq(panel._format_line(event, units), "Veradux hits Grulnak with Acid Slash for 42")


func test_format_miss_move_line():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
		"move_name": "Acid Slash",
		"result": {"type": BattleManager.ResultType.MISS},
	}
	assert_eq(panel._format_line(event, units), "Veradux's Acid Slash misses Grulnak")


func test_format_death_line():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {"type": BattleRunner.EventType.DEATH, "slot": 2}
	assert_eq(panel._format_line(event, units), "Grulnak falls")


func test_format_speech_line():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {"type": BattleRunner.EventType.SPEECH, "speaker_slot": 1, "say": "Watch out!"}
	assert_eq(panel._format_line(event, units), "Veradux: Watch out!")


# Regression test: the label used to sit inside a ScrollContainer, which
# stayed parked at the top while the label scrolled inside its own oversized
# viewport - the newest line was written but never visible. With the label as
# the panel's direct child, its own scroll_following keeps the tail in view.
func test_newest_line_stays_in_view():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	panel.toggle()
	var event: Dictionary = {"type": BattleRunner.EventType.DEATH, "slot": 2}
	for i in 60:
		panel.append_event(event, units)
	await wait_process_frames(3)

	var label: RichTextLabel = panel._log_text
	assert_true(label.get_line_count() > label.get_visible_line_count(), "more lines than fit - there is something to scroll")
	var bar: VScrollBar = label.get_v_scroll_bar()
	assert_almost_eq(bar.value, bar.max_value - bar.page, 1.0, "label is parked at the bottom, showing the newest lines")
	# The bottom-following above is only worth anything if the part of the
	# label that follows is actually on screen. Under the old ScrollContainer
	# nesting the label was taller than the panel and hung out the bottom, so
	# the followed lines were clipped away and the player saw stale ones.
	assert_true(
		panel.get_global_rect().encloses(label.get_global_rect()),
		"the whole label fits inside the panel, so the lines it scrolled to are the lines on screen"
	)
