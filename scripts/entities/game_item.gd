extends Resource
class_name GameItem

# Constants for item types and rarities
enum ItemType {
	NONE,
	TOOL,
	HEAD,
	CHEST,
	HAND,
	LEGS,
	FOOT,
	MAINHAND,
	OFFHAND,
	TWOHAND
}

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY
}

# ["Dreadnaught","Phantom","Enigma","Templar","Phaser"]
# DEPRECATED semantics (2026-07-18): these labels are dump-tooling junk - the
# raw value is a required UNIT id, not a player class. Use required_unit_id
# below for equip checks; this enum stays only because generated .tres store
# it for display.
enum ClassType {
	NONE = 0,
	DREADNAUGHT = 1,
	PHANTOM = 2,
	ENIGMA = 3,
	TEMPLAR = 4,
	PHASER = 5
}

@export var id: int
@export var looks: String
@export var sprite_image: Texture2D
@export var slot_image: Texture2D
@export var name: String
@export var display_name: String
@export var internal_name: String
@export var tooltip: String
@export var tooltipAlt: Array
@export var item_type: ItemType
@export var rarity: Rarity
@export var class_type: ClassType
# The real equip restriction (raw KRINITEM[3]): 0 = anyone, otherwise the
# unit id of the only party member who can wear it (4 = Veradux's Medic/KLIMA
# gear - the only restricted items in the game). The player's unit id is
# player_class + 1.
@export var required_unit_id: int
@export var required_level: int
@export var price: int
@export var price_modifier: float
@export var stats: Dictionary
