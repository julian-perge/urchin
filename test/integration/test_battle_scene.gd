# Every test here builds battle_scene.tscn and starts a battle from
# resources/battles on a save made for that test. The checks on the battle
# screen's extracted art and layout JSON never build the scene, so they are in
# test_battle_assets.gd.
extends GutTest

const BattleSceneRes = preload("res://scenes/battle_scene.tscn")
# Every checkout of the project shares one user:// folder, the player's real
# saves and achievements included, so the Re-Load test writes its slot in a
# folder of its own and every win here unlocks into a file of its own.
const TEST_SAVE_DIR: String = "user://test_battle_scene_saves/"
const ACHIEVEMENTS_FILE: String = "user://test_battle_scene_achievements.cfg"

var _achievements_path: String


func before_all():
	_achievements_path = ZoneManager.achievements_path
	ZoneManager.achievements_path = ACHIEVEMENTS_FILE


func after_all():
	ZoneManager.achievements_path = _achievements_path
	if FileAccess.file_exists(ACHIEVEMENTS_FILE):
		DirAccess.remove_absolute(ACHIEVEMENTS_FILE)


func test_full_battle_scene_run():
	var save = PlayerSave.new_game("SceneTest", 0)
	save.skill_points = 8
	TalentTree.learn(save, 0)
	TalentTree.learn(save, 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	watch_signals(scene)
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	# Battle 100: players [5, -2, 0, -1, 0] -> player, Prison Guard, Veradux.
	assert_eq(scene._presenters.size(), 3, "player + enemy + Veradux fighters spawned")
	assert_not_null(scene._presenters.get(1))
	assert_eq(scene.units[2].player_name, "Prison Guard")
	assert_eq(scene._presenters[2].displayed_hp, scene.units[2].life_n, "each fighter shows its own slot's unit")

	# Let the AI drive the player so the loop runs unattended.
	var player: CombatUnit = scene.units[1]
	player.ai_enabled = true
	player.move_pool_attack = TalentTree.get_known_move_ids(save)
	player.cooldowns_attack = []
	for i in player.move_pool_attack.size():
		player.cooldowns_attack.append(0)

	await wait_for_signal(scene.battle_finished, 30)
	assert_signal_emitted(scene, "battle_finished")
	assert_true(scene.runner.is_over(), "battle ran to completion")
	assert_has([0, 1, 2], scene.runner.win_condition)
	gut.p("scene battle outcome=%d turns=%d" % [scene.runner.win_condition, scene.runner.turn_count])
	if scene.runner.win_condition == BattleRunner.Outcome.WIN:
		var victory = scene.get_node_or_null("VictoryScreen")
		assert_not_null(victory, "victory screen shown on win")
		# Drops are click-to-keep now - claiming one lands in the inventory.
		if victory != null and not victory._drop_slots.is_empty():
			var drop: ItemSlot = victory._drop_slots[0]
			if drop.item != null:
				var item_id = drop.item.id
				victory._on_drop_clicked(drop, save)
				assert_has(save.item_array, item_id, "claimed drop landed in the inventory")
	else:
		assert_not_null(scene.get_node_or_null("UI/GameOverScreen"), "game over screen shown on loss/draw")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# Regression test for a turnTime:0 speech (one meant to play the instant the
# battle begins) reaching the player through the real scene, not just
# runner.events (see battle_runner.gd's setup() and its unit-level coverage
# in test_battle_runner.gd). Battle 105 (Doctor Leath's "Twisted Experiment")
# has exactly one speech, at turnTime:0.
func test_setup_time_speech_plays_through_the_real_scene():
	var save = PlayerSave.new_game("SpeechFlow", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 105, "is_story_progress": false, "is_boss": false, "train_cap": 9})
	assert_false(scene._pending_setup_events.is_empty(), "setup() handed the scene its pre-loop speech event")

	# Only the player needs driving - companions/enemies already come with
	# their own real AI move pools from CombatUnit.from_character().
	var player: CombatUnit = scene.units[BattleRunner.PLAYER_SLOT]
	player.ai_enabled = true
	player.move_pool_attack = TalentTree.STARTING_MOVES.get(save.player_class, [])
	player.cooldowns_attack = []
	for i in player.move_pool_attack.size():
		player.cooldowns_attack.append(0)

	await wait_for_signal(scene.battle_finished, 30)
	assert_true(scene._pending_setup_events.is_empty(), "_battle_loop() played and cleared the pre-loop event")
	var has_speech: bool = false
	for event in scene.runner.events:
		if event["type"] == BattleRunner.EventType.SPEECH:
			has_speech = true
	assert_true(has_speech, "the speech is still in the real log too")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# The tutorial's fourth and fifth lines are the narrator's. The narrator is
# playerKrin0, which every battle names "Information"
# (frame_201/DoAction.as:113-115), and the speech box shows the speaker's
# playerName (frame_217/PlaceObject2_3389_480 enterFrame, line 830).
func test_the_narrator_speaks_as_information():
	var shown: Array = await _speech_box_lines(2, CombatUnit.Difficulty.NORMAL)
	var texts: Array = shown.map(func(line): return line[0])
	assert_eq(texts.slice(3, 5), [
		"Information: Notice the grey 'ring' in the lower middle panel, around the exclamation mark. Wait until it turns blue.",
		"Information: Once the ring is blue, click on the enemy to target him. Your abilities will appear around him.",
	])


# Battle 105 opens with one of the game's two longest lines, 15 seconds
# (frame_42/DoAction_14.as:443). The speech box keeps a line up for
# timeToSay * 30 frames at the SWF's 30 fps (frame_217/PlaceObject2_3389_480
# enterFrame, line 841). Until the lines finish, the conductor neither runs the
# Heroic clock nor takes a pick, because its whole decision block waits for
# speechDone (lines 591-793 there), and so do target clicks
# (frame_217/DoAction_3.as:18).
func test_a_line_stays_up_for_its_whole_time_to_say():
	var shown: Array = await _speech_box_lines(105, CombatUnit.Difficulty.HARD)
	assert_eq(shown.map(func(line): return line[0]), [
		"Twisted Experiment: Oh the horrors! I can't take it anymore! Please. Let me... taste your... blood water.",
	], "battle 105 opens with Twisted Experiment's one line")
	assert_eq(shown.map(func(line): return line[1]), [15.0], "the line stays up for 15 seconds")
	assert_eq(shown.map(func(line): return line[2]), [false], "and the player can't act while it does")


# The conductor starts every battle with timerWait at 30 and counts it down a
# frame at a time (frame_217/PlaceObject2_3389_480 onClipEvent(load), line 6,
# and enterFrame, lines 5-8), and its whole decision block waits for 0 (line
# 589). At the SWF's 30 fps the opening lines start a second in, and the first
# decision, with its Heroic clock, opens only once that second and the lines
# are done. The tutorial runs it because its first half-turn is the player's:
# TeamSelect hands it to team 1 on speed alone, with no roll and no
# absolute_start in the record, so no hit can kill Sonny before that decision
# opens.
func test_the_battle_waits_a_second_before_its_opening_lines():
	var run: Dictionary = await _pauses_to_first_decision(2, CombatUnit.Difficulty.HARD)
	var first_two: Array = run["pauses"].slice(0, 2).map(func(pause): return [pause[0] != "", pause[1], pause[2]])
	assert_eq(first_two, [[false, 1.0, false], [true, 4.5, false]],
		"a second with nothing on screen, then Louis the Blind's 4.5 second line, and no pick open during either")
	assert_almost_eq(run["scene"]._decision_timer, 4.0, 0.25, "the Heroic window is whole when the first decision opens")


# Space during the tutorial's second line ends it, and the conductor then skips
# the third without counting it, so the fourth never matches and the fifth sits
# behind it (frame_217/PlaceObject2_3367_634 onClipEvent(keyDown), lines 2-9,
# and frame_217/PlaceObject2_3389_480 enterFrame, lines 815 and 852-856). The
# runner is left on the fourth line, so nothing later in the battle plays.
func test_space_during_a_line_ends_it_and_skips_the_rest():
	var run: Dictionary = await _pauses_to_first_decision(2, CombatUnit.Difficulty.NORMAL, func(scene, pause):
		if pause[0].begins_with("Sonny: "):
			scene._input(_space_press())
	)
	var shown: Array = run["pauses"].filter(func(pause): return pause[0] != "").map(func(pause): return pause[0])
	assert_eq(shown, [
		"Louis the Blind: I may be blind, but there's no mistaking that smell. Can you take him out?",
		"Sonny: Yes, I...I suppose I can. Ugh...I don't feel too well.",
	], "the opening stops at Sonny's line")
	assert_eq(run["scene"].runner.speech_cursor, 3, "and the runner is left on the fourth line")


# With the cap gone, Space is the only way to take a long line down early. The
# original ends it on the next frame, since Space sets nextSpeechKKK (keyDown,
# line 4) and the conductor moves on as soon as that is set. The battle loop is
# stubbed out so the line plays on its own real 15 second timer.
func test_space_takes_a_long_line_down_at_once():
	var save = PlayerSave.new_game("SpaceCut", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}
	var scene = partial_double(BattleSceneRes).instantiate()
	stub(scene, "_battle_loop").to_do_nothing()
	add_child_autofree(scene)
	scene.start_battle({"battle_id": 105, "is_story_progress": false, "is_boss": false, "train_cap": 9})
	var line: Dictionary = scene._pending_setup_events[0]
	var done: Array = [false]
	var show_line: Callable = func():
		await scene._play_speech(line)
		done[0] = true
	show_line.call()

	await wait_process_frames(2)
	assert_eq(scene.speech_label.text.left(20), "Twisted Experiment: ", "the 15 second line is up")
	scene._input(_space_press())
	await wait_process_frames(2)
	assert_true(done[0], "Space took it down within two frames")
	assert_eq(scene.speech_label.text, "", "and the speech box is empty")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func _move_result(kind: MoveResult.Kind, direction: MoveResult.Direction, amount: float) -> MoveResult:
	var result := MoveResult.new()
	result.kind = kind
	result.direction = direction
	result.amount = amount
	return result


