# equipment.gd
# Equip/unequip validation and stat transfer, ported from the item-slot click
# handler in the full SWF script export (DefineButton2_2981, 2026-07-18).
#
# The 7 equip slots (PlayerSave.equip_array) each accept one item type; a
# Two-Handed Arms weapon goes into the main-hand slot but is mutually
# exclusive with anything in the secondary slot. Restriction field
# (GameItem.required_unit_id, raw KRINITEM[3]): 0 = anyone, otherwise the
# wearer's unit id must match - the player's is player_class + 1. Only
# Veradux's gear (unit 4) is restricted in the entire item set.
# Equipping transfers the item's stat bonuses into the allocation pools
# (attributes -> stat_allocated, piercing/defense -> per/def), exactly like
# the original's StatSets/PerSets/DefSets += statUpdater/P/D.
#
# No autoload references - the GameItem lookup comes in as a parameter.
class_name Equipment
extends RefCounted

enum EquipResult {
	OK,
	LEVEL_TOO_LOW,  # ITEMERROR1
	WRONG_CLASS,  # ITEMERROR2
	WRONG_SLOT,  # ITEMERROR3
	SECONDARY_BLOCKS_TWO_HANDED,  # ITEMERROR4
	TWO_HANDED_BLOCKS_SECONDARY,  # ITEMERROR5
	INVALID,
}

# Original English error strings (frame1/sonny2_static_strings...).
const EQUIP_RESULT_MESSAGES: Dictionary[EquipResult, String] = {
	EquipResult.OK: "",
	EquipResult.LEVEL_TOO_LOW: "Your level is not high enough to use that item.",
	EquipResult.WRONG_CLASS: "You cannot equip this item. It could be for another class.",
	EquipResult.WRONG_SLOT: "This item does not fit into that slot.",
	EquipResult.SECONDARY_BLOCKS_TWO_HANDED: "You cannot equip this while you have a 'Secondary Arms' equipped.",
	EquipResult.TWO_HANDED_BLOCKS_SECONDARY: "You cannot equip this while you have a 'Two-Handed Arms' equipped.",
	EquipResult.INVALID: "Invalid item or slot.",
}

const MAIN_HAND_SLOT: int = 5
const SECONDARY_SLOT: int = 6
# equip_array index -> accepted GameItem.ItemType (the slot buttons' IPS
# values; Two-Handed is the extra case on the main-hand slot).
const EQUIP_SLOT_TYPES: Array[GameItem.ItemType] = [
	GameItem.ItemType.HEAD,
	GameItem.ItemType.CHEST,
	GameItem.ItemType.HAND,
	GameItem.ItemType.LEGS,
	GameItem.ItemType.FOOT,
	GameItem.ItemType.MAINHAND,
	GameItem.ItemType.OFFHAND,
]

# stat attributes dict key -> stat_allocated index (Leveling.Stat order).
const ATTRIBUTE_TO_STAT: Dictionary[String, Leveling.Stat] = {
	"health": Leveling.Stat.LIFE,
	"strength": Leveling.Stat.STRENGTH,
	"magic": Leveling.Stat.MAGIC,
	"speed": Leveling.Stat.SPEED,
	"focus": Leveling.Stat.FOCUS,
}


# The natural slot for an item, or -1 for non-equipment.
static func slot_for_item(item: GameItem) -> int:
	if item == null:
		return -1
	if item.item_type == GameItem.ItemType.TWOHAND:
		return MAIN_HAND_SLOT
	return EQUIP_SLOT_TYPES.find(item.item_type)


# Validation only - failure order mirrors the original's error priority.
static func can_equip(save: PlayerSave, item: GameItem, slot_index: int) -> EquipResult:
	if item == null or slot_index < 0 or slot_index >= EQUIP_SLOT_TYPES.size():
		return EquipResult.INVALID
	if item.required_level > save.level:
		return EquipResult.LEVEL_TOO_LOW
	if item.required_unit_id != 0 and item.required_unit_id != save.player_class + 1:
		return EquipResult.WRONG_CLASS
	var is_two_handed_into_main: bool = item.item_type == GameItem.ItemType.TWOHAND and slot_index == MAIN_HAND_SLOT
	if item.item_type != EQUIP_SLOT_TYPES[slot_index] and not is_two_handed_into_main:
		return EquipResult.WRONG_SLOT
	if is_two_handed_into_main and int(save.equip_array[SECONDARY_SLOT]) != 0:
		return EquipResult.SECONDARY_BLOCKS_TWO_HANDED
	return EquipResult.OK


