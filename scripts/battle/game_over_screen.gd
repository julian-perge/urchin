# game_over_screen.gd
# The screen a defeat or a draw ends the game on, the original's root frame 104
# (gameOverMenu), opened by battle_scene.gd's _finish_battle(). Re-Load reloads
# the slot the game was in and goes to the hub, or goes to the main menu when
# that slot holds no save (DefineButton2_2791 on(release)). Back goes to the
# main menu (DefineButton2_2702 on(release)). The background and Back are the
# shared menu pieces, menu_background.tscn and menu_back.tscn, which frame 104
# places as every menu frame does. The frame's Armor Games logo, copyright line
# and link are left out, see docs/adr/0002-leave-out-the-armor-games-branding.md.
extends Control
class_name GameOverScreen

# frame_104/DoAction.as:1-3 fills the three texts from KrinLang.ENGLISH. The
# tip names the ArmorGames forums, which stays, because it is the game's own
# text and not a link (docs/adr/0002-leave-out-the-armor-games-branding.md).
const DEAD_CAPTION: int = 50
const RELOAD_CAPTION: int = 51
const TIP: int = 0
const GAME_SCENE: String = "res://scenes/game.tscn"
const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"


# The original resets the whole game before it shows this screen, and the reset
# stops every sound and starts the music rotation over
# (frame_41/DoAction_2.as:12-14). The menu music starts again on the rotation's
# first track once Re-Load reaches the hub.
func _ready() -> void:
	$DeadLabel.text = Strings.menu(DEAD_CAPTION)
	$ReloadLabel.text = "< %s >" % Strings.menu(RELOAD_CAPTION)
	$TipLabel.text = Strings.text("GOTIP", TIP)
	AudioManagerAuto.stop_all_sounds()
	AudioManagerAuto.reset_music_rotation()


# Returns the scene to open instead of opening it, so a test can run the real
# load without a scene change taking down the test runner.
func reload_last_save() -> String:
	return GAME_SCENE if GameData.load_game(GameData.current_slot) else MAIN_MENU_SCENE


func _on_reload_pressed() -> void:
	_open_scene(reload_last_save())


func _on_back_pressed() -> void:
	_open_scene(MAIN_MENU_SCENE)


# A test stubs this, because a real scene change takes down the test runner.
func _open_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)
