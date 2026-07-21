# game_data.gd
# Save/load and player-economy state. Was previously a class_name-only, fully
# stubbed set of static functions (worked without an autoload registration,
# but couldn't hold real state or emit signals). Now a real autoload with
# instance state, since save data is inherently stateful and UI needs to react
# to gold/inventory changes.
#
# Save format: PlayerSave Resource (scripts/entities/player_save.gd), saved as
# a .tres per slot under user://saves/ - the natural Godot equivalent of the
# original's Flash SharedObject (.sol) local-storage slots. Not compatible
# with real original save files (resources/example_save_file*.json) and not
# meant to be - this is a fresh save format for the Godot rewrite.
extends Node

# No class_name here on purpose - this is registered as the "GameData"
# autoload (project.godot), and a class_name of the same name would collide
# with it ("Class X hides an autoload singleton"). Matches the existing
# zone_manager.gd/store_manager.gd pattern: no class_name, called by the
# autoload name directly.

const SAVE_DIR: String = "user://saves/"
const NUM_SLOTS: int = 4

signal save_loaded(slot: int)
signal gold_changed(new_amount: float)
signal inventory_changed

var current_slot: int = -1
var current_save: PlayerSave = null

func _ready():
	name = "GameData"
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot%d.tres" % slot

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))

# Sonny's starting outfit (frame_180: equipArray0 = [0,11,0,4,8,5,0]) -
# White T-Shirt, Levo Jeans, Proverse All Stars, A Broken Pipe.
const STARTING_EQUIPMENT: Dictionary[int, int] = {1: 11, 3: 4, 4: 8, 5: 5}

func new_game(slot: int, player_name: String, player_class: int = 0) -> void:
	current_slot = slot
	current_save = PlayerSave.new_game(player_name, player_class)
	for equip_slot in STARTING_EQUIPMENT:
		var item: GameItem = ItemManagerAuto.get_item(STARTING_EQUIPMENT[equip_slot])
		if item != null:
			Equipment.equip(current_save, item, equip_slot, ItemManagerAuto.items_by_id)

func load_game(slot: int) -> bool:
	if not has_save(slot):
		return false
	var save: Resource = ResourceLoader.load(_slot_path(slot))
	if not (save is PlayerSave):
		push_warning("load_game: slot %d did not contain a PlayerSave" % slot)
		return false
	# Saves created before the action bar was seeded at new game can't fight
	# (Pass only) - put the class starting moves back on an all-empty bar.
	if not save.move_matrix.any(func(move_id): return int(move_id) != 0):
		var starting_moves: Array = TalentTree.STARTING_MOVES.get(save.player_class, [])
		for i in starting_moves.size():
			save.move_matrix[i] = starting_moves[i]
	current_slot = slot
	current_save = save
	save_loaded.emit(slot)
	return true

func save_game() -> bool:
	if current_save == null or current_slot == -1:
		push_warning("save_game: no active save/slot")
		return false
	return ResourceSaver.save(current_save, _slot_path(current_slot)) == OK

func get_player_gold() -> float:
	return current_save.euro if current_save else 0.0

func get_player_inventory() -> Array[GameItem]:
	var inventory: Array[GameItem] = []
	if current_save == null:
		return inventory
	for item_id in current_save.item_array:
		if item_id != 0:
			var item: GameItem = ItemManagerAuto.get_item(item_id)
			if item:
				inventory.append(item)
	return inventory

func get_store_inventory() -> Array[GameItem]:
	return StoreManager.get_current_shop_items()

func can_afford_item(item: GameItem) -> bool:
	return current_save != null and current_save.euro >= item.price

func purchase_item(item: GameItem) -> bool:
	if not can_afford_item(item):
		return false
	var empty_slot: int = current_save.item_array.find(0)
	if empty_slot == -1:
		push_warning("purchase_item: inventory full")
		return false
	current_save.euro -= item.price
	current_save.item_array[empty_slot] = item.id
	gold_changed.emit(current_save.euro)
	inventory_changed.emit()
	return true

# Equips the item sitting in inventory slot inventory_index into equip slot
# equip_slot (see Equipment.EQUIP_SLOT_TYPES; pass -1 to use the item's
# natural slot). Any displaced item swaps back into that inventory slot.
# Returns the Equipment.EquipResult.
func equip_from_inventory(inventory_index: int, equip_slot: int = -1) -> int:
	if current_save == null or inventory_index < 0 or inventory_index >= current_save.item_array.size():
		return Equipment.EquipResult.INVALID
	var item: GameItem = ItemManagerAuto.get_item(int(current_save.item_array[inventory_index]))
	if item == null:
		return Equipment.EquipResult.INVALID
	if equip_slot == -1:
		equip_slot = Equipment.slot_for_item(item)
	var outcome: Dictionary = Equipment.equip(current_save, item, equip_slot, ItemManagerAuto.items_by_id)
	if outcome["result"] == Equipment.EquipResult.OK:
		current_save.item_array[inventory_index] = outcome["previous_item_id"]
		inventory_changed.emit()
	return outcome["result"]


# Unequips equip slot equip_slot into the first empty inventory slot.
func unequip_to_inventory(equip_slot: int) -> bool:
	if current_save == null:
		return false
	var empty_slot: int = current_save.item_array.find(0)
	if empty_slot == -1:
		push_warning("unequip_to_inventory: inventory full")
		return false
	var item_id: int = Equipment.unequip(current_save, equip_slot, ItemManagerAuto.items_by_id)
	if item_id == 0:
		return false
	current_save.item_array[empty_slot] = item_id
	inventory_changed.emit()
	return true


# Sells back at 15% of list price - the shop sell button's handler
# (DefineButton2_3015): Euro += Math.ceil(KRINITEM[5] * 0.15).
func sell_item(item: GameItem) -> bool:
	if current_save == null:
		return false
	var slot_index: int = current_save.item_array.find(item.id)
	if slot_index == -1:
		return false
	current_save.item_array[slot_index] = 0
	current_save.euro += ceil(item.price * 0.15)
	gold_changed.emit(current_save.euro)
	inventory_changed.emit()
	return true
