# The Victory Window on the Hub (spec/107-victory.md, "The flow"). The Hub opens
# it on the result a won battle hands it, keeps the hotbar inert until Proceed,
# and Proceed follows the original's order (DefineButton2_3004 on(release)).
# test_battle_scene.gd checks what the battle hands the Hub, and
# test_victory_window.gd checks the Window itself.
extends GutTest

const GameScene: PackedScene = preload("res://scenes/game.tscn")
const TEST_SAVE_DIR := "user://test_victory_proceed_saves/"

# Each case names the result a win hands the Hub and everything Proceed then
# shows. The cutscene comes first, then the map after a boss win, and only then
# the Abilities Window after a level-up or the Hub with its hint. The Victory
# Window stays under the cutscene. A boss win that also levels the player up
# opens only the map.
const PROCEED_CASES: Array[Dictionary] = [
	{"case": "a pending cutscene", "cutscene": "CS_CUT3", "goto": "Navigation", "is_boss": false, "levels": 1, "outcome": ["cutscene", "victory"], "inert": true},
	{"case": "a boss win with a level-up", "cutscene": "", "goto": "", "is_boss": true, "levels": 1, "outcome": ["map"], "inert": false},
	{"case": "a boss win without one", "cutscene": "", "goto": "", "is_boss": true, "levels": 0, "outcome": ["map"], "inert": false},
	{"case": "a level-up without a boss win", "cutscene": "", "goto": "", "is_boss": false, "levels": 1, "outcome": ["abilities"], "inert": false},
	{"case": "a plain win", "cutscene": "", "goto": "", "is_boss": false, "levels": 0, "outcome": ["hint"], "inert": false},
]

var _save_before: PlayerSave
var _slot_before: int


# Proceed autosaves into the current slot, so these tests write into a folder
# of their own and never into the player's real saves.
func before_each() -> void:
	_save_before = GameData.current_save
	_slot_before = GameData.current_slot
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)
	GameData.save_dir = TEST_SAVE_DIR


func after_each() -> void:
	GameData.current_save = _save_before
	GameData.current_slot = _slot_before
	GameData.save_dir = GameData.SAVE_DIR
	for file: String in DirAccess.get_files_at(TEST_SAVE_DIR):
		DirAccess.remove_absolute(TEST_SAVE_DIR + file)
	DirAccess.remove_absolute(TEST_SAVE_DIR)
	ZoneManager.pending_victory = {}
	ZoneManager.open_zone_map_on_load = false
	AudioManagerAuto.stop_music()


func _victory(cutscene: String, goto_scene: String, is_boss: bool, levels_gained: int) -> Dictionary:
	var settlement := BattleSettlement.new()
	settlement.fighters[0] = BattleSettlement.FighterExperience.new()
	settlement.cutscene = cutscene
	settlement.goto_scene = goto_scene
	settlement.levels_gained = levels_gained
	return {"settlement": settlement, "battle_id": 100, "is_boss": is_boss}


# The Hub as a won battle leaves it. It is a partial double whose _reload_hub()
# does nothing, because the real one changes the scene and would take the test
# runner down with it.
func _hub(victory: Dictionary, parent: Node = null) -> Control:
	var save := PlayerSave.new_game("Proceed", 0)
	save.autosave = false
	GameData.current_save = save
	ZoneManager.pending_victory = victory
	var game = partial_double(GameScene).instantiate()
	stub(game, "_reload_hub").to_do_nothing()
	if parent == null:
		add_child_autofree(game)
	else:
		parent.add_child(game)
	game.animation_speed = 0.0
	return game


# Proceed does nothing until the player's experience row has run its frames.
func _finish_player_row(game: Control) -> void:
	var row: VictoryExpRow = game.get_node("VictoryWindow/ExpRows/PlayerSlot/Row")
	while not row.is_finished():
		row.step()


func _proceed(game: Control) -> void:
	_finish_player_row(game)
	(game.get_node("VictoryWindow") as VictoryWindow)._on_proceed_pressed()


# Every outcome that shows, so a case that opens a second one fails.
func _outcomes(game: Control) -> Array[String]:
	var shown: Array[String] = []
	if game.get_node_or_null("CutscenePlayer") != null:
		shown.append("cutscene")
	if game.get_node("VictoryWindow").visible:
		shown.append("victory")
	if game.get_node("ZoneMapOverlay").visible:
		shown.append("map")
	if game.get_node("AbilitiesWindow").visible:
		shown.append("abilities")
	if game.get_node("HubCard").visible:
		shown.append("hint")
	return shown


