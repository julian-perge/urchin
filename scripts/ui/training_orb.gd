extends OrbBase
class_name TrainingFightOrb

signal training_requested

func _ready():
	orb_color = Color.html("FFCC00")
	tooltip_text = "Training"
	super._ready()

func interact():
	super.interact()
	training_requested.emit()
