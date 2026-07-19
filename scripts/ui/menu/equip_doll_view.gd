# equip_doll_view.gd
# The dressed player doll flanked by the 7 equip slots - shared by the
# inventory screen (frame 1 of the original menu clip) and the store screen
# (frame 16), which lay the same elements out at different positions.
# Call setup() with the slot-center map once, then refresh() after any
# save/equipment change.
extends Control
class_name EquipDollView

signal equip_slot_clicked(equip_index: int)

const ItemSlotScene = preload("res://scenes/ui/item_slot.tscn")
const CharacterVisualScript = preload("res://scripts/entities/character_visual.gd")

var _slots: Dictionary = {}  # equip index -> ItemSlot
var _doll: CharacterVisual


# slot_centers: equip index (0-6) -> stage-relative center. The doll draws
# at doll_position with doll_scale (origin = mid-body, like the battle);
# menu dolls stand still (the original only animates in battle), and
# face_left mirrors them (the shop doll faces left in the source).
func setup(slot_centers: Dictionary, doll_position: Vector2, doll_scale: float, face_left: bool = false) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_doll = CharacterVisualScript.new()
	_doll.animate = false
	_doll.position = doll_position
	_doll.scale = Vector2(-doll_scale if face_left else doll_scale, doll_scale)
	add_child(_doll)
	for equip_index in slot_centers:
		var slot: ItemSlot = ItemSlotScene.instantiate()
		slot.position = slot_centers[equip_index] - MenuTheme.SLOT_SIZE / 2.0
		slot.set_meta("equip_index", equip_index)
		slot.slot_clicked.connect(_on_slot_clicked)
		add_child(slot)
		_slots[equip_index] = slot


func refresh(save: PlayerSave, items_by_id: Dictionary) -> void:
	for equip_index in _slots:
		var slot: ItemSlot = _slots[equip_index]
		var item_id = int(save.equip_array[equip_index]) if equip_index < save.equip_array.size() else 0
		slot.set_item(items_by_id.get(item_id) if item_id != 0 else null)
	var unit = CombatUnit.from_player_save(save)
	_doll.dress_from_model(unit.model, CharacterVisual.resolve_equip_looks(unit, items_by_id))


func _on_slot_clicked(slot: ItemSlot) -> void:
	equip_slot_clicked.emit(int(slot.get_meta("equip_index")))
