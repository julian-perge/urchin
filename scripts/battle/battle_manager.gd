# battle_manager.gd
class_name BattleManager
extends Node

signal turn_started(character)
signal turn_ended(character)

var active_characters = []
var current_turn = 0

func execute_move(ability, source, target):
	# Convert from ActionScript executeMove()
	#var damage = calculate_damage(ability, source, target)
	#apply_damage(target, damage)
	print("execute_move")
