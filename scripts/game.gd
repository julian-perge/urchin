# game.gd
# Root of scenes/game.tscn - the zone hub shell. Hosts the current zone's
# scene (scenes/zones/*, swapped on ZoneManager.zone_changed), with the
# Windows, the world-map overlay, and the hotbar layered on top, with the
# Info card above all of them.
# Battles take over via ZoneManager's scene switch and return here. A won
# battle returns with ZoneManager.pending_victory set, and the Hub opens the
# Victory Window for it.
extends Control

# dev/converted_json/battle_hints.json, from convert_battle_hints.
const BATTLE_HINTS_FILE := "res://dev/converted_json/battle_hints.json"

@onready var zone_host: Control = $ZoneHost
@onready var _hub_card: HubCard = $HubCard

var _current_zone_scene: Node = null
var _hint_used: bool = false
# The battle whose hint waits for the player to close the Inventory or the Store.
# 0 means none waits.
var _hint_battle_waiting: int = 0
# ZoneManager.pending_victory as it was when this Hub opened the Victory Window.
var _victory: Dictionary = {}
# Tests set this to 0 so the cutscene that Proceed plays ends at once.
var animation_speed: float = 1.0


# Every time the hub opens, after a load or on the return from a battle, this
# restores the save's zone. It has to run here and not in _ready(), because
# Godot runs the children's _ready() first, and the hotbar and the store window
# read ZoneManager.current_zone in theirs.
func _enter_tree():
	if GameData.current_save != null:
		ZoneManager.current_zone = GameData.current_save.section_in


func _ready():
	for window: CanvasItem in get_tree().get_nodes_in_group("menu_screen"):
		window.visibility_changed.connect(_sync_art_visibility)
	_sync_art_visibility()
	ZoneManager.zone_changed.connect(_load_zone)
	_load_zone(ZoneManager.current_zone)
	AudioManagerAuto.play_menu_music()
	# A cutscene that goes on to the map opens it here instead of landing in the
	# same hub (see _on_victory_proceed()).
	if ZoneManager.open_zone_map_on_load:
		ZoneManager.open_zone_map_on_load = false
		$ZoneMapOverlay.visible = true
	for group: StringName in [&"inventory_window", &"store_window"]:
		var window: Node = get_tree().get_first_node_in_group(group)
		if window != null:
			window.get_node("WindowShell").close_pressed.connect(_on_hint_window_closed)
	$VictoryWindow.proceed_pressed.connect(_on_victory_proceed)
	if not ZoneManager.pending_victory.is_empty():
		_open_victory(ZoneManager.pending_victory)
		ZoneManager.pending_victory = {}


func _load_zone(zone_id: int) -> void:
	if _current_zone_scene != null:
		_current_zone_scene.queue_free()
		_current_zone_scene = null
	var scene_path: String = str(ZoneManager.ZONES.get(zone_id, {}).get("scene", ""))
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		push_warning("game: no scene for zone %d" % zone_id)
		return
	_current_zone_scene = load(scene_path).instantiate()
	zone_host.add_child(_current_zone_scene)


func set_art_visible(art_visible: bool) -> void:
	zone_host.visible = art_visible


# Shows the hint card for the battle just won, once for each win, as the
# original's krinNavTutSpeech does (frame_42/DoAction_21.as:62-76). The original
# clears its flag Krin.tutSpeecher on every win and sets it on the first call,
# and the port builds a new Hub for each win, so _hint_used starts false and
# needs no reset (DECODED_ALGORITHMS.md, "Post-battle hint"). battle_hints.json
# gives each battle's index into NAVTITLE2 and NAVTEXT2. Battle 33 has an index
# but no text, so it shows nothing. The Tutorial option is not checked, as in
# the original. Victory's Proceed calls it after a win that did not level the
# player up, and _on_hint_window_closed() after a win that did.
func show_battle_hint(battle_id: int) -> void:
	if _hint_used:
		return
	_hint_used = true
	var file := FileAccess.open(BATTLE_HINTS_FILE, FileAccess.READ)
	if file == null:
		push_error("game: cannot open %s" % BATTLE_HINTS_FILE)
		return
	var hints: Dictionary = JSON.parse_string(file.get_as_text())
	var index: int = int(hints.get(str(battle_id), -1))
	if Strings.has("NAVTITLE2", index) and Strings.has("NAVTEXT2", index):
		_hub_card.show_card(Strings.text("NAVTITLE2", index), Strings.text("NAVTEXT2", index))


