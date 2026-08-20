# battle_runner.gd
# The battle turn-loop orchestrator - the headless port of the AS3 per-frame
# conductor (frame217_KRIN_BATTLE_SCENE/onClipEvent_enterFrame.txt) plus its
# helpers TeamSelect/TeamSpeedAdder (frame217/2_dressing_chars.txt),
# krinAddMove (sonny2_moves.txt) and LowerCD (frame42/sonny2_ai_move_adder.txt).
#
# Slot layout (playerKrin1..6): odd slots = team 1, even slots = team 2.
# Slot 1 is the human player in single-player; slots 3/5 are allies, 2/4/6
# enemies. Empty slots simply have no entry in `units`.
#
# Flow per round: the team with the higher average derived speed acts first
# (re-evaluated every full round). A half-turn = one team's (up to) 3 units
# acting in speed order. advance_half_turn() runs one half-turn: it collects
# moves (AI units choose via BattleAI; the human's move comes in as
# player_action), executes them, ticks buffs, then does the end-of-half-turn
# bookkeeping (boss phases, win/lose, speeches, team rotation).
#
# The original ran real-time with a 120-second decision countdown
# (BattleTime/BattleTimeLimit, frame217/1_loading_battle_properties.txt); this
# port is the turn-based flow (difficulty 0/1 - turnBasedKrin). The countdown
# is a UI-layer concern (BATTLE_TIME_LIMIT is exposed for it).
#
# No autoload references (same rule as CombatUnit/BattleAI) - every lookup is
# injected via setup().
class_name BattleRunner
extends RefCounted

enum Outcome { LOSS = 0, WIN = 1, DRAW = 2, ONGOING = -1 }

# Every _log()'d entry's own "type" key - what battle_scene.gd's
# _play_events() matches on to decide how to present a half-turn's worth of
# events. A typo previously failed silently (a plain match on a bare string
# with no `_:` default just does nothing for an unrecognized case).
enum EventType {
	MOVE, STUNNED, MOVE_FAILED, DISPEL, DEATH, SPEECH, PHASE_ADVANCED, BATTLE_ENDED,
}

# A DEATH event's own "cause" key - MOVE plays at the killing blow's impact
# (see battle_scene.gd's _show_move_result), DAMAGE_OVER_TIME (a buff tick,
# not a move) has no impact moment to hook into so it plays from the queued
# event instead, same as always.
enum DeathCause { MOVE, DAMAGE_OVER_TIME }

const BATTLE_TIME_LIMIT: float = 120.0
const PLAYER_SLOT: int = 1
const TEAM_SLOTS: Dictionary[CombatUnit.Team, Array] = {
	CombatUnit.Team.ONE: [1, 3, 5], CombatUnit.Team.TWO: [2, 4, 6],
}

var units: Dictionary = {}  # slot (1..6) -> CombatUnit
var battle: BattleFight = null
var moves_by_id: Dictionary = {}
var buffs_by_id: Dictionary = {}
var buffs_by_name: Dictionary = {}
var battle_manager: BattleManager = null

var phase: int = 1
var turn_count: int = 0  # turnTimeKKK - half-turns elapsed
var turns_in_phase: int = 0  # turnTimeKKK2 - half-turns since the last phase change
var win_condition: int = Outcome.ONGOING
var team_move: int = 1  # team that won this round's speed check
var team_move_now: int = 1  # team acting this half-turn
var turn_time: int = 2  # half-turns left before the next speed re-evaluation
var absolute_start: int = 0
var healed_this_turn: Dictionary = {}
var speech_cursor: int = 0  # speechOn
var events: Array = []  # full battle log; advance_half_turn() also returns its slice


# Returns any events generated during setup itself (currently just a
# turnTime:0 speech, if the battle has one) - the caller must play these the
# same way it plays advance_half_turn()'s return value. advance_half_turn()
# only ever returns events.slice(events_start) measured from that specific
# call's own starting point, so anything _drain_speeches() appends here,
# before the first such call exists, would otherwise sit in events ahead of
# every future call's slice window and never reach whoever's actually
# consuming play-by-play events (battle_scene.gd doesn't read runner.events
# directly - only test code that inspects the full log after the fact does).
func setup(units_by_slot: Dictionary, battle_fight: BattleFight, moves: Dictionary, buffs_id: Dictionary, buffs_name: Dictionary, manager: BattleManager, player_passive_buff_names: Array = []) -> Array:
	var events_start: int = events.size()
	units = units_by_slot
	battle = battle_fight
	moves_by_id = moves
	buffs_by_id = buffs_id
	buffs_by_name = buffs_name
	battle_manager = manager
	absolute_start = battle.absolute_start if battle else 0

	for slot in units:
		var unit: CombatUnit = units[slot]
		unit.player_id = slot
		unit.team_side = 1 if slot % 2 == 1 else 2

	# updateStat_Player's buffAdderMatrix -> passiveBuffs hookup: the player's
	# learned passive talents applied as self-cast buffs at battle load.
	var player: CombatUnit = units.get(PLAYER_SLOT)
	if player:
		for buff_name in player_passive_buff_names:
			var buff: Buff = buffs_name.get(buff_name)
			if buff == null:
				push_warning("setup: unknown passive buff '%s'" % buff_name)
				continue
			player.apply_buff(buff, 1, player)
		player.apply_changes()

	_team_select()
	_drain_speeches()
	return events.slice(events_start)


