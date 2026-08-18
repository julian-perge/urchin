# combat_unit.gd
# Runtime battle participant, built from a static Character resource plus a
# level and difficulty. Ported from the AS3 stat-init path in
# frame42/sonny2_createNewBattle.txt (krinAddNewUnit), the level-scaling curve
# in frame42/sonny2_extra_stat_calcs.txt (getStat), and the buff system in
# frame42/sonny2_addNewBuffKrin.txt (applyBuffKrin/buffTicker/applyChangesKrin).
# Character.vitality/strength/magic/speed are NOT final stats - they are ratio
# coefficients fed into getStat() to produce the base stats below.
class_name CombatUnit
extends RefCounted

enum Difficulty { EASY, NORMAL, HARD }

# Matches BattleRunner.TEAM_SLOTS' keys and CombatUnit.team_side's own values
# (odd slots 1/3/5 = ONE, even slots 2/4/6 = TWO) - deliberately not
# zero-based so team_side's un-assigned-yet default of 0 stays a visibly
# invalid sentinel rather than aliasing a real team.
enum Team { ONE = 1, TWO = 2 }

# modVar_1 (strength/magic), modVar_2 (life), modVar_3 (speed), per difficulty.
const DIFFICULTY_MODIFIERS: Dictionary[Difficulty, Dictionary] = {
	Difficulty.EASY: {"strength_magic": 0.4, "life": 0.5, "speed": 0.9000000000000002},
	Difficulty.NORMAL: {"strength_magic": 0.8, "life": 0.85, "speed": 1.0},
	Difficulty.HARD: {"strength_magic": 1.0, "life": 1.0, "speed": 1.0},
}

const VIT_LIFE_FACTOR: int = 33
const ELEMENT_ORDER: Array[String] = ["Physical", "Magic", "Ice", "Fire", "Lightning", "Earth", "Shadow", "Poison"]
const MAX_BUFF_LIMIT: int = 40  # _root.maxBuffLimit

var player_id: int
var player_name: String
var plevel: int
var active: bool = true

# Battle-slot layout (playerKrin1..6): odd slots = team 1, even = team 2.
# Slot 1 is the human player. Set by BattleRunner at setup.
var team_side: int = 0
var team_adder: int = 0  # within-team act order (0 = fastest), from TeamSpeedAdder()

# AI (AImoveAdder) state. The 5 tuning scalars come from the unit template's
# agressionArray (see scripts/editor/units.gd for the position decode).
var ai_enabled: bool = false  # AION
var aggression: float = 50.0
var life_boundary_1: float = 80.0
var life_boundary_2: float = 20.0
var focus_aggression: float = 50.0
var focus_regen_limit: float = 15.0
# AI move pools + parallel per-move cooldown counters (CDArrayA/D/ABS).
# Absolute entries are {id, phase} - phase 0 = usable in any battle phase.
var move_pool_attack: Array = []
var move_pool_defense: Array = []
var move_pool_absolute: Array = []
var cooldowns_attack: Array = []
var cooldowns_defense: Array = []
var cooldowns_absolute: Array = []

# Player-controlled units: the 8-slot action bar (PlayerSave.move_matrix) and
# its parallel cooldown counters (abilityCoolDown).
var equipped_moves: Array = []
var ability_cooldowns: Array = []

# Base stats (pre-buff), set once at creation and never changed thereafter -
# changeArray deltas are what apply_changes() folds on top of these.
var base_strength: float
var base_magic: float
var base_speed: float
var base_life: float
var base_focus: float
var base_per: Dictionary = {}
var base_def: Dictionary = {}

# Derived (post-buff) stats - what execute_move() and everything else reads.
# Recomputed by apply_changes() any time a buff is applied/removed/ticks.
var strength_u: float
var magic_u: float
var speed_u: float
var life_u: float
var life_n: float
var focus_u: float
var focus_n: float
var per_u: Dictionary = {}
var def_u: Dictionary = {}

var dmg: float = 0.0
var dmg2: float = 0.0
var idmg: float = 0.0
var idmg2: float = 0.0
var idmgp: float = 0.0  # % damage reduction; idmgp2 (the actual multiplier) is derived as 1 - idmgp
var idmgp2: float = 1.0

