extends Control

# This would be your item data class or resource
class_name ItemSlot

@onready var item_icon = $ItemIcon

func display_item(item):
	if item:
		item_icon.texture = load("res://resources/%s.png" % item.icon)
	else:
		item_icon.texture = null
