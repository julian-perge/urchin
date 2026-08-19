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
