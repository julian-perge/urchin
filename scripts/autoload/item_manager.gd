# item_manager.gd
extends Node2D

class_name ItemManager

const ITEMS_DIR: String = "res://resources/items/"

var items: Array[GameItem] = []
var items_by_id: Dictionary = {}

func _ready():
	name = "ItemManager"
	load_data()

func load_data() -> void:
	print("Loading all item data")
	var dir = DirAccess.open(ITEMS_DIR)
	if dir == null:
		print("Could not open ", ITEMS_DIR)
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var item = load(ITEMS_DIR + file_name)
			if item is GameItem:
				items.append(item)
				items_by_id[item.id] = item
		file_name = dir.get_next()
	dir.list_dir_end()

func get_item(id: int) -> GameItem:
	return items_by_id.get(id)
