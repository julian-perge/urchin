extends OrbBase
class_name TrainingFightOrb

signal training_requested

func _ready():
	orb_color = Color.html("FFCC00")
	tooltip_text = "Training Fight\nClick here to fight a practice battle for experience."
	super._ready()

func interact():
	super.interact()
	training_requested.emit()
	# Uniform pick from the zone's unlocked training pool, broadcast via
	# ZoneManager.battle_selected (the future battle scene listens there).
	ZoneManager.request_training_fight()
