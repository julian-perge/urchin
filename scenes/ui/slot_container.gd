extends GridContainer

class_name SlotContainer

@export var item_slot: PackedScene = preload("res://scenes/ui/item_slot.tscn")

var slots

func display_item_slots(cols, rows):
	columns = cols
	slots = cols * rows
	for index in range(slots):
		var item_slot = item_slot.instantiate()
		add_child(item_slot)
		item_slot.display_item(Inventory.items[index])
	Inventory.items_changed.connect(_on_Inventory_items_changed.bind(self))

func _on_Inventory_items_changed(indexes):
	print("inventory store changed")
	for index in indexes:
		if index < slots:
			var item_slot = get_child(index)
			item_slot.display_item(Inventory.items[index])
