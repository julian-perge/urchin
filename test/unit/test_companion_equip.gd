# Companion equip from the Inventory's party faces (#195). The original runs one equip handler
# for every party member, indexed by Krin.MenuPlayerSelect, with that member's
# ClassStats and LevelStats as the class and level checks
# (DefineButton2_2981 on(press)).
extends GutTest

const SEEDS_FILE: String = "res://dev/source_files/action_script/frame_42/DoAction_17.as"
const SAVE_DIR: String = "user://test_companion_equip/"
const FELICITY: int = 3

# Felicity at level 22 in the original game, as the issue records it:
# [Vitality, Strength, Instinct, Speed, Focus].
const FELICITY_ALL_GEAR: Array = [40, 150, 40, 171, 125]
const FELICITY_NO_GEAR: Array = [40, 66, 40, 45, 100]

var save: PlayerSave
var real_save_dir: String


func before_each() -> void:
	save = PlayerSave.new_game("Companion", 0)
	save.party_roster = [0, 1, 2, 3, -1, -1]
	GameData.current_save = save
	GameData.menu_party_id = Party.PLAYER_PARTY_ID
	real_save_dir = GameData.save_dir


func after_each() -> void:
	GameData.current_save = null
	GameData.menu_party_id = Party.PLAYER_PARTY_ID
	GameData.save_dir = real_save_dir


func _stats(party_id: int) -> Array:
	var wearer: Equipment.Wearer = Party.companion_wearer(save, party_id, ItemManagerAuto.items_by_id)
	var template: Character = UnitManagerAuto.get_unit(Party.COMPANIONS[party_id]["unit_id"])
	var stats: Array = []
	for value in Party.companion_stats(wearer, template):
		stats.append(int(value))
	return stats


# The array that the AS seeds as "Krin.<name> = [...];" in DoAction_17.
func _seed(name: String) -> Array:
	var text: String = FileAccess.get_file_as_string(SEEDS_FILE)
	var regex := RegEx.create_from_string("Krin\\.%s = (\\[[^\\]]*\\]);" % name)
	var found: RegExMatch = regex.search(text)
	assert_not_null(found, "DoAction_17 seeds %s" % name)
	return JSON.parse_string(found.get_string(1)) if found != null else []


func _ints(values: Array) -> Array:
	var ints: Array = []
	for value in values:
		ints.append(int(value))
	return ints


# The equippable item with the lowest id that passes predicate.
func _first_free_item(predicate: Callable) -> GameItem:
	var ids: Array = ItemManagerAuto.items_by_id.keys()
	ids.sort()
	for id in ids:
		var item: GameItem = ItemManagerAuto.items_by_id[id]
		if Equipment.slot_for_item(item) != -1 and predicate.call(item):
			return item
	return null


func test_felicity_at_level_22_shows_the_original_stats_with_all_gear_and_with_none() -> void:
	assert_eq(int(save.party_levels[FELICITY]), 22)
	assert_eq(_stats(FELICITY), FELICITY_ALL_GEAR, "the seed gear")
	var equip: Array = Party.companion_equip(save, FELICITY)
	for slot in equip.size():
		equip[slot] = 0
	assert_eq(_stats(FELICITY), FELICITY_NO_GEAR, "no gear")


# With their seed gear, Veradux and Roald have the StatSets and PerSets seeds,
# the stats the port gave them before #195.
func test_veradux_and_roald_keep_the_seed_stats_with_their_seed_gear() -> void:
	for party_id in [1, 2]:
		var wearer: Equipment.Wearer = Party.companion_wearer(save, party_id, ItemManagerAuto.items_by_id)
		assert_eq(wearer.equip, _ints(_seed("equipArray%d" % party_id)), "party %d seed gear" % party_id)
		var stat_seed: Array = _ints(_seed("StatSets%d" % party_id))
		assert_eq(wearer.stat_allocated, stat_seed, "party %d StatSets" % party_id)
		var per_seed: Array = _seed("PerSets%d" % party_id)
		for element in CombatUnit.ELEMENT_ORDER.size():
			assert_eq(wearer.per[element], float(per_seed[element]), "party %d PerSets %d" % [party_id, element])
			assert_eq(wearer.def[element], 0.0, "party %d has no defense from gear" % party_id)


func test_the_class_check_uses_the_companions_class_stats() -> void:
	var items: Dictionary = ItemManagerAuto.items_by_id
	var veradux_gear: GameItem = items[int(Party.COMPANIONS[1]["equipment"][0])]
	assert_eq(veradux_gear.required_unit_id, 4, "the Medic-B gear is for unit 4")
	var veradux: Equipment.Wearer = Party.companion_wearer(save, 1, items)
	var roald: Equipment.Wearer = Party.companion_wearer(save, 2, items)
	assert_eq(Equipment.can_equip(veradux, veradux_gear, Equipment.EquipSlot.HEAD), Equipment.EquipResult.OK)
	assert_eq(Equipment.can_equip(roald, veradux_gear, Equipment.EquipSlot.HEAD), Equipment.EquipResult.WRONG_CLASS)
	assert_eq(Equipment.can_equip(Equipment.Wearer.for_player(save), veradux_gear, Equipment.EquipSlot.HEAD), Equipment.EquipResult.WRONG_CLASS)


