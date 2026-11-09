extends SceneTree

const ROOT := "/Users/sweetjp/tmp/2026-11-09-inner-shadow"
const PROTO := ROOT + "/proto/dev/prototypes/victory_containers"
const ART := ROOT + "/art"
const FILL := {"left": "grey", "right": "grey", "centre": "dark", "bar": "bar"}
const NAMES := ["left", "centre", "right", "bar"]
const DIST := 3.5355339

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


class InnerShadowBox:
	extends StyleBox
	var fill := Color.BLACK
	var line := Vector2.ONE
	var box := 5.0

	func _draw(to_canvas_item: RID, rect: Rect2) -> void:
		var rs := RenderingServer
		rs.canvas_item_add_rect(to_canvas_item, rect, fill)
		var black := Color.BLACK
		var p := rect.position
		var s := rect.size
		rs.canvas_item_add_rect(to_canvas_item, Rect2(p, Vector2(line.x, s.y)), black)
		rs.canvas_item_add_rect(to_canvas_item, Rect2(p + Vector2(s.x - line.x, 0), Vector2(line.x, s.y)), black)
		rs.canvas_item_add_rect(to_canvas_item, Rect2(p, Vector2(s.x, line.y)), black)
		rs.canvas_item_add_rect(to_canvas_item, Rect2(p + Vector2(0, s.y - line.y), Vector2(s.x, line.y)), black)
		var ramp_start: float = DIST - box * 0.5
		var stops: Array[float] = [0.0]
		for i in 7:
			stops.append(ramp_start + box * i / 6.0)
		var xs: Array[float] = stops.duplicate()
		xs.append(s.x)
		var ys: Array[float] = stops.duplicate()
		ys.append(s.y)
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		for y in ys:
			for x in xs:
				points.append(p + Vector2(x, y))
				var ax: float = clampf((x - ramp_start) / box, 0.0, 1.0)
				var ay: float = clampf((y - ramp_start) / box, 0.0, 1.0)
				colors.append(Color(0, 0, 0, 1.0 - ax * ay))
		var w := xs.size()
		for j in ys.size() - 1:
			for i in w - 1:
				var a := j * w + i
				if colors[a].a == 0.0 and colors[a + 1].a == 0.0 and colors[a + w].a == 0.0 and colors[a + w + 1].a == 0.0:
					continue
				indices.append_array(PackedInt32Array([a, a + 1, a + w, a + 1, a + w + 1, a + w]))
		rs.canvas_item_add_triangle_array(to_canvas_item, indices, points, colors)


var variants: Array[String] = [
	"flat", "plainart", "baked", "nine_raw_nearest", "nine_raw_linear",
	"nine_aligned_nearest", "nine_aligned_linear", "shader5", "shader45", "stylebox", "stylebox45", "shader_wrong", "shader_plainart",
]
var layout: Dictionary
var art: Dictionary
var info: Dictionary
var textures: Dictionary = {}
var index := -1
var wait := 0
var stage: Control
var out_dir := ROOT + "/out"


func _initialize() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string(PROTO + "/win_layout.json"))
	art = JSON.parse_string(FileAccess.get_file_as_string(PROTO + "/art.json"))
	info = JSON.parse_string(FileAccess.get_file_as_string(ART + "/info.json"))
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		if a == "--no-snap":
			root.gui_snap_controls_to_pixels = false
			root.snap_2d_transforms_to_pixel = false
		if a.begins_with("--only="):
			variants.assign(Array(a.substr(7).split(",")))
	_next()


func _process(_delta: float) -> bool:
	wait -= 1
	if wait > 0:
		return false
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, variants[index]]
	image.save_png(path)
	print("saved ", path, " ", image.get_size(), " format ", image.get_format())
	return _next()


func _next() -> bool:
	if stage != null:
		stage.free()
		stage = null
	index += 1
	if index >= variants.size():
		return true
	_build(variants[index])
	wait = 6
	return false


func _build(variant: String) -> void:
	stage = Control.new()
	stage.position = Vector2.ZERO
	stage.size = Vector2(800, 600)
	root.add_child(stage)
	var clear := ColorRect.new()
	clear.color = Color.MAGENTA
	clear.size = Vector2(800, 600)
	stage.add_child(clear)
	var backdrop := PanelContainer.new()
	backdrop.add_theme_stylebox_override("panel", _texture_style("backdrop", PROTO + "/images/art/backdrop.png", Vector2.ONE))
	_place(backdrop, layout["backdrop"]["rect"])
	stage.add_child(backdrop)
	for name: String in NAMES:
		var panel := PanelContainer.new()
		_style(panel, variant, name)
		_place(panel, layout["panels"][name]["rect"])
		stage.add_child(panel)


