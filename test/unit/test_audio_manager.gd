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


func test_real_cue_loads():
	var stream = manager._stream("_music_battle1")
	assert_not_null(stream, "extracted audio file resolves")
	assert_true(stream.loop, "music streams loop")
	assert_not_null(manager._stream("hit_sonny1"))
