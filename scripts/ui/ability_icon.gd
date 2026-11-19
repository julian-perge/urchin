# ability_icon.gd
# The ability icons that extract_ability_icons writes, with the orb's back disc
# in a colour. In the original the disc is its own clip, moveColor, whose load
# script gives it the colour its owner sets in KNcolor2, which every owner
# takes from the move's element (DefineSprite_2427/frame_15/PlaceObject2_2244_1).
# The extractor writes each icon without the disc, the disc once in white, and
# the icons that show it, and texture() draws the icon over the disc in the
# colour it is given.
class_name AbilityIcon
extends RefCounted

const ICON_DIR: String = "res://assets/ui/abilities/"
const DISC_PATH: String = "res://assets/ui/abilities/disc.png"
const DISC_LIST_PATH: String = "res://assets/ui/abilities/disc.json"

static var _tinted: Dictionary = {}
static var _textures: Dictionary = {}


# -> the icon for `move` with its disc in the move's element colour, or null
# when the extractor wrote no icon for it.
static func for_move(move: Ability) -> Texture2D:
	return texture(key(move.display_name), element_color(move))


# -> the icon file `icon_key` names with its disc in `disc_color`, or null
# when there is no such file. An icon that shows no disc comes back as it is.
static func texture(icon_key: String, disc_color: Color) -> Texture2D:
	var path: String = ICON_DIR + icon_key + ".png"
	if not ResourceLoader.exists(path):
		return null
	if not shows_disc(icon_key):
		return load(path)
	var cache_key: String = "%s %s" % [icon_key, disc_color.to_html()]
	if not _textures.has(cache_key):
		_textures[cache_key] = ImageTexture.create_from_image(_draw(load(path), disc_color))
	return _textures[cache_key]


# The colour each owner of an icon gives its disc: the element of the move's
# KRINABILITYB row, looked up in elementColorArray. A passive talent node's
# row is move 0's, because its ID is 0 (frame_41/DoAction_2.as:120).
static func element_color(move: Ability) -> Color:
	return MenuTheme.ELEMENT_COLORS[move.damage_element_type]


static func shows_disc(icon_key: String) -> bool:
	if _tinted.is_empty():
		var listed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DISC_LIST_PATH))
		for file_name: String in listed["tinted"]:
			_tinted[file_name.get_basename()] = true
	return _tinted.has(icon_key)


# Mirrors dev/urchin_dev/swf/extract/ability_icons.py's sanitize()
# (re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_")), so a move name with
# punctuation finds the file the extractor wrote.
static func key(label: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^A-Za-z0-9]+")
	return regex.sub(label, "_", true).lstrip("_").rstrip("_")


# setRGB keeps the disc's alpha and replaces its colour, and the icon's art
# sits on depths above it, so the art is drawn over the tinted disc.
static func _draw(icon: Texture2D, disc_color: Color) -> Image:
	var disc: Image = (load(DISC_PATH) as Texture2D).get_image()
	disc.convert(Image.FORMAT_RGBA8)
	var art: Image = icon.get_image()
	art.convert(Image.FORMAT_RGBA8)
	var drawn: Image = Image.create(disc.get_width(), disc.get_height(), false, Image.FORMAT_RGBA8)
	for y in disc.get_height():
		for x in disc.get_width():
			var alpha: float = disc.get_pixel(x, y).a
			drawn.set_pixel(x, y, Color(disc_color, alpha) if alpha > 0.0 else Color(0, 0, 0, 0))
	drawn.blend_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), Vector2i.ZERO)
	return drawn