func _space_press() -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = true
	return event


# Starts a battle in a scene whose _pause records every line the speech box
# shows: its text, how many seconds it stays up and whether the player could act
# meanwhile. It returns them at the player's first decision, or at the end of a
# battle that never reaches one, so they hold every line that plays before it.
func _speech_box_lines(battle_id: int, difficulty: CombatUnit.Difficulty) -> Array:
	var run: Dictionary = await _pauses_to_first_decision(battle_id, difficulty)
	return run["pauses"].filter(func(pause): return pause[0] != "")


# Starts a battle in a scene whose _pause only records each wait it is asked
# for: the speech box's text, the seconds, and whether the player could act
# meanwhile. during_pause, when given, runs inside each wait with the scene and
# that record, the way a key pressed mid-wait would land. Returns the scene and
# the records at the player's first decision, or once the battle is over when a
# hit kills Sonny before he gets one, as battle 105's opening crit can.
func _pauses_to_first_decision(battle_id: int, difficulty: CombatUnit.Difficulty, during_pause: Callable = Callable()) -> Dictionary:
	var save = PlayerSave.new_game("SpeechBox", 0)
	save.difficulty = difficulty
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = partial_double(BattleSceneRes).instantiate()
	var pauses: Array = []
	stub(scene, "_pause").to_call(func(seconds: float):
		var pause: Array = [scene.speech_label.text, seconds, scene.decision_open]
		pauses.append(pause)
		if during_pause.is_valid():
			during_pause.call(scene, pause)
	)
	add_child_autofree(scene)
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": battle_id, "is_story_progress": false, "is_boss": false, "train_cap": 9})
	await wait_until(func(): return scene.decision_open or scene._finished, 5)

	GameData.current_save = null
	ZoneManager.auto_start_battles = true
	return {"scene": scene, "pauses": pauses}


func _an_effect_is_playing() -> bool:
	return AudioManagerAuto._effect_players.any(func(player): return player.is_playing())


# The victory screen's Proceed calls stopAllSounds() before it goes to a
# cutscene (DefineButton2_3004 on(release), lines 8-11), which stops the effects
# as well as the music. The win of story battle 109 is set before the battle
# loop starts, so no fight is played and the test plays Felicity's death cry
# itself. Autosave is off so Proceed never writes a save slot.
func test_proceeding_into_a_cutscene_stops_sound_effects_too():
	var save = PlayerSave.new_game("CutsceneEffects", 0)
	save.autosave = false
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 109, "is_story_progress": true, "is_boss": true, "train_cap": 9})
	scene.runner.win_condition = BattleRunner.Outcome.WIN
	await wait_for_signal(scene.battle_finished, 5)

	AudioManagerAuto.play_effect(scene.units[2].voice_die)
	assert_true(_an_effect_is_playing(), "Felicity's death cry is playing when Proceed is pressed")
	scene.get_node("VictoryScreen").proceed_pressed.emit()
	var cutscene: CutscenePlayer = scene.get_node_or_null("CutscenePlayer")
	assert_not_null(cutscene, "the cutscene started")
	if cutscene != null:
		assert_eq(cutscene.video.stream.resource_path, "res://assets/cutscenes/CS_CUT2.ogv", "and it is the win's CS_CUT2")
	assert_false(_an_effect_is_playing(), "and no effect plays on into it")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# Starts the menu music the way the hub does when it opens (game.gd's _ready())
# and returns the cue it picked.
func _hub_menu_track() -> String:
	AudioManagerAuto.play_menu_music()
	var player: AudioStreamPlayer = AudioManagerAuto._music_players[AudioManagerAuto._active_music]
	return player.stream.resource_path.get_file().get_basename()


# When a cutscene ends, the original's cutscene clip sets soundPlayCounter and
# soundModeKrin back to 0 before it starts the menu music
# (frame_263/PlaceObject2_3466_80 enterFrame, lines 15-31), so the hub comes back
# on the rotation's first menu track. The test leaves the rotation on
# _music_menu2, where one menu track and one battle track leave it. The scene is
# a partial double whose _on_continue_pressed() does nothing, because the real
# one changes the scene and would take the test runner down with it, and the
# test ends the clip by emitting its video's own finished signal.
func test_a_cutscene_starts_the_menu_rotation_over():
	var save = PlayerSave.new_game("CutsceneRotation", 0)
	save.autosave = false
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = partial_double(BattleSceneRes).instantiate()
	stub(scene, "_on_continue_pressed").to_do_nothing()
	add_child_autofree(scene)
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 109, "is_story_progress": true, "is_boss": true, "train_cap": 9})
	scene.runner.win_condition = BattleRunner.Outcome.WIN
	await wait_for_signal(scene.battle_finished, 5)
	AudioManagerAuto._rotation_counter = 2
	scene.get_node("VictoryScreen").proceed_pressed.emit()
	scene.get_node("CutscenePlayer").video.finished.emit()
	assert_called(scene, "_on_continue_pressed")
	assert_eq(_hub_menu_track(), "_music_menu1", "the hub comes back on the first menu track")

	# CS_CUT2 ends on the zone map, so this clears the flag its end sets before
	# a later test opens the hub.
	ZoneManager.open_zone_map_on_load = false
	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# The first win of battle 513 queues CS_CUT5 with gotoSceneKrin "endMenu"
# (frame_219/DoAction.as:51-55), and the cutscene's end goes to endMenu, root
# frame 116, without starting any music (frame_263/PlaceObject2_3466_80
# enterFrame, lines 15-19 and 33). Frame 116 fills its text with
# KrinLang.ENGLISH.ENDING (frame_116/DoAction.as:1, frame_1/DoAction.as:2240)
# above the static OK! caption, and only OK! goes on to the hub
# (DefineButton2_2797 on(release), line 2). The scene is a partial double with
# _on_continue_pressed stubbed, because the real one changes the scene and
# takes the test runner down with it.
func test_the_first_513_win_ends_on_the_ending_screen_after_cs_cut5():
	var save = PlayerSave.new_game("EndingFlow", 0)
	save.section_in = 5
	save.quest_progress[5] = 13
	save.autosave = false
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}
	ZoneManager.open_zone_map_on_load = false

	var scene = partial_double(BattleSceneRes).instantiate()
	stub(scene, "_on_continue_pressed").to_do_nothing()
	add_child_autofree(scene)
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 513, "is_story_progress": true, "is_boss": true, "train_cap": BattleSetup.DEFAULT_TRAIN_CAP})
	scene.runner.win_condition = BattleRunner.Outcome.WIN
	await wait_for_signal(scene.battle_finished, 5)
	_proceed_and_play_cs_cut5_to_its_end(scene)

	assert_not_called(scene, "_on_continue_pressed")
	assert_false(ZoneManager.open_zone_map_on_load, "the zone map stays shut")
	assert_eq(AudioManagerAuto._music_mode, AudioManagerAuto.MusicMode.NONE, "no music plays on the ending screen")
	var ending = scene.get_node_or_null("UI/EndingScreen")
	assert_not_null(ending, "the ending screen is up")
	if ending != null:
		assert_true(ending.is_visible_in_tree(), "and showing")
		assert_eq(
			ending.get_node("EndingLabel").text,
			"Congratulations! You've beaten the game. So what now? If you haven't already, I recommend you to try the game on 'Heroic' difficulty, the way that it was designed to be played! Or perhaps pitch your own character against a friend's, using the 'PvP Arena' option. Visit www.ArmorGames.com for more games (including the first chapter of Sonny) and check for updates, in case we add some new Zones for you to play in. Seeya next time!",
			"ENDING"
		)
		assert_eq(ending.get_node("OkLabel").text, "OK!", "static text 2799")
		ending.get_node("OkButton").pressed.emit()
		assert_called(scene, "_on_continue_pressed")

	ZoneManager.open_zone_map_on_load = false
	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# For endMenu the end of CS_CUT5 sets soundPlayCounter and soundModeKrin back
