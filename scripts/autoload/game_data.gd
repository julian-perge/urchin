extends Node

class_name GameData

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

static func get_player_inventory() -> Dictionary:
	return {}

static func get_store_inventory() -> Dictionary:
	return {}

static func get_player_gold() -> float:
	return 1.0

static func can_afford_item(item_data: Dictionary) -> bool:
	return false

static func purchase_item(item_data: Dictionary) -> bool:
	return false

static func sell_item(item_data: Dictionary) -> bool:
	return false
