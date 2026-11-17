# game.gd
# Root of scenes/game.tscn - the zone hub shell. Hosts the current zone's
# scene (scenes/zones/*, swapped on ZoneManager.zone_changed), with the
# store window, the world-map overlay, and the hotbar layered on top, with the
# Info card above all of them.
# Battles take over via ZoneManager's scene switch and return here.
extends Control

# dev/converted_json/battle_hints.json, from convert_battle_hints.
const BATTLE_HINTS_FILE := "res://dev/converted_json/battle_hints.json"

@onready var zone_host: Control = $ZoneHost
@onready var _hub_card: HubCard = $HubCard

var _current_zone_scene: Node = null
var _hint_used: bool = false


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
	# A boss win, or a cutscene that just unlocked a new zone, opens the map here
	# instead of landing in the same hub (see battle_scene.gd's
	# _on_victory_proceed()).
	if ZoneManager.open_zone_map_on_load:
		ZoneManager.open_zone_map_on_load = false
		$ZoneMapOverlay.visible = true
	# A win that levelled the player up opens the Abilities window the way the
	# hotbar's button does, so the new skill point is in front of the player.
	if ZoneManager.open_abilities_on_load:
		ZoneManager.open_abilities_on_load = false
		$Hotbar.toggle_menu_screen("abilities_window")


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
# the original. Nothing calls this method until #241 lands.
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


func _sync_art_visibility() -> void:
	var art_visible: bool = true
	for window: CanvasItem in get_tree().get_nodes_in_group("menu_screen"):
		if window.visible:
			art_visible = false
	set_art_visible(art_visible)