func is_over() -> bool:
	return win_condition != Outcome.ONGOING


# True when it's the human player's team's half-turn and their unit can act -
# the caller should collect input and pass it to advance_half_turn().
func is_player_turn() -> bool:
	if is_over():
		return false
	var player: CombatUnit = units.get(PLAYER_SLOT)
	if player == null or not player.active or player.ai_enabled:
		return false
	return player.team_side == team_move_now


# Bar entries the player can currently pick: [{bar_index, move_id}]. Applies
# the same silence rule the AI uses (focus-costing moves blocked while
# silenced) - the original gated this in unextracted UI code.
func get_player_usable_moves() -> Array:
	var player: CombatUnit = units.get(PLAYER_SLOT)
	if player == null:
		return []
	var usable: Array[Variant] = []
	for bar_index in player.equipped_moves.size():
		var move_id: int = int(player.equipped_moves[bar_index])
		if move_id == 0:
			continue
		if bar_index < player.ability_cooldowns.size() and player.ability_cooldowns[bar_index] > 0:
			continue
		var move: Ability = moves_by_id.get(move_id)
		if move != null and player.silenced != 0 and move.focus_cost > 0:
			continue
		usable.append({"bar_index": bar_index, "move_id": move_id})
	return usable


# Runs one half-turn. player_action ({target_slot, move_id, bar_index}) is
# consumed only when is_player_turn(); pass {} to make the player pass.
# Returns the events generated by this half-turn.
func advance_half_turn(player_action: Dictionary = {}) -> Array:
	if is_over():
		return []
	var events_start: int = events.size()

	for slot in TEAM_SLOTS[CombatUnit.Team.ONE] + TEAM_SLOTS[CombatUnit.Team.TWO]:
		healed_this_turn[slot] = 0.0

	var queue: Array[Variant] = []
	for slot in _team_slots_in_order(team_move_now):
		var unit: CombatUnit = units.get(slot)
		if unit == null:
			continue
		var action: Dictionary[Variant, Variant] = {"caster_slot": slot, "target_slot": slot, "move_id": 0}
		if unit.active:
			if unit.ai_enabled:
				_lower_pool_cooldowns(unit)
				var choice: Dictionary = BattleAI.choose_move(slot, units, phase, healed_this_turn, moves_by_id)
				if not choice.is_empty():
					action = {
						"caster_slot": slot,
						"target_slot": choice["target_slot"],
						"move_id": choice["move_id"],
						"pool": choice["pool"],
						"pool_index": choice["pool_index"],
					}
			elif slot == PLAYER_SLOT and not player_action.is_empty():
				action = {
					"caster_slot": slot,
					"target_slot": int(player_action.get("target_slot", slot)),
					"move_id": int(player_action.get("move_id", 0)),
					"bar_index": int(player_action.get("bar_index", -1)),
				}
		queue.append(action)

	for action in queue:
		_execute_action(action)

	_end_half_turn()
	return events.slice(events_start)


func _team_slots_in_order(team: CombatUnit.Team) -> Array:
	var slots: Array = TEAM_SLOTS[team].duplicate()
	# TeamSpeedAdder: speed descending, slot id descending on ties.
	slots.sort_custom(func(a, b):
		var unit_a: CombatUnit = units.get(a)
		var unit_b: CombatUnit = units.get(b)
		var speed_a: float = unit_a.speed_u if unit_a else -1.0
		var speed_b: float = unit_b.speed_u if unit_b else -1.0
		if speed_a == speed_b:
			return a > b
		return speed_a > speed_b)
	return slots


func _lower_pool_cooldowns(unit: CombatUnit) -> void:
	for cooldowns in [unit.cooldowns_attack, unit.cooldowns_defense, unit.cooldowns_absolute]:
		for i in cooldowns.size():
			if cooldowns[i] > 0:
				cooldowns[i] -= 1