# to 0 and starts no music (frame_263/PlaceObject2_3466_80 enterFrame, lines
# 15-19), so the ending screen is silent and the Navigation frame that OK! opens
# starts the rotation over on its first menu track (frame_181/DoAction.as:15).
# The test plays Sonny's death cry and leaves the rotation on _music_menu2,
# where one menu track and one battle track leave it, before Proceed.
func test_the_ending_screen_stays_silent_and_ok_starts_the_first_menu_track():
	var save = PlayerSave.new_game("EndingSound", 0)
	save.section_in = 5
	save.quest_progress[5] = 13
	save.autosave = false
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = partial_double(BattleSceneRes).instantiate()
	stub(scene, "_on_continue_pressed").to_do_nothing()
	add_child_autofree(scene)
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 513, "is_story_progress": true, "is_boss": true, "train_cap": BattleSetup.DEFAULT_TRAIN_CAP})
	scene.runner.win_condition = BattleRunner.Outcome.WIN
	await wait_for_signal(scene.battle_finished, 5)
	AudioManagerAuto._rotation_counter = 2
	AudioManagerAuto.play_effect(scene.units[BattleRunner.PLAYER_SLOT].voice_die)
	assert_true(_an_effect_is_playing(), "Sonny's death cry is playing when Proceed is pressed")
	_proceed_and_play_cs_cut5_to_its_end(scene)

	var ending = scene.get_node_or_null("UI/EndingScreen")
	assert_not_null(ending, "the ending screen is up")
	assert_eq(AudioManagerAuto._music_mode, AudioManagerAuto.MusicMode.NONE, "no music plays on it")
	assert_false(_an_effect_is_playing(), "and no effect either")
	if ending != null:
		ending.get_node("OkButton").pressed.emit()
	assert_called(scene, "_on_continue_pressed")
	assert_eq(_hub_menu_track(), "_music_menu1", "the hub that OK! opens starts on the first menu track")

	AudioManagerAuto.stop_music()
	ZoneManager.open_zone_map_on_load = false
	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# The original's Proceed can't be pressed twice, because its release always
# leaves the frame of DefineSprite 3142 that the victory screen is drawn on, for
# the cutscene, the map or 3142's skills or hide frame (DefineButton2_3004
# on(release), lines 8-29). The test clicks the port's Proceed the way a player
# does, which leaves the keyboard focus on it, and then presses Enter and Space
# under CS_CUT5 and again under the ending screen.
func test_enter_and_space_after_clicking_proceed_press_nothing_under_the_cutscene_or_the_ending():
	var save = PlayerSave.new_game("ProceedFocus", 0)
	save.section_in = 5
	save.quest_progress[5] = 13
	save.autosave = false
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	# The scene gets a viewport of its own, because GUT's window sits above
	# everything in the root viewport and would take the click.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	add_child_autofree(viewport)
	var scene = partial_double(BattleSceneRes).instantiate()
	stub(scene, "_on_continue_pressed").to_do_nothing()
	viewport.add_child(scene)
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 513, "is_story_progress": true, "is_boss": true, "train_cap": BattleSetup.DEFAULT_TRAIN_CAP})
	scene.runner.win_condition = BattleRunner.Outcome.WIN
	await wait_for_signal(scene.battle_finished, 5)
	var proceed: Button = scene.get_node("VictoryScreen/ProceedButton")
	_click(viewport, proceed)
	assert_eq(get_call_count(scene, "_on_victory_proceed"), 1, "the click pressed Proceed")
	var cutscene: CutscenePlayer = scene.get_node_or_null("CutscenePlayer")
	assert_not_null(cutscene, "CS_CUT5 is playing")
	for key in [KEY_ENTER, KEY_SPACE]:
		_press(viewport, key)
		assert_eq(get_call_count(scene, "_on_victory_proceed"), 1, "%s under the cutscene presses nothing" % OS.get_keycode_string(key))
	if cutscene != null:
		cutscene.video.finished.emit()
	assert_not_null(scene.get_node_or_null("UI/EndingScreen"), "the ending screen is up")
	for key in [KEY_ENTER, KEY_SPACE]:
		_press(viewport, key)
		assert_eq(get_call_count(scene, "_on_victory_proceed"), 1, "%s under the ending screen presses nothing" % OS.get_keycode_string(key))
	assert_not_called(scene, "_on_continue_pressed")

	ZoneManager.open_zone_map_on_load = false
	GameData.current_save = null
	ZoneManager.auto_start_battles = true


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


# Presses Proceed on the victory screen and has CS_CUT5 report that it ended,
# which with animation_speed 0 runs the rest of _on_victory_proceed() at once.
func _proceed_and_play_cs_cut5_to_its_end(scene: Control) -> void:
	var victory: VictoryScreen = scene.get_node_or_null("VictoryScreen")
	assert_not_null(victory, "victory screen shown on win")
	if victory == null:
		return
	victory.proceed_pressed.emit()
	var cutscene: CutscenePlayer = scene.get_node_or_null("CutscenePlayer")
	assert_not_null(cutscene, "CS_CUT5 plays after Proceed")
	if cutscene == null:
		return
	assert_eq(cutscene.video.stream.resource_path, "res://assets/cutscenes/CS_CUT5.ogv")
	cutscene.video.finished.emit()


# The TUNNELS story orb compares the first fight at 409 against progressMax1,
# which questHub never defines, so bossFight stays false (DefineButton2_3239
# on(press), line 14) and addSound("Music", 2) plays the rotation's next track
# instead of _music_boss (frame_42/DoAction.as:55-77). A replay of the beaten
# zone sets bossFight at line 11, so the Hydra at 408 gets _music_boss.
func test_the_first_409_fight_plays_the_rotation_track_and_the_replay_the_boss_track():
	var save = PlayerSave.new_game("TunnelsMusic", 0)
	save.section_in = 4
	GameData.current_save = save
	var previous_zone: int = ZoneManager.current_zone
	ZoneManager.current_zone = 4
	ZoneManager.auto_start_battles = false
	for progress in [9, 10]:
		save.quest_progress[4] = progress
		AudioManagerAuto.stop_music()
		var cue: String = "_music_boss" if progress == 10 else AudioManagerAuto.MUSIC_ROTATION[AudioManagerAuto._rotation_counter]
		var info: Dictionary = ZoneManager.request_story_fight()
		ZoneManager.pending_battle = {}
		assert_eq(info.get("battle_id"), 409 if progress == 9 else 408, "the orb's pick at progress %d" % progress)
		var scene = add_child_autofree(BattleSceneRes.instantiate())
		scene.animation_speed = 0.0
		scene.start_battle(info)
		var music: AudioStreamPlayer = AudioManagerAuto._music_players[AudioManagerAuto._active_music]
		assert_eq(music.stream.resource_path, "res://assets/audio/%s.mp3" % cue, "battle %d's track" % info.get("battle_id"))

	AudioManagerAuto.stop_music()
	ZoneManager.current_zone = previous_zone
	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# The victory screen shows the battle's settlement. Training fight 1000 has only
# the -2 marker, so with Roald joined and deployed second, Veradux fights it
# and Roald doesn't, and the screen has rows for Sonny and Veradux alone. The
# win pays 7, round(0.7 * respecValue(1)), Sonny's XP is expWorkOut(1, 1), 90,
# and the battle's one drop is a pull from its rare pool. The win is set before
# the battle loop starts, so no fight is played.
func test_the_victory_screen_shows_the_battles_settlement():
	var save = PlayerSave.new_game("VictorySettlement", 0)
	save.party_roster = [0, 1, 2, -1, -1, -1]
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 1000, "is_story_progress": false, "is_boss": false, "train_cap": 9})
	scene.runner.win_condition = BattleRunner.Outcome.WIN
	await wait_for_signal(scene.battle_finished, 5)
	var victory: VictoryScreen = scene.get_node_or_null("VictoryScreen")
	assert_not_null(victory, "the win shows the victory screen")
	if victory != null:
		assert_eq(victory.get_node("MoneyValue").text, String.chr(0x20ac) + "7", "with the money the win paid")
		assert_eq(victory.get_node("ExpValue").text, "90%", "the XP Sonny earned")
		var drop_slots: Array = victory.get_children().filter(func(child): return child is ItemSlot)
		var rare_pool: Array = [300, 301, 302, 303, 304, 500]
		assert_eq(drop_slots.map(func(slot): return slot.item != null and slot.item.id in rare_pool), [true], "the drop")
		var rows: Array = victory.get_children().filter(func(child): return child is VictoryExperienceRow)
		assert_eq(rows.map(func(row): return row.name_label.text), ["Sonny", "Veradux"], "and rows for Sonny and Veradux alone")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# A win's achievements go to ZoneManager.achievements_path, which this file
# points at a file of its own, so a first win of 109 unlocks The Tape there.
func test_a_win_unlocks_into_zone_managers_achievements_file():
	if FileAccess.file_exists(ACHIEVEMENTS_FILE):
		DirAccess.remove_absolute(ACHIEVEMENTS_FILE)
	var save = PlayerSave.new_game("SceneTape", 0)
	save.quest_progress[1] = 9
	save.autosave = false
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 109, "is_story_progress": true, "is_boss": true, "train_cap": 9})
	scene.runner.win_condition = BattleRunner.Outcome.WIN
	await wait_for_signal(scene.battle_finished, 5)
	assert_true(Achievements.load_unlocked(ACHIEVEMENTS_FILE)[0], "The Tape is in ZoneManager's file")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# The original has no turn label. A win leaves its battle frame for Navigation
# (frame_219/DoAction.as:78-81), where KRINMENU draws the victory screen
# (frame_181/PlaceObject3_3142_175 onClipEvent(load), lines 3-7), so nothing is
# written across the top of that screen. The win is set while the battle waits
# on the player, which is when the turn label reads "Your move".
func test_the_victory_screen_shows_no_turn_label():
	GameData.current_save = PlayerSave.new_game("VictoryTurnLabel", 0)
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": false, "is_boss": false, "train_cap": 9})
	await wait_until(func(): return scene.decision_open, 5)
	assert_eq(scene.turn_label.text, "Your move", "the battle is waiting on the player")
	scene.runner.win_condition = BattleRunner.Outcome.WIN
	scene._on_pass_pressed()
	await wait_for_signal(scene.battle_finished, 5)
	assert_not_null(scene.get_node_or_null("VictoryScreen"), "the win shows the victory screen")
	assert_false(scene.turn_label.is_visible_in_tree(), "with no turn label over it")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# Battle 100 with its outcome set before the battle loop starts, so the loop
