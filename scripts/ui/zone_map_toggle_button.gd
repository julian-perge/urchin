# zone_map_toggle_button.gd
# The hotbar's world-map button - opens/closes the zone map panel
# (scenes/zone_map.tscn, in the "zone_map_panel" group). Split out from
# scripts/zones/zone_map.gd, which used to be attached to both this button AND
# the panel itself - one script can't sensibly serve both roles.
extends BaseButton

# BaseButton virtual - fires on press with no scene-side signal wiring.
func _pressed() -> void:
	var panel = get_tree().get_first_node_in_group("zone_map_panel")
	if panel:
		panel.visible = not panel.visible