func test_the_hub_opens_the_victory_window_with_the_hotbar_inert_and_the_art_hidden():
	var game: Control = _hub(_victory("", "", false, 0))
	assert_true(game.get_node("VictoryWindow").visible, "the Window is open")
	assert_true(game.get_node("Hotbar").is_inert(), "the hotbar is inert")
	assert_false(game.zone_host.visible, "the zone art is hidden")
	assert_true(ZoneManager.pending_victory.is_empty(), "the Hub took the result")


func test_a_hub_with_no_pending_victory_opens_no_window():
	var game: Control = _hub({})
	assert_false(game.get_node("VictoryWindow").visible)
	assert_false(game.get_node("Hotbar").is_inert(), "the hotbar is live")
	assert_true(game.zone_host.visible, "the zone art shows")


func test_proceed_follows_the_originals_order():
	for c: Dictionary in PROCEED_CASES:
		var game: Control = _hub(_victory(c["cutscene"], c["goto"], c["is_boss"], c["levels"]))
		_proceed(game)
		assert_eq(_outcomes(game), c["outcome"], c["case"])
		assert_eq(game.get_node("Hotbar").is_inert(), c["inert"], "%s: the hotbar" % c["case"])
		if c["outcome"] == ["hint"]:
			assert_true(game.zone_host.visible, "%s: the Hub art shows" % c["case"])
		if c["outcome"].has("cutscene"):
			assert_not_called(game, "_reload_hub")
			game.get_node("CutscenePlayer").video.finished.emit()
			assert_called(game, "_reload_hub")
		else:
			assert_not_called(game, "_reload_hub")
		game.free()


# Proceed autosaves first, when the option is on (DefineButton2_3004
# on(release), lines 4-7), and the Hub opening on the win saves nothing.
func test_proceed_autosaves_only_when_the_option_is_on():
	for autosave: bool in [true, false]:
		var game: Control = _hub(_victory("", "", false, 0))
		GameData.current_save.autosave = autosave
		GameData.current_slot = 1
		assert_false(FileAccess.file_exists(TEST_SAVE_DIR + "slot1.tres"), "the Hub saves nothing on load")
		_proceed(game)
		assert_eq(FileAccess.file_exists(TEST_SAVE_DIR + "slot1.tres"), autosave, "autosave %s" % autosave)
		DirAccess.remove_absolute(TEST_SAVE_DIR + "slot1.tres")
		game.free()


func _an_effect_is_playing() -> bool:
	return AudioManagerAuto._effect_players.any(func(player): return player.is_playing())


# Starts the menu music the way the Hub does when it opens (game.gd's _ready())
# and returns the cue it picked.
func _hub_menu_track() -> String:
	AudioManagerAuto.play_menu_music()
	var player: AudioStreamPlayer = AudioManagerAuto._music_players[AudioManagerAuto._active_music]
	return player.stream.resource_path.get_file().get_basename()


# The Victory Window's Proceed calls stopAllSounds() before it goes to a
# cutscene (DefineButton2_3004 on(release), lines 8-11), which stops the effects
# as well as the music.
func test_proceeding_into_a_cutscene_stops_sound_effects_too():
	var game: Control = _hub(_victory("CS_CUT2", "overMap", true, 0))
	AudioManagerAuto.play_effect("dead_sonny")
	assert_true(_an_effect_is_playing(), "Sonny's death cry is playing when Proceed is pressed")
	_proceed(game)
	var cutscene: CutscenePlayer = game.get_node_or_null("CutscenePlayer")
	assert_not_null(cutscene, "the cutscene started")
	if cutscene != null:
		assert_eq(cutscene.video.stream.resource_path, "res://assets/cutscenes/CS_CUT2.ogv", "and it is the win's CS_CUT2")
	assert_false(_an_effect_is_playing(), "and no effect plays on into it")
	assert_eq(AudioManagerAuto._music_mode, AudioManagerAuto.MusicMode.NONE, "and the menu music stops")


# When a cutscene ends, the original's cutscene clip sets soundPlayCounter and
# soundModeKrin back to 0 before it starts the menu music
# (frame_263/PlaceObject2_3466_80 enterFrame, lines 15-31), so the Hub comes
# back on the rotation's first menu track. CS_CUT2 goes on to overMap
# (frame_219/DoAction.as), so the next Hub opens the map.
func test_a_cutscene_starts_the_menu_rotation_over_and_overmap_opens_the_map_next():
	var game: Control = _hub(_victory("CS_CUT2", "overMap", true, 0))
	AudioManagerAuto._rotation_counter = 2
	_proceed(game)
	game.get_node("CutscenePlayer").video.finished.emit()
	assert_called(game, "_reload_hub")
	assert_true(ZoneManager.open_zone_map_on_load, "the next Hub opens the map")
	assert_eq(_hub_menu_track(), "_music_menu1", "the Hub comes back on the first menu track")


