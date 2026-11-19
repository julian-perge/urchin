# zone_map.gd
# The World map, the original's root frame overMap (spec/107-world-map.md). Its
# pieces sit where scenes/zone_map.tscn types them, and the rect test checks
# them against the SWF. The map has no close button, because the original's
# only way out is a zone the player can use, and zone 1 always is.
extends Control

# The player picked a zone the map can open. The original's zone button jumps
# to Navigation (DefineButton2_4155 on(release)), so the Hub fades in again.
signal zone_picked(zone_id: int)

const OPEN_FACE: Texture2D = preload("res://assets/ui/zone_map/zone_button_open.png")
const LOCKED_FACE: Texture2D = preload("res://assets/ui/zone_map/zone_button_locked.png")


func _ready():
	add_to_group("zone_map_panel")
	for zone_button in $Zones.get_children():
		var zone_id: int = int(zone_button.name.trim_prefix("Zone"))
		zone_button.pressed.connect(_on_zone_selected.bind(zone_id))
		zone_button.mouse_entered.connect(_show_tooltip.bind(zone_button, zone_id))
		zone_button.mouse_exited.connect(GameTooltip.hide_tooltip)
	visibility_changed.connect(_on_visibility_changed)


func close_map() -> void:
	visible = false


# The original hides the hotbar while the world map is up. The buttons refresh
# only when the map shows, so a map built with no save keeps the open faces that
# its .tscn holds, which is the state the rect record measures.
func _on_visibility_changed() -> void:
	if visible:
		_refresh_button_states()
	for hotbar in get_tree().get_nodes_in_group("hotbar"):
		hotbar.visible = not visible


# frame_449/DoAction.as sends a zone it cannot use to underGF's "blank" frame and
# clears its canUse, which the release script reads.
func _refresh_button_states():
	var max_zone: int = ZoneManager.max_zone()
	for zone_button: TextureButton in $Zones.get_children():
		var zone_id: int = int(zone_button.name.trim_prefix("Zone"))
		# Like the original's mb6 and mb7, which hide themselves on load
		# (DefineSprite_4173), a zone past the cap is hidden rather than shown locked.
		zone_button.visible = zone_id <= max_zone
		var usable: bool = ZoneManager.can_access_zone(zone_id)
		zone_button.disabled = not usable
		(zone_button.get_node("Art") as TextureRect).texture = OPEN_FACE if usable else LOCKED_FACE


# DefineButton2_4155 on(rollOver) reads no canUse, so a locked zone shows its
# name too.
func _show_tooltip(zone_button: Control, zone_id: int) -> void:
	GameTooltip.show_title_and_body(Strings.text("ZONES", zone_id), Strings.text("ZONES2", zone_id), zone_button)


func _on_zone_selected(zone_id: int):
	if ZoneManager.can_access_zone(zone_id):
		ZoneManager.change_zone(zone_id)
		close_map()
		zone_picked.emit(zone_id)
