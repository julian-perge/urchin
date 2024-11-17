# zone_map.gd
extends Control

@onready var zone_container = $ScrollContainer/Zones
@onready var zone_manager = get_node("/root/ZoneManager")

#func _ready():
	## Create zone buttons dynamically
	#for zone_id in ZoneManager.ZONES:
		#var zone_button = preload("res://scenes/zone_map.tscn").instantiate()
		#zone_button.setup(zone_id, ZoneManager.ZONES[zone_id])
		#zone_container.add_child(zone_button)
		#
		## Connect signals
		#zone_button.pressed.connect(_on_zone_selected.bind(zone_id))
		#
		## Update visual state
		#zone_button.set_accessible(zone_manager.can_access_zone(zone_id))
		#
	## Connect to zone manager signals
	#zone_manager.zone_unlocked.connect(_on_zone_unlocked)

func _on_zone_selected(zone_id: int):
	if zone_manager.can_access_zone(zone_id):
		zone_manager.change_zone(zone_id)
		hide() # Hide map after selecti"res://scenes/game.tscn"on

func _on_zone_unlocked(zone_id: int):
	# Update visual state of zone button
	for zone_button in zone_container.get_children():
		if zone_button.zone_id == zone_id:
			zone_button.set_accessible(true)
			break
