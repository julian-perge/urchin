# game.gd
# Root of scenes/game.tscn - the zone hub shell. Hosts the current zone's
# scene (scenes/zones/*, swapped on ZoneManager.zone_changed), with the
# store window, the world-map overlay, and the hotbar layered on top.
# Battles take over via ZoneManager's scene switch and return here.
extends Control

@onready var zone_host: Control = $ZoneHost

var _current_zone_scene: Node = null


func _ready():
	ZoneManager.zone_changed.connect(_load_zone)
	# Returning from a battle (or the menu): restore the save's zone.
	if GameData.current_save != null:
		ZoneManager.current_zone = GameData.current_save.section_in
	_load_zone(ZoneManager.current_zone)
	AudioManagerAuto.play_menu_music()


func _load_zone(zone_id: int) -> void:
	if _current_zone_scene != null:
		_current_zone_scene.queue_free()
		_current_zone_scene = null
	var scene_path = str(ZoneManager.ZONES.get(zone_id, {}).get("scene", ""))
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		push_warning("game: no scene for zone %d" % zone_id)
		return
	_current_zone_scene = load(scene_path).instantiate()
	zone_host.add_child(_current_zone_scene)
