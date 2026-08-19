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
	var path: String = "%s%s.png" % [ICON_DIR, _sanitize(buff.internal_name)]
	if not ResourceLoader.exists(path):
		return null
	return load(path)


# Mirrors dev/urchin_dev/swf/extract/buff_icons.py's own sanitize() exactly
# (re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_")), so a buff name with a
# character the extractor's filename can't hold resolves to the file that
# was actually written, rather than the two sides agreeing only because
# today's names happen not to need it.
static func _sanitize(name: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^A-Za-z0-9]+")
	return regex.sub(name, "_", true).lstrip("_").rstrip("_")
