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
