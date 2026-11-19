# The dressed player doll with the 7 equip slots. The Inventory window (frame 1
# of the original menu clip) and the Store window (frame 16) each place this
# node in their scene, with its Doll and its slots, at their own positions. The
# Inventory also places DollF, the female doll, which it shows instead of Doll
# for a female member, as updateDoll shows the _f part clips
# (DefineSprite_3142/frame_1/DoAction.as:32-51). The Store frame places no _f
# clips and no party faces, so the Store shows only the player and has no DollF.
# Call setup() once, then refresh() after each change to the save or the
# equipment, with the battle unit of the member it shows.
extends Control
class_name EquipDollView

signal equip_slot_clicked(equip_index: int)

var _slots: Dictionary = {}  # equip index -> ItemSlot
var _doll: CharacterVisual
var _female_doll: CharacterVisual


# The scene supplies the Doll and the slots, each with its position and scale,
# so setup() only connects them. A slot names its index in equip_index
# metadata, which clicks and drag-and-drop read.
func setup() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_doll = get_node("Doll") as CharacterVisual
	_female_doll = get_node_or_null("DollF") as CharacterVisual
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


func refresh(unit: CombatUnit, items_by_id: Dictionary) -> void:
	var equip_ids: Array = unit.equipment_ids
	for equip_index in _slots:
		var slot: ItemSlot = _slots[equip_index]
		var item_id: int = int(equip_ids[equip_index]) if equip_index < equip_ids.size() else 0
		slot.set_item(items_by_id.get(item_id) if item_id != 0 else null)
	var doll: CharacterVisual = _doll
	if _female_doll != null:
		var female: bool = unit.model.size() > 3 and unit.model[3] != "M"
		_doll.visible = not female
		_female_doll.visible = female
		doll = _female_doll if female else _doll
	doll.dress_from_model(unit.model, CharacterVisual.resolve_equip_looks(unit, items_by_id))


func _on_slot_clicked(slot: ItemSlot) -> void:
	equip_slot_clicked.emit(int(slot.get_meta("equip_index")))
