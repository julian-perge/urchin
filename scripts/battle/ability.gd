# ability.gd
# Move/ability data, loaded from dev/converted_json/moves_abilities.json
# by MoveManager. Field names/values decoded from frame42/sonny2_moves.txt
# (KRINABILITY short array) and frame42/sonny2_executeMove.txt (which fields
# the damage formula actually reads). Only the fields execute_move() needs are
# broken out as typed properties; everything else stays in ability_two_raw
# until phase 3b (buffs) needs it - see status_effect_id/effect_proc_chance/etc.
class_name Ability
extends Resource

@export var id: int
@export var display_name: String
@export var can_target_self: bool
@export var can_target_others: bool
@export var targets_allies: bool
@export var focus_cost: float
@export var flat_life_cost: float  # KRINABILITY[6] - flat health cost, paid alongside health_cost_percentage
@export var cooldown_turns: int
@export var hotbar_slot_limit: int  # KRINABILITY[8] - max copies equippable on the 8-slot action bar
@export var combat_speed_modifier: float
@export var attack_animation_type: String
# AS3 addNewMove param 12: for Melee moves the MODEL1 attack label to play
# on the caster (Attack / Attack_Upper / Attack_Stab); for Missile moves the
# projectile clip name (Krin.Firebolt etc.); unused for Shock (which casts).
@export var animation_label: String
# AS3 addNewMove param 13: the BOOM_* impact effect clip attached at the
# target (on melee impact / shock cast / missile arrival). Not rendered yet
# - see DECODED_ALGORITHMS.md.
@export var impact_effect_name: String
@export var effect_category: String  # "Full Damage" / "Heal" / "Focus" / "Attack" (unhandled, see execute_move)
@export var health_cost_percentage: float
@export var sound_effect_name: String

# ability_two fields consumed by execute_move()'s damage/heal/focus formulas.
@export var damage_element_type: CombatUnit.Element
@export var base_strength_bonus: float
@export var strength_damage_multiplier: float
@export var base_magic_bonus: float
@export var magic_damage_multiplier: float
@export var base_speed_bonus: float
@export var speed_damage_multiplier: float
@export var focus_amount_change: float
@export var focus_effect_multiplier: float  # AS3 IDKM2[10], "coEFKN6723" - flat multiplier on the final damage/heal output
@export var focus_scaling_modifier: float  # AS3 IDKM2[11] - scales with caster's current focus in focusCoEF
@export var focus_cost_multiplier: float  # AS3 IDKM2[25] - base term of focusCoEF
@export var heal_percent_max_health: float
# Pre-formatted tooltip strings from the original game (ability_two[17]/[18]).
# Read verbatim, no re-derivation - the source already bakes rank-specific
# percentages/chances into tooltip_description (verified: moves 100-103, all
# "Vicious Strike", have different tooltip_description text per rank even
# though damage_element_type/cooldown/focus_cost are identical across the
# family) - callers must resolve the SPECIFIC move id for the currently
# granted rank, not just the tree node's base move_id, or the tooltip will
# show stale rank-1 text forever. See TalentTree.granted_move_id().
@export var tooltip_description: String
@export var tooltip_cost: String

# status_effect_id (ability_two[13]) is a Variant in the source JSON: int 0
# when the move applies no buff, otherwise a String matching a Buff's
# internal_name (e.g. "AUTOREGEN") - NOT a numeric buff id. Normalized to ""
# here so callers can just check is_empty(). effect_proc_chance
# (ability_two[14]) is the buff-application chance; ability_two[22] (always 1
# in the data) turned out to be the per-buff DISPEL attempt chance - see
# dispel_chance below.
@export var status_effect_id: String
@export var effect_proc_chance: float
@export var effect_target_is_self: bool  # ability_two[21]: 0 = target, 1 = self

# Dispel fields (ability_two[15]/[16]/[19]/[22]) - decoded 2026-07-18 from the
# dispel block in frame217_KRIN_BATTLE_SCENE/onClipEvent_enterFrame.txt. On a
# successful strike, BEFORE the damage/heal resolves, the move removes up to
# dispel_count of the TARGET's active buffs whose element is in
# dispel_element_types and whose Buff.polarity == dispel_target_polarity; each
# candidate needs randf() <= dispel_chance and randf() >= the buff's
# dispel_resist_chance. Resolution lives in BattleRunner._resolve_dispels().
@export var dispel_element_types: Array[CombatUnit.Element] = []
@export var dispel_count: int
@export var dispel_target_polarity: int  # matched against Buff.polarity (1 = buffs, -1 = debuffs)
@export var dispel_chance: float  # 0..1 per-buff attempt chance

