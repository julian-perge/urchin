# manual_panel.gd
# The Game Manual (scenes/ui/menu/manual_panel.tscn), the original's designMenu,
# root frame 124. The left panel lists five topics, and the right panel shows
# the text of the topic the player picks (spec/107-game-manual.md).
class_name ManualPanel
extends Control

# MANUAL holds the five topic captions and MANUALEX their five texts.
const TOPIC_COUNT: int = 5

@onready var _body: Label = $Body


# frame_124/DoAction.as fills the five topics from MANUAL each time the Screen
# opens. They never change, so the panel fills them once.
func _ready() -> void:
	for topic in TOPIC_COUNT:
		get_node("Topics/Topic%d/Caption" % topic).text = Strings.text("MANUAL", topic)
	open()


# frame_124/DoAction.as also sets the body to EXPLAINEXTRA, "Please select a
# topic.", each time the Screen opens, so a topic read before does not stay.
func open() -> void:
	_body.text = Strings.text("EXPLAINEXTRA")


# The topic hit buttons DefineButton2_2800 to DefineButton2_2804 each set the
# body to one MANUALEX text on release. From the top, they show MANUALEX[0] to
# MANUALEX[4], so the scene binds each button to its topic's index.
func show_topic(topic: int) -> void:
	_body.text = Strings.text("MANUALEX", topic)
