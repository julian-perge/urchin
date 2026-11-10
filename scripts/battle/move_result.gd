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
# harms and a heal heals, and under sswitch each one does the other. A Shield
# block still leaves it HARM, with an amount of 0, because the original checks
# the shield before it checks sswitch (frame_42/DoAction_8.as:70-82). A heal of
# 0 stays HEAL under sswitch too, because the original checks the amount before
# it checks sswitch (frame_42/DoAction_8.as:172). Focus, status-only moves and
# misses are NONE.
var direction: Direction = Direction.NONE

# The damage that got past the shield, overkill included, or the heal before max
# life caps it. The original draws it over the target when it is above 0. A
# Shield block leaves it 0, and the original draws SHIELDED instead. On a focus
# move it is the focus change the move asks for, negative for a drain, which the
# original never draws (frame_42/DoAction_8.as:232-249).
var amount: float = 0.0

# True on a Shield block: the target's shield was bigger than the hit and took
# all of it (frame_42/DoAction_8.as:70-76). A shield exactly as big as the hit
# soaks it too, but that is not a Shield block. The original plays it as a hit
# that draws no number, so this stays false.
var shield_took_all: bool = false

# The target's life when the move started resolving on it, after the caster paid
# the move's costs.
var life_before: float = 0.0

var killed: bool = false
var critical: bool = false

# The internal name of the buff the move's status effect landed, or empty when
# none landed.
var buff_applied: String = ""

# Whether the target was stunned when the hit landed. The battle screen replays
# a half-turn only after the runner has resolved all of it, so by then the
# unit's own stun can already include a stun from later in that half-turn.
var target_stunned: bool = false

# The target once the move finished: its life, Focus, stun and buff slots after
# the status effect landed and after the stat recompute that follows every hit.
# That recompute moves life when the move lands or dispels a buff that changes
# max life. The battle screen draws the target from this at the impact, the way
# the original's applyChangesKrin redraws the target's bars, buff icons and stun
# pose after every strike that lands (the conductor, line 103, and
# frame_42/DoAction_10.as:342-379 and 468-481), because at replay time the unit
# can already hold changes from later in the half-turn.
var target_after: UnitSnapshot = UnitSnapshot.new()


# battle_scene.gd writes events to battle.log with JSON.stringify, which prints
# an object as its id, so the scene writes this dictionary in its place.
func to_dict() -> Dictionary:
	return {
		"kind": Kind.find_key(kind),
		"direction": Direction.find_key(direction),
		"amount": amount,
		"shield_took_all": shield_took_all,
		"life_before": life_before,
		"killed": killed,
		"critical": critical,
		"buff_applied": buff_applied,
		"target_stunned": target_stunned,
		"target_after": target_after.to_dict(),
	}
