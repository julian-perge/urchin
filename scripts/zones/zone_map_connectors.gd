# zone_map_connectors.gd
# Draws the connector line between each zone and the zone that unlocks it
# (frame_449/DoAction.as's krinMapper.lineMC loop) - was never ported at all,
# not a rendering regression. Per zone (i > 1 in the original, zone 1 has no
# incoming link): a thick black backing line, then a thinner line on top -
# blue if the path is open (ZoneProgression.is_zone_unlocked), gray if it's
# still locked. Sibling of $ZoneMap (background) and $Zones (the buttons
# whose positions this reads directly, so the lines always meet their
# centers even if the buttons get repositioned) in zone_map.tscn, drawn
# between the two so lines sit above the background but under the buttons.
extends Control

const BACKING_COLOR: Color = Color(0, 0, 0)
const BACKING_WIDTH: float = 6.0
const UNLOCKED_COLOR: Color = Color8(49, 137, 223)
const LOCKED_COLOR: Color = Color8(51, 51, 51)
const LINE_WIDTH: float = 2.0


func _ready() -> void:
	ZoneManager.zone_unlocked.connect(func(_zone_id): queue_redraw())
	visibility_changed.connect(queue_redraw)


func _draw() -> void:
	var save: PlayerSave = GameData.current_save
	for zone_id in ZoneProgression.QUEST_HUB:
		var linked: int = int(ZoneProgression.QUEST_HUB[zone_id]["linked_zone"])
		if linked <= 0:
			continue
		var from_button: Control = get_node("../Zones/Zone%d" % zone_id)
		var to_button: Control = get_node("../Zones/Zone%d" % linked)
		var from_point: Vector2 = from_button.position + from_button.size / 2.0
		var to_point: Vector2 = to_button.position + to_button.size / 2.0
		var unlocked: bool = save != null and ZoneProgression.is_zone_unlocked(save, zone_id)
		draw_line(from_point, to_point, BACKING_COLOR, BACKING_WIDTH)
		draw_line(from_point, to_point, UNLOCKED_COLOR if unlocked else LOCKED_COLOR, LINE_WIDTH)
