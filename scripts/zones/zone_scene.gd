extends Control

@export var zone_id: int = 1


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HubArt.mouse_filter = Control.MOUSE_FILTER_IGNORE
