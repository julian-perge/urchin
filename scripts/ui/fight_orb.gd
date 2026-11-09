extends OrbBase
class_name StoryFightOrb

signal fight_requested

func _ready():
	orb_color = Color.html("C40000")
	# DefineButton2_3188 on(rollOver) shows SYSTEM[13] over SYSTEM[14]
	# (frame_1/DoAction.as:80-81).
	tooltip_title = "Next Battle"
	tooltip_body = "Click here to enter the next progress battle of this zone."
	super._ready()

func interact():
	super.interact()
	fight_requested.emit()
	# Picks the next story battle for the current zone and broadcasts it via
	# ZoneManager.battle_selected (the future battle scene listens there).
	ZoneManager.request_story_fight()
