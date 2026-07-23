# victory_screen.gd
# The post-battle victory overlay (references/2026_07_18_flashpoint/16-18):
# - left panel "Character Experience": portrait + level + XP bar per fighter
# - middle: "Victory! Items that dropped:" with the drop slots - CLICK a
#   drop to keep it (moves into the first free inventory cell), gold
#   call-out text, money/exp gained, and the green Proceed! button
# - right: the shared InventoryPanel
# Reuses the menu chrome (MenuTheme) - the original showed this inside the
# same red menu shell.
extends Control
class_name VictoryScreen

signal proceed_pressed

const ItemSlotScene: PackedScene = preload("res://scenes/ui/item_slot.tscn")
const VictoryExperienceRowScene: PackedScene = preload("res://scenes/battle/victory_experience_row.tscn")

const INVENTORY_AT: Vector2 = Vector2(503.5, 81.6)
const DROP_ORIGIN: Vector2 = Vector2(321.0, 130.0)
const DROP_COLUMNS: int = 4

const PORTRAITS: Dictionary[int, String] = {
	0: "portraits/sonny.png",
	1: "portraits/veradux.png",
	2: "portraits/roald.png",
	3: "portraits/felicity.png",
	4: "portraits/wolfgang.png",
	5: "portraits/amber.png",
}

var inventory_panel: InventoryPanel

var _drop_slots: Array[ItemSlot] = []

@onready var _money_value: Label = $MoneyValue
@onready var _exp_value: Label = $ExpValue


func _ready():
	inventory_panel = preload("res://scenes/ui/inventory.tscn").instantiate()
	inventory_panel.position = INVENTORY_AT
	add_child(inventory_panel)
	inventory_panel.show_sell_button(false)


func _on_proceed_pressed() -> void:
	proceed_pressed.emit()


# rewards = BattleRewards.apply_victory result; drops = rolled item ids;
# party_ids = deployed companion party ids that fought.
func setup(save: PlayerSave, rewards: Dictionary, drops: Array, party_ids: Array) -> void:
	_money_value.text = "€%d" % int(rewards.get("money_gained", 0))
	_exp_value.text = "%d%%" % int(rewards.get("xp_gained", 0))
	_build_experience_rows(save, party_ids)
	_build_drop_slots(save, drops)
	inventory_panel.populate_from_save(save, ItemManagerAuto.items_by_id)
	inventory_panel.set_gold(save.euro)


func _build_experience_rows(save: PlayerSave, party_ids: Array) -> void:
	var fighters: Array[int] = [0]
	for party_id in party_ids:
		fighters.append(int(party_id))
	var y: float = 120.0
	for party_id in fighters:
		var row: VictoryExperienceRow = VictoryExperienceRowScene.instantiate()
		row.position = Vector2(0, y)
		add_child(row)
		var display_name: String
		var level: int
		var experience: float
		if party_id == 0:
			display_name = save.name_user
			level = save.level
			experience = save.experience
		else:
			display_name = str(Party.COMPANIONS.get(party_id, {}).get("name", "?"))
			level = int(save.party_levels[party_id]) if party_id < save.party_levels.size() else 1
			experience = float(save.party_exp[party_id]) if party_id < save.party_exp.size() else 0.0
		row.setup(PORTRAITS.get(party_id, PORTRAITS[0]), display_name, level, experience)
		y += 62.0


func _build_drop_slots(save: PlayerSave, drops: Array) -> void:
	for i in drops.size():
		var slot: ItemSlot = ItemSlotScene.instantiate()
		slot.position = DROP_ORIGIN + Vector2(
			(i % DROP_COLUMNS) * MenuTheme.SLOT_STEP,
			floorf(i / float(DROP_COLUMNS)) * MenuTheme.SLOT_STEP
		)
		add_child(slot)
		slot.set_item(ItemManagerAuto.get_item(int(drops[i])))
		slot.slot_clicked.connect(_on_drop_clicked.bind(save))
		_drop_slots.append(slot)


func _on_drop_clicked(slot: ItemSlot, save: PlayerSave) -> void:
	if slot.item == null:
		return
	var empty: int = save.item_array.find(0)
	if empty == -1:
		return  # inventory full - the drop stays claimable
	save.item_array[empty] = slot.item.id
	slot.set_item(null)
	inventory_panel.populate_from_save(save, ItemManagerAuto.items_by_id)
