# zone_scene.gd
# Root script for the per-zone hub scenes (scenes/zones/zone*.tscn). Each
# scene is laid out in the original 800x600 stage space: the hub art fills
# the rect (18, 16)-(782, 430) and the three orbs sit at the exact positions
# extracted from the original SWF's zone-hub sprite (sprite 3287, one labeled
# frame per zone; container offset (400, 222.9) applied).
#
# The orbs themselves are orb.tscn instances with the story/training/store
# scripts attached - they talk to ZoneManager directly. game.tscn's ZoneHost
# instances the right zone scene whenever ZoneManager.zone_changed fires.
extends Control

@export var zone_id: int = 1


func _ready():
	# Let clicks fall through to the orbs' hit boxes - a full-rect Control
	# with the default STOP filter would swallow every mouse event.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HubArt.mouse_filter = Control.MOUSE_FILTER_IGNORE
