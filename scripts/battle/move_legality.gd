# move_legality.gd
# The one rule for whether a unit may pick a move, decided when the move is
# chosen. BattleRunner keeps its own focus and life check for when the move
# runs, because the conductor has its own there too
# (frame_217/PlaceObject2_3389_480 enterFrame, line 355).
#
# The original refuses the player's picks in addMoveForPlayer
# (frame_42/DoAction_11.as:60-89) and filters the AI's in AImoveAdder
# (frame_42/DoAction_9.as:52, 87 and 128). Both use the same silence, focus and
# life tests, which can_afford() holds. Only the player checks a bar slot's
# cooldown, the target's required buffs and the target's relation, because the
# AI keeps one cooldown per pool and chooses its own target.
#
# No autoload references (same rule as CombatUnit and BattleAI). The buff lookup
# comes in as a parameter.
class_name MoveLegality
extends RefCounted

# Why a pick is refused, in the order refusal() tests for them. NONE means the
# pick is allowed.
enum Refusal { NONE, BAD_TARGET, LIFE, COOLDOWN, SILENCED, FOCUS, TARGET_STATUS }


static func can_afford(caster: CombatUnit, move: Ability) -> bool:
	return not (_is_silenced_from(caster, move) or _is_short_of_focus(caster, move) or _is_short_of_life(caster, move))


# The original writes one message per failed check and shows the last one
# written. The checks here run in the reverse of its order, so the first one
# that fails is the reason it would show.
static func refusal(caster: CombatUnit, move: Ability, bar_slot: int, target: CombatUnit, buffs_by_id: Dictionary) -> Refusal:
	if not _target_allowed(caster, move, target):
		return Refusal.BAD_TARGET
	if _is_short_of_life(caster, move):
		return Refusal.LIFE
	if bar_slot < caster.ability_cooldowns.size() and caster.ability_cooldowns[bar_slot] != 0:
		return Refusal.COOLDOWN
	if _is_silenced_from(caster, move):
		return Refusal.SILENCED
	if _is_short_of_focus(caster, move):
		return Refusal.FOCUS
	if _active_buffs_of_element(target, move.required_buff_element, buffs_by_id) < move.required_buff_count:
		return Refusal.TARGET_STATUS
	return Refusal.NONE


static func _is_silenced_from(caster: CombatUnit, move: Ability) -> bool:
	return move.focus_cost * caster.silenced != 0.0


static func _is_short_of_focus(caster: CombatUnit, move: Ability) -> bool:
	return caster.focus_n < move.focus_cost


# A caster needs strictly more life than the cost, so a move can never kill its
# own caster.
static func _is_short_of_life(caster: CombatUnit, move: Ability) -> bool:
	return caster.life_n <= move.flat_life_cost + round(caster.life_u * move.health_cost_percentage)


static func _target_allowed(caster: CombatUnit, move: Ability, target: CombatUnit) -> bool:
	if target == null or not target.active:
		return false
	if target == caster:
		return move.can_target_self
	if target.team_side == caster.team_side:
		return move.targets_allies
	return move.can_target_others


static func _active_buffs_of_element(unit: CombatUnit, element: CombatUnit.Element, buffs_by_id: Dictionary) -> int:
	var matching: int = 0
	for buff_slot in unit.buff_slots:
		if buff_slot["cd"] <= 0:
			continue
		var buff: Buff = buffs_by_id.get(buff_slot["buff_id"])
		if buff != null and buff.element_type == element:
			matching += 1
	return matching
