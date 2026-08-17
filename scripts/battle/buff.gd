# buff.gd
# Buff/debuff data, loaded from dev/converted_json/buffs.json
# by BuffManager. Field names decoded from frame42/sonny2_addNewBuffKrin.txt
# (applyBuffKrin/buffTicker/applyChangesKrin) - see convert_buffs.py for the
# full field-by-field notes. Application/tick logic lives on CombatUnit
# (apply_buff()/tick_buffs()), not here - this class is data only.
class_name Buff
extends Resource

@export var id: int
@export var internal_name: String
@export var display_name: String
@export var element_type: String
@export var duration_turns: int

@export var change_strength_flat: float
@export var change_strength_percent: float
@export var change_magic_flat: float
@export var change_magic_percent: float
@export var change_speed_flat: float
@export var change_speed_percent: float
@export var change_life_flat: float
@export var change_life_percent: float
@export var outgoing_damage_flat: float
@export var outgoing_damage_percent: float
@export var incoming_damage_flat: float
@export var incoming_damage_percent_or_reduction: float  # positive -> IDMG2, negative -> IDMGP

@export var dot_hot_base_value: float  # negative = heal over time
@export var focus_per_turn: float
@export var stun_delta: float
@export var reflect_delta: float
@export var shield_flat: float

@export var change_element_piercing: float
@export var change_element_defense: float
@export var change_element_piercing_percent: float
@export var change_element_defense_percent: float

@export var tooltip_description: String
@export var sswitch_delta: float

@export var dot_scale_caster_strength: float
@export var dot_scale_caster_magic: float
@export var dot_scale_caster_speed: float
@export var dot_scale_caster_life: float
@export var visual_filter_index: int

@export var heal_mod_plus_delta: float
@export var heal_mod_minus_delta: float
@export var heal_mod_delta: float

@export var shield_scale_caster_strength: float
@export var shield_scale_caster_magic: float
@export var shield_scale_caster_speed: float
@export var shield_scale_caster_life: float

@export var dot_scale_target_strength: float
@export var dot_scale_target_magic: float
@export var dot_scale_target_speed: float
@export var dot_scale_target_life: float

@export var idot_delta: float
@export var ihot_delta: float
@export var odot_delta: float
@export var focus_change_delta: float
@export var silenced_delta: float

# Dispel/stacking fields, decoded 2026-07-18 from
# frame217_KRIN_BATTLE_SCENE/onClipEvent_enterFrame.txt (formerly
# unknown_field_20/27/32 - see convert_buffs.py for the notes):
@export var polarity: int  # 1 = beneficial, -1 = harmful, 0 = neutral; dispel matches this
@export var is_unique: bool  # re-application refreshes duration instead of stacking
@export var dispel_resist_chance: float  # 0..1, dispel succeeds when randf() >= this

# AS3 leaves "empty" string fields as numeric 0 (55 buffs have 0 for
# display_name/tooltip) - coerce, don't crash the typed String assignment.
static func _text(value, default: String = "") -> String:
	return value if value is String else default


static func from_json(data: Dictionary) -> Buff:
	var buff: Buff = Buff.new()
	buff.id = int(data["id"])
	buff.internal_name = _text(data["internal_name"])
	buff.display_name = _text(data["0_display_name"])
	buff.element_type = _text(data["1_element_type"])
	buff.duration_turns = int(data["16_duration_turns"])

	buff.change_strength_flat = data["2_change_strength_flat"]
	buff.change_strength_percent = data["3_change_strength_percent"]
	buff.change_magic_flat = data["4_change_magic_flat"]
	buff.change_magic_percent = data["5_change_magic_percent"]
	buff.change_speed_flat = data["6_change_speed_flat"]
	buff.change_speed_percent = data["7_change_speed_percent"]
	buff.change_life_flat = data["8_change_life_flat"]
	buff.change_life_percent = data["9_change_life_percent"]
	buff.outgoing_damage_flat = data["10_outgoing_damage_flat"]
	buff.outgoing_damage_percent = data["11_outgoing_damage_percent"]
	buff.incoming_damage_flat = data["12_incoming_damage_flat"]
	buff.incoming_damage_percent_or_reduction = data["13_incoming_damage_percent_or_reduction"]

	buff.dot_hot_base_value = data["14_dot_hot_base_value"]
	buff.focus_per_turn = data["15_focus_per_turn"]
	buff.stun_delta = data["17_stun_delta"]
	buff.reflect_delta = data["18_reflect_delta"]
	buff.shield_flat = data["19_shield_flat"]

	buff.change_element_piercing = data["21_change_element_piercing"]
	buff.change_element_defense = data["22_change_element_defense"]
	buff.change_element_piercing_percent = data["23_change_element_piercing_percent"]
	buff.change_element_defense_percent = data["24_change_element_defense_percent"]

	buff.tooltip_description = _text(data["25_tooltip_description"])
	buff.sswitch_delta = data["26_sswitch_delta"]

	buff.dot_scale_caster_strength = data["28_dot_scale_caster_strength"]
	buff.dot_scale_caster_magic = data["29_dot_scale_caster_magic"]
	buff.dot_scale_caster_speed = data["30_dot_scale_caster_speed"]
	buff.visual_filter_index = int(data["31_visual_filter_index"])
	buff.dot_scale_caster_life = data["33_dot_scale_caster_life"]

	buff.heal_mod_plus_delta = data["35_heal_mod_plus_delta"]
	buff.heal_mod_minus_delta = data["36_heal_mod_minus_delta"]
	buff.heal_mod_delta = data["37_heal_mod_delta"]

	buff.shield_scale_caster_strength = data["38_shield_scale_caster_strength"]
	buff.shield_scale_caster_magic = data["39_shield_scale_caster_magic"]
	buff.shield_scale_caster_speed = data["40_shield_scale_caster_speed"]
	buff.shield_scale_caster_life = data["41_shield_scale_caster_life"]

	buff.dot_scale_target_strength = data["42_dot_scale_target_strength"]
	buff.dot_scale_target_magic = data["43_dot_scale_target_magic"]
	buff.dot_scale_target_speed = data["44_dot_scale_target_speed"]
	buff.dot_scale_target_life = data["45_dot_scale_target_life"]

	buff.idot_delta = data["46_idot_delta"]
	buff.ihot_delta = data["47_ihot_delta"]
	buff.odot_delta = data["48_odot_delta"]
	buff.focus_change_delta = data["49_focus_change_delta"]
	buff.silenced_delta = data["50_silenced_delta"]

	buff.polarity = int(data.get("20_polarity", 0))
	buff.is_unique = int(data.get("27_is_unique", 0)) == 1
	buff.dispel_resist_chance = data.get("32_dispel_resist_chance", 0.0)

	return buff
