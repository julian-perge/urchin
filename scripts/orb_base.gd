extends Area2D
class_name OrbBase

@export var tooltip_text: String = ""
@export var orb_color: Color = Color.WHITE
@export var hover_scale: float = 1.2
@export var pulse_speed: float = 1.0

var original_scale: Vector2
var is_hovering: bool = false

func _ready():
	original_scale = scale
	setup_orb()
	connect_signals()
	
func setup_orb():
	$Sprite2D.modulate = orb_color
	$Label.text = tooltip_text
	$Label.hide()
	
	# Setup glow effect
	$GlowEffect.color = orb_color
	$GlowEffect.emitting = true

func connect_signals():
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)

func _on_mouse_entered():
	print("Mouse entered for %s" % name)
	is_hovering = true
	var tween = create_tween()
	tween.tween_property(self, "scale", original_scale * hover_scale, 0.1)
	$Label.show()

func _on_mouse_exited():
	print("Mouse exited for %s" % name)
	is_hovering = false
	var tween = create_tween()
	tween.tween_property(self, "scale", original_scale, 0.1)
	$Label.hide()

func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		interact()

func _process(delta):
	if not is_hovering:
		# Add gentle floating animation
		position.y += sin(Time.get_ticks_msec() * 0.001 * pulse_speed) * 0.1

func interact():
	# Override in derived classes
	pass
