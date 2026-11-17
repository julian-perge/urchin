# hub_card.gd
# The Hub's Info card (scenes/ui/hub_card.tscn), the original's
# krinNavFadeSpeech: a dim over the whole Stage, a framed card with a title and
# a text, and a close prompt. The Hub's own controls sit under the dim, which
# takes every click while the card shows, so the Hub does nothing else until the
# player presses the prompt. The original's hit button covers the prompt only,
# so a click anywhere else on the card does nothing.
#
# The card is in the group "hub_card". A button or an info spot that opens it
# finds it there, as krinNavHideUI is reached from anywhere in the original
# (frame_42/DoAction_21.as:9-25).
class_name HubCard
extends Control

signal closed

const GROUP: StringName = &"hub_card"

@onready var _title: Label = %Title
@onready var _body: Label = %Body
@onready var _prompt: Label = %Prompt


func _ready() -> void:
	add_to_group(GROUP)
	# DefineSprite_2848/frame_1/DoAction.as:1 fills the prompt with SYSTEM[8].
	_prompt.text = Strings.system(8)


func show_card(title: String, text: String) -> void:
	_title.text = title
	_body.text = text
	show()


func hide_card() -> void:
	hide()


func _on_close_button_pressed() -> void:
	hide_card()
	closed.emit()
