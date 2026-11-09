# game_over_screen.gd
# The screen a defeat or a draw ends the game on, the original's root frame 104
# (gameOverMenu), opened by battle_scene.gd's _finish_battle(). Re-Load reloads
# the slot the game was in and goes to the hub, or goes to the main menu when
# that slot holds no save (DefineButton2_2791 on(release)). Back goes to the
# main menu (DefineButton2_2702 on(release)). The backdrop is the main menu's,
# which frame 104 shares, and the frame's Armor Games logo, copyright line and
# link are left out, see docs/adr/0002-leave-out-the-armor-games-branding.md.
extends Control
class_name GameOverScreen

const GAME_SCENE: String = "res://scenes/game.tscn"
const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"


# The original resets the whole game before it shows this screen, and the reset
# stops every sound and starts the music rotation over
# (frame_41/DoAction_2.as:12-14). The menu music starts again on the rotation's
# first track once Re-Load reaches the hub.
func _ready() -> void:
	AudioManagerAuto.stop_all_sounds()
	AudioManagerAuto.reset_music_rotation()


# Returns the scene to open instead of opening it, so a test can run the real
# load without a scene change taking down the test runner.
func reload_last_save() -> String:
	return GAME_SCENE if GameData.load_game(GameData.current_slot) else MAIN_MENU_SCENE


func _on_reload_pressed() -> void:
	get_tree().change_scene_to_file(reload_last_save())


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
