extends OrbBase
class_name ItemStoreOrb

signal store_opened

func _ready():
	super._ready()
	orb_color = Color.CYAN
	tooltip_text = "Item Store"

func interact():
	store_opened.emit()
