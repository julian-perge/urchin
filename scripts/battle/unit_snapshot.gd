# unit_snapshot.gd
# What an event left on the unit it changed: its life, its Focus, its stun and
# its buff slots. The runner resolves a whole half-turn before the replay
# starts, so by the time an event plays, the unit already holds every later
# change in that half-turn. FighterPresenter draws its bars, stun pose and buff
# icons from the snapshot of the last event it has shown, and never from the
# unit.
class_name UnitSnapshot
extends RefCounted

var life: float = 0.0
var life_max: float = 0.0
var focus: float = 0.0
var focus_max: float = 0.0
var stun: float = 0.0
# Copies of the unit's buff slots, in the unit's slot order, each one
# {cd, buff_id, buff_value, shield_buff_value} like CombatUnit.buff_slots.
var buff_slots: Array = []


static func of(unit: CombatUnit) -> UnitSnapshot:
	var snapshot := UnitSnapshot.new()
	snapshot.life = unit.life_n
	snapshot.life_max = unit.life_u
	snapshot.focus = unit.focus_n
	snapshot.focus_max = unit.focus_u
	snapshot.stun = unit.stun
	snapshot.buff_slots = unit.buff_slots.duplicate(true)
	return snapshot


# Returns a copy of this snapshot with `new_life` as its life. Events hold their
# snapshots after they play, so a change goes on a copy.
func with_life(new_life: float) -> UnitSnapshot:
	var snapshot := UnitSnapshot.new()
	snapshot.life = new_life
	snapshot.life_max = life_max
	snapshot.focus = focus
	snapshot.focus_max = focus_max
	snapshot.stun = stun
	snapshot.buff_slots = buff_slots.duplicate(true)
	return snapshot


# battle_scene.gd writes events to battle.log with JSON.stringify, which prints
# an object as its id, so the scene writes this dictionary in its place. It
# lists only the slots that hold a buff, because the other slots are blank.
func to_dict() -> Dictionary:
	return {
		"life": life,
		"life_max": life_max,
		"focus": focus,
		"focus_max": focus_max,
		"stun": stun,
		"buffs": buff_slots.filter(func(slot): return int(slot["cd"]) != 0).map(
			func(slot): return {"buff_id": slot["buff_id"], "cd": slot["cd"]}
		),
	}