var shield: float = 0.0
var shield_counter: float = 0.0
var sswitch: float = 0.0
var stun: float = 0.0
var reflect: float = 0.0
var silenced: float = 0.0
var heal_mod: float = 1.0
var heal_mod_plus: float = 1.0
var heal_mod_minus: float = 1.0
var idot: float = 1.0  # incoming DOT multiplier
var ihot: float = 1.0  # incoming HOT multiplier
var odot: float = 1.0  # outgoing DOT multiplier (read off the CASTER when a DOT buff is applied)
var focus_change: float = 0.0  # one-shot FOCUSU adjustment, consumed by apply_changes()

# changeArray[0..11]: STR flat/%, MAG flat/%, SPD flat/%, LIFE flat/%,
# DMG, DMG2, IDMG, IDMG2-or-IDMGP (see apply_buff).
var change_array: Array = []
# Per-element offense/defense deltas, only touched by buffs whose element_type matches.
var change_array_ep: Array = []
var change_array_ep2: Array = []
var change_array_ed: Array = []
var change_array_ed2: Array = []
# [0..7] per-element DOT accumulation, [8] HOT (heal) accumulation, [9] focus-per-turn total.
var dot_ticker_array: Array = []
# Active buff slots: {cd, buff_id, buff_value, shield_buff_value}.
var buff_slots: Array = []

var voice_hit: Array = []
var voice_die: String = ""

# Visual identity for the paper doll (CharacterVisual): the AS3 model array
# ["MODELx", skin, hair, gender], raw equipped item ids (resolved to "looks"
# keys by the battle scene via the item lookup), and skinSetter - a looks key
# that fills armor slots 0-4 wholesale for uniformed enemies (e.g. "ZPCI").
var model: Array = ["MODEL1", "ONE", "ONE", "M"]
var equipment_ids: Array = []
var skin_setter: String = ""

# getStat(), ported exactly from sonny2_extra_stat_calcs.txt. `mode` is a
# Variant on purpose - the AS3 checks `== true` / `== false` as distinct cases
# and leaves s_a unscaled when the caller passes neither (e.g. plain damage
# stat lookups vs. the point-allocation curve, which always passes a bool).
# GDScript has no Python-style `[value] * n` array repetition - `*` isn't
# defined on Array at all.
static func _zero_array(size: int) -> Array:
	var arr: Array[int] = []
	arr.resize(size)
	arr.fill(0.0)
	return arr

static func get_stat(ratio: float, level: int, mode = null) -> float:
	if level <= 0:
		return 0.0
	var s_a: float
	if level <= 5:
		s_a = (9.25 * level + 45.75) / 4.0 * (ratio / 10.0)
	else:
		s_a = (
			-0.0000213 * pow(level, 5)
			+ 0.002 * pow(level, 4)
			- 0.0693 * pow(level, 3)
			+ 1.43 * pow(level, 2)
			- 8.8533 * level
			+ 39.5
		) * (ratio / 10.0)
	var s_r: float
	if level < 20:
		s_r = -0.01929824 * level + 0.7159600000000003
	else:
		s_r = 0.33000000000000007
	if mode:
		s_a *= s_r / 2.0
	elif mode == false:
		s_a *= 1.0 - s_r
	return s_a