func _execute_action(action: Dictionary) -> void:
	var caster: CombatUnit = units.get(action["caster_slot"])
	if caster == null:
		return
	var should_tick_buffs: bool = caster.active  # usedBuff - dead units don't tick

	# The player's bar cooldowns tick down when their own action dispatches.
	if not caster.ai_enabled and action["caster_slot"] == PLAYER_SLOT:
		for i in caster.ability_cooldowns.size():
			if caster.ability_cooldowns[i] > 0:
				caster.ability_cooldowns[i] -= 1

	var move_id: int = int(action["move_id"])
	var target: CombatUnit = units.get(action.get("target_slot", 0))
	if move_id != 0 and caster.active:
		if caster.stun != 0:
			_log({"type": EventType.STUNNED, "caster_slot": action["caster_slot"]})
		elif target != null and target.active:
			_execute_move_action(action, caster, target)
		# Target already dead and caster not stunned: the move silently
		# fizzles with no cost, matching the original's dispatch condition.

	if should_tick_buffs and caster.active:
		caster.tick_buffs(buffs_by_id)
		if not caster.active:
			_log({"type": EventType.DEATH, "slot": action["caster_slot"], "cause": DeathCause.DAMAGE_OVER_TIME})


func _execute_move_action(action: Dictionary, caster: CombatUnit, target: CombatUnit) -> void:
	var move: Ability = moves_by_id.get(int(action["move_id"]))
	if move == null:
		push_warning("advance_half_turn: unknown move id %d" % action["move_id"])
		return

	var life_cost = move.flat_life_cost + round(caster.life_u * move.health_cost_percentage)
	if caster.focus_n < move.focus_cost or caster.life_n <= life_cost:
		var reason: String = "focus" if caster.focus_n < move.focus_cost else "health"
		_log({"type": EventType.MOVE_FAILED, "caster_slot": caster.player_id, "move_id": move.id, "reason": reason})
		return

	caster.focus_n -= move.focus_cost
	caster.life_n -= life_cost

	# Cooldown starts when the move actually fires.
	if caster.ai_enabled and action.has("pool"):
		var cooldowns: Array = []
		match action["pool"]:
			CombatUnit.MovePool.ATTACK:
				cooldowns = caster.cooldowns_attack
			CombatUnit.MovePool.DEFENSE:
				cooldowns = caster.cooldowns_defense
			CombatUnit.MovePool.ABSOLUTE:
				cooldowns = caster.cooldowns_absolute
		if action["pool_index"] >= 0 and action["pool_index"] < cooldowns.size():
			cooldowns[action["pool_index"]] = move.cooldown_turns
	elif action.get("bar_index", -1) >= 0 and action["bar_index"] < caster.ability_cooldowns.size():
		caster.ability_cooldowns[action["bar_index"]] = move.cooldown_turns

	if not _accuracy_roll(caster, target, move):
		# A miss is still a "move" event, not its own separate one - the
		# original always plays the caster's run/swing/cast animation for
		# the move's own type (dispatched on addNewMove param 10, gated by
		# nothing else - see DECODED_ALGORITHMS.md's "Battle presentation
		# per animation type") and only the impact-time damage NUMBER swaps
		# to a special miss frame. Logging a bare "miss" type here instead
		# skipped straight to a floating MISS label with no animation at all.
		_log_move_result(caster, target, move, {"type": BattleManager.ResultType.MISS})
		return

	var dispelled: Array = _resolve_dispels(move, target)
	if not dispelled.is_empty():
		_log({"type": EventType.DISPEL, "caster_slot": caster.player_id, "target_slot": target.player_id, "removed": dispelled})

	if move.hits_all_enemies:
		for slot in TEAM_SLOTS[CombatUnit.Team.TWO if caster.team_side == CombatUnit.Team.ONE else CombatUnit.Team.ONE]:
			var enemy: CombatUnit = units.get(slot)
			if enemy != null and enemy.active:
				var result: Dictionary = battle_manager.execute_move(move, caster, enemy, buffs_by_name)
				enemy.apply_changes()
				_log_move_result(caster, enemy, move, result)
	else:
		var result: Dictionary = battle_manager.execute_move(move, caster, target, buffs_by_name)
		target.apply_changes()
		_log_move_result(caster, target, move, result)


