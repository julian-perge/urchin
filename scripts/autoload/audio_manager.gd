# audio_manager.gd
# The runtime audio dispatcher, ported from addSound()
# (frame42/sonny2_addSound_audio_manager.txt): one-shot SFX through a
# rotating pool of 3 players, background music through 2 alternating players
# with a crossfade ramp (5/80 volume units per tick in the original; here a
# tween over the equivalent duration). Streams load lazily from
# assets/audio/<cue>.mp3 - the 147 extracted files named by AS3 cue key.
#
# Public API mirrors the original call sites:
#   play_effect("sfx_hit2")      <- addSound("Effects", cue)
#   play_menu_music()            <- addSound("Music", 1)
#   play_battle_music(is_boss)   <- addSound("Music", 2)
#   stop_all_sounds()            <- stopAllSounds()
#   stop_effects()               <- my_sound1.stop() to my_sound3.stop()
#   reset_music_rotation()       <- soundPlayCounter = 0 and soundModeKrin = 0
#   set_first_fight_music(n)     <- soundPlayCounter = n and bangStart = true
# The menu/battle rotation cycles soundPlayArray exactly like the original.
extends Node

# Emitted for every cue that starts on an effect channel, voices included. The
# battle scene and each fighter play their sounds straight through this node,
# so the battle scene tests listen here to hear what a move plays.
signal effect_played(cue: String)

const AUDIO_ROOT: String = "res://assets/audio"
const EFFECT_PLAYER_COUNT: int = 3
# Original volumes are 0-80 on Flash's 0-100 scale.
const FULL_VOLUME_DB: float = -2.0
const CROSSFADE_SECONDS: float = 16.0 / 30.0  # 80 volume units at 5 per 30fps frame

# soundPlayArray (frame41): the alternating menu/battle track rotation.
const MUSIC_ROTATION: Array[Variant] = [
	"_music_menu1", "_music_battle1", "_music_menu2", "_music_battle2",
	"_music_menu1", "_music_battle3", "_music_menu2", "_music_battle1",
	"_music_menu1", "_music_battle2", "_music_menu2", "_music_battle3",
]

enum MusicMode { NONE = 0, MENU = 1, BATTLE = 2 }

var sound_enabled: bool = true
# The original's bangStart. Frames 165 and 180 turn it on before a new game's
# first fights (see set_first_fight_music()). The next battle track that starts
# turns it off again. That track cuts off the track before it and starts at full
# volume, where every other battle track fades in (frame_42/DoAction.as:85-97).
# While the sound is off no battle track starts, so the flag stays on.
var bang_start: bool = false
# The original's Krin.soundToMake and Krin.missToMake, the sounds its impact
# block plays for a hit and for a miss (the conductor, lines 19-21 and 105-108).
# Each move that dispatches and pays sets both (see battle_scene.gd's
# _set_landing_sounds), and nothing else does, so a move that lands for free
# plays the sounds of the last paid move. resetHere recreates Krin
# (frame_41/DoAction_2.as:7), so main_menu.gd clears both with
# forget_landing_sounds(). An empty name plays nothing, as addSound plays nothing
# for undefined (frame_42/DoAction.as:7).
var sound_to_make: String = ""
var miss_to_make: String = ""
# How loud the music plays, as a percentage of full volume. The battle's Speech
# box sets it to 100 - _alpha / 1.2 while it fades, which drops the music to about
# 17 percent under a line (frame_217/PlaceObject2_3367_634 enterFrame, line 2).
# A crossfade that is running keeps its own volumes, and a track that starts
# plays at this level.
var music_level: float = 100.0:
	set(value):
		music_level = value
		if _fade_tween != null and _fade_tween.is_running():
			return
		var player: AudioStreamPlayer = _music_players[_active_music]
		player.volume_db = _level_db()

var _effect_players: Array[AudioStreamPlayer] = []
var _effect_counter: int = 0
var _music_players: Array[AudioStreamPlayer] = []
var _active_music: int = 0
var _music_mode: int = MusicMode.NONE
var _rotation_counter: int = 0
var _streams: Dictionary = {}
var _fade_tween: Tween = null


func _ready():
	name = "AudioManager"
	for i in EFFECT_PLAYER_COUNT:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_effect_players.append(player)
	for i in 2:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_music_players.append(player)


