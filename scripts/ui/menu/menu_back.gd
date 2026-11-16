# menu_back.gd
# Back (scenes/ui/menu/menu_back.tscn), which every menu Screen after the
# title shows at the same spot: the caption whatToSayX over hit button 2702.
# The original's Back goes to mainMenu from all of them (DefineButton2_2702
# on(release), line 2), so main_menu.gd connects each one to the title.
class_name MenuBack
extends Control

signal pressed

# frame_46/DoAction.as:1 fills whatToSayX with MENU[26].
const CAPTION: int = 26


func _ready() -> void:
	$Caption.text = Strings.menu(CAPTION)


func _on_hit_button_pressed() -> void:
	pressed.emit()
