extends Node

# Signals
signal store_opened
signal store_closed

@onready var game_window = get_tree().get_first_node_in_group("game_window")
@onready var store_window = get_tree().get_first_node_in_group("store_window")

func _ready() -> void:
	store_window.hide()

func open_store() -> void:
	print("opening store from manager")
	store_window.open_store()
	game_window.hide()

func close_store() -> void:
	print("Closing store from  manager")
	store_window.hide()
	game_window.show()


const KRIN_SHOP_ITEMS = {
	# JAIL/PRISON
	0: [508, 509, 510, 511, 512, 513, 502, 514, 0, 0, 0, 0, 0, 0, 0],
	# "VILLAGE"
	1: [326, 327, 328, 382, 329, 526, 524, 523, 352, 353, 354, 350, 0, 0, 0],
	# "TRAIN"
	2: [528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 557, 558, 560, 554, 556],
	# "TUNNELS"
	3: [598, 599, 600, 601, 604, 574, 576, 580, 582, 583, 586, 590, 592, 593, 594],
	# "CITY"
	4: [650, 652, 653, 654, 656, 609, 614, 619, 629, 634, 611, 616, 621, 631, 636],
	# "ROME"
	5: [689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 703],
	# "JAPAN"
	6: [659, 668, 669, 674, 677, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	# "UTOPIA"
	7: [689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 703],
}
