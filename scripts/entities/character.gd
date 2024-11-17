# character.gd
class_name Character
extends Node2D

var stats = {
	"health": 100,
	"strength": 30,
	"speed": 100,
	"magic": 30,
	"focus": 100
}

var abilities = []
var buffs = []

func _init():
	pass
