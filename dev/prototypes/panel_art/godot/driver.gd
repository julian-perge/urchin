extends SceneTree

# Draws each KRINMENU label's backdrop and panels under one StyleBox variant and
# saves the framebuffer, so the variants can be scored against ffdec and Flash.
# Every variant carries the inner shadow shader ticket 115 decided on.

const HERE := "/Users/sweetjp/tmp/2026-11-09-panel-art"
const PROTO := "/Users/sweetjp/tmp/2026-11-09-inner-shadow/proto/dev/prototypes/victory_containers"

const SHADOW_SHADER := """
shader_type canvas_item;
uniform float cx = 3.5355339;
uniform float cy = 3.5355339;
uniform float box = 5.0;
varying vec2 local;
void vertex() {
	local = VERTEX;
}
void fragment() {
	float ax = clamp((local.x - (cx - box * 0.5)) / box, 0.0, 1.0);
	float ay = clamp((local.y - (cy - box * 0.5)) / box, 0.0, 1.0);
	COLOR.rgb *= ax * ay;
}
"""


class CustomBox:
	extends StyleBox
	var fill := Color.BLACK
	var line := 1.0

	func _draw(to_canvas_item: RID, rect: Rect2) -> void:
		var rs := RenderingServer
		rs.canvas_item_add_rect(to_canvas_item, rect, Color.BLACK)
		rs.canvas_item_add_rect(to_canvas_item, rect.grow(-line), fill)


var data: Dictionary
var art: Dictionary
var proto_art: Dictionary
var layout: Dictionary
var queue: Array = []
var index := -1
var wait := 0
var stage: Control
var out_dir := HERE + "/out"
var textures := {}
var shadow: ShaderMaterial


func _initialize() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(HERE + "/labels.json"))
	art = JSON.parse_string(FileAccess.get_file_as_string(HERE + "/art.json"))
	proto_art = JSON.parse_string(FileAccess.get_file_as_string(PROTO + "/art.json"))
	layout = JSON.parse_string(FileAccess.get_file_as_string(PROTO + "/win_layout.json"))
	var label_names: Array = data["labels"].keys()
	var variants: Array = ["flat_axis", "flat_mean", "flat_mean_brect", "custom", "art2", "art4"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--labels="):
			label_names = Array(a.substr(9).split(","))
		elif a.begins_with("--variants="):
			variants = Array(a.substr(11).split(","))
	var shader := Shader.new()
	shader.code = SHADOW_SHADER
	shadow = ShaderMaterial.new()
	shadow.shader = shader
	for label in label_names:
		for variant in variants:
			queue.append([label, variant])
	_next()


func _process(_delta: float) -> bool:
	wait -= 1
	if wait > 0:
		return false
	var image := root.get_texture().get_image()
	var current: Array = queue[index]
	var path := "%s/%s__%s.png" % [out_dir, current[0], current[1]]
	image.save_png(path)
	print("saved ", path, " ", image.get_size())
	return _next()


func _next() -> bool:
	if stage != null:
		stage.free()
		stage = null
	index += 1
	if index >= queue.size():
		return true
	_build(queue[index][0], queue[index][1])
	wait = 6
	return false


func _build(label: String, variant: String) -> void:
	stage = Control.new()
	stage.size = Vector2(800, 600)
	root.add_child(stage)
	var clear := ColorRect.new()
	clear.color = Color.MAGENTA
	clear.size = Vector2(800, 600)
	stage.add_child(clear)
	var backdrop := PanelContainer.new()
	backdrop.add_theme_stylebox_override("panel", _proto_backdrop())
	_place(backdrop, layout["backdrop"]["rect"])
	stage.add_child(backdrop)
	for p: Dictionary in data["labels"][label]["panels"]:
		var panel := PanelContainer.new()
		var rect: Array = p["rect"]
		var style: StyleBox
		var fill := Color(p["fill"])
		var sx: float = p["sx"]
		var sy: float = p["sy"]
		var stroke: float = p["stroke"]
		var fr: Array = p["fill_rect"]
		match variant:
			"flat_axis":
				var f := StyleBoxFlat.new()
				f.bg_color = fill
				f.border_color = Color.BLACK
				f.border_width_left = maxi(roundi(sx), 1)
				f.border_width_right = f.border_width_left
				f.border_width_top = maxi(roundi(sy), 1)
				f.border_width_bottom = f.border_width_top
				style = f
			"flat_mean":
				var f := StyleBoxFlat.new()
				f.bg_color = fill
				f.border_color = Color.BLACK
				var b := maxi(roundi(stroke), 1)
				f.set_border_width_all(b)
				style = f
				rect = _grow(fr, b * 0.5)
			"flat_mean_brect":
				var f := StyleBoxFlat.new()
				f.bg_color = fill
				f.border_color = Color.BLACK
				f.set_border_width_all(maxi(roundi(stroke), 1))
				style = f
			"custom":
				var c := CustomBox.new()
				c.fill = fill
				c.line = stroke
				style = c
				rect = _grow(fr, stroke * 0.5)
			"art2", "art4":
				style = _art_style(p, 2 if variant == "art2" else 4)
		panel.material = shadow
		panel.add_theme_stylebox_override("panel", style)
		_place(panel, rect)
		stage.add_child(panel)


func _grow(r: Array, by: float) -> Array:
	return [float(r[0]) - by, float(r[1]) - by, float(r[2]) + by * 2.0, float(r[3]) + by * 2.0]


func _place(control: Control, r: Array) -> void:
	control.position = Vector2(r[0], r[1])
	control.size = Vector2(r[2], r[3])


func _proto_backdrop() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _load(PROTO + "/images/art/backdrop.png")
	var entry: Dictionary = proto_art["backdrop"]
	var a: Array = entry["rect"]
	var s: Array = entry["shape_rect"]
	style.expand_margin_left = float(s[0]) - float(a[0])
	style.expand_margin_top = float(s[1]) - float(a[1])
	style.expand_margin_right = (float(a[0]) + float(a[2])) - (float(s[0]) + float(s[2]))
	style.expand_margin_bottom = (float(a[1]) + float(a[3])) - (float(s[1]) + float(s[3]))
	return style


func _art_style(p: Dictionary, z: int) -> StyleBoxTexture:
	var key := "%d_z%d" % [int(p["sprite"]), z]
	var entry: Dictionary = art[key]
	var a: Array = entry["rect"]
	var b: Array = entry["bounds"]
	var sx: float = p["sx"]
	var sy: float = p["sy"]
	var style := StyleBoxTexture.new()
	style.texture = _load(HERE + "/art/" + key + ".png")
	style.expand_margin_left = (float(b[0]) - float(a[0])) * sx
	style.expand_margin_top = (float(b[1]) - float(a[1])) * sy
	style.expand_margin_right = (float(a[0]) + float(a[2]) - float(b[2])) * sx
	style.expand_margin_bottom = (float(a[1]) + float(a[3]) - float(b[3])) * sy
	return style


func _load(path: String) -> Texture2D:
	if not textures.has(path):
		textures[path] = ImageTexture.create_from_image(Image.load_from_file(path))
	return textures[path]
