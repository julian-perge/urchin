# character.gd
extends Resource
class_name Character

#var stats = {
	#"health": 100,
	#"strength": 30,
	#"speed": 100,
	#"magic": 30,
	#"focus": 100
#}
#
#var abilities = []
#var buffs = []

@export var name: String
@export var vitality: float
@export var strength: float
@export var magic: float
@export var speed: float
@export var focus: float
@export var moves: Dictionary
@export var stats: Dictionary
@export var visuals: Dictionary
