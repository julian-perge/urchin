extends Area2D
class_name OrbBase

@export var tooltip_text: String = ""

@export var orb_color: Color = Color.WHITE
@export var hover_scale: float = 1.2
@export var pulse_speed: float = 1.0

var original_scale: Vector2
var is_hovering: bool = false

var tooltip_scene = preload("res://scenes/ui/orb_tooltip.tscn")

func _ready():
	original_scale = scale
	$AnimationPlayer.stop()
	$AnimationPlayer.play("spin")
	setup_orb()
	
func setup_orb():
	print("Setting up orb color %s for %s" % [orb_color, name])
	$bottom.modulate = orb_color
	$middle.modulate = orb_color
	$top.modulate = orb_color

func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		interact()

func interact():
	print("Emitting event for %s" % name)
	pass

#func _make_custom_tooltip(for_text: String) -> Control:
	#print("_make_custom_tooltip, name %s , text %s" % [name, for_text])
	##var tooltip = tooltip_scene.instantiate()
	##tooltip.get_node("MarginContainer/VBoxContainer/Title").text = for_text
	##tooltip.tooltip_text = for_text
	#var tooltip = Label.new()
	#tooltip.text = for_text
	#return tooltip


func _on_mouse_entered() -> void:
	print("mouse ", name)
