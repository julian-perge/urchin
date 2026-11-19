# ending_screen.gd
# The screen the game ends on, the original's root frame 116 (endMenu), which
# game.gd's _on_victory_proceed() opens once CS_CUT5, the cutscene after
# the first win of battle 513, ends (frame_219/DoAction.as:51-55). It shows
# KrinLang.ENGLISH.ENDING (frame_116/DoAction.as:1) word for word, so the
# sentences about PvP Arena and www.ArmorGames.com stay, as ADR 0002 and ADR
# 0006 record. OK! emits ok_pressed, which takes the player to the hub the way
# the original's OK! goes to Navigation (DefineButton2_2797 on(release), line
# 2). The backdrop is the menu background scene, which frame 116 shares, and the
# frame's Armor Games logo, copyright line and "Play MORE Games!" link are left
# out like the game over screen's, see
# docs/adr/0002-leave-out-the-armor-games-branding.md.
extends Control
class_name EndingScreen

signal ok_pressed


func _ready() -> void:
	$EndingLabel.text = Strings.text("ENDING")


func _on_ok_pressed() -> void:
	ok_pressed.emit()
