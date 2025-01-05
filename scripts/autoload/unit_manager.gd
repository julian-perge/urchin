# zone_manager.gd
extends Node2D

class_name UnitManager

const UNITS_FILE: String = "res://resources/units.json"

var units_data: Array = []
var units: Array[Character] = []

func _ready():
	name = "UnitManager"
	#load_data()
	#for _unit in units_data:
		#units.append(Character.new(_unit))

func load_data() -> void:
	print("Loading all units data")
	var file = FileAccess.open(UNITS_FILE, FileAccess.READ)
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error == OK:
		units_data = json.get_data()
	else:
		print("JSON Parse Error: ", json.get_error_message(), " in ", UNITS_FILE, " at line ", json.get_error_line())
