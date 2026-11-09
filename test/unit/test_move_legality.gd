# MoveLegality, one table per gate. Every row starts from a unit and a move that
# pass everything, so the one thing a row changes is the gate it is about. The
# original's checks are frame_42/DoAction_11.as:60-89 for the player and
# frame_42/DoAction_9.as:52, 87 and 128 for the AI.
extends GutTest

const Refusal = MoveLegality.Refusal


func _unit(team: CombatUnit.Team) -> CombatUnit:
	var unit := CombatUnit.new()
	unit.team_side = team
	unit.life_u = 1000.0
	unit.life_n = 1000.0
	unit.focus_u = 10000.0
	unit.focus_n = 10000.0
	unit.ability_cooldowns = [0, 0, 0, 0, 0, 0, 0, 0]
	return unit


func _caster() -> CombatUnit:
	return _unit(CombatUnit.Team.ONE)


func _enemy() -> CombatUnit:
	return _unit(CombatUnit.Team.TWO)


func _move() -> Ability:
	var move := Ability.new()
	move.can_target_self = true
	move.can_target_others = true
	move.targets_allies = true
	return move


func _buff(id: int, element: CombatUnit.Element) -> Buff:
	var buff := Buff.new()
	buff.id = id
	buff.element_type = element
	return buff


func _hold_buff(unit: CombatUnit, buff_id: int, turns_left: int) -> void:
	unit.buff_slots.append({"cd": turns_left, "buff_id": buff_id, "buff_value": 0.0, "shield_buff_value": 0.0})


func test_cooldown_gate():
	for row in [
		{"name": "the slot is ready", "cooldown": 0, "bar_slot": 2, "expect": Refusal.NONE},
		{"name": "one turn left on the slot", "cooldown": 1, "bar_slot": 2, "expect": Refusal.COOLDOWN},
		{"name": "only another slot is cooling", "cooldown": 1, "bar_slot": 3, "expect": Refusal.NONE},
	]:
		var caster := _caster()
		caster.ability_cooldowns[2] = row["cooldown"]
		assert_eq(MoveLegality.refusal(caster, _move(), row["bar_slot"], _enemy(), {}), row["expect"], row["name"])


func test_silence_gate():
	for row in [
		{"name": "not silenced", "silenced": 0.0, "cost": 10.0, "expect": Refusal.NONE},
		{"name": "silenced and the move costs focus", "silenced": 1.0, "cost": 10.0, "expect": Refusal.SILENCED},
		{"name": "two silences stacked", "silenced": 2.0, "cost": 10.0, "expect": Refusal.SILENCED},
		{"name": "silenced but the move is free", "silenced": 1.0, "cost": 0.0, "expect": Refusal.NONE},
	]:
		var caster := _caster()
		caster.silenced = row["silenced"]
		var move := _move()
		move.focus_cost = row["cost"]
		assert_eq(MoveLegality.refusal(caster, move, 0, _enemy(), {}), row["expect"], row["name"])


func test_focus_gate():
	for row in [
		{"name": "exactly the cost", "focus": 10.0, "cost": 10.0, "expect": Refusal.NONE},
		{"name": "one short", "focus": 9.0, "cost": 10.0, "expect": Refusal.FOCUS},
		{"name": "no focus and a free move", "focus": 0.0, "cost": 0.0, "expect": Refusal.NONE},
	]:
		var caster := _caster()
		caster.focus_n = row["focus"]
		var move := _move()
		move.focus_cost = row["cost"]
		assert_eq(MoveLegality.refusal(caster, move, 0, _enemy(), {}), row["expect"], row["name"])


