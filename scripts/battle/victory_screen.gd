# victory_screen.gd
# The post-battle victory overlay (references/2026_07_18_flashpoint/16-18):
# - left panel "Character Experience": portrait + level + XP bar per fighter
# - middle: "Victory! Items that dropped:" with the drop slots - CLICK a
#   drop to keep it (moves into the first free inventory cell), gold
#   call-out text, money/exp gained, and the green Proceed! button
# - right: the shared RightColumn, with its sell slot hidden
# Reuses the menu chrome (MenuTheme) - the original showed this inside the
# same red menu shell.
extends Control
class_name VictoryScreen

signal proceed_pressed

const ItemSlotScene: PackedScene = preload("res://scenes/ui/item_slot.tscn")

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

var _drop_slots: Array[ItemSlot] = []

@onready var right_column: RightColumn = $RightColumn
@onready var _money_value: Label = $MoneyValue
@onready var _exp_value: Label = $ExpValue
@onready var _player_row: VictoryExpRow = $ExpRows/PlayerSlot/Row
@onready var _companion_row_0: VictoryExpRow = $ExpRows/CompanionSlot0/Row
@onready var _companion_row_1: VictoryExpRow = $ExpRows/CompanionSlot1/Row


func _ready():
	right_column.show_sell_button(false)


# The original's Proceed works once, because its release always leaves the
# frame the victory screen is drawn on (DefineButton2_3004 on(release), lines
# 8-29). This screen stays under the cutscene and the ending screen, and a click
# leaves the keyboard focus on the button, so it is disabled once pressed and
# Enter or Space can't press it a second time.
func _on_proceed_pressed() -> void:
	$ProceedButton.disabled = true
	proceed_pressed.emit()


func setup(save: PlayerSave, settlement: BattleSettlement) -> void:
	_money_value.text = "€%d" % settlement.money_gained
	_exp_value.text = "%d%%" % int(settlement.xp_gained)
	_build_experience_rows(settlement)
	_build_drop_slots(save, settlement.drops)
	right_column.populate_from_save(save, ItemManagerAuto.items_by_id)
	right_column.set_gold(save.euro)


# The player's row is at the top. The two below show friendlySlotsFFTT[0] and
# [1] and are hidden when no companion fought in that place.
func _build_experience_rows(settlement: BattleSettlement) -> void:
	_player_row.setup(PORTRAITS[0], Party.PLAYER_NAME, settlement.fighters[0])
	var companion_rows: Array[VictoryExpRow] = [_companion_row_0, _companion_row_1]
	for i in companion_rows.size():
		var row: VictoryExpRow = companion_rows[i]
		var fighter: BattleSettlement.FighterExperience = null
		var party_id: int = -1
		if i < settlement.fighting_party.size():
			party_id = settlement.fighting_party[i]
			fighter = settlement.fighters.get(party_id)
		row.visible = fighter != null
		if fighter != null:
			var display_name: String = str(Party.COMPANIONS.get(party_id, {}).get("name", "?"))
			row.setup(PORTRAITS.get(party_id, PORTRAITS[0]), display_name, fighter)


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
	right_column.populate_from_save(save, ItemManagerAuto.items_by_id)
