# stance_row.gd
# One companion's stance-mode row in the battle bottom bar (name + 5
# aggression-preset buttons). battle_scene.gd instances one per deployed
# companion (0-2, only for those actually in the fight), positions it, and
# wires each button's press to that companion's party id + mode - both are
# only known at instance time. _refresh_stance_row() (still in
# battle_scene.gd) re-styles the buttons on every stance change; this
# script only exposes them.
extends Control
class_name StanceRow

@onready var name_label: Label = $NameLabel
@onready var buttons: Array[Button] = [$Mode0, $Mode1, $Mode2, $Mode3, $Mode4]


func setup(unit_name: String) -> void:
	name_label.text = unit_name