func test_life_gate():
	for row in [
		{"name": "life equal to a percentage cost", "life": 80.0, "total": 1000.0, "flat": 0.0, "percent": 0.08, "expect": Refusal.LIFE},
		{"name": "one above a percentage cost", "life": 81.0, "total": 1000.0, "flat": 0.0, "percent": 0.08, "expect": Refusal.NONE},
		{"name": "life equal to a flat cost", "life": 5.0, "total": 1000.0, "flat": 5.0, "percent": 0.0, "expect": Refusal.LIFE},
		{"name": "life equal to flat plus percentage", "life": 85.0, "total": 1000.0, "flat": 5.0, "percent": 0.08, "expect": Refusal.LIFE},
		{"name": "one above flat plus percentage", "life": 86.0, "total": 1000.0, "flat": 5.0, "percent": 0.08, "expect": Refusal.NONE},
		{"name": "12.5 rounds up to a cost of 13", "life": 13.0, "total": 100.0, "flat": 0.0, "percent": 0.125, "expect": Refusal.LIFE},
		{"name": "one above the rounded cost", "life": 14.0, "total": 100.0, "flat": 0.0, "percent": 0.125, "expect": Refusal.NONE},
	]:
		var caster := _caster()
		caster.life_n = row["life"]
		caster.life_u = row["total"]
		var move := _move()
		move.flat_life_cost = row["flat"]
		move.health_cost_percentage = row["percent"]
		assert_eq(MoveLegality.refusal(caster, move, 0, _enemy(), {}), row["expect"], row["name"])


func test_required_target_buff_gate():
	const ICE_ID: int = 1
	const SHADOW_ID: int = 2
	const UNKNOWN_ID: int = 99
	var buffs_by_id: Dictionary = {
		ICE_ID: _buff(ICE_ID, CombatUnit.Element.ICE),
		SHADOW_ID: _buff(SHADOW_ID, CombatUnit.Element.SHADOW),
	}
	var ice: CombatUnit.Element = CombatUnit.Element.ICE
	var shadow: CombatUnit.Element = CombatUnit.Element.SHADOW
	for row in [
		{"name": "no requirement on a clean target", "held": [], "element": ice, "needs": 0, "expect": Refusal.NONE},
		{"name": "needs one, holds none", "held": [], "element": shadow, "needs": 1, "expect": Refusal.TARGET_STATUS},
		{"name": "needs one, holds one", "held": [[SHADOW_ID, 3]], "element": shadow, "needs": 1, "expect": Refusal.NONE},
		{"name": "an expired buff does not count", "held": [[SHADOW_ID, 0]], "element": shadow, "needs": 1, "expect": Refusal.TARGET_STATUS},
		{"name": "another element does not count", "held": [[ICE_ID, 3]], "element": shadow, "needs": 1, "expect": Refusal.TARGET_STATUS},
		{"name": "an unknown buff does not count", "held": [[UNKNOWN_ID, 3]], "element": shadow, "needs": 1, "expect": Refusal.TARGET_STATUS},
		{"name": "one short of three", "held": [[ICE_ID, 3], [ICE_ID, 1], [SHADOW_ID, 2]], "element": ice, "needs": 3, "expect": Refusal.TARGET_STATUS},
		{"name": "exactly three", "held": [[ICE_ID, 3], [ICE_ID, 1], [ICE_ID, 2]], "element": ice, "needs": 3, "expect": Refusal.NONE},
	]:
		var target := _enemy()
		for held in row["held"]:
			_hold_buff(target, held[0], held[1])
		var move := _move()
		move.required_buff_element = row["element"]
		move.required_buff_count = row["needs"]
		assert_eq(MoveLegality.refusal(_caster(), move, 0, target, buffs_by_id), row["expect"], row["name"])


func test_required_target_buff_gate_reads_the_target_and_not_the_caster():
	var caster := _caster()
	_hold_buff(caster, 1, 3)
	var move := _move()
	move.required_buff_element = CombatUnit.Element.ICE
	move.required_buff_count = 1
	var buffs_by_id: Dictionary = {1: _buff(1, CombatUnit.Element.ICE)}
	assert_eq(MoveLegality.refusal(caster, move, 0, _enemy(), buffs_by_id), Refusal.TARGET_STATUS)


