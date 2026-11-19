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


# frame_104/DoAction.as:1-3 fills the three texts from KrinLang.ENGLISH, which
# dev/converted_json/strings.json holds. The test reads the file itself, so a
# text typed into the scene or the script fails it.
func _strings() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://dev/converted_json/strings.json"))


func test_the_texts_come_from_strings_json() -> void:
	var strings: Dictionary = _strings()
	var screen: GameOverScreen = add_child_autofree(GameOverScene.instantiate())
	assert_eq((screen.get_node("DeadLabel") as Label).text, strings["MENU"][50], "MENU[50]")
	assert_eq((screen.get_node("ReloadLabel") as Label).text, "< %s >" % strings["MENU"][51], "MENU[51] between angle brackets")
	assert_eq((screen.get_node("TipLabel") as Label).text, strings["GOTIP"][0], "GOTIP[0], word for word")


# A screen that is not in the tree yet has not run _ready, so its Labels show
# only what the .tscn types.
func test_the_scene_types_none_of_the_texts() -> void:
	var screen: GameOverScreen = autofree(GameOverScene.instantiate())
	for path: String in ["DeadLabel", "ReloadLabel", "TipLabel"]:
		assert_eq((screen.get_node(path) as Label).text, "", path)
