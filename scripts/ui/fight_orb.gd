# story_fight_orb.gd
extends OrbBase
class_name StoryFightOrb

signal fight_requested

func _ready():
	super._ready()
	orb_color = Color.RED
	tooltip_text = "Next Story Fight"

func interact():
	fight_requested.emit()
	print("Emitting event for %s" % name)