func test_target_relation_gate():
	var caster := _caster()
	var ally := _unit(CombatUnit.Team.ONE)
	var enemy := _enemy()
	for row in [
		{"name": "self, self-targeting move", "target": caster, "flag": "can_target_self", "expect": Refusal.NONE},
		{"name": "self, ally-targeting move", "target": caster, "flag": "targets_allies", "expect": Refusal.BAD_TARGET},
		{"name": "self, enemy-targeting move", "target": caster, "flag": "can_target_others", "expect": Refusal.BAD_TARGET},
		{"name": "ally, self-targeting move", "target": ally, "flag": "can_target_self", "expect": Refusal.BAD_TARGET},
		{"name": "ally, ally-targeting move", "target": ally, "flag": "targets_allies", "expect": Refusal.NONE},
		{"name": "ally, enemy-targeting move", "target": ally, "flag": "can_target_others", "expect": Refusal.BAD_TARGET},
		{"name": "enemy, self-targeting move", "target": enemy, "flag": "can_target_self", "expect": Refusal.BAD_TARGET},
		{"name": "enemy, ally-targeting move", "target": enemy, "flag": "targets_allies", "expect": Refusal.BAD_TARGET},
		{"name": "enemy, enemy-targeting move", "target": enemy, "flag": "can_target_others", "expect": Refusal.NONE},
	]:
		var move := Ability.new()
		move.set(row["flag"], true)
		assert_eq(MoveLegality.refusal(caster, move, 0, row["target"], {}), row["expect"], row["name"])


func test_a_missing_or_dead_target_is_a_bad_target():
	assert_eq(MoveLegality.refusal(_caster(), _move(), 0, null, {}), Refusal.BAD_TARGET, "missing")
	var dead := _enemy()
	dead.active = false
	assert_eq(MoveLegality.refusal(_caster(), _move(), 0, dead, {}), Refusal.BAD_TARGET, "dead")


# When several checks fail, the original shows the message of the last one it
# ran. This starts with all six failing and fixes them from last to first, so
# each assert sees the next reason come through.
func test_the_last_check_the_original_runs_names_the_refusal():
	var caster := _caster()
	caster.life_n = 80.0
	caster.ability_cooldowns[0] = 2
	caster.silenced = 1.0
	caster.focus_n = 5.0
	var move := _move()
	move.can_target_others = false
	move.health_cost_percentage = 0.08
	move.focus_cost = 10.0
	move.required_buff_count = 1
	var target := _enemy()

	assert_eq(MoveLegality.refusal(caster, move, 0, target, {}), Refusal.BAD_TARGET)
	move.can_target_others = true
	assert_eq(MoveLegality.refusal(caster, move, 0, target, {}), Refusal.LIFE)
	caster.life_n = 1000.0
	assert_eq(MoveLegality.refusal(caster, move, 0, target, {}), Refusal.COOLDOWN)
	caster.ability_cooldowns[0] = 0
	assert_eq(MoveLegality.refusal(caster, move, 0, target, {}), Refusal.SILENCED)
	caster.silenced = 0.0
	assert_eq(MoveLegality.refusal(caster, move, 0, target, {}), Refusal.FOCUS)
	caster.focus_n = 10.0
	assert_eq(MoveLegality.refusal(caster, move, 0, target, {}), Refusal.TARGET_STATUS)
	move.required_buff_count = 0
	assert_eq(MoveLegality.refusal(caster, move, 0, target, {}), Refusal.NONE)


func test_can_afford_covers_silence_focus_and_life():
	for row in [
		{"name": "nothing wrong", "silenced": 0.0, "focus": 10.0, "life": 81.0, "expect": true},
		{"name": "silenced", "silenced": 1.0, "focus": 10.0, "life": 81.0, "expect": false},
		{"name": "one focus short", "silenced": 0.0, "focus": 9.0, "life": 81.0, "expect": false},
		{"name": "life equal to the cost", "silenced": 0.0, "focus": 10.0, "life": 80.0, "expect": false},
	]:
		var caster := _caster()
		caster.silenced = row["silenced"]
		caster.focus_n = row["focus"]
		caster.life_n = row["life"]
		var move := _move()
		move.focus_cost = 10.0
		move.health_cost_percentage = 0.08
		assert_eq(MoveLegality.can_afford(caster, move), row["expect"], row["name"])


