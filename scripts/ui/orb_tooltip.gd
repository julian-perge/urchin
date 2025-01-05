extends Control
class_name OrbTooltip

var title_label: Label
var description_label: Label

func _ready() -> void:
	print("ready orb tooltip")
	title_label = get_node("CanvasLayer/PopupPanel/Title")
	description_label = get_node("CanvasLayer/PopupPanel/Desc")
