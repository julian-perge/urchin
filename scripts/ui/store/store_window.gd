# store_window.gd
extends Control

signal store_closed

@onready var gold_amount = %PlayerGold
@onready var sell_button = %SellItemButton
@onready var delete_button = %DeleteItemButton
@onready var store_items = %StoreItems
@onready var inventory_grid = %InventoryGrid

var selected_inventory_item: ItemSlot = null
var is_initialized: bool = false

func _ready():
	# Connect button signals
	if sell_button and delete_button:
		sell_button.pressed.connect(_on_sell_pressed)
		delete_button.pressed.connect(_on_delete_pressed)
		is_initialized = true
	else:
		print("Store window nodes not ready yet")
	print("Initalized store window")
	refresh_store()

func open_store():
	show()
	refresh_store()

func refresh_store():
	update_gold_display()
	load_store_items()
	load_inventory()

func update_gold_display() -> void:
	var money = GameData.get_player_gold()
	# Handle negative numbers by adding the "minus" sign in advance, as we discard it
	# when looping over the number.
	var formatted_number := "-" if sign(money) == -1 else ""
	var index := 0
	var number_string := str(abs(money))
	
	for digit in number_string:
		formatted_number += digit
		
		var counter := number_string.length() - index
		
		# Don't add a comma at the end of the number, but add a comma every 3 digits
		# (taking into account the number's length).
		if counter >= 2 and counter % 3 == 1:
			formatted_number += ","
			
		index += 1
	
	#gold_amount.text = "€ " + formatted_number

func load_store_items():
	pass
	#for child in store_items.get_children():
		#child.queue_free()
	#
	#var store_inventory: Array[GameItem] = ItemManagerAuto.items.slice(1,7)
	#print("Loading store items")
	#for item_data in store_inventory:
		#print("store item_data -> %s" % [item_data.name])
		#var item_slot = preload("res://scenes/ui/item_slot.tscn").instantiate()
		#store_items.add_child(item_slot)
		#item_slot.set_item(item_data)

func load_inventory():
	pass
	#for child in inventory_grid.get_children():
		#child.queue_free()
	#
	#var player_inventory = GameData.get_player_inventory()
	#print("Loading store items")
	#for item_data in player_inventory:
		#print("inv item_data -> %s" % [item_data.name])
		#var item_slot = preload("res://scenes/ui/item_slot.tscn").instantiate()
		#inventory_grid.add_child(item_slot)
		#item_slot.set_item(item_data)

func _on_sell_pressed():
	# Handle selling selected item
	pass

func _on_delete_pressed():
	# Handle deleting selected item
	pass


func _on_exit_pressed() -> void:
	StoreManager.close_store()
