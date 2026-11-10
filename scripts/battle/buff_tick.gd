# buff_tick.gd
# What one Buff tick did to the unit whose buffs ticked, as CombatUnit.tick_buffs
# resolved it. BattleRunner logs one in every BUFF_TICK event, and the battle
# screen and the combat log read these facts instead of working them out from
# the unit, the way they read a MoveResult.
class_name BuffTick
extends RefCounted

# Which way the tick moved the unit's life, after any turn-around by sswitch.
# buffTicker nets its healing and every element's damage into one total, so a tick
# moves life one way or not at all. Damage harms and healing heals, and under
# sswitch each one does the other. A tick that a shield soaked whole stays HARM
# with an amount of 0, as a Shield block does. A tick whose total came to 0 is
# NONE.
var direction: MoveResult.Direction = MoveResult.Direction.NONE

# What the Floating number shows: the damage that got past the shield, or the
# healing before max life caps it. It is 0 for a tick whose total came to 0 and
# for one that a shield soaked whole (frame_42/DoAction_10.as:64-98).
var amount: float = 0.0

# The element with the strictly largest damage in the tick, taken in the order of
# CombatUnit.ELEMENT_ORDER, or PHYSICAL when no element dealt any
# (frame_42/DoAction_10.as:25-40). A harmful tick draws its number in this
# element's color.
var element: CombatUnit.Element = CombatUnit.Element.PHYSICAL

# True when some element dealt damage in the tick, so that `element` is the one
# that dealt the most. It is false when `element` is only the PHYSICAL that the
# original's colorToBe starts at, as it is for a tick that hurts the unit only
# because sswitch turned its healing around.
var element_dealt_damage: bool = false

# True when the unit's shield was bigger than the whole total, so the shield took
# all of it and the unit lost no life. A shield exactly as big as the total does
# not count: the original takes its other branch, which leaves a total of 0
# (frame_42/DoAction_10.as:64-85).
var shield_took_all: bool = false

# True when the tick took the unit's last life.
var killed: bool = false

# The unit once the tick finished: its life and max life, its Focus, its stun and
# its buff slots after the buffs that ran out came off and the stats were
# recomputed (frame_42/DoAction_10.as:135). A buff that changes max life moves
# max life and life together when it runs out, so a bar draws both from this.
var after: UnitSnapshot = UnitSnapshot.new()


# True when the original's buffTickChecker is truthy: the total came to something
# other than 0, or a shield soaked the whole of it (frame_42/DoAction_10.as:99).
# Only such a tick draws a Floating number, gets a line in the combat log and
# holds the next action back. A tick that only moved Focus or only ran buffs out
# does none of them.
func did_something() -> bool:
	return shield_took_all or amount > 0.0


# battle_scene.gd writes events to battle.log with JSON.stringify, which prints
# an object as its id, so the scene writes this dictionary in its place.
func to_dict() -> Dictionary:
	return {
		"direction": MoveResult.Direction.find_key(direction),
		"amount": amount,
		"element": CombatUnit.ELEMENT_ORDER[element],
		"element_dealt_damage": element_dealt_damage,
		"shield_took_all": shield_took_all,
		"killed": killed,
		"after": after.to_dict(),
	}
