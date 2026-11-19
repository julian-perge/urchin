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


# addSound does nothing at all while Krin.sound is off (frame_42/DoAction.as:3),
# so the music mode and the rotation stay where they were.
func test_music_leaves_the_mode_and_the_rotation_alone_while_the_sound_is_off():
	manager.sound_enabled = false
	manager.play_menu_music()
	manager.play_battle_music(false)
	manager.play_battle_music(true)
	assert_eq(manager._music_mode, manager.MusicMode.NONE)
	assert_eq(manager._rotation_counter, 0)


# Frames 165 and 180 set the rotation and bangStart before a new game's first
# fights (frame_165/DoAction.as:4-5, frame_180/DoAction.as:4-6). The battle track
# that uses bangStart cuts the old track off and starts at full volume
# (frame_42/DoAction.as:85-91).
func test_the_first_fight_music_starts_its_track_at_full_volume():
	manager.play_menu_music()
	manager.set_first_fight_music(3)
	manager.play_battle_music(false)
	var music: AudioStreamPlayer = manager._music_players[manager._active_music]
	assert_eq(music.stream.resource_path, "res://assets/audio/_music_battle2.mp3", "the counter picks the track")
	assert_almost_eq(music.volume_db, manager._level_db(), 0.001, "at full volume")
	assert_false(manager._music_players[1 - manager._active_music].playing, "the menu track is cut off")
	assert_false(manager.bang_start, "and the track uses bangStart up")


# Only the battle track after frame 165 or 180 uses bangStart. Every later battle
# track fades in from silence (frame_42/DoAction.as:92-96).
func test_the_battle_track_after_the_first_fight_fades_in_again():
	manager.set_first_fight_music(1)
	manager.play_battle_music(false)
	manager.play_menu_music()
	manager.play_battle_music(false)
	var music: AudioStreamPlayer = manager._music_players[manager._active_music]
	assert_lt(music.volume_db, manager._level_db() - 10.0, "the next battle track starts low and fades in")


# Frames 165 and 180 set the counter and bangStart even while the sound is off,
# and addSound does nothing then (frame_42/DoAction.as:3). So bangStart waits for
# the first battle track that does play.
func test_bang_start_waits_while_the_sound_is_off():
	manager.sound_enabled = false
	manager.set_first_fight_music(1)
	manager.play_battle_music(false)
	assert_eq(manager._rotation_counter, 1, "the frame sets the counter with the sound off")
	assert_true(manager.bang_start, "and bangStart stays on")
	manager.sound_enabled = true
	manager.play_battle_music(false)
	var music: AudioStreamPlayer = manager._music_players[manager._active_music]
	assert_eq(music.stream.resource_path, "res://assets/audio/_music_battle1.mp3")
	assert_almost_eq(music.volume_db, manager._level_db(), 0.001, "the first battle track that plays starts at full volume")