static func from_character(character: Character, level: int, difficulty: Difficulty, battle_slot: int) -> CombatUnit:
	var unit: CombatUnit = CombatUnit.new()
	unit.player_id = battle_slot
	unit.player_name = character.name
	unit.plevel = level

	var mods = DIFFICULTY_MODIFIERS[difficulty]
	unit.base_life = round(mods["life"] * get_stat(character.vitality, level) * VIT_LIFE_FACTOR)
	unit.base_strength = round(mods["strength_magic"] * get_stat(character.strength, level))
	unit.base_magic = round(mods["strength_magic"] * get_stat(character.magic, level))
	unit.base_speed = round(mods["speed"] * get_stat(character.speed, level))
	unit.base_focus = character.focus

	var piercing = character.stats.get("piercing", [])
	var defense = character.stats.get("defense", [])
	var level_scale: float = 1.0 + level * 0.15
	for i in ELEMENT_ORDER.size():
		var element = ELEMENT_ORDER[i]
		unit.base_per[element] = (piercing[i] if i < piercing.size() else 0.0) * level_scale
		unit.base_def[element] = (defense[i] if i < defense.size() else 0.0) * level_scale

	var voice = character.visuals.get("voice", {})
	unit.voice_hit = voice.get("hit", [])
	unit.voice_die = voice.get("die", "")
	var visual_model = character.visuals.get("model", [])
	if visual_model.size() >= 4:
		unit.model = visual_model.duplicate()
	unit.equipment_ids = character.visuals.get("equipment", []).duplicate()
	var skin: String = str(character.visuals.get("skin", "0"))
	unit.skin_setter = "" if skin == "0" else skin

	unit.ai_enabled = true
	var aggression_array = character.stats.get("aggression", [])
	if aggression_array.size() >= 5:
		unit.aggression = float(aggression_array[0])
		unit.life_boundary_1 = float(aggression_array[1])
		unit.life_boundary_2 = float(aggression_array[2])
		unit.focus_aggression = float(aggression_array[3])
		unit.focus_regen_limit = float(aggression_array[4])
	unit.move_pool_attack = character.moves.get("attack", []).duplicate()
	unit.move_pool_defense = character.moves.get("defense", []).duplicate()
	unit.move_pool_absolute = []
	for absolute_entry in character.moves.get("absolute", []):
		# Older generated .tres store absolute entries as bare move ids (the
		# phase lock was dropped); treat those as usable in any phase.
		if absolute_entry is Dictionary:
			unit.move_pool_absolute.append({"id": int(absolute_entry["id"]), "phase": int(absolute_entry["phase"])})
		else:
			unit.move_pool_absolute.append({"id": int(absolute_entry), "phase": 0})
	unit.cooldowns_attack = _zero_array(unit.move_pool_attack.size())
	unit.cooldowns_defense = _zero_array(unit.move_pool_defense.size())
	unit.cooldowns_absolute = _zero_array(unit.move_pool_absolute.size())

	unit.change_array = _zero_array(12)
	unit.change_array_ep = _zero_array(8)
	unit.change_array_ep2 = _zero_array(8)
	unit.change_array_ed = _zero_array(8)
	unit.change_array_ed2 = _zero_array(8)
	unit.dot_ticker_array = _zero_array(10)
	unit.buff_slots = []
	for i in MAX_BUFF_LIMIT:
		unit.buff_slots.append({"cd": 0, "buff_id": -1, "buff_value": 0.0, "shield_buff_value": 0.0})

	unit.life_u = unit.base_life
	unit.life_n = unit.base_life
	unit.focus_u = unit.base_focus
	unit.focus_n = unit.base_focus
	unit.apply_changes()
	return unit

# Build the human player's battle unit from their save - ported from
# updateStat_Player (frame201_LOAD_BATTLE_SCENE/sonny2_LOAD_BATTLE_SCENE.txt).
# Unlike enemies, the player's stats are absolute accumulated values, not
# getStat() ratio curves. Passive talent buffs (buff_adder_matrix ->
# passiveBuffs) are applied by BattleRunner at setup, since resolving buff
# names needs the buff lookup this class deliberately doesn't hold.
static func from_player_save(save: PlayerSave, battle_slot: int = 1) -> CombatUnit:
	var unit: CombatUnit = CombatUnit.new()
	unit.player_id = battle_slot
	unit.player_name = save.name_user
	unit.plevel = save.level

	unit.base_strength = save.strength
	unit.base_magic = save.magic
	unit.base_speed = save.speed
	unit.base_life = round(save.life * VIT_LIFE_FACTOR)
	unit.base_focus = save.focus

	# PER/DEF = allocated points + 100 + 15 per level (the same formula the
	# original uses for companions, arena players, and the stat screen).
	for element in ELEMENT_ORDER:
		unit.base_per[element] = save.per.get(element, 0.0) + 100.0 + 15.0 * save.level
		unit.base_def[element] = save.def.get(element, 0.0) + 100.0 + 15.0 * save.level

	unit.voice_hit = ["hit_sonny1", "hit_sonny2", "hit_sonny3"]
	unit.voice_die = "dead_sonny"
	# Sonny's default appearance (frame_42 seeds: skin ONE, hair ONE, male);
	# appearance customization isn't persisted yet.
	unit.model = ["MODEL1", "ONE", "ONE", "M"]
	unit.equipment_ids = save.equip_array.duplicate()

	unit.ai_enabled = false
	unit.equipped_moves = save.move_matrix.duplicate()
	unit.ability_cooldowns = _zero_array(8)

	unit.change_array = _zero_array(12)
	unit.change_array_ep = _zero_array(8)
	unit.change_array_ep2 = _zero_array(8)
	unit.change_array_ed = _zero_array(8)
	unit.change_array_ed2 = _zero_array(8)
	unit.dot_ticker_array = _zero_array(10)
	unit.buff_slots = []
	for i in MAX_BUFF_LIMIT:
		unit.buff_slots.append({"cd": 0, "buff_id": -1, "buff_value": 0.0, "shield_buff_value": 0.0})

	unit.life_u = unit.base_life
	unit.life_n = unit.base_life
	unit.focus_u = unit.base_focus
	unit.focus_n = unit.base_focus
	unit.apply_changes()
	return unit

