extends Button

@onready var texture_rect = $TextureRect

var hover_tween: Tween

#func _on_texture_rect_mouse_entered() -> void:
	#hover_tween = create_tween()
	#hover_tween.tween_property(
		#texture_rect.material,
		#"shader_parameter/hover_intensity",
		#1.0,
		#0.5
	#).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
#
#func _on_texture_rect_mouse_exited() -> void:
	#hover_tween = create_tween()
	#hover_tween.tween_property(
		#texture_rect.material,
		#"shader_parameter/hover_intensity",
		#0.0,
		#0.5
	#).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
