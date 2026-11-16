# slot_panel.gd
# The slot list (scenes/ui/menu/slot_panel.tscn), the original's dataMenu, root
# frame 74: four rows of "Slot", the slot's number and the save's name. Each
# row's hit button covers the caption and the number and not the name, as
# DefineButton2_2719 to 2722 do. main_menu.gd fills the names and decides what
# a click and a hover do. The arena's pick text, edit text 2718, is left out
# (docs/adr/0006-leave-out-the-pvp-arena.md).
class_name SlotPanel
extends Control

signal slot_pressed(slot: int)
signal slot_hovered(slot: int)
signal slot_unhovered

# frame_74/DoAction.as:12 fills slotNamerText, which every row shows, from MENU.
const SLOT_CAPTION: int = 23


func _ready() -> void:
	for row in $Rows.get_children():
		row.get_node("SlotLabel").text = Strings.menu(SLOT_CAPTION)


# Slots count from 1, as the original's slot1 to slot4 do.
func set_save_name(slot: int, save_name: String) -> void:
	get_node("Rows/Row%d/SaveName" % slot).text = save_name


func hit_button(slot: int) -> Button:
	return get_node("Rows/Row%d/HitButton" % slot)


func _on_hit_button_pressed(slot: int) -> void:
	slot_pressed.emit(slot)


func _on_hit_button_mouse_entered(slot: int) -> void:
	slot_hovered.emit(slot)


func _on_hit_button_mouse_exited() -> void:
	slot_unhovered.emit()