# The hit/miss roll, separate from the crit roll inside execute_move().
# "Shock"-type moves and attacks against stunned targets always hit.
func _accuracy_roll(caster: CombatUnit, target: CombatUnit, move: Ability) -> bool:
	if move.attack_animation_type == "Shock" or target.stun != 0:
		return true
	var miss_chance: float
	var denominator: float = caster.speed_u * move.combat_speed_modifier
	if denominator <= 0:
		miss_chance = 75.0
	else:
		var speed_ratio: float = target.speed_u / denominator
		miss_chance = speed_ratio * (speed_ratio * 3.0 + 3.0)
		if miss_chance > 75.0:
			miss_chance = 75.0
		if miss_chance < 1.0:
			miss_chance = 0.0
	return randi_range(0, 99) > miss_chance


# Ported from the dispel block that runs on a successful strike, before the
# damage/heal resolves. The dispel budget is consumed by every
# polarity-matched candidate, even when the chance/resist rolls fail.
func _resolve_dispels(move: Ability, target: CombatUnit) -> Array:
	if move.dispel_count <= 0:
		return []
	var remaining: int = move.dispel_count
	var removed: Array[Variant] = []
	for slot_index in target.buff_slots.size():
		var slot = target.buff_slots[slot_index]
		if slot["cd"] <= 0:
			continue
		var buff: Buff = buffs_by_id.get(slot["buff_id"])
		if buff == null or not move.dispel_element_types.has(buff.element_type):
			continue
		if remaining <= 0:
			continue
		if move.dispel_target_polarity != buff.polarity:
			continue
		remaining -= 1
		if randf() <= move.dispel_chance and randf() >= buff.dispel_resist_chance:
			slot["cd"] = 0
			target.apply_buff(buff, -1, null, slot_index, slot["buff_value"])
			removed.append(buff.internal_name)
	if not removed.is_empty():
		target.apply_changes()
	return removed


func _end_half_turn() -> void:
	turn_count += 1
	turns_in_phase += 1

	_check_phase_advance()

	if battle and battle.win_date >= 0 and battle.win_date == turn_count:
		win_condition = battle.win_date_condition

	_check_win_lose()
	if is_over():
		_log({"type": EventType.BATTLE_ENDED, "outcome": win_condition, "turns": turn_count})
		return

	turn_time -= 1
	if turn_time == 0:
		_team_select()
	else:
		team_move_now = CombatUnit.Team.TWO if team_move_now == CombatUnit.Team.ONE else CombatUnit.Team.ONE

	_drain_speeches()
	if is_over():
		_log({"type": EventType.BATTLE_ENDED, "outcome": win_condition, "turns": turn_count})


func _check_phase_advance() -> void:
	var entry: Dictionary = _phase_entry(phase)
	if entry.is_empty():
		return
	var watched: CombatUnit = units.get(int(entry.get("player", 0)))
	if watched == null:
		return
	var advance: bool = false
	if watched.life_n / watched.life_u <= float(entry.get("life", 0.0)):
		advance = true
	elif int(entry.get("teamLeft", 0)) > 0 and _team_active_count(watched.team_side) <= int(entry.get("teamLeft", 0)):
		advance = true
	elif int(entry.get("turn", 0)) > 0 and int(entry.get("turn", 0)) <= turns_in_phase:
		advance = true
	if advance:
		phase += 1
		turns_in_phase = 0
		_log({"type": EventType.PHASE_ADVANCED, "phase": phase})


# battle.phases keys are String indices; entry "0" is the "EMPTY" placeholder.
# Tolerates both the cleaned shape (plain Dictionary) and the pre-2026-07-18
# converted shape ({"type": "Object", "members": {...}}) still present in
# older generated .tres files.
func _phase_entry(index: int) -> Dictionary:
	if battle == null or battle.phases.is_empty():
		return {}
	var entry = battle.phases.get(str(index))
	if entry is Dictionary:
		if entry.has("members") and entry["members"] is Dictionary:
			return entry["members"]
		return entry
	return {}


func _team_active_count(team: CombatUnit.Team) -> int:
	var count: int = 0
	for slot in TEAM_SLOTS[team]:
		var unit: CombatUnit = units.get(slot)
		if unit != null and unit.active:
			count += 1
	return count


func _check_win_lose() -> void:
	var win_count: int = 0
	var lose_count: int = 0
	var player: CombatUnit = units.get(PLAYER_SLOT)
	var player_team: CombatUnit.Team = player.team_side as CombatUnit.Team if player else CombatUnit.Team.ONE

	# Tutorial-battle special case: losing your own unit in KBR2 is an
	# immediate loss even though allies remain.
	if (player == null or not player.active) and battle and battle.id == 2:
		lose_count += 1

	if _team_active_count(CombatUnit.Team.ONE) == 0:
		if player_team == CombatUnit.Team.ONE:
			lose_count += 1
		else:
			win_count += 1
	if _team_active_count(CombatUnit.Team.TWO) == 0:
		if player_team == CombatUnit.Team.TWO:
			lose_count += 1
		else:
			win_count += 1

	if win_condition == Outcome.ONGOING:
		if win_count > 0:
			win_condition = Outcome.WIN
		if lose_count > 0:
			win_condition = Outcome.LOSS
		if win_count > 0 and lose_count > 0:
			win_condition = Outcome.DRAW