# goes straight to _finish_battle() and no fight is played.
func _finish_battle_100_with(outcome: BattleRunner.Outcome) -> Control:
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}
	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": false, "is_boss": false, "train_cap": 9})
	scene.runner.win_condition = outcome
	await wait_for_signal(scene.battle_finished, 5)
	ZoneManager.auto_start_battles = true
	return scene


# The original's end clip sends a draw to loseCombat as well
# (DefineSprite_3355/frame_85/DoAction.as:5-16, frame_241/DoAction.as:1), and
# loseCombat resets the game and opens gameOverMenu, root frame 104
# (frame_230/DoAction.as:1-5, frame_43/DoAction.as:21-25). Frame 104 fills its
# texts from KrinLang.ENGLISH (frame_104/DoAction.as:1-3, with the strings at
# frame_1/DoAction.as:258-259 and 2239), and its Back caption shows MENU[26]
# (frame_46/DoAction.as:1, frame_1/DoAction.as:234). The reset also runs
# stopAllSounds() (frame_41/DoAction_2.as:13).
func _assert_game_over_screen(scene: Control) -> void:
	assert_null(scene.get_node_or_null("VictoryScreen"), "no victory screen")
	var texts: Array = scene.find_children("*", "Label", true, false).map(func(label): return label.text)
	assert_false("Defeat..." in texts or "Draw." in texts, "the port's old result text is gone")
	assert_eq(AudioManagerAuto._music_mode, AudioManagerAuto.MusicMode.NONE, "the music stops")
	var game_over = scene.get_node_or_null("UI/GameOverScreen")
	assert_not_null(game_over, "the game over screen is up")
	if game_over == null:
		return
	assert_true(game_over.is_visible_in_tree(), "and showing")
	assert_eq(game_over.get_node("DeadLabel").text, "You're dead, Sonny...", "MENU[50]")
	assert_eq(game_over.get_node("ReloadLabel").text, "< Click here to Re-Load >", "MENU[51] between angle brackets")
	assert_eq(
		game_over.get_node("TipLabel").text,
		"Having problems winning a fight? Observe your enemies carefully and try to find a weakness. Being victorious in Sonny is about having a successful strategy, so you may need to re-evaluate your ability configuration and execution. If you want guides on how to beat a specific stage, I recommend you to check out the ArmorGames or KrinLabs forums for some help.",
		"GOTIP[0]"
	)
	assert_eq(game_over.get_node("BackLabel").text, "Back", "MENU[26]")


func test_a_loss_ends_the_game_on_the_game_over_screen():
	GameData.current_save = PlayerSave.new_game("LossFlow", 0)
	var scene = await _finish_battle_100_with(BattleRunner.Outcome.LOSS)
	_assert_game_over_screen(scene)
	GameData.current_save = null


func test_a_draw_ends_the_game_on_the_game_over_screen():
	GameData.current_save = PlayerSave.new_game("DrawFlow", 0)
	var scene = await _finish_battle_100_with(BattleRunner.Outcome.DRAW)
	_assert_game_over_screen(scene)
	GameData.current_save = null


const SWF_FRAME_SECONDS: float = 1.0 / 30.0


# Battle 100 decided as `outcome` before its loop has run, then finished the way
# the loop finishes it once the runner is over. The fade runs at full speed, and
# its tween is paused before its first step so each test steps it itself.
func _decide_battle_100(outcome: BattleRunner.Outcome) -> Control:
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}
	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": false, "is_boss": false, "train_cap": 9})
	scene.runner.win_condition = outcome
	scene.animation_speed = 1.0
	scene._finish_battle()
	var fade: Tween = scene.get("_fade_tween")
	if fade != null:
		fade.pause()
	ZoneManager.auto_start_battles = true
	return scene


# Once winCondition is set, the conductor plays blacker5, DefineSprite 3355, on
# from the stop() on its frame 31 (frame_217/PlaceObject2_3389_480 enterFrame,
# lines 257-261, and DefineSprite_3355/frame_31/DoAction.as). Its frames 32 to 82
# fade black shape 333 in, and its frame 85 takes the shape away and sends the
# result (DefineSprite_3355/frame_85/DoAction.as:5-16), 54 frames or 1.8 s after
# the battle was decided. Each step ends halfway through a frame, so a check reads
# the alpha the SWF gives that frame.
func _assert_fades_to_black_before(scene: Control, screen_path: String) -> void:
	var fade: Tween = scene.get("_fade_tween")
	assert_not_null(fade, "the decided battle starts a fade")
	if fade == null:
		return
	var black: ColorRect = scene.get_node("Fade/Black")
	fade.custom_step(SWF_FRAME_SECONDS * 0.5)
	assert_eq(black.color.a, 0.0, "frame 31 shows no black")
	fade.custom_step(SWF_FRAME_SECONDS * 2.0)
	assert_eq(black.color.a, 10.0 / 256.0, "frame 33 shows the first black")
	fade.custom_step(SWF_FRAME_SECONDS * 49.0)
	assert_eq(black.color.a, 1.0, "frame 82 is full black")
	fade.custom_step(SWF_FRAME_SECONDS * 2.0)
	assert_eq(black.color.a, 1.0, "and frame 84 still is")
	assert_null(scene.get_node_or_null(screen_path), "with no result screen up yet")
	fade.custom_step(SWF_FRAME_SECONDS)
	assert_not_null(scene.get_node_or_null(screen_path), "frame 85 shows the result screen")
	assert_eq(black.color.a, 0.0, "and takes the black away")


# The original pays a win on winCombat and on the victory screen's own frame, and
# both come after blacker5's frame 85 (frame_219/DoAction.as and
# DefineSprite_3142/frame_9).
func test_a_win_fades_to_black_before_the_victory_screen():
	var save = PlayerSave.new_game("FadeWin", 0)
	GameData.current_save = save
	var euro: float = save.euro
	var scene = _decide_battle_100(BattleRunner.Outcome.WIN)
	assert_eq(save.euro, euro, "the win pays nothing when the fade starts")
	_assert_fades_to_black_before(scene, "VictoryScreen")
	assert_gt(save.euro, euro, "and pays once the victory screen is up")
	GameData.current_save = null


func test_a_loss_fades_to_black_before_the_game_over_screen():
	GameData.current_save = PlayerSave.new_game("FadeLoss", 0)
	var scene = _decide_battle_100(BattleRunner.Outcome.LOSS)
	_assert_fades_to_black_before(scene, "UI/GameOverScreen")
	GameData.current_save = null


func test_a_draw_fades_to_black_before_the_game_over_screen():
	GameData.current_save = PlayerSave.new_game("FadeDraw", 0)
	var scene = _decide_battle_100(BattleRunner.Outcome.DRAW)
	_assert_fades_to_black_before(scene, "UI/GameOverScreen")
	GameData.current_save = null


# The battle frame opens on blacker5's frame 1, and its frames 1 to 28 fade black
# shape 333 out before the stop() on its frame 31, so every battle fades in from
# black. The clip sits on the battle frame's top depth, and the shape covers the
# whole stage.
func test_a_battle_fades_in_from_black():
	GameData.current_save = PlayerSave.new_game("FadeIn", 0)
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}
	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.start_battle({"battle_id": 100, "is_story_progress": false, "is_boss": false, "train_cap": 9})
	var fade: Tween = scene.get("_fade_tween")
	assert_not_null(fade, "the battle starts a fade")
	if fade != null:
		fade.pause()
		var black: ColorRect = scene.get_node("Fade/Black")
		assert_eq(black.color, Color.BLACK, "the battle opens on full black")
		assert_eq(black.get_global_rect(), scene.get_viewport_rect(), "over the whole window")
		assert_gt(scene.get_node("Fade").layer, scene.get_node("UI").layer, "and over the turn and speech labels")
		fade.custom_step(SWF_FRAME_SECONDS * 27.5)
		assert_eq(black.color.a, 1.0 / 256.0, "frame 28 shows the last black")
		fade.custom_step(SWF_FRAME_SECONDS)
		assert_eq(black.color.a, 0.0, "and frame 29 none")
	ZoneManager.auto_start_battles = true
	GameData.current_save = null


# The reset that runs before gameOverMenu calls stopAllSounds()
# (frame_41/DoAction_2.as:13), which stops the effects as well as the music. The
# loss is set before the battle loop starts, so no fight is played and the test
# plays Sonny's death cry itself.
func test_the_game_over_screen_stops_sound_effects_too():
	GameData.current_save = PlayerSave.new_game("LossEffects", 0)
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": false, "is_boss": false, "train_cap": 9})
	scene.runner.win_condition = BattleRunner.Outcome.LOSS
	AudioManagerAuto.play_effect(scene.units[BattleRunner.PLAYER_SLOT].voice_die)
	assert_true(_an_effect_is_playing(), "Sonny's death cry is playing when the battle ends")
	await wait_for_signal(scene.battle_finished, 5)
	assert_not_null(scene.get_node_or_null("UI/GameOverScreen"), "the loss shows the game over screen")
	assert_false(_an_effect_is_playing(), "and no effect plays on over it")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# The reset before gameOverMenu also sets soundPlayCounter and soundModeKrin back
