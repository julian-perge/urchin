# buff_icons.gd
# Resolves a Buff to its real icon, extracted from the original's own
# per-buff icon sheet (DefineSprite 100 - see
# dev/urchin_dev/swf/extract/buff_icons.py). No family/polarity fallback
# scheme - every buff either has a real extracted icon or (a handful of
# buffs the original itself never assigned a distinct frame to) doesn't,
# in which case this returns null and the caller skips that buff's icon.
class_name BuffIcons
extends RefCounted

const ICON_DIR: String = "res://assets/ui/buffs/"


static func icon_for(buff: Buff) -> Texture2D:
	if buff == null or buff.internal_name.is_empty():
		return null
	var path: String = "%s%s.png" % [ICON_DIR, buff.internal_name]
	if not ResourceLoader.exists(path):
		return null
	return load(path)