# Full check including the two-handed exclusion on the secondary slot (needs
# the item lookup to inspect the equipped weapon).
static func can_equip_with_lookup(save: PlayerSave, item: GameItem, slot_index: int, items_by_id: Dictionary) -> EquipResult:
	var result = can_equip(save, item, slot_index)
	if result != EquipResult.OK:
		return result
	if slot_index == SECONDARY_SLOT:
		var main_hand: GameItem = items_by_id.get(int(save.equip_array[MAIN_HAND_SLOT]))
		if main_hand != null and main_hand.item_type == GameItem.ItemType.TWOHAND:
			return EquipResult.TWO_HANDED_BLOCKS_SECONDARY
	return result


# Equips item into slot_index, transferring stat bonuses. Returns
# {result, previous_item_id} - the caller decides where the displaced item
# goes (inventory/cursor). save untouched on failure.
static func equip(save: PlayerSave, item: GameItem, slot_index: int, items_by_id: Dictionary) -> Dictionary:
	var result = can_equip_with_lookup(save, item, slot_index, items_by_id)
	if result != EquipResult.OK:
		return {"result": result, "previous_item_id": 0}
	var previous_item_id: int = int(save.equip_array[slot_index])
	if previous_item_id != 0:
		_apply_item_stats(save, items_by_id.get(previous_item_id), -1)
	save.equip_array[slot_index] = item.id
	_apply_item_stats(save, item, 1)
	Leveling.compute_stats(save)
	return {"result": EquipResult.OK, "previous_item_id": previous_item_id}


# Removes the item in slot_index, reverting its stat bonuses. Returns the
# removed item id (0 if the slot was empty).
static func unequip(save: PlayerSave, slot_index: int, items_by_id: Dictionary) -> int:
	if slot_index < 0 or slot_index >= save.equip_array.size():
		return 0
	var item_id: int = int(save.equip_array[slot_index])
	if item_id == 0:
		return 0
	_apply_item_stats(save, items_by_id.get(item_id), -1)
	save.equip_array[slot_index] = 0
	Leveling.compute_stats(save)
	return item_id


# Summed attribute bonuses of everything equipped - the respec re-seed
# (Leveling.respec's equipment_stat_bonuses; the respec button recomputes
# StatSets0 from equipArray0's statUpdater values).
static func total_stat_bonuses(save: PlayerSave, items_by_id: Dictionary) -> Array:
	var totals: Array[Variant] = [0, 0, 0, 0, 0]
	for item_id in save.equip_array:
		var item: GameItem = items_by_id.get(int(item_id))
		if item == null:
			continue
		var attributes: Dictionary = item.stats.get("attributes", {})
		for key in ATTRIBUTE_TO_STAT:
			totals[ATTRIBUTE_TO_STAT[key]] += int(attributes.get(key, 0))
	return totals


static func _apply_item_stats(save: PlayerSave, item: GameItem, direction: int) -> void:
	if item == null:
		return
	var attributes: Dictionary = item.stats.get("attributes", {})
	for key in ATTRIBUTE_TO_STAT:
		save.stat_allocated[ATTRIBUTE_TO_STAT[key]] += direction * int(attributes.get(key, 0))
	var piercing: Dictionary = item.stats.get("piercing", {})
	var defense: Dictionary = item.stats.get("defense", {})
	for element in CombatUnit.ELEMENT_ORDER:
		save.per[element] = save.per.get(element, 0.0) + direction * float(piercing.get(element, 0))
		save.def[element] = save.def.get(element, 0.0) + direction * float(defense.get(element, 0))