# to 0 (frame_41/DoAction_2.as:12-14), so the hub that Re-Load opens starts the
# rotation over on its first menu track (frame_181/DoAction.as:15). The test
# leaves the rotation on _music_menu2, where one menu track and one battle track
# leave it.
func test_the_game_over_screen_starts_the_menu_rotation_over():
	GameData.current_save = PlayerSave.new_game("LossRotation", 0)
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": false, "is_boss": false, "train_cap": 9})
	scene.runner.win_condition = BattleRunner.Outcome.LOSS
	AudioManagerAuto._rotation_counter = 2
	await wait_for_signal(scene.battle_finished, 5)
	assert_not_null(scene.get_node_or_null("UI/GameOverScreen"), "the loss shows the game over screen")
	assert_eq(_hub_menu_track(), "_music_menu1", "and the hub Re-Load opens starts on the first menu track")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# Re-Load has to read the slot back from disk. The test saves a slot holding
# 100 euro in a folder of its own, loads it the way the main menu does, then
# sets the euro in memory to 999. Loading the slot again through Godot's
# resource cache would hand back that same PlayerSave, 999 euro and all.
func test_reload_brings_back_the_last_save():
	GameData.save_dir = TEST_SAVE_DIR
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)
	GameData.new_game(1, "ReloadFlow")
	GameData.current_save.euro = 100.0
	assert_true(GameData.save_game(), "the test slot was written")
	assert_true(GameData.load_game(1), "and loaded back")
	GameData.current_save.euro = 999.0

	var scene = await _finish_battle_100_with(BattleRunner.Outcome.LOSS)
	var game_over = scene.get_node_or_null("UI/GameOverScreen")
	assert_not_null(game_over, "the loss shows the game over screen")
	if game_over != null:
		assert_eq(game_over.reload_last_save(), "res://scenes/game.tscn", "a saved slot reloads into the hub")
		assert_eq(GameData.current_slot, 1, "the same slot")
		assert_eq(GameData.current_save.euro, 100.0, "the saved euro, not the 999 spent since")

	GameData.current_save = null
	GameData.current_slot = -1
	DirAccess.remove_absolute(TEST_SAVE_DIR + "slot1.tres")
	DirAccess.remove_absolute(TEST_SAVE_DIR)
	GameData.save_dir = GameData.SAVE_DIR


# The debug battle's throwaway save sits in slot -1, which save_game() never
# writes, so Re-Load finds no save there and goes to the main menu, the way the
# original does for an empty slot (DefineButton2_2791 on(release), lines 9-12).
func test_reload_without_a_save_goes_to_the_main_menu():
	GameData.new_game(-1, "Debug")
	var scene = await _finish_battle_100_with(BattleRunner.Outcome.LOSS)
	var game_over = scene.get_node_or_null("UI/GameOverScreen")
	assert_not_null(game_over, "the loss shows the game over screen")
	if game_over != null:
		assert_eq(game_over.reload_last_save(), "res://scenes/main_menu.tscn", "no save, so the main menu")
	GameData.current_save = null


# RadialMenu's own tests cover the menu. This is the scene's half of it, through
# real clicks: a unit's hit button opens the menu and a pick reaches the runner.
# Orb 0's centre sits inside that same hit button, so the pick only lands while
# the menu is above the overlays in the tree.
func test_clicking_a_unit_then_an_orb_runs_that_move():
	GameData.current_save = PlayerSave.new_game("MenuWiring", 0)
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	# GUT's window sits above everything in the root viewport and would take
	# the clicks, so the scene gets a viewport of its own.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	add_child_autofree(viewport)
	var scene = BattleSceneRes.instantiate()
	viewport.add_child(scene)
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	await wait_until(func(): return scene.decision_open, 5)
	var player: CombatUnit = scene.units[BattleRunner.PLAYER_SLOT]
	var first_event: int = scene.runner.events.size()

	var hit_button: Button = scene._presenters[2].hit_area
	_click(viewport, hit_button)
	assert_true(scene.radial_menu.visible, "clicking the enemy opened the menu")
	var orb: Button = scene.radial_menu.orbs[0]
	assert_true(hit_button.get_global_rect().has_point(orb.get_global_rect().get_center()), "sanity: the orb overlaps the hit button")
	_click(viewport, orb)
	assert_false(scene.decision_open, "the click on the orb ended the decision")
	assert_false(scene.radial_menu.visible, "and closed the menu")

	await wait_until(func(): return scene.runner.events.size() > first_event, 5)
	var player_moves: Array = scene.runner.events.slice(first_event).filter(
		func(event): return event["type"] == BattleRunner.EventType.MOVE and int(event["caster_slot"]) == BattleRunner.PLAYER_SLOT
	)
	assert_eq(player_moves.size(), 1, "the player's half-turn ran one move")
	if player_moves.size() == 1:
		assert_eq(int(player_moves[0]["move_id"]), int(player.equipped_moves[0]), "the move on the picked orb")
		assert_eq(int(player_moves[0]["target_slot"]), 2, "on the clicked unit")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# The retreat button is the original's battle Quit button,
