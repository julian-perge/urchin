# floating_number.gd
# One Floating number, the original's NumberFixer (DefineSprite 53): the number
# that rises over a unit and fades when a Move result lands on it, or in its
# place the MISS or SHIELDED word. FloatingNumberLayer makes each one and steps
# it.
#
# extract_floating_numbers writes each of NumberFixer's four labels into
# floating_number.json as a list of frames. On each frame the clip's holder,
# "flasher", has a scale, a height, an alpha and a share of white, and this
# plays one label from there. The holder holds one node per glyph, which is a
# digit or the word of the miss or shield label. A glyph is the layers the
# extractor rendered, bottom first, and its KN layer takes the number's color.
#
# The playhead is one number that advance() steps at the SWF's frame rate,
# rather than a Tween, so nothing can outlive the battle. A Tween that outlived
# the Radial menu once closed the next menu to open (08dc6a7).
extends Node2D
class_name FloatingNumber

const ART_DIR: String = "res://assets/ui/battle/floating_number/"
const SHADER: Shader = preload("res://scenes/battle/floating_number.gdshader")

# Which of NumberFixer's labels this plays: normal, critical, miss or shield.
var label: String = ""
# The glyphs the holder draws, from the left.
var glyphs: Array[String] = []
# The color each glyph's KN layer takes.
var tint: Color = Color.WHITE
# The original's "flasher" clip, which holds one node per glyph.
var flasher: Node2D

var _frames: Array = []
var _fps: float = 0.0
# The playhead, counted from the label's first frame as 0.
var _frame: int = 0
# The time since the playhead last stepped, counted in frames of the SWF.
var _frames_due: float = 0.0
var _plain: ShaderMaterial
var _tinted: ShaderMaterial


# layout is floating_number.json, and offsets holds where each glyph sits along
# the holder, in the holder's own units.
func setup(layout: Dictionary, label_name: String, color: Color, glyph_names: Array[String], offsets: Array[float]) -> void:
	label = label_name
	glyphs = glyph_names
	tint = color
	_fps = float(layout["fps"])
	_frames = layout["labels"][label]["frames"]
	_plain = _material(false)
	_tinted = _material(true)
	flasher = Node2D.new()
	add_child(flasher)
	for i in glyphs.size():
		flasher.add_child(_glyph(layout["glyphs"][glyphs[i]], offsets[i]))
	_show_frame()


# Steps the playhead on by `delta` seconds at the SWF's frame rate. After the
# label's last frame the number leaves its layer and frees itself, where
# NumberFixer's next frame runs removeMovieClip(this).
func advance(delta: float) -> void:
	_frames_due += delta * _fps
	while _frames_due >= 1.0:
		_frames_due -= 1.0
		_frame += 1
		if _frame == _frames.size():
			get_parent().remove_child(self)
			queue_free()
			return
	_show_frame()


func _material(tinted: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("tinted", tinted)
	material.set_shader_parameter("tint", tint)
	return material


func _glyph(layers: Array, x: float) -> Node2D:
	var glyph := Node2D.new()
	glyph.position.x = x
	for layer in layers:
		var rect: Dictionary = layer["rect"]
		var sprite := Sprite2D.new()
		sprite.texture = load(ART_DIR + layer["png"])
		sprite.centered = false
		sprite.position = Vector2(rect["x"], rect["y"])
		sprite.scale = Vector2(rect["w"], rect["h"]) / sprite.texture.get_size()
		sprite.material = _tinted if layer["tinted"] else _plain
		glyph.add_child(sprite)
	return glyph


func _show_frame() -> void:
	var frame: Dictionary = _frames[_frame]
	flasher.position.y = frame["y"]
	flasher.scale = Vector2.ONE * float(frame["scale"])
	flasher.modulate.a = frame["alpha"]
	_plain.set_shader_parameter("white", frame["white"])
	_tinted.set_shader_parameter("white", frame["white"])
