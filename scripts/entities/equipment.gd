# equipment.gd
# Equip/unequip validation and stat transfer, ported from the item-slot click
# handler in the full SWF script export (DefineButton2_2981, 2026-07-18).
#
# The 7 equip slots each accept one item type; a Two-Handed Arms weapon goes
# into the main-hand slot but is mutually exclusive with anything in the
# secondary slot. Restriction field (GameItem.required_unit_id, raw
# KRINITEM[3]): 0 = anyone, otherwise it must match the wearer's class, the
# original's ClassStats entry. Only Veradux's gear (unit 4) is restricted in
# the entire item set.
# Equipping transfers the item's stat bonuses into the allocation pools
# (attributes -> stat_allocated, piercing/defense -> per/def), exactly like
# the original's StatSets/PerSets/DefSets += statUpdater/P/D.
# The original runs one handler for every party member, indexed by
# Krin.MenuPlayerSelect, so every function here acts on a Wearer: the player
# (Wearer.for_player) or a Companion (Party.companion_wearer).
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

# PlayerSave.equip_array index -> "kind" of slot - unlike the UI's own 0-6
# equip-slot indices (equip_doll_view.gd's equip_index), which never branch
# on which slot it is and stay plain int, this file constantly checks WHICH
# slot (EQUIP_SLOT_TYPES[slot], MAIN_HAND_SLOT/SECONDARY_SLOT's special
# casing), so it earns a real enum.
enum EquipSlot { HEAD, CHEST, HAND, LEGS, FOOT, MAINHAND, OFFHAND }
const MAIN_HAND_SLOT: EquipSlot = EquipSlot.MAINHAND
const SECONDARY_SLOT: EquipSlot = EquipSlot.OFFHAND
# EquipSlot -> accepted GameItem.ItemType (the slot buttons' IPS values;
# Two-Handed is the extra case on the main-hand slot).
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


# The equip array, level, class and bonus pools of the member who wears the
# gear. For the player they are the save's own arrays, so a change writes
# through to the save. A Companion's bonus pools are rebuilt from the seeds
# and its gear each time (Party.companion_wearer), and only its equip array is
# saved.
class Wearer:
	var equip: Array
	var level: int
	# The original's ClassStats entry: player_class + 1 for the player, the
	# unit template id for a Companion.
	var class_id: int
	var stat_allocated: Array = [0, 0, 0, 0, 0]
	var per: Dictionary = {}
	var def: Dictionary = {}
	# Set only for the player, whose derived stats are cached in the save and
	# need Leveling.compute_stats after each change.
	var player_save: PlayerSave = null

	func _init(equip_ids: Array, wearer_level: int, wearer_class_id: int) -> void:
		equip = equip_ids
		level = wearer_level
		class_id = wearer_class_id
		for element in CombatUnit.ELEMENT_ORDER.size():
			per[element] = 0.0
			def[element] = 0.0

	static func for_player(save: PlayerSave) -> Wearer:
		var wearer := Wearer.new(save.equip_array, save.level, save.player_class + 1)
		wearer.stat_allocated = save.stat_allocated
		wearer.per = save.per
		wearer.def = save.def
		wearer.player_save = save
		return wearer


# The natural slot for an item, or -1 for non-equipment.
static func slot_for_item(item: GameItem) -> int:
	if item == null:
		return -1
	if item.item_type == GameItem.ItemType.TWOHAND:
		return MAIN_HAND_SLOT
	return EQUIP_SLOT_TYPES.find(item.item_type)


# Validation only - failure order mirrors the original's error priority.
static func can_equip(wearer: Wearer, item: GameItem, slot_index: EquipSlot) -> EquipResult:
	if item == null or slot_index < 0 or slot_index >= EQUIP_SLOT_TYPES.size():
		return EquipResult.INVALID
	if item.required_level > wearer.level:
		return EquipResult.LEVEL_TOO_LOW
	if item.required_unit_id != 0 and item.required_unit_id != wearer.class_id:
		return EquipResult.WRONG_CLASS
	var is_two_handed_into_main: bool = item.item_type == GameItem.ItemType.TWOHAND and slot_index == MAIN_HAND_SLOT
	if item.item_type != EQUIP_SLOT_TYPES[slot_index] and not is_two_handed_into_main:
		return EquipResult.WRONG_SLOT
	if is_two_handed_into_main and int(wearer.equip[SECONDARY_SLOT]) != 0:
		return EquipResult.SECONDARY_BLOCKS_TWO_HANDED
	return EquipResult.OK


