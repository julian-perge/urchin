# zone_map.gd
# Script for the zone map panel (scenes/zone_map.tscn) - the 7 hand-placed
# TextureButton nodes under $Zones (Zone1..Zone7). This used to be shared with
# the hotbar's map-toggle button (scripts/ui/zone_map_toggle_button.gd now
# covers that instead), which is why most of this was commented out before -
# one script can't sensibly serve both a single toggle button and a 7-button
# panel at the same time.
extends Control

func _ready():
	add_to_group("zone_map_panel")
	visible = false
	for zone_button in $Zones.get_children():
		var zone_id: int = int(zone_button.name.trim_prefix("Zone"))
		zone_button.pressed.connect(_on_zone_selected.bind(zone_id))
	if has_node("CloseButton"):
		$CloseButton.pressed.connect(close_map)
	ZoneManager.zone_unlocked.connect(_on_zone_unlocked)
	visibility_changed.connect(_on_visibility_changed)
	_refresh_button_states()


func close_map() -> void:
	visible = false


# The original hides the hotbar while the world map is up.
func _on_visibility_changed() -> void:
	if visible:
		_refresh_button_states()
	for hotbar in get_tree().get_nodes_in_group("hotbar"):
		hotbar.visible = not visible

func _refresh_button_states():
	for zone_button in $Zones.get_children():
		var zone_id: int = int(zone_button.name.trim_prefix("Zone"))
		zone_button.disabled = not ZoneManager.can_access_zone(zone_id)

func _on_zone_selected(zone_id: int):
	if ZoneManager.can_access_zone(zone_id):
		ZoneManager.change_zone(zone_id)
		close_map()

func _on_zone_unlocked(_zone_id: int):
	_refresh_button_states()
