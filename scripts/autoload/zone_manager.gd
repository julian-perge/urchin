# zone_manager.gd
extends Node2D

class_name ZoneManager

@onready var current_zone: int = 1
@onready var unlocked_zones: Array[int] = [1] # Start with first zone unlocked

signal zone_changed(zone_id: int)
signal zone_unlocked(zone_id: int)

func unlock_zone(zone_id: int):
	if zone_id not in unlocked_zones:
		unlocked_zones.append(zone_id)
		zone_unlocked.emit(zone_id)

func can_access_zone(zone_id: int) -> bool:
	return zone_id in unlocked_zones

func change_zone(zone_id: int):
	if can_access_zone(zone_id):
		current_zone = zone_id
		zone_changed.emit(zone_id)

# Zone definitions stored as resource
const ZONES = {
	1: {
		"name": "New Alcatraz",
		"subtitle": "The Iron Prison",
		"background": "alcatraz_bg",
		"max_stages": 12
	},
	2: {
		"name": "Oberursel",
		"subtitle": "The Frozen Village",
		"background": "village_bg",
		"max_stages": 15
	}
	# Add other zones...
}
