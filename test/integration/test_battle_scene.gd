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


# Task 4 (cutscene plan): drives a real win of story battle 109 (zone 1's
# boss, CUTSCENE_BATTLES -> CS_CUT2) through the actual game
# code path - BattleSetup/BattleRunner combat, _finish_battle(),
# ZoneProgression.after_battle_won(), and the VictoryScreen "Proceed" ->
# CutscenePlayer wiring - and confirms the cutscene id is threaded through
# correctly end to end. Enemy life is knocked to 1 and the player's life
# pool is inflated so the outcome is a deterministic WIN rather than left to
# real combat RNG (as test_full_battle_scene_run above accepts); every hit,
# miss, and turn order decision along the way is still the real combat sim.
#
# This intentionally stops short of letting the real cutscene finish:
# CutscenePlayer.play() suspends until the clip ends or its failsafe timeout
# fires (real .ogv decode, 16-70s, no skip mechanism - see
# cutscene_player.gd), and
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
	save.quest_progress[1] = 9  # battle 109 is zone 1's boss
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
	scene.start_battle({"battle_id": 109, "is_story_progress": true, "is_boss": true, "train_cap": 9})
	assert_eq(scene.battle.id, 109, "loaded the intended story battle")

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
	assert_eq(ZoneProgression.quest_progress(save, 1), 10, "story win advanced progress past 109")
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

	# The original silences the battle track before jumping into a cutscene,
	# so the clip's own audio isn't competing with it for the whole runtime.
	assert_eq(
		AudioManagerAuto._music_mode, AudioManagerAuto.MusicMode.NONE,
		"battle music stopped before the cutscene started"
	)
	# Consumed, not just read: a second Proceed press while the clip is
	# playing must not find a cutscene id still waiting and start a second
	# player on top of the first.
	assert_eq(scene._pending_cutscene, "", "pending cutscene cleared once it was handed to the player")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func test_is_point_over_radial_menu_area():
	var save = PlayerSave.new_game("MenuAreaTest", 0)
	save.skill_points = 8
	TalentTree.learn(save, 0)
	TalentTree.learn(save, 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	scene._player_action_pending = true
	scene._on_unit_clicked(2)  # battle 100's enemy slot (Prison Guard)
	assert_not_null(scene._radial_menu, "menu opened")

	var overlay: Control = scene._overlays[2]
	var unit_center: Vector2 = overlay.hit_button.get_global_rect().get_center()
	assert_true(scene._is_point_over_radial_menu_area(unit_center), "over the unit's own hit area")

	var orb: Control = scene._radial_menu.get_child(0)
	var orb_center: Vector2 = orb.get_global_rect().get_center()
	assert_true(scene._is_point_over_radial_menu_area(orb_center), "over an orb, well outside the unit's hit area")

	assert_false(scene._is_point_over_radial_menu_area(Vector2(-1000, -1000)), "nowhere near either")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func test_radial_menu_fades_out_on_hover_leave():
	var save = PlayerSave.new_game("MenuFadeTest", 0)
	save.skill_points = 8
	TalentTree.learn(save, 0)
	TalentTree.learn(save, 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	scene._player_action_pending = true
	scene._on_unit_clicked(2)
	assert_not_null(scene._radial_menu)

	# Directly invoke the same handler _process() would call once the
	# leave-grace timer fires - avoids waiting on real timer duration in
	# the test while still exercising the real fade-then-free logic.
	scene._start_radial_menu_fade_out()
	await scene.get_tree().create_timer(scene.RING_FADE_OUT_TIME + 0.1).timeout
	assert_null(scene._radial_menu, "faded out and freed")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func test_radial_menu_hover_return_cancels_fade_out():
	var save = PlayerSave.new_game("MenuCancelFadeTest", 0)
	save.skill_points = 8
	TalentTree.learn(save, 0)
	TalentTree.learn(save, 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	scene._player_action_pending = true
	scene._on_unit_clicked(2)
	assert_not_null(scene._radial_menu)

	var overlay: Control = scene._overlays[2]
	var unit_center: Vector2 = overlay.hit_button.get_global_rect().get_center()

	# Start the fade, let it run partway, then simulate the mouse landing
	# back on the unit - the same call _process() makes every frame, with a
	# point _is_point_over_radial_menu_area() reports as "over the menu".
	scene._start_radial_menu_fade_out()
	await scene.get_tree().create_timer(scene.RING_FADE_OUT_TIME * 0.3).timeout
	scene._update_radial_menu_fade(unit_center)
	assert_not_null(scene._radial_menu, "mouse returned before the fade finished - menu must stay open")
	assert_eq(scene._radial_menu.modulate.a, 1.0, "snapped back to fully visible")
	# The in-flight tween must actually be killed (not merely overridden for
	# one frame) - otherwise its tween_callback(_close_radial_menu) would
	# still free the menu once the original fade duration elapses, even
	# though the mouse came back. A killed Tween never fires its remaining
	# steps, so nulling the field here is proof, not a guess.
	assert_null(scene._radial_menu_fade_tween, "in-flight fade tween was killed, not left running")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# Regression test: clicking a second unit while the first unit's menu is
# fading out used to close the SECOND menu a moment later. _close_radial_menu()
# nulled its reference to the in-flight fade tween without killing the tween
# itself, and a Godot Tween whose target node is freed keeps running - its
# trailing tween_callback(_close_radial_menu) still fired and took the newly
# opened menu with it.
func test_opening_a_second_menu_survives_the_first_menus_fade():
	var save = PlayerSave.new_game("MenuStaleTweenTest", 0)
	save.skill_points = 8
	TalentTree.learn(save, 0)
	TalentTree.learn(save, 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	# The headless mouse sits nowhere near the menu, so _process() keeps
	# restarting the leave-grace timer on the second menu. Stretching the
	# grace period keeps that legitimate fade-out from firing inside the
	# window this test measures, leaving the stale tween as the only thing
	# that could close the second menu.
	scene._radial_menu_leave_timer.wait_time = 30.0
	scene._player_action_pending = true

	scene._on_unit_clicked(2)
	assert_not_null(scene._radial_menu, "first menu opened on the enemy slot")
	scene._start_radial_menu_fade_out()
	await scene.get_tree().create_timer(scene.RING_FADE_OUT_TIME * 0.3).timeout

	# Player clicks a different unit partway through the first menu's fade.
	scene._on_unit_clicked(BattleRunner.PLAYER_SLOT)
	assert_not_null(scene._radial_menu, "second menu opened")
	assert_eq(scene._radial_menu_owner_slot, BattleRunner.PLAYER_SLOT, "second menu belongs to the newly clicked slot")

	# Well past the point where the first menu's fade would have completed
	# and run its trailing callback.
	await scene.get_tree().create_timer(scene.RING_FADE_OUT_TIME + 0.2).timeout
	assert_not_null(scene._radial_menu, "second menu outlived the first menu's fade tween")
	assert_eq(scene._radial_menu_owner_slot, BattleRunner.PLAYER_SLOT, "and it is still the second menu, not a leftover")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


# Regression test: a move-caused death used to only play when the QUEUED
# "death" event was reached in _play_events(), which only happens after the
# caster's whole move await resolves - for melee, that's after the runback
# finishes, not when the killing blow actually lands. _show_move_result()
# is where the impact itself is shown (the damage number, the HIT flinch)
# - death needs to fire there too, synchronously, not wait for a later,
# separate event further down the same half-turn's list.
func test_death_plays_at_impact_not_after_caster_returns():
	var save = PlayerSave.new_game("DeathTiming", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})
	var enemy_slot := 2  # battle 100's Prison Guard
	scene._show_move_result(
		{"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": enemy_slot, "move_id": 100,
			"result": {"type": BattleManager.ResultType.DAMAGE, "amount": 99999.0, "target_died": true}},
		enemy_slot
	)
	assert_eq(
		scene._visuals[enemy_slot]._state, CharacterVisual.State.DEAD,
		"death played synchronously inside _show_move_result, not deferred to a later event"
	)
	assert_false(scene._overlays[enemy_slot].visible, "overlay hidden the same moment")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func test_decision_timer_ticks_down_while_player_is_deciding():
	var save = PlayerSave.new_game("TimerTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	scene._player_action_pending = true
	scene._reset_decision_timer()
	assert_eq(scene._decision_timer, BattleRunner.BATTLE_TIME_LIMIT, "resets to the full 120s")

	scene._process(10.0)
	assert_almost_eq(scene._decision_timer, BattleRunner.BATTLE_TIME_LIMIT - 10.0, 0.001)

	scene._process(9999.0)
	assert_eq(scene._decision_timer, 0.0, "clamps at 0, never goes negative")

	GameData.current_save = null
	ZoneManager.auto_start_battles = true


func test_decision_timer_does_not_tick_while_not_player_action_pending():
	var save = PlayerSave.new_game("TimerTest2", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	scene._player_action_pending = false
	scene._decision_timer = 50.0
	scene._process(10.0)
	assert_eq(scene._decision_timer, 50.0, "doesn't tick during an AI turn")

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


func test_hover_ring_fades_in_only_during_player_decision_window():
	var save = PlayerSave.new_game("RingFadeTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	var ring: Control = scene._rings[2]  # battle 100's enemy slot (Prison Guard)
	assert_eq(ring.modulate.a, 0.0, "starts invisible")

	# Not the player's turn - hovering must not start a fade-in.
	scene._player_action_pending = false
	scene._on_unit_hovered(2, true)
	await scene.get_tree().create_timer(0.3).timeout
	assert_eq(ring.modulate.a, 0.0, "no fade-in outside the player's decision window")

	# The player's turn - hovering fades it in.
	scene._player_action_pending = true
	scene._on_unit_hovered(2, true)
	await scene.get_tree().create_timer(0.3).timeout
	assert_almost_eq(ring.modulate.a, 1.0, 0.05, "faded in during the decision window")

	# Fade-out is never gated, even outside the decision window.
	scene._player_action_pending = false
	scene._on_unit_hovered(2, false)
	await scene.get_tree().create_timer(0.8).timeout
	assert_almost_eq(ring.modulate.a, 0.0, 0.05, "fades back out regardless of turn state")

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
# as a whole - _show_move_result's pre-existing _float_text() call parents a
# damage-number (or "MISS") Label under battlefield on every hit AND every
# miss, so a raw child-count comparison can't tell an ImpactEffect apart from
# that floatie.
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
		"result": {"type": BattleManager.ResultType.DAMAGE, "amount": 10.0, "did_crit": false, "target_died": false},
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
		"result": {"type": BattleManager.ResultType.MISS},
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
	var result: Dictionary = {
		"type": BattleManager.ResultType.DAMAGE, "amount": 10.0,
		"did_crit": false, "target_died": false,
	}
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


func test_shock_cast_tints_with_the_moves_own_visual_effect_color():
	var save = PlayerSave.new_game("CastTintTest", 0)
	GameData.current_save = save
	ZoneManager.auto_start_battles = false
	ZoneManager.pending_battle = {}

	var scene = add_child_autofree(BattleSceneRes.instantiate())
	scene.animation_speed = 0.0
	scene.start_battle({"battle_id": 100, "is_story_progress": true, "is_boss": false, "train_cap": 9})

	var move: Ability = MoveManagerAuto.get_move(4)  # Heal, Shock, "0x33FF00"
	var caster_visual: CharacterVisual = scene._visuals[1]
	var event: Dictionary = {
		"type": BattleRunner.EventType.MOVE, "caster_slot": 1, "target_slot": 2,
		"move_id": 4, "move_name": move.display_name,
		"result": {"type": BattleManager.ResultType.HEAL, "amount": 10.0, "did_crit": false, "target_died": false},
	}
	scene._play_move_event(event)  # not awaited - modulate is set synchronously before the Shock branch's pause

	var expected: Color = move.visual_effect_color.lerp(Color.WHITE, 0.4)
	assert_almost_eq(caster_visual.modulate.r, expected.r, 0.01)
	assert_almost_eq(caster_visual.modulate.g, expected.g, 0.01)
	assert_almost_eq(caster_visual.modulate.b, expected.b, 0.01)

	GameData.current_save = null
	ZoneManager.auto_start_battles = true
