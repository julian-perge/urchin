extends Control

@export var zone_id: int = 1


func _ready():
	# The root and the art cover the whole Hub. With the default filter they
	# would take every mouse event before it reaches an orb's hit box.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HubArt.mouse_filter = Control.MOUSE_FILTER_IGNORE
