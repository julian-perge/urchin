# buff_manager.gd
extends Node2D

class_name BuffManager

const BUFFS_FILE: String = "res://conversion_scripts/converted_json/buffs.json"

var buffs_by_id: Dictionary = {}
var buffs_by_internal_name: Dictionary = {}

func _ready():
	name = "BuffManager"
	load_data()

func load_data() -> void:
	print("Loading all buff data")
	var file: FileAccess = FileAccess.open(BUFFS_FILE, FileAccess.READ)
	if file == null:
		print("Could not open ", BUFFS_FILE)
		return
	var json = JSON.parse_string(file.get_as_text())
	file.close()
	for buff_data in json:
		var buff: Buff = Buff.from_json(buff_data)
		buffs_by_id[buff.id] = buff
		buffs_by_internal_name[buff.internal_name] = buff

func get_buff(id: int) -> Buff:
	return buffs_by_id.get(id)

# Moves reference buffs by internal_name (e.g. "AUTOREGEN"), not numeric id -
# see Ability.status_effect_id.
func get_buff_by_name(internal_name: String) -> Buff:
	return buffs_by_internal_name.get(internal_name)