func test_the_level_check_uses_the_companions_level() -> void:
	var items: Dictionary = ItemManagerAuto.items_by_id
	var felicity_helm: GameItem = items[int(Party.COMPANIONS[FELICITY]["equipment"][0])]
	var veradux: Equipment.Wearer = Party.companion_wearer(save, 1, items)
	var felicity: Equipment.Wearer = Party.companion_wearer(save, FELICITY, items)
	assert_eq(Equipment.can_equip(veradux, felicity_helm, Equipment.EquipSlot.HEAD), Equipment.EquipResult.LEVEL_TOO_LOW)
	assert_eq(Equipment.can_equip(felicity, felicity_helm, Equipment.EquipSlot.HEAD), Equipment.EquipResult.OK)


func test_unequip_and_equip_through_the_menu_change_the_companions_battle_unit() -> void:
	GameData.menu_party_id = FELICITY
	var player_gear: Array = save.equip_array.duplicate()
	var geared: CombatUnit = Party.build_companion_unit(save, FELICITY, UnitManagerAuto.units_by_id, ItemManagerAuto.items_by_id, 3)
	var removed: Array = []
	for slot in 7:
		var item_id: int = int(Party.companion_equip(save, FELICITY)[slot])
		assert_true(GameData.unequip_to_inventory(slot), "slot %d unequips" % slot)
		removed.append(item_id)
	assert_eq(Party.companion_equip(save, FELICITY), [0, 0, 0, 0, 0, 0, 0])
	assert_eq(save.equip_array, player_gear, "the player's gear is untouched")
	var bare: CombatUnit = Party.build_companion_unit(save, FELICITY, UnitManagerAuto.units_by_id, ItemManagerAuto.items_by_id, 3)
	assert_eq(bare.base_speed, float(FELICITY_NO_GEAR[3]))
	assert_eq(bare.base_strength, float(FELICITY_NO_GEAR[1]))
	assert_eq(bare.base_per[CombatUnit.Element.PHYSICAL], geared.base_per[CombatUnit.Element.PHYSICAL] - 397.0, "the gear's piercing goes")
	assert_eq(bare.equipment_ids, [0, 0, 0, 0, 0, 0, 0], "the battle doll wears what she wears")

	for item_id in removed:
		var index: int = save.item_array.find(item_id)
		assert_eq(GameData.equip_from_inventory(index), Equipment.EquipResult.OK, "item %d equips back" % item_id)
	var regeared: CombatUnit = Party.build_companion_unit(save, FELICITY, UnitManagerAuto.units_by_id, ItemManagerAuto.items_by_id, 3)
	assert_eq(regeared.base_speed, float(FELICITY_ALL_GEAR[3]))
	assert_eq(regeared.base_per, geared.base_per)
	assert_eq(regeared.base_def, geared.base_def)


func test_a_defense_item_raises_the_companions_battle_defense() -> void:
	var armor: GameItem = _first_free_item(func(item: GameItem) -> bool:
		return item.required_unit_id == 0 and item.required_level <= 22 and float(item.stats.get("defense", {}).get("Physical", 0)) > 0.0)
	assert_not_null(armor)
	if armor == null:
		return
	var slot: int = Equipment.slot_for_item(armor)
	Party.companion_equip(save, FELICITY)[slot] = 0
	var before: CombatUnit = Party.build_companion_unit(save, FELICITY, UnitManagerAuto.units_by_id, ItemManagerAuto.items_by_id, 3)
	save.item_array[0] = armor.id
	GameData.menu_party_id = FELICITY
	assert_eq(GameData.equip_from_inventory(0), Equipment.EquipResult.OK)
	var after: CombatUnit = Party.build_companion_unit(save, FELICITY, UnitManagerAuto.units_by_id, ItemManagerAuto.items_by_id, 3)
	assert_eq(after.base_def[CombatUnit.Element.PHYSICAL], before.base_def[CombatUnit.Element.PHYSICAL] + float(armor.stats["defense"]["Physical"]))


func test_party_equip_survives_save_and_load() -> void:
	GameData.save_dir = SAVE_DIR
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	GameData.current_slot = 1
	Party.companion_equip(save, FELICITY)[0] = 0
	assert_true(GameData.save_game())
	assert_true(GameData.load_game(1))
	assert_eq(GameData.current_save.party_equip[FELICITY][0], 0)
	assert_eq(GameData.current_save.party_equip[1], Party.COMPANIONS[1]["equipment"])
	DirAccess.remove_absolute(SAVE_DIR + "slot1.tres")


func test_a_save_without_party_equip_loads_with_the_seed_gear() -> void:
	GameData.save_dir = SAVE_DIR
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	GameData.current_slot = 1
	save.party_equip = []
	assert_true(GameData.save_game())
	assert_true(GameData.load_game(1))
	for party_id in Party.COMPANIONS:
		assert_eq(GameData.current_save.party_equip[party_id], Party.COMPANIONS[party_id]["equipment"])
	DirAccess.remove_absolute(SAVE_DIR + "slot1.tres")
