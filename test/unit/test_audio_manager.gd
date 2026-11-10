# Unit tests for the audio dispatcher (scripts/autoload/audio_manager.gd).
# Instantiates the script directly (not via the autoload) so this stays
# self-contained; playback itself is inaudible headless - these cover the
# rotation/mode logic and missing-cue safety.
extends GutTest

const AudioManagerScript = preload("res://scripts/autoload/audio_manager.gd")

var manager


func before_each():
	manager = add_child_autofree(AudioManagerScript.new())


func test_players_created():
	assert_eq(manager._effect_players.size(), 3, "3-channel SFX pool")
	assert_eq(manager._music_players.size(), 2, "2 crossfading music channels")


func test_rotation_cycles_like_the_original():
	var seen = []
	for i in 13:
		seen.append(manager._next_rotation_cue())
	assert_eq(seen[0], "_music_menu1")
	assert_eq(seen[1], "_music_battle1")
	assert_eq(seen[12], "_music_menu1", "wraps after 12 entries")


func test_unknown_cue_is_safe():
	manager.play_effect("definitely_not_a_real_cue")
	manager.play_effect("")
	pass_test("no crash on unknown/empty cues")


func test_music_modes_idempotent():
	manager.play_battle_music(false)
	var rotation_after_first = manager._rotation_counter
	manager.play_battle_music(false)
	assert_eq(manager._rotation_counter, rotation_after_first, "same mode twice does not restart")
	manager.play_menu_music()
	assert_ne(manager._rotation_counter, rotation_after_first, "mode switch advances")


# The original's Space handler in battle stops my_sound1 to my_sound3
# (frame_217/PlaceObject2_3367_634 onClipEvent(keyDown), lines 6-8), the three
# channels addSound("Effects") plays every cue on in turn
# (frame_42/DoAction.as:5-15 and 119-121).
func test_stop_effects_stops_every_effect_channel():
	for cue in ["hit_sonny1", "hit_sonny2", "hit_sonny3"]:
		manager.play_effect(cue)
	assert_true(manager._effect_players.all(func(player): return player.playing), "each channel is playing a cue")
	manager.stop_effects()
	assert_false(manager._effect_players.any(func(player): return player.playing), "and none is after stop_effects")


func test_real_cue_loads():
	var stream = manager._stream("_music_battle1")
	assert_not_null(stream, "extracted audio file resolves")
	assert_true(stream.loop, "music streams loop")
	assert_not_null(manager._stream("hit_sonny1"))


# The battle scene tests hear what a move plays through effect_played, so it
# names only cues that really start, not one that is off, empty or missing.
func test_an_effect_that_starts_playing_is_announced():
	watch_signals(manager)
	manager.play_effect("hit_sonny1")
	manager.play_effect("definitely_not_a_real_cue")
	manager.play_effect("")
	manager.sound_enabled = false
	manager.play_effect("hit_sonny2")
	assert_signal_emit_count(manager, "effect_played", 1)
	assert_signal_emitted_with_parameters(manager, "effect_played", ["hit_sonny1"])
