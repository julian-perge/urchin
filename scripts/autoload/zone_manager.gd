# zone_manager.gd
# Scene-facing zone state. Progression rules live in ZoneProgression
# (scripts/zones/zone_progression.gd, pure/testable); this autoload glues
# them to GameData's active save and the zone-map/orb UI.
extends Node2D

@onready var current_zone: int = 1

# The battle pick handed to the battle scene: {battle_id, is_story_progress,
# is_boss, train_cap}. Set by request_story_fight()/request_training_fight(),
# consumed by battle_scene.gd's _ready().
var pending_battle: Dictionary = {}
# Tests/headless flows set this false to keep request_* from switching scenes.
var auto_start_battles: bool = true

signal zone_changed(zone_id: int)
signal zone_unlocked(zone_id: int)
signal battle_selected(info: Dictionary)

func can_access_zone(zone_id: int) -> bool:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return zone_id == 1
	if zone_id > ZoneProgression.max_zone(save.difficulty):
		return false
	return ZoneProgression.is_zone_unlocked(save, zone_id)

func change_zone(zone_id: int):
	if can_access_zone(zone_id):
		current_zone = zone_id
		if GameData.current_save != null:
			GameData.current_save.section_in = zone_id
		zone_changed.emit(zone_id)

# Story-fight orb handler: picks the next story battle in the current zone.
func request_story_fight() -> Dictionary:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return {}
	save.section_in = current_zone
	var info: Dictionary = ZoneProgression.pick_story_battle(save)
	if not info.is_empty():
		info["train_cap"] = BattleSetup.DEFAULT_TRAIN_CAP
		_launch_battle(info)
	return info

# Training orb handler: uniform pick from the zone's unlocked training pool.
func request_training_fight() -> Dictionary:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return {}
	save.section_in = current_zone
	var info: Dictionary = ZoneProgression.pick_training_battle(save)
	if not info.is_empty():
		info["is_story_progress"] = false
		info["is_boss"] = false
		save.used_training = true  # the Predator/Legend achievement tracker
		_launch_battle(info)
	return info

func _launch_battle(info: Dictionary) -> void:
	pending_battle = info
	battle_selected.emit(info)
	if auto_start_battles:
		get_tree().change_scene_to_file.call_deferred("res://scenes/battle_scene.tscn")

# Call on battle victory: advances story progress, may add companions, may
# name a cutscene. Re-emits zone_unlocked for any newly reachable zones.
func report_battle_won(battle_id: int, was_story_progress: bool) -> Dictionary:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return {}
	var unlocked_before: Array[Variant] = []
	for zone_id in ZONES:
		if ZoneProgression.is_zone_unlocked(save, zone_id):
			unlocked_before.append(zone_id)
	var result: Dictionary = ZoneProgression.after_battle_won(save, battle_id, was_story_progress)
	for zone_id in ZONES:
		if ZoneProgression.is_zone_unlocked(save, zone_id) and zone_id not in unlocked_before:
			zone_unlocked.emit(zone_id)
	return result

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
# Names/subtitles: frame1/sonny2_zones.txt (KrinLang.ENGLISH.ZONES/ZONES2).
# zone_background/sky_background: derived empirically from battles.json - each
# zone's battle id range (KBR1xx=zone1, KBR2xx=zone2, ... KBR7xx=zone7) is
# dominated by one zone_background/sky_background pair; asset files live in
# assets/backgrounds/zone/ and assets/backgrounds/sky/. Zone 2 and zone 6 also
# use a second background (CHURCH) for a subset of their battles, and zone 7
# (the last, thinnest zone in the original game) reuses zone 5's assets rather
# than having its own.
const ZONES: Dictionary[Variant, Variant] = {
	1: {
		"name": "New Alcatraz",
		"subtitle": "The Iron Prison",
		"zone_background": "JAIL",
		"sky_background": "SKY_JAIL",
		"max_stages": 9,
		"training_max_stages": 9,
		"scene": "res://scenes/zones/zone1_prison.tscn",
	},
	2: {
		"name": "Oberursel",
		"subtitle": "The Frozen Village",
		"zone_background": "SNOW",
		"sky_background": "SKY_SNOW",
		"max_stages": 12,
		"training_max_stages": 12,
		"scene": "res://scenes/zones/zone2_village.tscn",
	},
	3: {
		"name": "Ivory Line",
		"subtitle": "The Train",
		"zone_background": "TRAIN",
		"sky_background": "SKY_TRAIN",
		"max_stages": 8,
		"training_max_stages": 15,
		"scene": "res://scenes/zones/zone3_train.tscn",
	},
	4: {
		"name": "Labyrinth",
		"subtitle": "Tunnel of Illusions",
		"zone_background": "TUNNEL",
		"sky_background": "SKY_TUNNEL",
		"max_stages": 9,
		"training_max_stages": 18,
		"scene": "res://scenes/zones/zone4_tunnels.tscn",
	},
	5: {
		"name": "Hew",
		"subtitle": "The Dystopia",
		"zone_background": "STREETS",
		"sky_background": "SKY_STREETS",
		"max_stages": 13,
		"training_max_stages": 23,
		"scene": "res://scenes/zones/zone5_city.tscn",
	},
	6: {
		"name": "Il Sanctus",
		"subtitle": "The Supreme Court",
		"zone_background": "CHURCH",
		"sky_background": "SKY_ROME",
		"max_stages": 3,
		"training_max_stages": 40,
		"scene": "res://scenes/zones/zone6_rome.tscn",
	},
	7: {
		"name": "Sho'Tul Shelf",
		"subtitle": "The Divided Cliff",
		"zone_background": "STREETS",
		"sky_background": "SKY_TUNNEL",
		"max_stages": 3,
		"training_max_stages": 30,
		"scene": "res://scenes/zones/zone7_shotul.tscn",
	}
}
