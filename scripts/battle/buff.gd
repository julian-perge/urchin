# buff.gd
class_name Buff
extends Resource

@export var duration: int
@export var effect_value: float
@export var effect_type: String

func apply(target: Character):
	# Convert from ActionScript applyBuffKrin()
	match effect_type:
		"damage":
			target.stats.health -= effect_value
		"heal":
			target.stats.health += effect_value