func test_the_ai_will_not_pick_a_move_it_cannot_afford_from_any_pool():
	const MOVE_ID: int = 7
	var move := _move()
	move.id = MOVE_ID
	move.focus_cost = 10.0
	var moves_by_id: Dictionary = {MOVE_ID: move}
	for pool in ["attack", "defense", "absolute"]:
		var caster := _caster()
		match pool:
			"attack":
				caster.move_pool_attack = [MOVE_ID]
				caster.cooldowns_attack = [0]
			"defense":
				caster.move_pool_defense = [MOVE_ID]
				caster.cooldowns_defense = [0]
			"absolute":
				caster.move_pool_absolute = [{"id": MOVE_ID, "phase": 0}]
				caster.cooldowns_absolute = [0]
		var units: Dictionary = {1: caster, 2: _enemy()}
		assert_eq(BattleAI.choose_move(1, units, 1, {}, moves_by_id).get("move_id"), MOVE_ID, "%s pool, affordable" % pool)
		caster.silenced = 1.0
		assert_eq(BattleAI.choose_move(1, units, 1, {}, moves_by_id), {}, "%s pool, silenced" % pool)


# Corruption needs one Shadow buff on its target
# (frame_42/DoAction_6.as:1613-1614). It is a Psychological starting move, so a
# new Psychological player could otherwise open every battle with it.
func test_corruption_needs_a_shadow_buff_on_its_target():
	var corruption: Ability = MoveManagerAuto.get_move(479)
	var shadow: Buff = BuffManagerAuto.get_buff_by_name("SHADOWINFUSION")
	assert_eq(shadow.element_type, CombatUnit.Element.SHADOW)
	var buffs_by_id: Dictionary = BuffManagerAuto.buffs_by_id
	var target := _enemy()

	assert_eq(MoveLegality.refusal(_caster(), corruption, 1, target, buffs_by_id), Refusal.TARGET_STATUS, "no Shadow buff")
	_hold_buff(target, shadow.id, 1)
	assert_eq(MoveLegality.refusal(_caster(), corruption, 1, target, buffs_by_id), Refusal.NONE, "one active Shadow buff")
	target.buff_slots[0]["cd"] = 0
	assert_eq(MoveLegality.refusal(_caster(), corruption, 1, target, buffs_by_id), Refusal.TARGET_STATUS, "an expired Shadow buff")


# Shatter needs three Ice buffs on its target (frame_42/DoAction_6.as:852-892).
func test_shatter_needs_three_ice_buffs_on_its_target():
	var shatter: Ability = MoveManagerAuto.get_move(224)
	var ice: Buff = BuffManagerAuto.get_buff_by_name("FRAGILE")
	var shadow: Buff = BuffManagerAuto.get_buff_by_name("SHADOWINFUSION")
	assert_eq(ice.element_type, CombatUnit.Element.ICE)
	var buffs_by_id: Dictionary = BuffManagerAuto.buffs_by_id
	var target := _enemy()

	_hold_buff(target, ice.id, 1)
	_hold_buff(target, ice.id, 1)
	_hold_buff(target, shadow.id, 1)
	assert_eq(MoveLegality.refusal(_caster(), shatter, 0, target, buffs_by_id), Refusal.TARGET_STATUS, "two Ice and a Shadow")
	_hold_buff(target, ice.id, 1)
	assert_eq(MoveLegality.refusal(_caster(), shatter, 0, target, buffs_by_id), Refusal.NONE, "the third Ice buff")


# Bloodshed costs 8% of total life (frame_42/DoAction_6.as:1029).
func test_bloodshed_needs_more_life_than_its_cost():
	var bloodshed: Ability = MoveManagerAuto.get_move(257)
	assert_eq(bloodshed.health_cost_percentage, 0.08)
	var caster := _caster()

	caster.life_n = round(caster.life_u * 0.08)
	assert_eq(MoveLegality.refusal(caster, bloodshed, 0, _enemy(), {}), Refusal.LIFE, "life equal to the cost")
	caster.life_n += 1
	assert_eq(MoveLegality.refusal(caster, bloodshed, 0, _enemy(), {}), Refusal.NONE, "one point above the cost")
