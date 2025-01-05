# zone_manager.gd
extends Node2D

class_name ItemManager

const ITEMS_FILE: String = "res://resources/items.json"

var items_data: Array = []
var items: Array[GameItem] = []

func _ready():
	name = "ItemManager"
	#load_data()
	#for _item in items_data:
		#items.append(GameItem.new(_item))

func load_data() -> void:
	print("Loading all item data")
	var file = FileAccess.open(ITEMS_FILE, FileAccess.READ)
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error == OK:
		items_data = json.get_data()
	else:
		print("JSON Parse Error: ", json.get_error_message(), " in ", ITEMS_FILE, " at line ", json.get_error_line())