func _place(control: Control, r: Array) -> void:
	control.position = Vector2(r[0], r[1])
	control.size = Vector2(r[2], r[3])


func _factor(name: String) -> Vector2:
	var s: Array = layout["panels"][name]["scale"]
	return Vector2(s[0], s[1])


func _flat_style(name: String) -> StyleBoxFlat:
	var panel: Dictionary = layout["panels"][name]
	var factor := _factor(name)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(panel["fills"][0]["color"])
	style.border_color = Color.BLACK
	style.border_width_left = maxi(roundi(factor.x), 1)
	style.border_width_right = style.border_width_left
	style.border_width_top = maxi(roundi(factor.y), 1)
	style.border_width_bottom = style.border_width_top
	return style


func _style(panel: PanelContainer, variant: String, name: String) -> void:
	var style: StyleBox
	var factor := _factor(name)
	match variant:
		"flat":
			style = _flat_style(name)
		"plainart":
			style = _texture_style("panel_%s_plain" % name, PROTO + "/images/art/panel_%s_plain.png" % name, factor)
		"baked":
			style = _texture_style("panel_%s_shadow" % name, PROTO + "/images/art/panel_%s_shadow.png" % name, factor)
		"nine_raw_nearest", "nine_raw_linear":
			style = _nine_raw(name)
		"nine_aligned_nearest", "nine_aligned_linear":
			style = _nine_aligned(name)
		"shader5", "shader45", "shader_wrong":
			style = _flat_style(name)
			var shader := Shader.new()
			shader.code = SHADOW_SHADER
			var material := ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("box", 4.5 if variant == "shader45" else 5.0)
			if variant == "shader_wrong":
				material.set_shader_parameter("cx", 5.5)
				material.set_shader_parameter("cy", 5.5)
			panel.material = material
		"shader_plainart":
			style = _texture_style("panel_%s_plain" % name, PROTO + "/images/art/panel_%s_plain.png" % name, factor)
			var plain_shader := Shader.new()
			plain_shader.code = SHADOW_SHADER
			var plain_material := ShaderMaterial.new()
			plain_material.shader = plain_shader
			panel.material = plain_material
		"stylebox", "stylebox45":
			var box := InnerShadowBox.new()
			box.fill = Color(layout["panels"][name]["fills"][0]["color"])
			box.line = factor
			box.box = 5.0 if variant == "stylebox" else 4.5
			style = box
	if variant.ends_with("_linear"):
		panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	panel.add_theme_stylebox_override("panel", style)


func _nine_raw(name: String) -> StyleBoxTexture:
	var key: String = FILL[name] + "_z1"
	var entry: Dictionary = info[key]
	var a: Array = entry["rect"]
	var s: Array = entry["shape_rect"]
	var style := StyleBoxTexture.new()
	style.texture = _load(ART + "/" + key + ".png")
	var left := float(s[0]) - float(a[0])
	var top := float(s[1]) - float(a[1])
	var right := float(a[0]) + float(a[2]) - (float(s[0]) + float(s[2]))
	var bottom := float(a[1]) + float(a[3]) - (float(s[1]) + float(s[3]))
	style.texture_margin_left = ceilf(left) + 8.0
	style.texture_margin_top = ceilf(top) + 8.0
	style.texture_margin_right = ceilf(right) + 2.0
	style.texture_margin_bottom = ceilf(bottom) + 2.0
	style.expand_margin_left = ceilf(left)
	style.expand_margin_top = ceilf(top)
	style.expand_margin_right = ceilf(right)
	style.expand_margin_bottom = ceilf(bottom)
	return style


func _nine_aligned(name: String) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _load(ART + "/" + FILL[name] + "_aligned_1x.png")
	style.texture_margin_left = 8.0
	style.texture_margin_top = 8.0
	style.texture_margin_right = 2.0
	style.texture_margin_bottom = 2.0
	return style


func _texture_style(key: String, path: String, factor: Vector2) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _load(path)
	var entry: Dictionary = art[key]
	var a: Array = entry["rect"]
	var s: Array = entry["shape_rect"]
	style.expand_margin_left = (float(s[0]) - float(a[0])) * factor.x
	style.expand_margin_top = (float(s[1]) - float(a[1])) * factor.y
	style.expand_margin_right = ((float(a[0]) + float(a[2])) - (float(s[0]) + float(s[2]))) * factor.x
	style.expand_margin_bottom = ((float(a[1]) + float(a[3])) - (float(s[1]) + float(s[3]))) * factor.y
	return style


func _load(path: String) -> Texture2D:
	if not textures.has(path):
		textures[path] = ImageTexture.create_from_image(Image.load_from_file(path))
	return textures[path]
