extends OrbBase
class_name ItemStoreOrb

func _ready():
	orb_color = Color.html("68CBF4")
	# DefineButton2_3187 on(rollOver) shows SYSTEM[15] over SYSTEM[16]
	# (frame_1/DoAction.as:82-83).
	tooltip_title = Strings.system(15)
	tooltip_body = Strings.system(16)
	super._ready()

func interact():
	super.interact()
	StoreManager.open_store()