# CS_CUT5 goes on to endMenu, root frame 116, without starting any music
# (frame_263/PlaceObject2_3466_80 enterFrame, lines 15-19 and 33). Frame 116
# fills its text with KrinLang.ENGLISH.ENDING (frame_116/DoAction.as:1,
# frame_1/DoAction.as:2240) above the static OK! caption, and only OK! goes on
# to the Hub (DefineButton2_2797 on(release), line 2), whose Navigation frame
# starts the rotation over (frame_181/DoAction.as:15).
func test_cs_cut5_ends_on_the_silent_ending_screen_and_ok_goes_to_the_hub():
	var game: Control = _hub(_victory("CS_CUT5", "endMenu", true, 0))
	AudioManagerAuto._rotation_counter = 2
	_proceed(game)
	var cutscene: CutscenePlayer = game.get_node("CutscenePlayer")
	assert_eq(cutscene.video.stream.resource_path, "res://assets/cutscenes/CS_CUT5.ogv")
	cutscene.video.finished.emit()

	assert_not_called(game, "_reload_hub")
	assert_false(ZoneManager.open_zone_map_on_load, "the zone map stays shut")
	assert_eq(AudioManagerAuto._music_mode, AudioManagerAuto.MusicMode.NONE, "no music plays on the ending screen")
	var ending: EndingScreen = game.get_node_or_null("EndingScreen")
	assert_not_null(ending, "the ending screen is up")
	if ending == null:
		return
	assert_true(ending.is_visible_in_tree(), "and showing")
	var strings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://dev/converted_json/strings.json"))
	assert_eq(ending.get_node("EndingLabel").text, strings["ENDING"], "ENDING")
	assert_eq(ending.get_node("OkLabel").text, "OK!", "static text 2799")
	ending.get_node("OkButton").pressed.emit()
	assert_called(game, "_reload_hub")
	assert_eq(_hub_menu_track(), "_music_menu1", "the Hub that OK! opens starts on the first menu track")


# The original's Proceed can't be pressed twice, because its release always
# leaves the frame of DefineSprite 3142 that the Window is drawn on, for the
# cutscene, the map or 3142's skills or hide frame (DefineButton2_3004
# on(release), lines 8-29). The test clicks the port's Proceed the way a player
# does, which leaves the keyboard focus on it, and then presses Enter and Space
# under CS_CUT5 and again under the ending screen.
func test_enter_and_space_after_clicking_proceed_press_nothing_under_the_cutscene_or_the_ending():
	# The Hub gets a viewport of its own, because GUT's window sits above
	# everything in the root viewport and would take the click.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 575)
	add_child_autofree(viewport)
	var game: Control = _hub(_victory("CS_CUT5", "endMenu", true, 0), viewport)
	_finish_player_row(game)
	_click(viewport, game.get_node("VictoryWindow/ProceedButton"))
	assert_eq(get_call_count(game, "_on_victory_proceed"), 1, "the click pressed Proceed")
	var cutscene: CutscenePlayer = game.get_node_or_null("CutscenePlayer")
	assert_not_null(cutscene, "CS_CUT5 is playing")
	for key in [KEY_ENTER, KEY_SPACE]:
		_press(viewport, key)
		assert_eq(get_call_count(game, "_on_victory_proceed"), 1, "%s under the cutscene presses nothing" % OS.get_keycode_string(key))
	if cutscene != null:
		cutscene.video.finished.emit()
	assert_not_null(game.get_node_or_null("EndingScreen"), "the ending screen is up")
	for key in [KEY_ENTER, KEY_SPACE]:
		_press(viewport, key)
		assert_eq(get_call_count(game, "_on_victory_proceed"), 1, "%s under the ending screen presses nothing" % OS.get_keycode_string(key))
	assert_not_called(game, "_reload_hub")


# A left click on the control's center, pushed through the viewport's GUI input.
func _click(viewport: Viewport, control: Control) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = control.get_global_rect().get_center()
		event.global_position = event.position
		viewport.push_input(event, true)


# Presses and releases the key, because a focused button acts on the release.
func _press(viewport: Viewport, key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		viewport.push_input(event, true)
