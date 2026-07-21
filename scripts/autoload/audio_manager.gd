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
# The menu/battle rotation cycles soundPlayArray exactly like the original.
extends Node

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


func play_menu_music() -> void:
	if _music_mode == MusicMode.MENU:
		return
	_music_mode = MusicMode.MENU
	_start_music(_next_rotation_cue(), false)


# hard_start = the original's bangStart (battle entry cuts straight to full
# volume instead of crossfading).
func play_battle_music(is_boss: bool, hard_start: bool = false) -> void:
	if _music_mode == MusicMode.BATTLE:
		return
	_music_mode = MusicMode.BATTLE
	var cue: String = "_music_boss" if is_boss else _next_rotation_cue()
	if is_boss:
		_next_rotation_cue()  # the original advances the rotation either way
	_start_music(cue, hard_start)


func stop_music() -> void:
	_music_mode = MusicMode.NONE
	for player in _music_players:
		player.stop()


func voice(unit_cues: Array) -> void:
	if not unit_cues.is_empty():
		play_effect(unit_cues[randi_range(0, unit_cues.size() - 1)])


func _next_rotation_cue() -> String:
	var cue = MUSIC_ROTATION[_rotation_counter]
	_rotation_counter = (_rotation_counter + 1) % MUSIC_ROTATION.size()
	return cue


func _start_music(cue: String, hard_start: bool) -> void:
	if not sound_enabled:
		return
	var stream: AudioStream = _stream(cue)
	if stream == null:
		return
	var old_player: AudioStreamPlayer = _music_players[_active_music]
	_active_music = (_active_music + 1) % 2
	var new_player: AudioStreamPlayer = _music_players[_active_music]
	new_player.stream = stream
	if _fade_tween != null:
		_fade_tween.kill()
	if hard_start:
		old_player.stop()
		new_player.volume_db = FULL_VOLUME_DB
		new_player.play()
		return
	new_player.volume_db = -40.0
	new_player.play()
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(new_player, "volume_db", FULL_VOLUME_DB, CROSSFADE_SECONDS)
	if old_player.playing:
		_fade_tween.tween_property(old_player, "volume_db", -40.0, CROSSFADE_SECONDS)
		_fade_tween.chain().tween_callback(old_player.stop)


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
