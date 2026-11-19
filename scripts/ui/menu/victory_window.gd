# The Victory Window, the "win" label of KRINMENU (spec/107-victory.md). It
# shows the experience rows, the items the win dropped, the gain and Proceed,
# beside the shared right column. victory_window.tscn places every piece, and
# test_screen_rects.gd checks it against the SWF.
#
# A click on a drop moves it into the first free inventory cell, and a full
# inventory leaves the drop claimable. Proceed does nothing until the player's
# experience row has run its frames, as the original's PauseForScreen2 does.
class_name VictoryWindow
extends Control

# The Hub (game.gd) runs the original's Proceed when this fires. It fires once.
signal proceed_pressed

const ItemSlotScene: PackedScene = preload("res://scenes/ui/item_slot.tscn")

const DROPS_PER_ROW: int = 5

const PORTRAITS: Dictionary[int, String] = {
	0: "portraits/sonny.png",
	1: "portraits/veradux.png",
	2: "portraits/roald.png",
	3: "portraits/felicity.png",
	4: "portraits/wolfgang.png",
	5: "portraits/amber.png",
}

# The 15 drop slots in grid order, row by row.
var _drop_slots: Array[ItemSlot] = []
var _save: PlayerSave

@onready var right_column: RightColumn = $RightColumn
@onready var _player_row: VictoryExpRow = $ExpRows/PlayerSlot/Row
@onready var _companion_row_0: VictoryExpRow = $ExpRows/CompanionSlot0/Row
@onready var _companion_row_1: VictoryExpRow = $ExpRows/CompanionSlot1/Row
@onready var _no_items_label: Label = $NoItemsLabel
@onready var _click_hint_label: Label = $ClickHintLabel
@onready var _money_value: Label = $MoneyValue
@onready var _exp_value: Label = $ExpValue
@onready var _proceed_button: Button = $ProceedButton


func _ready() -> void:
	$Heading.text = Strings.menu(15)
	$DropsLabel.text = Strings.text("VICTORY", 0)
	$MoneyLabel.text = Strings.text("VICTORY", 2)
	$ExpLabel.text = Strings.text("VICTORY", 3)
	$ProceedHintLabel.text = Strings.text("VICTORY", 4)
	$ProceedLabel.text = Strings.menu(13)
	right_column.show_sell_button(false)
	for row: Node in $Drops.get_children():
		for column in DROPS_PER_ROW:
			var slot: ItemSlot = ItemSlotScene.instantiate()
			slot.name = "Slot%d" % column
			slot.slot_clicked.connect(_on_drop_clicked)
			row.add_child(slot)
			_drop_slots.append(slot)


func setup(save: PlayerSave, settlement: BattleSettlement) -> void:
	_save = save
	# The original's script types the euro sign and the percent sign beside the
	# gain, and strings.json holds neither. They stay typed here by decision.
	_money_value.text = String.chr(0x20ac) + str(settlement.money_gained)
	_exp_value.text = str(int(settlement.xp_gained)) + "%"
	_build_experience_rows(settlement)
	_show_drops(settlement.drops)
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


# With no drops, "No Items Found." shows and the click hint is empty. With
# drops, it is the other way round (DefineSprite_3142/frame_9/DoAction.as).
func _show_drops(drops: Array) -> void:
	for i in _drop_slots.size():
		var slot: ItemSlot = _drop_slots[i]
		_set_drop(slot, ItemManagerAuto.get_item(int(drops[i])) if i < drops.size() else null)
	var any_drop: bool = not drops.is_empty()
	_no_items_label.text = "" if any_drop else Strings.menu(12)
	_click_hint_label.text = Strings.text("VICTORY", 1) if any_drop else ""


# A drop slot with no item is hidden and keeps its place. `visible = false`
# would make the FloatBox rows pull the slots after it forward.
func _set_drop(slot: ItemSlot, item: GameItem) -> void:
	slot.set_item(item)
	slot.modulate.a = 1.0 if item != null else 0.0
	slot.mouse_filter = Control.MOUSE_FILTER_STOP if item != null else Control.MOUSE_FILTER_IGNORE


func _on_drop_clicked(slot: ItemSlot) -> void:
	if slot.item == null:
		return
	var empty: int = _save.item_array.find(0)
	if empty == -1:
		return  # inventory full - the drop stays claimable
	_save.item_array[empty] = slot.item.id
	_set_drop(slot, null)
	right_column.populate_from_save(_save, ItemManagerAuto.items_by_id)


# The original's Proceed works once, because its release always leaves the frame
# this Window is drawn on (DefineButton2_3004 on(release)). The Hub keeps this
# Window under the cutscene and the ending screen, and a click leaves
# the keyboard focus on the button, so the button is disabled once pressed and
# Enter or Space can't press it a second time. Before the player's row has run
# its frames, Proceed does nothing, as with PauseForScreen2 in the original.
func _on_proceed_pressed() -> void:
	if _proceed_button.disabled or not _player_row.is_finished():
		return
	_proceed_button.disabled = true
	proceed_pressed.emit()