# The original opens the Victory Window on Navigation's load, and it sets
# PauseForScreen, so the hotbar, the orbs and the info spots do nothing until
# Proceed (frame_181/PlaceObject3_3142_175 onClipEvent(load), lines 3-7). The
# Window is in the "menu_screen" group, so the zone art hides while it shows.
func _open_victory(victory: Dictionary) -> void:
	_victory = victory
	$VictoryWindow.setup(GameData.current_save, victory["settlement"])
	$Hotbar.set_inert(true)
	$VictoryWindow.visible = true


# Proceed follows the original's order (DefineButton2_3004 on(release)): the
# autosave, then a queued cutscene, then the map after a boss win, and otherwise
# the Abilities Window after a level-up or the Hub with its hint. A boss win that
# also levels the player up opens only the map.
func _on_victory_proceed() -> void:
	if GameData.current_save != null and GameData.current_save.autosave:
		GameData.save_game()
	var settlement: BattleSettlement = _victory["settlement"]
	var battle_id: int = int(_victory["battle_id"])
	if not settlement.cutscene.is_empty():
		await _play_victory_cutscene(settlement.cutscene, settlement.goto_scene)
	elif bool(_victory["is_boss"]):
		# The original goes to overMap, a frame without the hotbar. The port's map
		# opens over the Hub, so the hotbar has to be live when the map closes.
		$Hotbar.set_inert(false)
		$VictoryWindow.visible = false
		$ZoneMapOverlay.visible = true
	else:
		$Hotbar.set_inert(false)
		if settlement.levels_gained > 0:
			# The original shows its skills frame and calls no hint. The hint
			# waits until the player closes the Inventory or the Store, as the
			# original's button 2853 does (DefineButton2_2853 on(press)).
			$Hotbar.toggle_menu_screen("abilities_window")
			_hint_battle_waiting = battle_id
		else:
			$VictoryWindow.visible = false
			show_battle_hint(battle_id)


# The original stops every sound before it jumps to the cutscene. Without that,
# the menu music plays on under the cutscene's own audio. The Victory Window
# stays under the cutscene, and its Proceed stays disabled.
func _play_victory_cutscene(cutscene_id: String, goto_scene: String) -> void:
	AudioManagerAuto.stop_all_sounds()
	var cutscene: CutscenePlayer = preload("res://scenes/cutscenes/cutscene_player.tscn").instantiate()
	cutscene.animation_speed = animation_speed
	add_child(cutscene)
	await cutscene.play(cutscene_id)
	# The original's cutscene clip starts the music rotation over when the clip
	# ends, before it starts the menu music (frame_263/PlaceObject2_3466_80
	# enterFrame, lines 15-31), so the next Hub plays the first menu track.
	AudioManagerAuto.reset_music_rotation()
	# gotoSceneKrin (frame_219): CS_CUT5 ends on the ending screen, and a
	# cutscene that just unlocked a new zone opens the zone map in the next Hub.
	# The original starts no music for the ending screen
	# (frame_263/PlaceObject2_3466_80 enterFrame, lines 15-19), so the menu track
	# waits until its OK! reaches the Hub.
	if goto_scene == "endMenu":
		var ending: EndingScreen = preload("res://scenes/battle/ending_screen.tscn").instantiate()
		ending.name = "EndingScreen"
		ending.ok_pressed.connect(_reload_hub)
		add_child(ending)
		return
	if goto_scene == "overMap":
		ZoneManager.open_zone_map_on_load = true
	_reload_hub()


# Builds a new Hub, as the original's jump to Navigation runs that frame again.
# The new Hub restores the save's zone and starts the menu music in _ready().
func _reload_hub() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_hint_window_closed() -> void:
	if _hint_battle_waiting == 0:
		return
	var battle_id: int = _hint_battle_waiting
	_hint_battle_waiting = 0
	show_battle_hint(battle_id)


func _sync_art_visibility() -> void:
	var art_visible: bool = true
	for window: CanvasItem in get_tree().get_nodes_in_group("menu_screen"):
		if window.visible:
			art_visible = false
	set_art_visible(art_visible)
