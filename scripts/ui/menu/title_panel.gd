# title_panel.gd
# The title (scenes/ui/menu/title_panel.tscn), the original's mainMenu, root
# frame 46. main_menu.gd connects game_manual_pressed to the Game Manual
# (spec/107-game-manual.md) and credits_pressed to the Credits Screen
# (spec/107-credits.md).
class_name TitlePanel
extends Control

signal play_pressed
signal game_manual_pressed
signal credits_pressed

# frame_46/DoAction_3.as:2-6 fills the captions from MENU. It also fills
# MENU[19] and MENU[90], the two links to the publisher's site, which the port
# leaves out (docs/adr/0002-leave-out-the-armor-games-branding.md).
const PLAY_CAPTION: int = 18
const GAME_MANUAL_CAPTION: int = 20
const CREDITS_CAPTION: int = 91


func _ready() -> void:
	$Captions/PlaySlot/Caption.text = Strings.menu(PLAY_CAPTION)
	$Captions/GameManualSlot/Caption.text = Strings.menu(GAME_MANUAL_CAPTION)
	$Captions/CreditsSlot/Caption.text = Strings.menu(CREDITS_CAPTION)


func _on_play_button_pressed() -> void:
	play_pressed.emit()


func _on_game_manual_button_pressed() -> void:
	game_manual_pressed.emit()


func _on_credits_button_pressed() -> void:
	credits_pressed.emit()
