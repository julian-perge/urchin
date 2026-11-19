# zone_map_connectors.gd
# Draws the link between each zone the map shows and the zone that unlocks it,
# as frame_449/DoAction.as draws them into krinMapper.lineMC, with the loop
# stopping at the same zone cap that hides the buttons. Each link is a 6 px
# black line, then a 2 px line on top: blue when the linked zone is beaten
# (ZoneProgression.is_zone_unlocked), gray when not. Each line runs between
# the centres of the two zone buttons in zone_map.tscn, which are the
# registration points of mb1 to mb7. This node sits between the map art and
# the buttons, as lineMC sits between them in sprite 4173.
#
# lineMC carries a DropShadow, which extract_zone_map writes to zone_map.json.
# draw_line() has no blur, so the shadow is every line drawn again first, moved
# by the shadow's distance at its angle, in its colour at its alpha times its
# strength. The blur of 2 px is left out.
extends Control

const RECORD_FILE := "res://assets/ui/zone_map/zone_map.json"
const BACKING_COLOR: Color = Color(0, 0, 0)
const BACKING_WIDTH: float = 6.0
const UNLOCKED_COLOR: Color = Color8(49, 137, 223)
const LOCKED_COLOR: Color = Color8(51, 51, 51)
const LINE_WIDTH: float = 2.0

var _shadow_offset: Vector2 = Vector2.ZERO
var _shadow_color: Color = Color.TRANSPARENT


func _ready() -> void:
	visibility_changed.connect(queue_redraw)
	var file := FileAccess.open(RECORD_FILE, FileAccess.READ)
	if file == null:
		push_error("zone map: cannot open %s" % RECORD_FILE)
		return
	var shadow: Dictionary = JSON.parse_string(file.get_as_text())["line_shadow"]
	_shadow_offset = Vector2.from_angle(deg_to_rad(float(shadow["angle"]))) * float(shadow["distance"])
	_shadow_color = Color.html(str(shadow["color"]))
	_shadow_color.a = minf(float(shadow["alpha"]) * float(shadow["strength"]), 1.0)


func _draw() -> void:
	var links: Array[Dictionary] = _links()
	for link: Dictionary in links:
		draw_line(link["from"] + _shadow_offset, link["to"] + _shadow_offset, _shadow_color, BACKING_WIDTH)
	for link: Dictionary in links:
		draw_line(link["from"], link["to"], BACKING_COLOR, BACKING_WIDTH)
		draw_line(link["from"], link["to"], UNLOCKED_COLOR if link["unlocked"] else LOCKED_COLOR, LINE_WIDTH)


func _links() -> Array[Dictionary]:
	var save: PlayerSave = GameData.current_save
	var max_zone: int = ZoneManager.max_zone()
	var links: Array[Dictionary] = []
	for zone_id in ZoneProgression.QUEST_HUB:
		var linked: int = int(ZoneProgression.QUEST_HUB[zone_id]["linked_zone"])
		if linked <= 0 or zone_id > max_zone:
			continue
		var from_button: Control = get_node("../Zones/Zone%d" % zone_id)
		var to_button: Control = get_node("../Zones/Zone%d" % linked)
		links.append({
			"from": from_button.position + from_button.size / 2.0,
			"to": to_button.position + to_button.size / 2.0,
			"unlocked": save != null and ZoneProgression.is_zone_unlocked(save, zone_id),
		})
	return links
