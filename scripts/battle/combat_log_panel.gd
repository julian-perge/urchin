# combat_log_panel.gd
# This panel is a combat log the original game never had. It starts hidden,
# and the Log button (LogToggleButton in battle_scene.tscn) shows and hides
# it. _play_events() in battle_scene.gd calls append_event() with each event
# just before playing it, whether or not the panel is showing.
# docs/adr/0001-keep-the-combat-log.md records why the port keeps it and the
# rule that each line says what a move or a Buff tick did to its target, which
# matters under an sswitch buff, where damage heals and a heal hurts.
extends PanelContainer
class_name CombatLogPanel

# The label is the panel's only child and does its own scrolling
# (scroll_following keeps the newest line in view). An outer ScrollContainer
# used to wrap it, and the two fought: the label scrolled inside its own
# oversized viewport while the container stayed parked at the top, so the
# player never saw a new line without dragging the scrollbar.
@onready var _log_text: RichTextLabel = $LogText

# A long boss fight can run hundreds of events; capping the backing line
# array (rather than letting `text +=` grow forever) bounds both the
# string-reallocation cost and the RichTextLabel's own line cache.
const MAX_LINES: int = 200

var _lines: Array[String] = []


func toggle() -> void:
	visible = not visible


# Appends one line for an event, if that event type produces a readable line at
# all.
func append_event(event: Dictionary, units: Dictionary) -> void:
	var line: String = _format_line(event, units)
	if line.is_empty():
		return
	_lines.append(line)
	if _lines.size() > MAX_LINES:
		_lines.pop_front()
	_log_text.text = "\n".join(_lines)


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
				_unit_name(units, int(event["caster_slot"])), BattleRunner.FailReason.find_key(event["reason"]).to_lower(),
			]
		BattleRunner.EventType.DISPEL:
			return "%s's buffs are dispelled" % _unit_name(units, int(event["target_slot"]))
		BattleRunner.EventType.BUFF_TICK:
			return _format_tick_line(event, units)
		BattleRunner.EventType.DEATH:
			return "%s falls" % _unit_name(units, int(event["slot"]))
		BattleRunner.EventType.SPEECH:
			return "%s: %s" % [str(event["speaker_name"]), str(event.get("say", ""))]
		_:
			return ""


# A Buff tick gets a line when it did something, worded by what it did to the
# unit: ADR 0001 has each line say what happened to its target. A tick that did
# nothing gets none, and neither does a tick that only moved Focus or ran a buff
# out, because the original draws nothing for those either. A tick that kills its
# unit is followed by a DEATH event, which has its own line.
func _format_tick_line(event: Dictionary, units: Dictionary) -> String:
	var tick: BuffTick = event["tick"]
	var unit_name: String = _unit_name(units, int(event["caster_slot"]))
	if tick.shield_took_all:
		return "%s's shield soaks the damage from buffs" % unit_name
	match tick.direction:
		MoveResult.Direction.HARM when tick.amount > 0:
			return "%s takes %d %s damage from buffs" % [unit_name, int(tick.amount), CombatUnit.ELEMENT_ORDER[tick.element]]
		MoveResult.Direction.HEAL when tick.amount > 0:
			return "%s regains %d life from buffs" % [unit_name, int(tick.amount)]
	return ""


func _format_move_line(event: Dictionary, units: Dictionary) -> String:
	var caster_name: String = _unit_name(units, int(event["caster_slot"]))
	var target_name: String = _unit_name(units, int(event["target_slot"]))
	var move_name: String = str(event.get("move_name", "a move"))
	var result: MoveResult = event["result"]
	# ADR 0001 has each line say what the move did to its target, so a line is
	# worded by which way the move pushed the target's life. A move that pushed it
	# neither way is worded by its kind, and so is a heal of 0, which keeps the
	# HEAL direction only because the original checks a heal's amount before it
	# checks sswitch.
	match result.direction:
		MoveResult.Direction.HARM:
			return "%s hits %s with %s for %d" % [caster_name, target_name, move_name, int(result.amount)]
		MoveResult.Direction.HEAL when result.kind != MoveResult.Kind.HEAL or result.amount > 0:
			return "%s heals %s with %s for %d" % [caster_name, target_name, move_name, int(result.amount)]
	match result.kind:
		MoveResult.Kind.HEAL:
			if result.buff_applied.is_empty():
				return "%s's %s has no effect on %s" % [caster_name, move_name, target_name]
			return "%s uses %s on %s" % [caster_name, move_name, target_name]
		MoveResult.Kind.FOCUS:
			if result.amount < 0:
				return "%s drains %s's focus by %d" % [caster_name, target_name, -int(result.amount)]
			return "%s restores %s's focus by %d" % [caster_name, target_name, int(result.amount)]
		MoveResult.Kind.MISS:
			return "%s's %s misses %s" % [caster_name, move_name, target_name]
		MoveResult.Kind.STATUS_ONLY:
			if result.buff_applied.is_empty():
				return "%s's %s has no effect on %s" % [caster_name, move_name, target_name]
			return "%s hits %s with %s" % [caster_name, target_name, move_name]
		_:
			return ""
