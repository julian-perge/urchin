extends SlotContainer

func _ready():
	display_item_slots(Inventory.cols, Inventory.rows)
	await get_tree().create_timer(1)
	position = (get_viewport_rect().size - get_rect().size) / 2
	#hide()