# Ported from applyChangesKrin() - recomputes every derived (_u) stat from the
# base stats plus whatever the active buffs have accumulated into
# change_array/change_array_e*. Call after any apply_buff()/tick_buffs().
func apply_changes() -> void:
	var epy: Array = change_array
	strength_u = max(ceil((base_strength + epy[0]) * (1 + epy[1])), 0)
	magic_u = max(ceil((base_magic + epy[2]) * (1 + epy[3])), 0)
	speed_u = max(ceil((base_speed + epy[4]) * (1 + epy[5])), 0)

	if focus_change != 0:
		focus_u = base_focus + focus_change
		focus_n = focus_u
		focus_change = 0

	var life_adder = ceil((base_life + epy[6]) * (1 + epy[7]) - life_u)
	var was_alive: bool = life_n > 0
	var life_ratio: float = life_n / life_u
	life_u += life_adder
	if life_u < 1:
		life_u = 1
	if life_adder > 0:
		life_n += life_adder
	else:
		life_n = round(life_ratio * life_u)
	if life_n <= 0 and was_alive:
		life_n = 1
	if life_n > life_u:
		life_n = life_u

	dmg = epy[8]
	dmg2 = epy[9]
	idmg = epy[10]
	idmg2 = epy[11]
	idmgp2 = max(1 - idmgp, 0)

	for i in ELEMENT_ORDER.size():
		var element = ELEMENT_ORDER[i]
		per_u[element] = max((base_per[element] + change_array_ep[i]) * (change_array_ep2[i] + 1), 1)
		def_u[element] = max((base_def[element] + change_array_ed[i]) * (change_array_ed2[i] + 1), 1)

# Ported from applyBuffKrin(). `direction` is +1 to apply, -1 to remove (the AS3
# `iftbc`). `caster` is only read when direction == +1 (fresh application) - the
# original passes a bare `0` for it on auto-expire removal since every
# caster-scaled term is gated behind `if(iftbc==1)`, so `null` is fine there.
# `slot_index`/`stored_buff_value` are required when direction == -1, identifying
# which buff_slots entry is expiring and what magnitude it had (buffTicker
# tracks this per-slot, since a fresh apply_buff() calculates the value once
# and it doesn't get recalculated at removal time).
func apply_buff(buff: Buff, direction: int, caster: CombatUnit = null, slot_index: int = -1, stored_buff_value: float = 0.0) -> void:
	stun += direction * buff.stun_delta
	# stun is checked with `!= 0` everywhere (the AS3 did the same on an
	# int) - snap float residue so an expired stun can't wobble the doll or
	# eat turns forever.
	if absf(stun) < 0.001:
		stun = 0.0
	reflect += direction * buff.reflect_delta
	heal_mod_plus += direction * buff.heal_mod_plus_delta
	heal_mod_minus -= direction * buff.heal_mod_minus_delta
	heal_mod += direction * buff.heal_mod_delta
	idot += direction * buff.idot_delta
	ihot += direction * buff.ihot_delta
	odot += direction * buff.odot_delta
	focus_change += direction * buff.focus_change_delta
	silenced += direction * buff.silenced_delta

	var applied_slot: int = slot_index
	if direction == 1:
		applied_slot = -1
		for i in buff_slots.size():
			if applied_slot == -1 and buff_slots[i]["cd"] == 0:
				buff_slots[i]["cd"] = buff.duration_turns
				buff_slots[i]["buff_id"] = buff.id
				applied_slot = i
		if applied_slot == -1:
			push_warning("apply_buff: no free buff slot for '%s'" % buff.internal_name)
			return

	sswitch += direction * buff.sswitch_delta

	var deltas: Array[Variant] = [
		buff.change_strength_flat, buff.change_strength_percent,
		buff.change_magic_flat, buff.change_magic_percent,
		buff.change_speed_flat, buff.change_speed_percent,
		buff.change_life_flat, buff.change_life_percent,
		buff.outgoing_damage_flat, buff.outgoing_damage_percent,
		buff.incoming_damage_flat, buff.incoming_damage_percent_or_reduction,
	]
	for s in 12:
		if s == 11:
			if deltas[s] > 0:
				change_array[s] += direction * deltas[s]
			elif deltas[s] < 0:
				idmgp -= direction * deltas[s]
		else:
			change_array[s] += direction * deltas[s]

	var shield_amount: float
	if direction == 1:
		shield_amount = max(
			buff.shield_flat
			+ caster.strength_u * buff.shield_scale_caster_strength
			+ caster.magic_u * buff.shield_scale_caster_magic
			+ caster.speed_u * buff.shield_scale_caster_speed
			+ caster.life_u * buff.shield_scale_caster_life,
			0
		)
		buff_slots[applied_slot]["shield_buff_value"] = shield_amount
	else:
		shield_amount = buff_slots[applied_slot]["shield_buff_value"]

	if direction == 1:
		shield += shield_amount
	else:
		var shield_void: float = shield_counter - shield
		if shield_void < shield_amount:
			shield -= shield_amount - shield_void
	shield_counter += direction * shield_amount
	if shield_counter <= 0:
		shield_counter = 0
		shield = 0

	dot_ticker_array[9] += direction * buff.focus_per_turn

	for i in ELEMENT_ORDER.size():
		if ELEMENT_ORDER[i] != buff.element_type:
			continue
		change_array_ep[i] += direction * buff.change_element_piercing
		change_array_ep2[i] += direction * buff.change_element_piercing_percent
		change_array_ed[i] += direction * buff.change_element_defense
		change_array_ed2[i] += direction * buff.change_element_defense_percent

		var change_value: float
		if direction == 1:
			change_value = ceil(
				caster.odot * (
					buff.dot_hot_base_value
					+ buff.dot_scale_caster_strength * caster.strength_u
					+ buff.dot_scale_caster_magic * caster.magic_u
					+ buff.dot_scale_caster_speed * caster.speed_u
					+ buff.dot_scale_caster_life * caster.life_u
					+ buff.dot_scale_target_strength * strength_u
					+ buff.dot_scale_target_magic * magic_u
					+ buff.dot_scale_target_speed * speed_u
					+ buff.dot_scale_target_life * life_u
				)
			)
			buff_slots[applied_slot]["buff_value"] = change_value
		else:
			change_value = -stored_buff_value

		var signed_value: float = direction * change_value
		if signed_value < 0:
			dot_ticker_array[8] += change_value
		else:
			dot_ticker_array[i] += change_value

