# The Game over Screen on its own (spec/107-game-over.md). The way in and
# Re-Load are tested through a real battle in test_battle_scene.gd.
extends GutTest

const GameOverScene: PackedScene = preload("res://scenes/battle/game_over_screen.tscn")


# A partial double of the screen whose _open_scene does nothing, because the real
# one changes the scene and would take the test runner down with it.
func _screen_without_scene_change() -> GameOverScreen:
	var screen = partial_double(GameOverScene).instantiate()
	stub(screen, "_open_scene").to_do_nothing()
	add_child_autofree(screen)
	return screen


# Back goes to mainMenu from frame 104, as from every menu frame
# (DefineButton2_2702 on(release), line 2).
func test_back_opens_the_main_menu() -> void:
	var screen: GameOverScreen = _screen_without_scene_change()
	(screen.get_node("Back/HitButton") as Button).pressed.emit()
	assert_called(screen, "_open_scene", [GameOverScreen.MAIN_MENU_SCENE])
