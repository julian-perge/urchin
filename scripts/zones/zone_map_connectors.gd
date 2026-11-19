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
# Each line has round caps, because frame_449/DoAction.as gives lineStyle() no
# caps argument and Flash then rounds both ends. A round cap on a straight line
# is a circle of half the line's width at each end.
#
# lineMC carries a DropShadow, which extract_zone_map writes to zone_map.json.
# The child CanvasGroup Shadow draws behind the lines. Its Lines node draws
# every line again, opaque and moved by the shadow's distance at its angle, and
# scenes/ui/zone_map_shadow.gdshader blurs them and tints them to the shadow's
# colour, alpha and strength.
extends Control

const RECORD_FILE := "res://assets/ui/zone_map/zone_map.json"
const BACKING_COLOR: Color = Color(0, 0, 0)
const BACKING_WIDTH: float = 6.0
const UNLOCKED_COLOR: Color = Color8(49, 137, 223)
const LOCKED_COLOR: Color = Color8(51, 51, 51)
const LINE_WIDTH: float = 2.0

@onready var _shadow: CanvasGroup = $Shadow
@onready var _shadow_lines: Node2D = $Shadow/Lines


func _ready() -> void:
	visibility_changed.connect(_redraw)
	get_viewport().size_changed.connect(_redraw)
	_shadow_lines.draw.connect(_draw_shadow)
	var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECORD_FILE))
	if not (record is Dictionary and (record as Dictionary).has("line_shadow")):
		push_error("zone map: %s holds no line_shadow" % RECORD_FILE)
		return
	var shadow: Dictionary = record["line_shadow"]
	_shadow_lines.position = Vector2.from_angle(deg_to_rad(float(shadow["angle"]))) * float(shadow["distance"])
	var tint := Color.html(str(shadow["color"]))
	tint.a = float(shadow["alpha"])
	var shadow_material := _shadow.material as ShaderMaterial
	shadow_material.set_shader_parameter("shadow_color", tint)
	shadow_material.set_shader_parameter("blur", Vector2(float(shadow["blur"][0]), float(shadow["blur"][1])))
	shadow_material.set_shader_parameter("strength", float(shadow["strength"]))


func _redraw() -> void:
	queue_redraw()
	_shadow_lines.queue_redraw()


# Flash measures the blur in stage px, so the shader needs the screen px for each
# stage px. That changes with the window's size, so _ready() also redraws the
# lines when the window's size changes.
func _draw_shadow() -> void:
	var stage_scale: float = get_viewport().get_final_transform().get_scale().x
	(_shadow.material as ShaderMaterial).set_shader_parameter("stage_scale", stage_scale)
	for link: Dictionary in _links():
		_capped_line(_shadow_lines, link["from"], link["to"], Color.WHITE, BACKING_WIDTH)


func _draw() -> void:
	for link: Dictionary in _links():
		_capped_line(self, link["from"], link["to"], BACKING_COLOR, BACKING_WIDTH)
		_capped_line(self, link["from"], link["to"], UNLOCKED_COLOR if link["unlocked"] else LOCKED_COLOR, LINE_WIDTH)


static func _capped_line(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	canvas.draw_line(from, to, color, width)
	canvas.draw_circle(from, width / 2.0, color)
	canvas.draw_circle(to, width / 2.0, color)


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
