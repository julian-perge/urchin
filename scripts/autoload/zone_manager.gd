# zone_manager.gd
extends Node2D

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
# Krin.zoneName = ["EMPTY","PRISON","VILLAGE","TRAIN","TUNNELS","CITY","ROME","JAPAN","UTOPIA","JAPAN","STORM","EDEN","DOME","BETA"];
# questHub.push("EMPTY");
#questHub.push({progressMax:9,linked:0,nameLabel:"Prison"});
#trainFight[1] = new Array();
#trainFight[1] = [[1000,-1],[1001,5],[1002,6],[1003,9]];
#trainFightCap[1] = 9;

#questHub.push({progressMax:12,linked:1,nameLabel:"Village"});
#trainFight[2] = new Array();
#trainFight[2] = [[1004,-1],[1005,2],[1006,3],[1007,5],[1008,6],[1009,8],[1010,9],[1011,11]];
#trainFightCap[2] = 12;

#questHub.push({progressMax:8,linked:2,nameLabel:"Train"});
#trainFight[3] = new Array();
#trainFight[3] = [[1015,-1],[1012,2],[1013,3],[1014,4]];
#trainFightCap[3] = 15;

#questHub.push({progressMax:9,linked:3,nameLabel:"Tunnels"});
#trainFight[4] = new Array();
#trainFight[4] = [[1016,-1],[1017,4],[1018,5],[1019,6],[1020,8]];
#trainFightCap[4] = 18;

#questHub.push({progressMax:13,linked:4,nameLabel:"City"});
#trainFight[5] = new Array();
#trainFight[5] = [[1022,-1],[1021,4],[1023,2],[1024,4],[1025,10]];
#trainFightCap[5] = 23;

#questHub.push({progressMax:3,linked:5,nameLabel:"Zone 6"});
#trainFight[6] = new Array();
#trainFight[6] = [[1026,-1]];
#trainFightCap[6] = 40;

#questHub.push({progressMax:3,linked:6,nameLabel:"Zone 7"});
#trainFight[7] = new Array();
#trainFight[7] = [[1022,-1],[1021,4],[1023,2],[1024,4],[1025,10]];
#trainFightCap[7] = 30;
const ZONES = {
	1: {
		"name": "New Alcatraz",
		"subtitle": "The Iron Prison",
		"background": "alcatraz_bg",
		"max_stages": 9,
		"training_max_stages": 9,
	},
	2: {
		"name": "Oberursel",
		"subtitle": "The Frozen Village",
		"background": "village_bg",
		"max_stages": 12,
		"training_max_stages": 12,
	},
	3: {
		"name": "Ivory Line",
		"subtitle": "The Train",
		"background": "village_bg",
		"max_stages": 8,
		"training_max_stages": 15,
	},
	4: {
		"name": "Oberursel",
		"subtitle": "The Frozen Village",
		"background": "village_bg",
		"max_stages": 9,
		"training_max_stages": 18,
	},
	5: {
		"name": "Oberursel",
		"subtitle": "The Frozen Village",
		"background": "village_bg",
		"max_stages": 13,
		"training_max_stages": 23,
	},
	6: {
		"name": "Oberursel",
		"subtitle": "The Frozen Village",
		"background": "village_bg",
		"max_stages": 3,
		"training_max_stages": 40,
	},
	7: {
		"name": "Oberursel",
		"subtitle": "The Frozen Village",
		"background": "village_bg",
		"max_stages": 3,
		"training_max_stages": 30,
	}
}
