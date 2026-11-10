# CombatLogPanel's event->text formatter - mirrors battle_scene.gd's
# _play_events() match structure so every animated event type also gets
# a readable log line. .claude/plan_battle_screen_niceties.md Task 5.
extends GutTest

const CombatLogPanelScene = preload("res://scenes/battle/combat_log_panel.tscn")

var units: Dictionary


func _result(kind: MoveResult.Kind, direction: MoveResult.Direction, amount: float) -> MoveResult:
	var result := MoveResult.new()
	result.kind = kind
	result.direction = direction
	result.amount = amount
	return result


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
		"result": _result(MoveResult.Kind.DAMAGE, MoveResult.Direction.HARM, 42.0),
	}
	assert_eq(panel._format_line(event, units), "Veradux hits Grulnak with Acid Slash for 42")


func test_format_sswitched_damage_line_reads_as_a_heal():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
		"move_name": "Acid Slash",
		"result": _result(MoveResult.Kind.DAMAGE, MoveResult.Direction.HEAL, 42.0),
	}
	var line: String = panel._format_line(event, units)
	assert_false(line.contains("hits"), "damage under sswitch healed the target, so the line can't say it hit")
	assert_eq(line, "Veradux heals Grulnak with Acid Slash for 42", "the line reads like any other heal and still names the attack")


func test_format_heal_move_line():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
		"move_name": "Heal",
		"result": _result(MoveResult.Kind.HEAL, MoveResult.Direction.HEAL, 42.0),
	}
	assert_eq(panel._format_line(event, units), "Veradux heals Grulnak with Heal for 42")


func test_format_sswitched_heal_line_reads_as_a_hit():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
		"move_name": "Heal",
		"result": _result(MoveResult.Kind.HEAL, MoveResult.Direction.HARM, 42.0),
	}
	assert_eq(panel._format_line(event, units), "Veradux hits Grulnak with Heal for 42")


# A heal of 0 moves no life, which is all a buff-only Heal move like Block ever
# heals, and the original draws nothing for it (frame_42/DoAction_8.as:172).
func test_format_heal_of_0_line_says_what_landed_instead():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
		"move_name": "Block",
		"result": _result(MoveResult.Kind.HEAL, MoveResult.Direction.HEAL, 0.0),
	}
	event["result"].buff_applied = "BLOCK"
	assert_eq(panel._format_line(event, units), "Veradux uses Block on Grulnak")
	event["result"].buff_applied = ""
	assert_eq(panel._format_line(event, units), "Veradux's Block has no effect on Grulnak", "no buff landed, so nothing happened to the target")


# A Focus move's amount is the change in focus it asks for, and Regulate and
# Disrupt ask for a negative one, which drains the target's focus.
func test_format_focus_move_line_says_whether_it_gave_or_drained():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var gift: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
		"move_name": "Aim For The Heart",
		"result": _result(MoveResult.Kind.FOCUS, MoveResult.Direction.NONE, 30.0),
	}
	var drain: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
		"move_name": "Regulate",
		"result": _result(MoveResult.Kind.FOCUS, MoveResult.Direction.NONE, -30.0),
	}
	assert_eq(panel._format_line(gift, units), "Veradux restores Grulnak's focus by 30")
	assert_eq(panel._format_line(drain, units), "Veradux drains Grulnak's focus by 30")


func test_format_miss_move_line():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
		"move_name": "Acid Slash",
		"result": _result(MoveResult.Kind.MISS, MoveResult.Direction.NONE, 0.0),
	}
	assert_eq(panel._format_line(event, units), "Veradux's Acid Slash misses Grulnak")


func test_format_status_only_move_line():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
		"move_name": "Shatter Bolt",
		"result": _result(MoveResult.Kind.STATUS_ONLY, MoveResult.Direction.NONE, 0.0),
	}
	event["result"].buff_applied = "SHATTERBOLT"
	assert_eq(panel._format_line(event, units), "Veradux hits Grulnak with Shatter Bolt")
	event["result"].buff_applied = ""
	assert_eq(panel._format_line(event, units), "Veradux's Shatter Bolt has no effect on Grulnak", "no status landed, so nothing happened to the target")


func test_format_failed_move_line_names_the_cost():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {"type": BattleRunner.EventType.MOVE_FAILED, "caster_slot": 1, "reason": BattleRunner.FailReason.FOCUS}
	assert_eq(panel._format_line(event, units), "Veradux doesn't have enough focus")
	event["reason"] = BattleRunner.FailReason.HEALTH
	assert_eq(panel._format_line(event, units), "Veradux doesn't have enough health")


func test_format_death_line():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {"type": BattleRunner.EventType.DEATH, "slot": 2}
	assert_eq(panel._format_line(event, units), "Grulnak falls")


func test_format_speech_line():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var event: Dictionary = {"type": BattleRunner.EventType.SPEECH, "speaker_slot": 1, "speaker_name": "Veradux", "say": "Watch out!"}
	assert_eq(panel._format_line(event, units), "Veradux: Watch out!")


func test_log_caps_at_max_lines_dropping_oldest():
	var panel: CombatLogPanel = add_child_autofree(CombatLogPanelScene.instantiate())
	var total: int = CombatLogPanel.MAX_LINES + 20
	for i in total:
		var event: Dictionary = {
			"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
			"move_name": "Acid Slash",
			"result": _result(MoveResult.Kind.DAMAGE, MoveResult.Direction.HARM, float(i)),
		}
		panel.append_event(event, units)

	var lines: PackedStringArray = panel._log_text.text.split("\n")
	assert_eq(lines.size(), CombatLogPanel.MAX_LINES, "capped at MAX_LINES, not left to grow unbounded")
	assert_string_contains(lines[0], "for 20", "the oldest 20 lines were dropped")
	assert_string_contains(lines[lines.size() - 1], "for %d" % (total - 1), "the newest line survives")


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