# ability_two[20]: the move hits ALL living enemies of the caster instead of
# one target (executeMove runs once per enemy in the conductor).
@export var hits_all_enemies: bool

@export var ability_two_raw: Dictionary

# The raw JSON encodes AS3 `undefined` as {"type": "Undefined"} - any field can
# carry that instead of a number/string (move 0 "None" is almost entirely
# undefined). These coercers make from_json safe for every row in the file.
static func _num(value, default: float = 0.0) -> float:
	if value is float or value is int:
		return float(value)
	if value is bool:
		return 1.0 if value else 0.0
	return default

static func _text(value, default: String = "") -> String:
	return value if value is String else default

static func from_json(data: Dictionary) -> Ability:
	var ability: Ability = Ability.new()
	var ability_two: Dictionary = data.get("ability_two", {})

	ability.id = int(_num(data.get("1_id"), 0.0))
	ability.display_name = _text(data.get("0_display_name"))
	ability.can_target_self = data.get("2_can_target_self")
	ability.can_target_others = data.get("3_can_target_others")
	ability.targets_allies = data.get("4_targets_allies")
	ability.focus_cost = _num(data.get("5_focus_resource_cost"))
	ability.flat_life_cost = _num(data.get("6_deprecated_life_check"))
	ability.cooldown_turns = int(_num(data.get("7_cooldown_turns")))
	ability.hotbar_slot_limit = int(_num(data.get("8_hotbar_slot_limit")))
	ability.combat_speed_modifier = _num(data.get("9_combat_speed_modifier"))
	ability.attack_animation_type = _text(data.get("10_attack_animation_type"))
	ability.animation_label = _text(data.get("12_animation_model_name"))
	ability.impact_effect_name = _text(data.get("13_impact_effect_name"))
	ability.effect_category = _text(data.get("14_effect_category"))
	ability.health_cost_percentage = _num(data.get("16_health_cost_percentage"))
	ability.sound_effect_name = _text(data.get("18_sound_effect_name"))

	ability.damage_element_type = CombatUnit.element_from_name(_text(ability_two.get("0_damage_element_type")))
	ability.base_strength_bonus = _num(ability_two.get("1_base_strength_bonus"))
	ability.strength_damage_multiplier = _num(ability_two.get("2_strength_damage_multiplier"))
	ability.base_magic_bonus = _num(ability_two.get("3_base_magic_bonus"))
	ability.magic_damage_multiplier = _num(ability_two.get("4_magic_damage_multiplier"))
	ability.base_speed_bonus = _num(ability_two.get("5_base_speed_bonus"))
	ability.speed_damage_multiplier = _num(ability_two.get("6_speed_damage_multiplier"))
	ability.focus_amount_change = _num(ability_two.get("9_focus_amount_change"))
	ability.focus_effect_multiplier = _num(ability_two.get("10_focus_effect_multiplier"))
	ability.focus_scaling_modifier = _num(ability_two.get("11_focus_scaling_modifier"))
	ability.focus_cost_multiplier = _num(ability_two.get("25_focus_cost_multiplier"))
	ability.heal_percent_max_health = _num(ability_two.get("12_heal_percent_max_health"))
	ability.tooltip_description = _text(ability_two.get("17_tooltip_description"))
	ability.tooltip_cost = _text(ability_two.get("18_tooltip_cost"))

	var raw_status_effect_id = ability_two.get("13_status_effect_id", 0)
	ability.status_effect_id = raw_status_effect_id if raw_status_effect_id is String else ""
	ability.effect_proc_chance = _num(ability_two.get("14_effect_proc_chance"))
	ability.effect_target_is_self = int(_num(ability_two.get("21_effect_target"))) == 1

	var raw_dispel_elements = ability_two.get("15_element_types_affected", [])
	ability.dispel_element_types = []
	if raw_dispel_elements is Array:
		for raw_name in raw_dispel_elements:
			ability.dispel_element_types.append(CombatUnit.element_from_name(str(raw_name)))
	ability.dispel_count = int(_num(ability_two.get("16_dispel_buff_count")))
	ability.dispel_target_polarity = int(_num(ability_two.get("19_status_effect_tick_rate"), 1.0))
	ability.dispel_chance = _num(ability_two.get("22_buff_application_chance"), 1.0)
	ability.hits_all_enemies = ability_two.get("20_is_multi_target")

	ability.ability_two_raw = ability_two
	return ability