# Ported from buffTicker() - runs once per turn: resolves this turn's DOT/HOT,
# ticks buff durations down, auto-expires anything that hits 0, and refreshes
# every derived stat via apply_changes(). Visual-only side effects
# (color flash, filter tracking) are left out, same as execute_move().
#
# `buffs_by_id` (numeric id -> Buff, e.g. BuffManagerAuto.buffs_by_id) is taken
# as a parameter rather than referenced directly, on purpose: autoload
# singleton identifiers only resolve inside an actually-running game (Play) -
# referencing one directly from a plain RefCounted class like this one breaks
# compilation of the WHOLE script anywhere it's loaded outside that context
# (EditorScript, tests, ...), including for callers that never call this
# function at all.
func tick_buffs(buffs_by_id: Dictionary = {}) -> void:
	var total_damage: float = 0.0
	var total_focus = dot_ticker_array[9]
	total_damage += dot_ticker_array[8] * heal_mod_plus * heal_mod_minus * ihot
	if total_damage > 0:
		total_damage = 0

	for i in ELEMENT_ORDER.size():
		var element_damage = ceil(
			(1 + idmg2) * idmgp2 * idot
			* (dot_ticker_array[i] * ((100 + plevel * 15) / def_u[ELEMENT_ORDER[i]]))
		)
		total_damage += element_damage

	var expiring: Array[int] = []
	for i in buff_slots.size():
		if buff_slots[i]["cd"] > 0:
			buff_slots[i]["cd"] -= 1
			if buff_slots[i]["cd"] == 0:
				expiring.append(i)
	for slot_index in expiring:
		var slot = buff_slots[slot_index]
		var buff = buffs_by_id.get(slot["buff_id"])
		if buff:
			apply_buff(buff, -1, null, slot_index, slot["buff_value"])

	if sswitch > 0:
		total_damage *= -1

	var shield_difference: float = 0.0
	if shield > 0 and total_damage > 0:
		shield_difference = shield - total_damage
	if shield_difference > 0:
		shield -= total_damage
	else:
		if total_damage > 0:
			total_damage -= shield
			if total_damage < 0:
				total_damage = 0
			shield = 0
		life_n -= total_damage

	focus_n = clamp(focus_n - total_focus, 0, focus_u)

	if life_n <= 0:
		life_n = 0
		focus_n = 0
		active = false

	apply_changes()
