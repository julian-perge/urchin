extends OrbBase
class_name TrainingFightOrb

signal training_requested

func _ready():
	super._ready()
	orb_color = Color.YELLOW
	tooltip_text = "Training"

func interact():
	training_requested.emit()
