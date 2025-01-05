extends OrbBase
class_name StoryFightOrb

signal fight_requested

func _ready():
	orb_color = Color.html("C40000")
	tooltip_text = "Next Story Fight"
	super._ready()

func interact():
	super.interact()
	fight_requested.emit()
