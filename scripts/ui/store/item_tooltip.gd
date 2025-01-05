extends PanelContainer

class_name ItemTooltip

@onready var title_container = %TitleContainer
@onready var type_container = %TypeContainer
@onready var stats_container = %StatsContainer

var stat_label_scene = preload("res://scenes/ui/store/stat_label.tscn")

func _ready():
	hide()

func display(item_data: GameItem, global_pos: Vector2):
	# Set position
	global_position = global_pos
	print("Displaying %s at %s" % [item_data.name, global_position])
	
	# Update header (price and name)
	title_container.text = "€%d - %s" % [item_data.price_modifier, item_data.name]
	
	# Update type info
	type_container.text = "Lvl. %d %s" % [item_data.required_level, item_data.item_type]
	
	# Clear old stats
	for child in stats_container.get_children():
		child.queue_free()
	
	# Add new stats
	for stat in item_data.stats:
		var stat_label = stat_label_scene.instantiate()
		stats_container.add_child(stat_label)
		stat_label.text = "%s +%d" % [stat, item_data.stats[stat]]
		stat_label.modulate = Color.YELLOW  # Make stats yellow like in screenshot
	
	show()

func hide_tooltip():
	hide()