# TeamSelect(): the faster team (average derived speed of living units) opens
# the round; ties go to team 1 in single player. absolute_start (from the
# battle definition) force-picks the opener - once, unless time_lock holds it.
func _team_select() -> void:
	var averages: Dictionary[CombatUnit.Team, float] = {CombatUnit.Team.ONE: 0.0, CombatUnit.Team.TWO: 0.0}
	for team in [CombatUnit.Team.ONE, CombatUnit.Team.TWO]:
		var total: float = 0.0
		var count: int = 0
		for slot in TEAM_SLOTS[team]:
			var unit: CombatUnit = units.get(slot)
			if unit != null and unit.active:
				total += unit.speed_u
				count += 1
		averages[team] = total / count if count > 0 else 0.0

	if absolute_start != 0:
		averages[absolute_start] = INF
		if battle == null or not battle.time_lock:
			absolute_start = 0

	if averages[CombatUnit.Team.ONE] >= averages[CombatUnit.Team.TWO]:
		team_move = CombatUnit.Team.ONE
	else:
		team_move = CombatUnit.Team.TWO
	turn_time = 2
	team_move_now = team_move

	for team in [CombatUnit.Team.ONE, CombatUnit.Team.TWO]:
		var ordered: Array = _team_slots_in_order(team)
		for rank in ordered.size():
			var unit: CombatUnit = units.get(ordered[rank])
			if unit != null:
				unit.team_adder = rank


# Scripted dialogue: emit every speech matching the current phase/timing, in
# turnTime2 sequence, skipping dead speakers. Narrator lines (player 0) always
# show. After a drain that emitted nothing new, an endGame-flagged phase entry
# that was just passed ends the battle (winOrLose).
func _drain_speeches() -> void:
	if battle == null or battle.speeches.is_empty():
		return
	var sequence: int = 0
	var emitted: int = 0
	while speech_cursor < battle.speeches.size():
		var speech: Dictionary = battle.speeches[speech_cursor]
		if int(speech.get("phase", 0)) != phase:
			break
		if int(speech.get("turnTime", 0)) != turns_in_phase:
			break
		if int(speech.get("turnTime2", 0)) != sequence:
			break
		var speaker_slot: int = _speech_speaker_slot(speech.get("player", 0))
		speech_cursor += 1
		if speaker_slot == 0 or (units.get(speaker_slot) != null and units[speaker_slot].active):
			sequence += 1
			emitted += 1
			_log({
				"type": EventType.SPEECH,
				"speaker_slot": speaker_slot,
				"say": speech.get("say", ""),
				"time_to_say": speech.get("timeToSay", 0.0),
				"voice_over": speech.get("voiceOver", ""),
			})
	if emitted == 0:
		var passed_entry: Dictionary = _phase_entry(phase - 1)
		if not passed_entry.is_empty() and passed_entry.get("endGame", false):
			win_condition = int(passed_entry.get("winOrLose", Outcome.WIN))


# getPNum(): numeric speaker < 7 is a slot number (0 = narrator); otherwise
# it's a unit name matched against the living roster.
func _speech_speaker_slot(speaker) -> int:
	if speaker is float or speaker is int:
		var slot: int = int(speaker)
		return slot if slot < 7 else 0
	for slot in units:
		var unit: CombatUnit = units[slot]
		if unit != null and unit.player_name == str(speaker):
			return slot
	return 0


func _log_move_result(caster: CombatUnit, target: CombatUnit, move: Ability, result: Dictionary) -> void:
	var entry: Dictionary[Variant, Variant] = {
		"type": EventType.MOVE,
		"caster_slot": caster.player_id,
		"target_slot": target.player_id,
		"move_id": move.id,
		"move_name": move.display_name,
		"result": result,
	}
	_log(entry)
	if result.get("target_died", false):
		_log({"type": EventType.DEATH, "slot": target.player_id, "cause": DeathCause.MOVE})


func _log(entry: Dictionary) -> void:
	entry["turn"] = turn_count
	entry["acting_team"] = team_move_now
	events.append(entry)
