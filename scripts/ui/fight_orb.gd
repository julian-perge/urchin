extends OrbBase
class_name StoryFightOrb

signal fight_requested

func _ready():
	orb_color = Color.html("C40000")
	tooltip_text = "Story Battle\nClick here to take on the next story fight."
	super._ready()

func interact():
	super.interact()
	fight_requested.emit()
	# Picks the next story battle for the current zone and broadcasts it via
	# ZoneManager.battle_selected (the future battle scene listens there).
	ZoneManager.request_story_fight()
