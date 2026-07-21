# move_manager.gd
extends Node2D

class_name MoveManager

const MOVES_FILE: String = "res://python_conversion_scripts/converted_json/moves_abilities.json"

var moves_by_id: Dictionary = {}

func _ready():
	name = "MoveManager"
	load_data()

func load_data() -> void:
	print("Loading all move data")
	var file: FileAccess = FileAccess.open(MOVES_FILE, FileAccess.READ)
	if file == null:
		print("Could not open ", MOVES_FILE)
		return
	var json = JSON.parse_string(file.get_as_text())
	file.close()
	for move_data in json:
		var ability: Ability = Ability.from_json(move_data)
		moves_by_id[ability.id] = ability

func get_move(id: int) -> Ability:
	return moves_by_id.get(id)
