# unit_manager.gd
extends Node2D

class_name UnitManager

const UNITS_DIR: String = "res://resources/units/"

var units: Array[Character] = []
# Unit template id -> Character (what BattleSetup.build_units consumes).
var units_by_id: Dictionary = {}

func _ready():
	name = "UnitManager"
	load_data()

func load_data() -> void:
	print("Loading all units data")
	var dir: DirAccess = DirAccess.open(UNITS_DIR)
	if dir == null:
		print("Could not open ", UNITS_DIR)
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var unit = load(UNITS_DIR + file_name)
			if unit is Character:
				units.append(unit)
				# Older generated .tres predate Character.id - the filename
				# prefix ("15_doctor_hedger.tres") carries the id either way.
				var unit_id: int = unit.id if unit.id != 0 else int(file_name.get_slice("_", 0))
				units_by_id[unit_id] = unit
		file_name = dir.get_next()
	dir.list_dir_end()

func get_unit(id: int) -> Character:
	return units_by_id.get(id)
