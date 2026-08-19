# combat_log_panel.gd
# A toggleable, live-narrated combat log - the first scrollable-text panel
# in the project. Mirrors battle_scene.gd's _play_events() event-type
# match exactly, so every event type that already drives animation/audio
# also gets a readable line here. Off/hidden by default.
extends PanelContainer
class_name CombatLogPanel

# The label is the panel's only child and does its own scrolling
# (scroll_following keeps the newest line in view). An outer ScrollContainer
# used to wrap it, and the two fought: the label scrolled inside its own
# oversized viewport while the container stayed parked at the top, so the
# player never saw a new line without dragging the scrollbar.
@onready var _log_text: RichTextLabel = $LogText


func toggle() -> void:
	visible = not visible


# Appends one line for an event, if that event type produces a readable
# line at all (phase_advanced/battle_ended don't - same events
# _play_events() plays a sound/does nothing visible for, respectively).
func append_event(event: Dictionary, units: Dictionary) -> void:
	var line: String = _format_line(event, units)
	if line.is_empty():
		return
	if _log_text.text != "":
		_log_text.text += "\n"
	_log_text.text += line


func _unit_name(units: Dictionary, slot: int) -> String:
	var unit: CombatUnit = units.get(slot)
	return unit.player_name if unit != null else "???"


func _format_line(event: Dictionary, units: Dictionary) -> String:
	match event.get("type"):
		BattleRunner.EventType.MOVE:
			return _format_move_line(event, units)
		BattleRunner.EventType.STUNNED:
			return "%s is stunned" % _unit_name(units, int(event["caster_slot"]))
		BattleRunner.EventType.MOVE_FAILED:
			return "%s doesn't have enough %s" % [
				_unit_name(units, int(event["caster_slot"])), str(event.get("reason", "")),
			]
		BattleRunner.EventType.DISPEL:
			return "%s's buffs are dispelled" % _unit_name(units, int(event["target_slot"]))
		BattleRunner.EventType.DEATH:
			return "%s falls" % _unit_name(units, int(event["slot"]))
		BattleRunner.EventType.SPEECH:
			return "%s: %s" % [_unit_name(units, int(event.get("speaker_slot", 0))), str(event.get("say", ""))]
		_:
			return ""


func _format_move_line(event: Dictionary, units: Dictionary) -> String:
	var caster_name: String = _unit_name(units, int(event["caster_slot"]))
	var target_name: String = _unit_name(units, int(event["target_slot"]))
	var move_name: String = str(event.get("move_name", "a move"))
	var result: Dictionary = event.get("result", {})
	match result.get("type"):
		BattleManager.ResultType.DAMAGE:
			return "%s hits %s with %s for %d" % [caster_name, target_name, move_name, int(result.get("amount", 0))]
		BattleManager.ResultType.HEAL:
			return "%s heals %s for %d" % [caster_name, target_name, int(result.get("amount", 0))]
		BattleManager.ResultType.FOCUS:
			return "%s restores %s's focus by %d" % [caster_name, target_name, int(result.get("amount", 0))]
		BattleManager.ResultType.MISS:
			return "%s's %s misses %s" % [caster_name, move_name, target_name]
		_:
			return ""
