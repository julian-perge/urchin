extends Area2D
class_name OrbBase

# Each orb's script sets these from its button's on(rollOver) strings, which
# the tooltip shows as a title over a body.
var tooltip_title: String = ""
var tooltip_body: String = ""

@export var orb_color: Color = Color.WHITE
@export var hover_scale: float = 1.2
@export var pulse_speed: float = 1.0

var original_scale: Vector2
var is_hovering: bool = false

var tooltip_scene: PackedScene = preload("res://scenes/ui/orb_tooltip.tscn")

func _ready():
	original_scale = scale
	$AnimationPlayer.stop()
	$AnimationPlayer.play("spin")
	setup_orb()
	var hit_box: Control = $Control
	hit_box.gui_input.connect(_on_hit_box_input)
	hit_box.mouse_entered.connect(func(): GameTooltip.show_title_and_body(tooltip_title, tooltip_body, hit_box))
	hit_box.mouse_exited.connect(GameTooltip.hide_tooltip)

func _on_hit_box_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _hub_is_inert():
			interact()


# The hotbar holds the Hub's inert state (hotbar.gd, set_inert). An orb with no
# hotbar in its tree is never inert.
func _hub_is_inert() -> bool:
	var hotbar: Node = get_tree().get_first_node_in_group("hotbar")
	return hotbar != null and hotbar.is_inert()

func setup_orb():
	print("Setting up orb color %s for %s" % [orb_color, name])
	$bottom.modulate = orb_color
	$middle.modulate = orb_color
	$top.modulate = orb_color

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