# Full check including the two-handed exclusion on the secondary slot (needs
# the item lookup to inspect the equipped weapon).
static func can_equip_with_lookup(wearer: Wearer, item: GameItem, slot_index: EquipSlot, items_by_id: Dictionary) -> EquipResult:
	var result = can_equip(wearer, item, slot_index)
	if result != EquipResult.OK:
		return result
	if slot_index == SECONDARY_SLOT:
		var main_hand: GameItem = items_by_id.get(int(wearer.equip[MAIN_HAND_SLOT]))
		if main_hand != null and main_hand.item_type == GameItem.ItemType.TWOHAND:
			return EquipResult.TWO_HANDED_BLOCKS_SECONDARY
	return result


# Equips item into slot_index, transferring stat bonuses. Returns
# {result, previous_item_id} - the caller decides where the displaced item
# goes (inventory/cursor). The wearer is untouched on failure.
static func equip(wearer: Wearer, item: GameItem, slot_index: EquipSlot, items_by_id: Dictionary) -> Dictionary:
	var result = can_equip_with_lookup(wearer, item, slot_index, items_by_id)
	if result != EquipResult.OK:
		return {"result": result, "previous_item_id": 0}
	var previous_item_id: int = int(wearer.equip[slot_index])
	if previous_item_id != 0:
		apply_item_stats(wearer, items_by_id.get(previous_item_id), -1)
	wearer.equip[slot_index] = item.id
	apply_item_stats(wearer, item, 1)
	_recompute_player_stats(wearer)
	return {"result": EquipResult.OK, "previous_item_id": previous_item_id}


# Removes the item in slot_index, reverting its stat bonuses. Returns the
# removed item id (0 if the slot was empty).
static func unequip(wearer: Wearer, slot_index: EquipSlot, items_by_id: Dictionary) -> int:
	if slot_index < 0 or slot_index >= wearer.equip.size():
		return 0
	var item_id: int = int(wearer.equip[slot_index])
	if item_id == 0:
		return 0
	apply_item_stats(wearer, items_by_id.get(item_id), -1)
	wearer.equip[slot_index] = 0
	_recompute_player_stats(wearer)
	return item_id


# Summed attribute bonuses of everything equipped - the respec re-seed
# (Leveling.respec's equipment_stat_bonuses; the respec button recomputes
# StatSets0 from equipArray0's statUpdater values).
static func total_stat_bonuses(equip_ids: Array, items_by_id: Dictionary) -> Array:
	var totals: Array[Variant] = [0, 0, 0, 0, 0]
	for item_id in equip_ids:
		var item: GameItem = items_by_id.get(int(item_id))
		if item == null:
			continue
		var attributes: Dictionary = item.stats.get("attributes", {})
		for key in ATTRIBUTE_TO_STAT:
			totals[ATTRIBUTE_TO_STAT[key]] += int(attributes.get(key, 0))
	return totals


# Adds (direction 1) or removes (direction -1) one item's bonuses in the
# wearer's pools.
static func apply_item_stats(wearer: Wearer, item: GameItem, direction: int) -> void:
	if item == null:
		return
	var attributes: Dictionary = item.stats.get("attributes", {})
	for key in ATTRIBUTE_TO_STAT:
		wearer.stat_allocated[ATTRIBUTE_TO_STAT[key]] += direction * int(attributes.get(key, 0))
	# item.stats is parsed straight from JSON, so its "piercing"/"defense" sub-
	# dicts are necessarily String-keyed (JSON object keys are always text) -
	# read by element NAME here, write into the per/def pools by Element below.
	var piercing: Dictionary = item.stats.get("piercing", {})
	var defense: Dictionary = item.stats.get("defense", {})
	for i in CombatUnit.ELEMENT_ORDER.size():
		var element_name: String = CombatUnit.ELEMENT_ORDER[i]
		wearer.per[i] = wearer.per.get(i, 0.0) + direction * float(piercing.get(element_name, 0))
		wearer.def[i] = wearer.def.get(i, 0.0) + direction * float(defense.get(element_name, 0))


static func _recompute_player_stats(wearer: Wearer) -> void:
	if wearer.player_save != null:
		Leveling.compute_stats(wearer.player_save)
