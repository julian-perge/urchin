extends OrbBase
class_name ItemStoreOrb

func _ready():
	orb_color = Color.html("68CBF4")
	tooltip_text = "Item Store"
	super._ready()

func interact():
	super.interact()
	StoreManager.open_store()
