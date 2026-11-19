# disc_reader.gd
# Reads the colour of an ability icon's disc back out of a drawn icon, for the
# tests of each place that shows one. Most icons' art covers all of the disc
# but its anti-aliased rim, so no pixel shows the disc alone. At the pixel where
# the disc adds the most alpha, the drawn pixel is the art over the disc, and
# that equation gives the disc's colour.
extends RefCounted


static func disc_color(drawn: Texture2D, icon_key: String) -> Color:
	var art: Image = (load(AbilityIcon.ICON_DIR + icon_key + ".png") as Texture2D).get_image()
	art.convert(Image.FORMAT_RGBA8)
	var image: Image = drawn.get_image()
	image.convert(Image.FORMAT_RGBA8)
	var best: Vector2i = Vector2i(-1, -1)
	var best_gain: float = 0.0
	for y in image.get_height():
		for x in image.get_width():
			var gain: float = image.get_pixel(x, y).a - art.get_pixel(x, y).a
			if gain > best_gain:
				best_gain = gain
				best = Vector2i(x, y)
	if best.x < 0:
		return Color(0, 0, 0, 0)
	var over: Color = image.get_pixelv(best)
	var under: Color = art.get_pixelv(best)
	var premultiplied: Color = (Color(over.r, over.g, over.b) * over.a - Color(under.r, under.g, under.b) * under.a) / best_gain
	return Color(premultiplied.r, premultiplied.g, premultiplied.b)
