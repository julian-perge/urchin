# move_result.gd
# What one move did to its target, as BattleManager resolved it. BattleRunner
# logs one in every MOVE event, and the battle screen, the combat log and the
# achievement counters read these facts instead of working them out from the
# move and the unit.
class_name MoveResult
extends RefCounted

enum Kind { DAMAGE, HEAL, FOCUS, MISS, STATUS_ONLY }
enum Direction { HARM, HEAL, NONE }

# The move's effect category, or MISS when the hit roll failed and nothing
# resolved. STATUS_ONLY is a move that computes no amount, so only its status
# effect can land.
var kind: Kind = Kind.STATUS_ONLY

# Which way the move pushed the target's life once sswitch had its say. Damage
# harms and a heal heals, and under sswitch each one does the other. A shield
# that takes the whole hit still leaves it HARM, with an amount of 0. A heal of
# 0 stays HEAL under sswitch too, because the original checks the amount before
# it checks sswitch (frame_42/DoAction_8.as:172). Focus, status-only moves and
# misses are NONE.
var direction: Direction = Direction.NONE

# The number the original draws over the target: the damage that got past the
# shield with any overkill included, the heal before max life caps it, or the
# change in focus.
var amount: float = 0.0

# True when the target's shield was bigger than the hit, which the original
# plays as a shield block (frame_42/DoAction_8.as:70-76). A shield exactly as
# big as the hit soaks it too, but the original plays that as a hit for 0, so
# this stays false.
var shield_took_all: bool = false

# The target's life when the move started resolving on it, after the caster paid
# the move's costs, and its life once the move finished, after the stat
# recompute that follows every hit. That recompute moves life when the move lands
# or dispels a buff that changes max life.
var life_before: float = 0.0
var life_after: float = 0.0

var killed: bool = false
var critical: bool = false

# The internal name of the buff the move's status effect landed, or empty when
# none landed.
var buff_applied: String = ""

# Whether the target was stunned when the hit landed. The battle screen replays
# a half-turn only after the runner has resolved all of it, so by then the
# unit's own stun can already include a stun from later in that half-turn.
var target_stunned: bool = false


# battle_scene.gd writes events to battle.log with JSON.stringify, which prints
# an object as its id, so the scene writes this dictionary in its place.
func to_dict() -> Dictionary:
	return {
		"kind": Kind.find_key(kind),
		"direction": Direction.find_key(direction),
		"amount": amount,
		"shield_took_all": shield_took_all,
		"life_before": life_before,
		"life_after": life_after,
		"killed": killed,
		"critical": critical,
		"buff_applied": buff_applied,
		"target_stunned": target_stunned,
	}