func play_effect(cue: String) -> void:
	if not sound_enabled or cue == "":
		return
	var stream: AudioStream = _stream(cue)
	if stream == null:
		return
	var player: AudioStreamPlayer = _effect_players[_effect_counter]
	_effect_counter = (_effect_counter + 1) % EFFECT_PLAYER_COUNT
	player.stream = stream
	player.volume_db = FULL_VOLUME_DB
	player.play()
	effect_played.emit(cue)


# addSound does nothing at all while Krin.sound is off (frame_42/DoAction.as:3),
# so the music mode and the rotation do not change either.
func play_menu_music() -> void:
	if not sound_enabled or _music_mode == MusicMode.MENU:
		return
	_music_mode = MusicMode.MENU
	_start_music(_next_rotation_cue(), false)


func play_battle_music(is_boss: bool) -> void:
	if not sound_enabled or _music_mode == MusicMode.BATTLE:
		return
	_music_mode = MusicMode.BATTLE
	var cue: String = "_music_boss" if is_boss else _next_rotation_cue()
	if is_boss:
		_next_rotation_cue()  # the original advances the rotation either way
	_start_music(cue, bang_start)
	bang_start = false


func forget_landing_sounds() -> void:
	sound_to_make = ""
	miss_to_make = ""


func stop_music() -> void:
	_music_mode = MusicMode.NONE
	for player in _music_players:
		player.stop()


# The original's my_sound1.stop() to my_sound3.stop(), which its battle Space
# handler calls (frame_217/PlaceObject2_3367_634 onClipEvent(keyDown), lines
# 6-8). Those are the three channels addSound("Effects") plays every cue on in
# turn (frame_42/DoAction.as:5-15 and 119-121), so this stops any voice-over too.
func stop_effects() -> void:
	for player in _effect_players:
		player.stop()


# This is the original's stopAllSounds(), which stops the music and all three
# effect channels.
func stop_all_sounds() -> void:
	stop_music()
	stop_effects()


func reset_music_rotation() -> void:
	_music_mode = MusicMode.NONE
	_rotation_counter = 0


# The last frames of IntroSeq and IntroSeq2 set soundPlayCounter and turn
# bangStart on before the Tutorial and before battle 100
# (frame_165/DoAction.as:4-5, frame_180/DoAction.as:4-6). They do it whether the
# sound is on or off, because they do not go through addSound.
func set_first_fight_music(rotation_counter: int) -> void:
	_rotation_counter = rotation_counter
	bang_start = true


func voice(unit_cues: Array) -> void:
	if not unit_cues.is_empty():
		play_effect(unit_cues[randi_range(0, unit_cues.size() - 1)])


func _next_rotation_cue() -> String:
	var cue = MUSIC_ROTATION[_rotation_counter]
	_rotation_counter = (_rotation_counter + 1) % MUSIC_ROTATION.size()
	return cue


func _start_music(cue: String, hard_start: bool) -> void:
	var stream: AudioStream = _stream(cue)
	if stream == null:
		return
	var old_player: AudioStreamPlayer = _music_players[_active_music]
	_active_music = (_active_music + 1) % 2
	var new_player: AudioStreamPlayer = _music_players[_active_music]
	new_player.stream = stream
	if _fade_tween != null:
		_fade_tween.kill()
	var target_db: float = _level_db()
	if hard_start:
		old_player.stop()
		new_player.volume_db = target_db
		new_player.play()
		return
	new_player.volume_db = -40.0
	new_player.play()
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(new_player, "volume_db", target_db, CROSSFADE_SECONDS)
	if old_player.playing:
		_fade_tween.tween_property(old_player, "volume_db", -40.0, CROSSFADE_SECONDS)
		_fade_tween.chain().tween_callback(old_player.stop)


# The volume that music_level asks for.
func _level_db() -> float:
	return FULL_VOLUME_DB + linear_to_db(maxf(music_level, 0.001) / 100.0)


func _stream(cue: String) -> AudioStream:
	if _streams.has(cue):
		return _streams[cue]
	var path: String = "%s/%s.mp3" % [AUDIO_ROOT, cue]
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: no audio file for cue '%s'" % cue)
		_streams[cue] = null
		return null
	var stream = load(path)
	if stream is AudioStreamMP3 and cue.begins_with("_music"):
		stream.loop = true
	_streams[cue] = stream
	return stream
