extends OrbBase
class_name TrainingFightOrb

signal training_requested

func _ready():
	orb_color = Color.html("FFCC00")
	# DefineButton2_3186 on(rollOver) shows SYSTEM[29] over SYSTEM[30]
	# (frame_1/DoAction.as:96-97).
	tooltip_title = "Training Fight"
	tooltip_body = "Click here to fight an enemy for training."
	super._ready()

func interact():
	super.interact()
	training_requested.emit()
	# Uniform pick from the zone's unlocked training pool, broadcast via
	# ZoneManager.battle_selected (the future battle scene listens there).
	ZoneManager.request_training_fight()
