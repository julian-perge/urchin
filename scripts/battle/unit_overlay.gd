# unit_overlay.gd
# The unmirrored per-unit HUD overlay shown over each battling character's
# paper doll: name, health bar + value, focus bar, and a hover/click zone.
# battle_scene.gd instances one per unit slot, positions it at the unit's
# world position, and wires the hover/click signals itself (the slot each
# instance represents is only known at instance time, not authoring time).
# The hover ring's actual `_draw()` callback also stays in battle_scene.gd
# (its color depends on the unit's live relation to the player) - this
# script only exposes the ring node for that connection.
extends Control
class_name UnitOverlay

@onready var ring: Control = $Ring
@onready var name_label: Label = $NameLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_value: Label = $HealthValue
@onready var focus_bar: ProgressBar = $FocusBar
@onready var hit_button: Button = $HitButton


func setup(unit_name: String) -> void:
	name_label.text = unit_name
