extends SceneTree

const DOWNLOADS := "/Users/sweetjp/tmp/2026-11-09-urchin-sans-font/downloads/"
const ARIMO := ["arimo-regular/Arimo-Regular.ttf", "arimo-bold/Arimo-Bold.ttf"]
const HEROS := ["heros-regular/texgyreheros-regular.otf", "heros-bold/texgyreheros-bold.otf"]
const VARIANTS: Array = [
	["Arimo", ARIMO, 0, 0, TextServer.HINTING_LIGHT, TextServer.SUBPIXEL_POSITIONING_AUTO],
	["Heros", HEROS, 0, 1, TextServer.HINTING_LIGHT, TextServer.SUBPIXEL_POSITIONING_AUTO],
	["Arimo unhinted", ARIMO, 1, 0, TextServer.HINTING_NONE, TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER],
	["Heros unhinted", HEROS, 1, 1, TextServer.HINTING_NONE, TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER],
]

var frames := 0


func _font(relative: String, hinting: int, subpixel: int) -> FontFile:
	var font := FontFile.new()
	font.load_dynamic_font(DOWNLOADS + relative)
	font.hinting = hinting
	font.subpixel_positioning = subpixel
	return font


func _initialize() -> void:
	var lines: Array = JSON.parse_string(FileAccess.get_file_as_string("res://lines.json"))
	var manifest: Array = []
	var y := 0.0
	for line in lines:
		var size: int = line["size"]
		var height := float(size) * 1.5 + 4.0
		for variant in VARIANTS:
			var rect := ColorRect.new()
			rect.color = Color(line["bg"])
			rect.position = Vector2(400 * variant[2], y + height * variant[3])
			rect.size = Vector2(400, height)
			root.add_child(rect)
			var label := Label.new()
			label.text = line["text"]
			label.position = Vector2(8, 0)
			label.size = Vector2(384, height)
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_override("font", _font(variant[1][1 if line["bold"] else 0], variant[4], variant[5]))
			label.add_theme_font_size_override("font_size", size)
			label.add_theme_color_override("font_color", Color(line["color"]))
			rect.add_child(label)
			manifest.append({"text": line["text"], "face": variant[0], "x": rect.position.x, "y": rect.position.y, "height": height})
		y += height * 2.0
	print("total height ", y)
	FileAccess.open("res://rows.json", FileAccess.WRITE).store_string(JSON.stringify(manifest))


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 20:
		return false
	var image := root.get_texture().get_image()
	print("capture size ", image.get_size(), " format ", image.get_format())
	var converted := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGB8)
	for row in image.get_height():
		for column in image.get_width():
			converted.set_pixel(column, row, image.get_pixel(column, row).linear_to_srgb())
	converted.save_png("res://godot_render.png")
	return true