# DefineButton2_3356, which shows SYSTEM[25] over SYSTEM[26]
# (frame_1/DoAction.as:92-93) in place of a native tooltip.
func test_the_retreat_button_shows_the_original_quit_tooltip():
	var save = PlayerSave.new_game("QuitTooltipTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	var retreat: Button = scene.get_node("BottomBar/RetreatButton")
	assert_eq(retreat.tooltip_text, "", "no native tooltip")
	retreat.mouse_entered.emit()
	var texts: Array = []
	if GameTooltip._root.visible:
		for section in GameTooltip._sections.get_children():
			for label in section.get_child(0).get_children():
				texts.append(label.text)
	assert_eq(texts, ["Quit", "Click here to exit. Warning! All unsaved progress will be lost!"])
	retreat.mouse_exited.emit()
	assert_false(GameTooltip._root.visible, "leaving the button hides it")

	GameTooltip.hide_tooltip()
	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# A heal bigger than an sswitch target's life kills it, and the original plays
# the death at that impact (frame_42/DoAction_8.as:208-228). The runner logs a
# killing blow as the MOVE whose result killed, then a DEATH caused by the move,
# and _play_events() only pauses on that DEATH, leaving the death itself to
# FighterPresenter.show_result().
func test_heal_that_kills_an_sswitch_target_plays_the_death():
	var save = PlayerSave.new_game("RetrogradeKill", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	var caster: CombatUnit = scene.units[1]
	var target_slot := 2  # battle 100's Prison Guard
	scene.units[target_slot].life_n = 1.0
	scene._refresh_bars()
	var killing_heal: MoveResult = _move_result(MoveResult.Kind.HEAL, MoveResult.Direction.HARM, 37.0)
	killing_heal.life_before = 1.0
	killing_heal.killed = true

	await scene._play_events([
		{"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": target_slot,
			"move_id": 4, "move_name": "Heal", "result": killing_heal},
		{"type": BattleRunner.EventType.DEATH, "slot": target_slot, "cause": BattleRunner.DeathCause.MOVE},
	])

	var presenter: FighterPresenter = scene._presenters[target_slot]
	assert_eq(presenter.get_node("Doll")._state, CharacterVisual.State.DEAD, "the heal killed the target, so its doll plays the death")
	assert_false(presenter.get_node("Overlay").visible, "its overlay is hidden with it")
	assert_eq(presenter.displayed_hp, 0.0, "the bar drops to empty")
	assert_eq(
		scene._combat_log._log_text.text,
		"%s hits Prison Guard with Heal for 37\nPrison Guard falls" % caster.player_name,
		"the log calls the heal a hit, then the fall"
	)

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func test_decision_timer_ticks_down_while_player_is_deciding():
	var save = PlayerSave.new_game("TimerTest", 0)
	save.difficulty = CombatUnit.Difficulty.HARD
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	scene.decision_open = true
	scene._reset_decision_timer()
	assert_eq(scene._decision_timer, 4.0, "resets to 120 frames at the SWF's 30 fps")

	scene._process(1.5)
	assert_almost_eq(scene._decision_timer, 2.5, 0.001)

	scene._process(9999.0)
	assert_eq(scene._decision_timer, 0.0, "clamps at 0, never goes negative")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func test_decision_timer_does_not_tick_while_the_decision_is_closed():
	var save = PlayerSave.new_game("TimerTest2", 0)
	save.difficulty = CombatUnit.Difficulty.HARD
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	scene.decision_open = false
	scene._decision_timer = 2.0
	scene._process(10.0)
	assert_eq(scene._decision_timer, 2.0, "doesn't tick during an AI turn")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# On Heroic the original's conductor adds 1 to BattleTimeNow every frame while
# the player's team decides, and starts the half-turn when it reaches
# BattleTimeLimit whether or not the player picked
# (frame_217/PlaceObject2_3389_480 enterFrame, lines 593-596 and 769-792).
# BattleTimeLimit is 120 (frame_217/DoAction.as:2) and the SWF runs at 30 fps,
# so the window is 4 seconds. The player's slot still holds the pass that every
# dispatch leaves behind (lines 470-473), so running out is a pass.
func test_heroic_decision_passes_the_turn_when_the_window_runs_out():
	var save = PlayerSave.new_game("HeroicWindow", 0)
	save.difficulty = CombatUnit.Difficulty.HARD
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	# The test steps _process by hand, so the time the engine spends loading the
	# battle never counts against the window.
	scene.set_process(false)
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	await wait_until(func(): return scene.decision_open, 5)
	var turn: int = scene.runner.turn_count
	var first_event: int = scene.runner.events.size()

	scene._process(3.9)
	assert_true(scene.decision_open, "the player can still pick just before 4 seconds")
	scene._process(0.2)
	assert_false(scene.decision_open, "4 seconds without a pick ends the decision")

	await wait_until(func(): return scene.runner.turn_count > turn, 5)
	assert_gt(scene.runner.turn_count, turn, "the player's half-turn ran")
	var player_events: Array = scene.runner.events.slice(first_event).filter(
		func(event): return event["turn"] == turn and int(event.get("caster_slot", 0)) == BattleRunner.PLAYER_SLOT
	)
	assert_eq(player_events, [], "the player passed")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# Easy and Normal set turnBasedKrin (frame_201/DoAction.as:65-79). There the
# conductor holds the clock just under the limit until the player picks (lines
# 639-642), so the decision never runs out and the clock never moves.
func test_normal_decision_waits_for_the_player_with_no_countdown():
	var save = PlayerSave.new_game("NormalWindow", 0)
	save.difficulty = CombatUnit.Difficulty.NORMAL
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	await wait_until(func(): return scene.decision_open, 5)
	var time_left: float = scene._decision_timer

	for second in 10:
		scene._process(1.0)
	assert_true(scene.decision_open, "10 seconds without a pick still waits for the player")
	assert_eq(scene._decision_timer, time_left, "nothing counts down")
	assert_false(scene._countdown_label.visible, "Normal shows no countdown")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# The conductor sets turnBasedKrin at the end of any half-turn that finds the
# player's unit dead (lines 200-202) and nothing clears it, so on Heroic the
# clock stops for the rest of the battle.
func test_heroic_countdown_stops_once_the_player_is_dead():
	var save = PlayerSave.new_game("HeroicDeath", 0)
	save.difficulty = CombatUnit.Difficulty.HARD
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	# Real frames must not run the 4 second window out before the test kills the
	# player, so the test steps _process by hand here too.
	scene.set_process(false)
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	await wait_until(func(): return scene.decision_open, 5)
	scene._process(0.0)
	assert_true(scene._countdown_label.visible, "Heroic shows the countdown while the player is alive")

	var player: CombatUnit = scene.units[BattleRunner.PLAYER_SLOT]
	player.life_n = 0.0
	player.active = false
	scene._on_pass_pressed()
	var finished: bool = await wait_for_signal(scene.battle_finished, 30)
	assert_true(finished, "the rest of the battle never waits on the dead player")
	scene._process(0.0)
	assert_false(scene._countdown_label.visible, "the countdown is gone for the rest of the battle")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# Battle 600 runs the CHURCH hall under the ROME sky. The sky is a horizon
# strip whose bottom sits on the ground line, and the layout JSON says that
# line is y = 306.0 for ROME - not the 292.0 the old constant used.
func test_sky_is_placed_from_the_layout_json():
	var save = PlayerSave.new_game("SkyRectTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 600, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	assert_almost_eq(scene.sky.position.y + scene.sky.size.y, 306.0, 0.5,
		"sky bottom sits where the SWF puts it")
	assert_almost_eq(scene.sky.size.y, 176.0, 0.5, "sky strip height from the JSON")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# The fill covers everything above the sky strip, so it has to be opaque. The
# sky art cannot supply that colour: the SWF renders are trimmed to their own
# soft top edge, so five of the nine skies read alpha 0 at row 0 centre. Battle
# 201 runs the SNOW sky, one of the five.
func test_sky_fill_is_opaque_over_a_sky_whose_top_row_is_transparent():
	var art: Image = load("res://assets/backgrounds/sky/SKY_SNOW.png").get_image()
	assert_eq(art.get_pixel(int(art.get_width() / 2.0), 0).a, 0.0,
		"SNOW's top row centre is transparent, which is what broke the old fill")

	var save = PlayerSave.new_game("SkyFillTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 201, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	assert_eq(scene.sky_fill.color.a, 1.0, "the fill above the strip is opaque")
	assert_eq(scene.sky_fill.color, Color.BLACK, "and is the black the original paints there")
	assert_gt(scene.sky_fill.size.y, 0.0, "the fill actually covers something")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# DefineSprite 3312 places "p5" above "p3" (y 12.60 vs y 50.10), matching the
# battlefield where slot 5 is the upper fighter and slot 3 the lower one
# (SLOT_POSITIONS). Battle 100 (resources/battles/100_KBR100.tres) deploys a
# companion into both: players[1].id == -2 fills slot 3 and players[3].id ==
# -1 fills slot 5. A fresh save only has Veradux (party id 1) in the roster,
# so Roald (party id 2) is added here the way update_roster_after_battle would
# once zone 2's story clears, to get a companion into both slots at once.
func test_stance_rows_stack_with_slot_5_on_top():
	var save = PlayerSave.new_game("StanceOrderTest", 0)
	save.party_roster = [0, 1, 2, -1, -1, -1]
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	assert_eq(scene.units[3].player_name, "Veradux", "battle 100 deploys Veradux into slot 3")
	assert_eq(scene.units[5].player_name, "Roald", "battle 100 deploys Roald into slot 5")

	var slot3_row: StanceRow = null
	var slot5_row: StanceRow = null
	for child in scene.stance_host.get_children():
		if child is StanceRow:
			if child.name_label.text == "Veradux":
				slot3_row = child
			elif child.name_label.text == "Roald":
				slot5_row = child
	assert_not_null(slot3_row, "slot 3's row (Veradux) was built")
	assert_not_null(slot5_row, "slot 5's row (Roald) was built")
	assert_lt(slot5_row.position.y, slot3_row.position.y,
		"slot 5's row sits above slot 3's row, matching the SWF's p5/p3 stack")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# Battle 508 places unit template 71, whose name is Felicity, on the player's
# team in slot 3, while the save's companion Felicity (party id 3) hasn't joined.
# The port used to give that guest the companion's stance row by matching the
# name.
func test_a_guest_with_a_companions_name_gets_no_stance_row():
	var save = PlayerSave.new_game("GuestRowTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 508, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	assert_eq(scene.units[3].player_name, "Felicity", "battle 508 fields Felicity in slot 3")
	assert_eq(scene.stance_host.get_children().filter(func(child): return child is StanceRow), [], "the guest gets no stance row")
	assert_true(scene._stance_rows.is_empty(), "and nothing keeps a row for the guest")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func test_a_deployed_companion_gets_the_row_the_guest_does_not():
	var save = PlayerSave.new_game("CompanionRowTest", 0)
	save.party_roster = [0, 1, 2, 3, -1, -1]
	save.party_deployed = [3, 1]
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	var row: StanceRow = scene._stance_rows[3]
	assert_eq(row.name_label.text, "Felicity", "party id 3's row carries the name Felicity")
	row.buttons[Party.AggressionStance.RELENTLESS].pressed.emit()
	assert_eq(scene.units[3].aggression, 90.0, "the press puts slot 3's Felicity on Relentless")
	assert_eq(scene.units[5].aggression, 50.0, "and leaves slot 5's Veradux on Tactical")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# The original builds each companion fresh at the start of every battle on
# Tactical, with agMode 2 (frame_42/DoAction_14.as:208-213). Its stance button
# writes only that battle's unit (DefineButton2_3289 on(press), lines 9-14),
# and the stance row highlights that unit's agMode (setAG, lines 12-14 of both
# copies in DefineSprite 3312). So a pick retunes the companion at once and is
# gone by the next battle. The expected numbers are columns 3 (Aggressive) and
# 2 (Tactical) of agModeAr1 to agModeAr5 (frame_42/DoAction_12.as:2-6), and
# party id 1 is Veradux.
func test_a_stance_pick_does_not_carry_into_the_next_battle():
	var save = PlayerSave.new_game("StanceResetTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}
	var info := {"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9}

	var first = add_child_autofree(BattleSceneRes.instantiate())
	first.animation_speed = 0.0
	first.start_battle(info)
	var veradux: CombatUnit = first.units[3]
	assert_eq(veradux.player_name, "Veradux", "battle 100 deploys Veradux into slot 3")
	var row: StanceRow = first._stance_rows[1]
	row.buttons[Party.AggressionStance.AGGRESSIVE].pressed.emit()
	assert_eq(
		[veradux.aggression, veradux.life_boundary_1, veradux.life_boundary_2,
			veradux.focus_aggression, veradux.focus_regen_limit],
		[70.0, 40.0, 15.0, 15.0, 5.0], "the press puts Veradux on Aggressive at once")
	assert_eq(row.buttons[Party.AggressionStance.AGGRESSIVE].get_node("Cover").texture.resource_path,
		StanceRow.COVER_SELECTED, "the row highlights Aggressive")

	var second = add_child_autofree(BattleSceneRes.instantiate())
	second.animation_speed = 0.0
	second.start_battle(info)
	veradux = second.units[3]
	assert_eq(
		[veradux.aggression, veradux.life_boundary_1, veradux.life_boundary_2,
			veradux.focus_aggression, veradux.focus_regen_limit],
		[50.0, 75.0, 35.0, 70.0, 30.0], "Veradux starts the next battle on Tactical")
	row = second._stance_rows[1]
	assert_eq(row.buttons[Party.AggressionStance.TACTICAL].get_node("Cover").texture.resource_path,
		StanceRow.COVER_SELECTED, "the next battle's row highlights Tactical")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# Battle 600 is one of the five zone-6 fights the original runs in the CHURCH
# hall under the ROME sky (Krin.ZoneBG and Krin.SkyBG are separate fields, and
# 16 of the 99 battles set them to different labels). Deriving the sky from the
# hall name would load SKY_CHURCH here.
func test_sky_comes_from_sky_background_not_the_hall_name():
	var battle: BattleFight = load("res://resources/battles/600_KBR600.tres")
	assert_eq(battle.zone_background, "CHURCH", "fixture still has the mismatched pair")
	assert_eq(battle.sky_background, "ROME")

	var save = PlayerSave.new_game("SkyTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 600, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	assert_eq(
		scene.background.texture.resource_path,
		"res://assets/backgrounds/battle/CHURCH.png",
		"hall comes from zone_background"
	)
	assert_eq(
		scene.sky.texture.resource_path,
		"res://assets/backgrounds/sky/SKY_ROME.png",
		"sky comes from sky_background, not from the hall"
	)

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func test_bottom_bar_uses_extracted_backdrop_art():
	var save = PlayerSave.new_game("BackdropTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	var backdrop: TextureRect = scene.get_node("BottomBar/Backdrop")
	assert_not_null(backdrop, "Backdrop is a TextureRect now")
	assert_eq(
		backdrop.texture.resource_path, "res://assets/ui/battle/hotbar_background.png",
		"backdrop uses the extracted art"
	)

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# FighterPresenter's own tests cover the ring. This is the scene's half of it:
# the mouse reaches a fighter through its hit button, and the ring only comes up
# while a Decision is open. The level label comes and goes with the ring, and
# reading it means the test doesn't have to wait out a fade.
func test_hovering_a_fighter_shows_its_ring_only_during_a_decision():
	GameData.current_save = PlayerSave.new_game("RingGate", 0)
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	var presenter: FighterPresenter = scene._presenters[2]  # battle 100's Prison Guard
	var levels_shown: Callable = func() -> int:
		return presenter.get_node("Overlay").get_children().filter(func(child):
			return child is Label and child.text.begins_with("Lvl.") and not child.is_queued_for_deletion()
		).size()

	scene.decision_open = false
	presenter.hit_area.mouse_entered.emit()
	assert_eq(levels_shown.call(), 0, "nothing shows outside a Decision")

	scene.decision_open = true
	presenter.hit_area.mouse_entered.emit()
	assert_eq(levels_shown.call(), 1, "it shows during one")
	presenter.hit_area.mouse_exited.emit()
	assert_eq(levels_shown.call(), 0, "leaving during the Decision takes it away")

	presenter.hit_area.mouse_entered.emit()
	assert_eq(levels_shown.call(), 1, "sanity: it is back up")
	scene.decision_open = false
	presenter.hit_area.mouse_exited.emit()
	assert_eq(levels_shown.call(), 0, "and leaving takes it away after the Decision has closed too")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# The runner applies the whole half-turn before the replay, so every fighter's
# focus and buffs are already true when the first hit lands. The scene shows
# them at every impact and after every event, on every fighter and not just the
# one that was hit.
func test_an_impact_and_each_event_redraw_every_fighter():
	GameData.current_save = PlayerSave.new_game("AllSlotsRedraw", 0)
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	var bystander: CombatUnit = scene.units[BattleRunner.PLAYER_SLOT]
	var overlay: UnitOverlay = scene._presenters[BattleRunner.PLAYER_SLOT].get_node("Overlay")

	bystander.focus_n = 1.0
	scene._show_move_result(
		{"type": BattleRunner.EventType.MOVE, "caster_slot": 2, "target_slot": 3, "move_id": 1,
			"result": _move_result(MoveResult.Kind.MISS, MoveResult.Direction.NONE, 0.0)},
		3
	)
	assert_eq(overlay.focus_bar.value, 1.0, "an impact on someone else redraws this fighter")

	bystander.focus_n = 2.0
	await scene._play_events([{"type": BattleRunner.EventType.DISPEL, "caster_slot": 2, "target_slot": 3, "removed": []}])
	assert_eq(overlay.focus_bar.value, 2.0, "and so does any other event")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# A stun that a later hit lands is already on its target when the replay
# starts, but the doll takes it at the hit that lands it, the way the original's
# applyChangesKrin does after that strike, and keeps it once the hit's flinch
# has played.
func test_a_stun_starts_at_the_hit_that_lands_it_and_outlasts_its_flinch():
	GameData.current_save = PlayerSave.new_game("StunAtItsHit", 0)
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	var doll: CharacterVisual = scene._presenters[2].get_node("Doll")
	scene.units[2].stun = 1.0

	await scene._play_events([{"type": BattleRunner.EventType.DISPEL, "caster_slot": 1, "target_slot": 3, "removed": []}])
	assert_ne(doll._state, CharacterVisual.State.STUN, "an earlier event doesn't start the stun")

	var stunning_hit: MoveResult = _move_result(MoveResult.Kind.DAMAGE, MoveResult.Direction.HARM, 10.0)
	stunning_hit.life_after = scene.units[2].life_n
	stunning_hit.stun_after = 1.0
	scene._show_move_result({"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2, "move_id": 434, "result": stunning_hit}, 2)
	for frame in 60:
		doll._process(1.0 / 30.0)
	assert_eq(doll._state, CharacterVisual.State.STUN, "the hit that lands it leaves the doll stunned")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# battle.log is the debug record of every event. It is written with
# JSON.stringify, which prints an object as its id and an enum as its number.
func test_battle_log_names_a_results_fields_and_a_failed_moves_cost():
	var scene = autofree(BattleSceneRes.instantiate())
	var hit: MoveResult = _move_result(MoveResult.Kind.DAMAGE, MoveResult.Direction.HARM, 12.0)
	var move_line: Dictionary = JSON.parse_string(scene._event_log_text({"type": BattleRunner.EventType.MOVE, "result": hit}))
	var failed_line: Dictionary = JSON.parse_string(scene._event_log_text(
		{"type": BattleRunner.EventType.MOVE_FAILED, "caster_slot": 1, "reason": BattleRunner.FailReason.HEALTH}
	))
	assert_eq(
		[move_line["result"]["kind"], move_line["result"]["direction"], move_line["result"]["amount"]],
		["DAMAGE", "HARM", 12.0],
		"a result's fields, with its enums by name"
	)
	assert_eq(failed_line["reason"], "HEALTH", "and a failed move's cost by name")


func _float_labels(scene) -> Array:
	return scene.battlefield.get_children().filter(func(child): return child is Label)


func test_the_replay_floats_status_text_over_the_right_fighter():
	GameData.current_save = PlayerSave.new_game("StatusFloats", 0)
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	await scene._play_events([
		{"type": BattleRunner.EventType.STUNNED, "caster_slot": 1},
		{"type": BattleRunner.EventType.MOVE_FAILED, "caster_slot": 3, "reason": BattleRunner.FailReason.FOCUS},
		{"type": BattleRunner.EventType.DISPEL, "caster_slot": 1, "target_slot": 2, "removed": []},
	])

	var above_fighter: Callable = func(slot: int) -> Vector2:
		return scene._presenters[slot].get_node("Doll").position + FighterPresenter.FLOAT_OFFSET
	assert_eq(
		_float_labels(scene).map(func(label): return [label.text, label.position, label.modulate]),
		[
			["STUNNED", above_fighter.call(1), Color.YELLOW],
			["NOT ENOUGH FOCUS", above_fighter.call(3), Color.ORANGE],
			["DISPEL", above_fighter.call(2), Color.CYAN],
		]
	)

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# A damage-over-time death has no impact to play at, so its DEATH event plays
# it. A move's death already played at the blow, so its DEATH event only paces.
func test_the_death_event_plays_only_the_deaths_no_move_landed():
	GameData.current_save = PlayerSave.new_game("DeathEvent", 0)
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	var doll: CharacterVisual = scene._presenters[2].get_node("Doll")

	await scene._play_events([{"type": BattleRunner.EventType.DEATH, "slot": 2, "cause": BattleRunner.DeathCause.MOVE}])
	assert_ne(doll._state, CharacterVisual.State.DEAD, "a move's DEATH event plays nothing")

	await scene._play_events([{"type": BattleRunner.EventType.DEATH, "slot": 2, "cause": BattleRunner.DeathCause.DAMAGE_OVER_TIME}])
	assert_eq(doll._state, CharacterVisual.State.DEAD, "a damage-over-time death plays here")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# The player's life is moved behind the bar's back during the Decision, the way
# a life cost or a damage-over-time tick moves it with no hit to show it. The
# life is far more than the enemy can take in a half-turn.
func test_the_end_of_a_half_turn_snaps_every_fighter_to_its_unit():
	GameData.current_save = PlayerSave.new_game("HalfTurnSnap", 0)
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	await wait_until(func(): return scene.decision_open, 5)
	var player: CombatUnit = scene.units[BattleRunner.PLAYER_SLOT]
	player.life_u = 999999.0
	player.life_n = 500000.0

	scene._on_pass_pressed()
	await wait_until(func(): return scene.decision_open or scene._finished, 10)
	assert_eq(scene._presenters[BattleRunner.PLAYER_SLOT].displayed_hp, player.life_n, "the bar caught up with the unit")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func test_a_hit_number_takes_its_moves_element_color():
	GameData.current_save = PlayerSave.new_game("HitColor", 0)
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	var move: Ability = MoveManagerAuto.get_move(5)  # Nuke
	scene._show_move_result(
		{"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2, "move_id": move.id,
			"result": _move_result(MoveResult.Kind.DAMAGE, MoveResult.Direction.HARM, 10.0)},
		2
	)
	var number: Label = _float_labels(scene)[-1]
	assert_ne(number.modulate, Color.WHITE, "sanity: this move's color isn't the no-move white")
	assert_eq(number.modulate, MenuTheme.ELEMENT_COLORS[move.damage_element_type])

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# The tests' instant mode lands the blow at once. At full speed the blow waits
# for the swing, which goes to the target with the move's own attack label.
func test_a_melee_move_swings_at_its_target_with_its_own_label():
	GameData.current_save = PlayerSave.new_game("MeleeWiring", 0)
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	var move: Ability = MoveManagerAuto.moves_by_id.values().filter(func(candidate):
		return candidate.attack_animation_type == "Melee" and candidate.animation_label == "Attack_Stab" and not candidate.impact_effect_name.is_empty()
	)[0]
	var event: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2, "move_id": move.id,
		"result": _move_result(MoveResult.Kind.DAMAGE, MoveResult.Direction.HARM, 10.0),
	}
	var impacts: int = _count_impact_effects(scene)

	scene._play_move_event(event)  # not awaited, because instant mode doesn't suspend
	assert_eq(_count_impact_effects(scene), impacts + 1, "instant mode lands the blow at once")

	scene.animation_speed = 1.0
	scene._play_move_event(event)  # not awaited, because this swing never ends
	assert_eq(_count_impact_effects(scene), impacts + 1, "at full speed the blow waits for the swing")
	var doll: CharacterVisual = scene._presenters[1].get_node("Doll")
	assert_eq(doll._attack_label, move.animation_label, "the move's own swing")
	assert_eq(doll._melee_offset, scene._melee_offset(1, 2), "run to the target")

	scene.animation_speed = 0.0
	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# The scene is the only place that reads these two tables, and a presenter
# handed empty ones would still pass all of its own tests.
func test_a_fighter_wears_its_items_and_shows_its_buffs_from_the_real_tables():
	var save = PlayerSave.new_game("FighterTables", 0)
	var armor: GameItem = ItemManagerAuto.items_by_id.values().filter(func(item): return item.looks == "ARCTIC")[0]
	save.equip_array[1] = armor.id
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	var presenter: FighterPresenter = scene._presenters[BattleRunner.PLAYER_SLOT]
	assert_eq(presenter.get_node("Doll")._parts["chest"].get_child_count(), 2, "the chest's skin plus the armor")

	var player: CombatUnit = scene.units[BattleRunner.PLAYER_SLOT]
	player.apply_buff(BuffManagerAuto.get_buff_by_name("TIEDYE"), 1, player)
	player.apply_changes()
	scene._refresh_bars(false)
	assert_eq(presenter.get_node("Overlay").buff_row.get_child_count(), 1, "the buff row found the buff")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# A fighter's voices only reach the speakers through these two connections, and
# a presenter with neither connected would still pass all of its own tests.
func test_each_fighter_sends_its_sounds_to_the_audio_manager():
	GameData.current_save = PlayerSave.new_game("FighterAudio", 0)
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	for slot in scene._presenters:
		var presenter: FighterPresenter = scene._presenters[slot]
		assert_true(presenter.voice_cue.is_connected(AudioManagerAuto.voice), "slot %d's voices" % slot)
		assert_true(presenter.effect_cue.is_connected(AudioManagerAuto.play_effect), "slot %d's effects" % slot)

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func test_combat_log_toggle_and_live_narration():
	var save = PlayerSave.new_game("LogTest", 0)
	save.skill_points = 8
	TalentTree.learn(save, 0)
	TalentTree.learn(save, 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	assert_false(scene._combat_log.visible, "off by default")
	scene._on_log_toggle_pressed()
	assert_true(scene._combat_log.visible, "toggled on")
	scene._on_log_toggle_pressed()
	assert_false(scene._combat_log.visible, "toggled back off")

	var player: CombatUnit = scene.units[1]
	player.ai_enabled = true
	player.move_pool_attack = TalentTree.get_known_move_ids(save)
	player.cooldowns_attack = []
	for i in player.move_pool_attack.size():
		player.cooldowns_attack.append(0)

	await wait_for_signal(scene.battle_finished, 30)
	assert_ne(scene._combat_log._log_text.text, "", "narrated at least one line over the course of a real battle")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# Counts ImpactEffect instances specifically, not battlefield.get_child_count()
# as a whole - FighterPresenter.float_text() parents a damage-number (or "MISS")
# Label under battlefield on every hit AND every miss, so a raw child-count
# comparison can't tell an ImpactEffect apart from that floatie.
func _count_impact_effects(scene) -> int:
	var count: int = 0
	for child in scene.battlefield.get_children():
		if child is ImpactEffect:
			count += 1
	return count


func test_melee_hit_spawns_an_impact_effect_at_the_target():
	var save = PlayerSave.new_game("ImpactMeleeTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	var before: int = _count_impact_effects(scene)
	var event: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
		"move_id": 1, "move_name": "Leading Strike",  # Melee, impact_effect_name BOOM_SPARK
		"result": _move_result(MoveResult.Kind.DAMAGE, MoveResult.Direction.HARM, 10.0),
	}
	await scene._play_move_event(event)

	assert_gt(_count_impact_effects(scene), before, "an ImpactEffect was added to the battlefield")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func test_melee_miss_does_not_spawn_an_impact_effect():
	var save = PlayerSave.new_game("ImpactMissTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	var before: int = _count_impact_effects(scene)
	var event: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
		"move_id": 1, "move_name": "Leading Strike",
		"result": _move_result(MoveResult.Kind.MISS, MoveResult.Direction.NONE, 0.0),
	}
	await scene._play_move_event(event)

	assert_eq(_count_impact_effects(scene), before, "a miss shows no impact effect, matching strikeSuccess")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func test_missile_fire_spawns_a_bolt_and_its_impact_on_arrival():
	# The one test that runs _fire_projectile for real. Every other test on
	# this scene uses animation_speed 0, which returns from the top of that
	# function before it touches anything - the gap that hid a stale
	# Projectile.new() call through five tasks of this plan.
	var save = PlayerSave.new_game("MissileFireTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	var move: Ability = MoveManagerAuto.get_move(5)  # Nuke: Missile, Krin.Magicbolt, BOOM_SLASHORANGE
	var result: MoveResult = _move_result(MoveResult.Kind.DAMAGE, MoveResult.Direction.HARM, 10.0)
	var impacts_before: int = _count_impact_effects(scene)
	# Deliberately not awaited: _fire_projectile suspends on the bolt's
	# reached_target, and the bolt has to be hand-driven from out here to
	# get there, exactly as test_projectile.gd drives it.
	scene.animation_speed = 1.0
	scene._fire_projectile(1, 2, move, result)

	var bolt: Projectile = null
	for child in scene.battlefield.get_children():
		if child is Projectile:
			bolt = child
	assert_not_null(bolt, "a real Projectile was added to the battlefield")
	assert_eq(bolt.clip_name, "Krin.Magicbolt", "the move's own bolt clip was threaded through")
	assert_eq(bolt.trail_color, move.visual_effect_color, "the move's own trail color was threaded through")
	assert_true(bolt.did_hit, "a DAMAGE result is a hit, not a miss")

	for i in 200:
		bolt._process(1.0 / 30.0)
		if bolt.is_queued_for_deletion():
			break
	assert_true(bolt.is_queued_for_deletion(), "the bolt reached the target and freed itself")
	assert_gt(_count_impact_effects(scene), impacts_before,
		"_fire_projectile resumed past its await and spawned the impact effect")

	scene.animation_speed = 0.0
	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# On a miss the original's bolt keeps flying past its target instead of freeing
# itself there (frame_42/DoAction_4.as:188-205), which Projectile.did_hit
# decides.
func test_a_missed_bolt_is_told_it_missed():
	GameData.current_save = PlayerSave.new_game("MissileMissTest", 0)
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	scene.animation_speed = 1.0
	# Deliberately not awaited, like the bolt test above, since nothing drives
	# this bolt to its target.
	scene._fire_projectile(1, 2, MoveManagerAuto.get_move(5), _move_result(MoveResult.Kind.MISS, MoveResult.Direction.NONE, 0.0))

	var bolts: Array = scene.battlefield.get_children().filter(func(child): return child is Projectile)
	assert_eq(bolts.size(), 1, "the bolt is out")
	assert_false(bolts[0].did_hit, "and it knows it missed")

	scene.animation_speed = 0.0
	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func test_shock_cast_tints_with_the_moves_own_visual_effect_color():
	var save = PlayerSave.new_game("CastTintTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	var move: Ability = MoveManagerAuto.get_move(4)  # Heal, Shock, "0x33FF00"
	var caster_visual: CharacterVisual = scene._presenters[1].get_node("Doll")
	var event: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
		"move_id": 4, "move_name": move.display_name,
		"result": _move_result(MoveResult.Kind.HEAL, MoveResult.Direction.HEAL, 10.0),
	}
	scene._play_move_event(event)  # not awaited - modulate is set synchronously before the Shock branch's pause

	var expected: Color = move.visual_effect_color.lerp(Color.WHITE, 0.4)
	assert_almost_eq(caster_visual.modulate.r, expected.r, 0.01)
	assert_almost_eq(caster_visual.modulate.g, expected.g, 0.01)
	assert_almost_eq(caster_visual.modulate.b, expected.b, 0.01)

	GameData.current_save = null
	ZoneManager.auto_start_battles = true
