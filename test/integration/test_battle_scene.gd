# Integration test for the playable battle scene: real save + real battle 100
# through BattleSetup/BattleRunner with paper-doll visuals, run to completion
# headless (animation_speed 0, player driven by the AI).
extends GutTest

const BattleSceneRes = preload("res://scenes/battle_scene.tscn")


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
	assert_eq(scene._visuals.size(), 3, "player + enemy + Veradux dolls spawned")
	assert_not_null(scene._visuals.get(1))
	assert_eq(scene.units[2].player_name, "Prison Guard")
	assert_eq(scene._visuals[2].scale.x, -1.0, "enemy mirrored to face left")
	assert_gt(scene._health_bars[1].max_value, 0.0, "health bars wired")

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
		assert_eq(ZoneProgression.quest_progress(save, 1), 1, "victory advanced story progress")
		assert_gt(save.euro, 0.0, "victory paid out")
		# Drops are click-to-keep now - claiming one lands in the inventory.
		if victory != null and not victory._drop_slots.is_empty():
			var drop: ItemSlot = victory._drop_slots[0]
			if drop.item != null:
				var item_id = drop.item.id
				victory._on_drop_clicked(drop, save)
				assert_has(save.item_array, item_id, "claimed drop landed in the inventory")
	else:
		assert_true(scene.result_panel.visible, "result panel shown on loss/draw")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# Task 4 (cutscene plan): drives a real win of story battle 108 (zone 1's
# last real battle, CUTSCENE_BATTLES -> CS_CUT2) through the actual game
# code path - BattleSetup/BattleRunner combat, _finish_battle(),
# ZoneProgression.after_battle_won(), and the VictoryScreen "Proceed" ->
# CutscenePlayer wiring - and confirms the cutscene id is threaded through
# correctly end to end. Enemy life is knocked to 1 and the player's life
# pool is inflated so the outcome is a deterministic WIN rather than left to
# real combat RNG (as test_full_battle_scene_run above accepts); every hit,
# miss, and turn order decision along the way is still the real combat sim.
#
# This intentionally stops short of letting the real cutscene finish:
# CutscenePlayer.play() only ever suspends on `await video.finished` (real
# .ogv decode, 16-70s, no skip mechanism - see cutscene_player.gd), and
# _on_continue_pressed() beyond it calls get_tree().change_scene_to_file(),
# which would tear down whatever the GUT runner considers its own current
# scene. Verifying playback actually starts with the right stream is as far
# as this test goes; queue_free() via add_child_autofree(scene) cleans up
# the still-suspended coroutines harmlessly when the test ends.
func test_story_battle_win_threads_cutscene_id_through_victory_flow():
	var save = PlayerSave.new_game("CutsceneFlow", 0)
	save.skill_points = 8
	TalentTree.learn(save, 0)
	TalentTree.learn(save, 0)
	save.quest_progress[1] = 8  # battle 108 is zone 1's last real (pre-boss) battle
	# No slot is selected in this test (GameData.current_save is set directly
	# below) - autosave defaulting true would make _on_victory_proceed() log a
	# benign "no active save/slot" warning; off here since it's not what this
	# test is checking.
	save.autosave = false
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	watch_signals(scene)
	scene.start_battle({"battle_id": 108, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	assert_eq(scene.battle.id, 108, "loaded the intended story battle")

	# Tilt the fight so the real sim reaches WIN deterministically: enemy
	# dies on the first landed hit, player is unkillable within the turn cap.
	for slot in scene.units:
		var unit: CombatUnit = scene.units[slot]
		if unit.team_side == 2:
			unit.life_n = 1.0
		elif slot == BattleRunner.PLAYER_SLOT:
			unit.life_u = 999999.0
			unit.life_n = 999999.0

	var player: CombatUnit = scene.units[BattleRunner.PLAYER_SLOT]
	player.ai_enabled = true
	player.move_pool_attack = TalentTree.get_known_move_ids(save)
	player.cooldowns_attack = []
	for i in player.move_pool_attack.size():
		player.cooldowns_attack.append(0)

	await wait_for_signal(scene.battle_finished, 30)
	assert_signal_emitted(scene, "battle_finished")
	assert_eq(scene.runner.win_condition, BattleRunner.Outcome.WIN, "tilted fight wins deterministically")
	assert_eq(ZoneProgression.quest_progress(save, 1), 9, "story win advanced progress past 108")
	assert_eq(scene._pending_cutscene, "CS_CUT2", "battle_scene threaded ZoneProgression's cutscene id into _pending_cutscene")

	var victory: VictoryScreen = scene.get_node_or_null("VictoryScreen")
	assert_not_null(victory, "victory screen shown on win")

	# Fires the same signal the real "Proceed" button does. _on_victory_proceed()
	# runs synchronously up to `await cutscene.play(...)`, which itself runs
	# synchronously (animation_speed 0 skips the fade tweens) up to the real
	# `await video.finished` - so by the time this call returns control here,
	# CutscenePlayer exists, is a real child, and has already called play().
	victory.proceed_pressed.emit()

	var cutscene: CutscenePlayer = scene.get_node_or_null("CutscenePlayer")
	assert_not_null(cutscene, "CutscenePlayer instantiated and added as a child of battle_scene")
	if cutscene != null:
		assert_true(cutscene.video.is_playing(), "play() started the video")
		assert_eq(
			cutscene.video.stream.resource_path, "res://assets/cutscenes/CS_CUT2.ogv",
			"the cutscene id threaded all the way to CutscenePlayer.play() matches CS_CUT2"
		)

	GameData.current_save = null
	ZoneManager.auto_start_battles = true
