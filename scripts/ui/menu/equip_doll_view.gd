# The dressed player doll with the 7 equip slots. The Inventory window (frame 1
# of the original menu clip) and the Store window (frame 16) each place this
# node in their scene, with its Doll and its slots, at their own positions.
# Call setup() once, then refresh() after each change to the save or the
# equipment.
extends Control
class_name EquipDollView

signal equip_slot_clicked(equip_index: int)

var _slots: Dictionary = {}  # equip index -> ItemSlot
var _doll: CharacterVisual


# The scene supplies the Doll and the slots, each with its position and scale,
# so setup() only connects them. A slot names its index in equip_index
# metadata, which clicks and drag-and-drop read.
func setup() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_doll = get_node("Doll") as CharacterVisual
	for child: Node in get_children():
		if not child is ItemSlot or not child.has_meta("equip_index"):
			continue
		var slot: ItemSlot = child
		var equip_index: int = int(slot.get_meta("equip_index"))
		slot.set_meta("drag_source", "equip")
		slot.set_meta("drag_index", equip_index)
		slot.empty_slot_type = Equipment.EQUIP_SLOT_TYPES[equip_index]
		slot.slot_clicked.connect(_on_slot_clicked)
		_slots[equip_index] = slot


func refresh(save: PlayerSave, items_by_id: Dictionary) -> void:
	for equip_index in _slots:
		var slot: ItemSlot = _slots[equip_index]
		var item_id: int = int(save.equip_array[equip_index]) if equip_index < save.equip_array.size() else 0
		slot.set_item(items_by_id.get(item_id) if item_id != 0 else null)
	var unit: CombatUnit = CombatUnit.from_player_save(save)
	_doll.dress_from_model(unit.model, CharacterVisual.resolve_equip_looks(unit, items_by_id))


func _on_slot_clicked(slot: ItemSlot) -> void:
	equip_slot_clicked.emit(int(slot.get_meta("equip_index")))
