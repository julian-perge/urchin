# mode_panel.gd
# The choice (scenes/ui/menu/mode_panel.tscn), the original's subMenu, root
# frame 56: New Game or Load Game. The original's third choice, PvP Arena, is
# left out (docs/adr/0006-leave-out-the-pvp-arena.md).
class_name ModePanel
extends Control

signal new_game_pressed
signal load_game_pressed

# frame_56/DoAction.as:1-2 fills the captions from MENU.
const NEW_GAME_CAPTION: int = 21
const LOAD_GAME_CAPTION: int = 22


func _ready() -> void:
	$Captions/NewGameSlot/Caption.text = Strings.menu(NEW_GAME_CAPTION)
	$Captions/LoadGameSlot/Caption.text = Strings.menu(LOAD_GAME_CAPTION)


func _on_new_game_button_pressed() -> void:
	new_game_pressed.emit()


func _on_load_game_button_pressed() -> void:
	load_game_pressed.emit()
