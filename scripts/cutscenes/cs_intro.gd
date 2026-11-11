# cs_intro.gd
# CS_INTRO, the text screen the original opens the Tutorial on: four lines over a
# dark gradient. The original draws it from the root timeline and not from an
# animation, so CutscenePlayer shows this scene where it plays a clip for every
# other Cutscene. extract_cs_intro reads where each line sits and how it is
# styled out of the SWF into cs_intro.json, and this scene builds a Label for
# each one from there.
#
# The lines are MENU[86] to MENU[89], which the original's frame script puts in
# its four text fields (frame_263/DoAction.as:2-5). They are not the older text
# the fields bake in as their initialText, which the extractor never writes.
#
# The gradient is 800x575, the Stage's size, and the window is 800x600 until
# julian-perge/urchin#111 changes its base resolution. So the scene stretches the
# gradient over the whole window, as main_menu.tscn does with its background, and
# leaves the lines at their Stage coordinates.
class_name CsIntro
extends Control

const LAYOUT_PATH: String = "res://assets/cutscenes/cs_intro.json"

# How long the original holds the lines, in seconds. It is the frame count of the
# original's silent timer sprite, at the SWF's frame rate.
var hold_seconds: float = 0.0


func _ready() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	hold_seconds = float(layout["hold_frames"]) / float(layout["fps"])
	for line: Dictionary in layout["lines"]:
		add_child(_line_label(line))


func _line_label(line: Dictionary) -> Label:
	var label := Label.new()
	label.text = line["text"]
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect: Dictionary = line["rect"]
	label.position = Vector2(rect["x"], rect["y"])
	label.size = Vector2(rect["w"], rect["h"])
	label.horizontal_alignment = LabelLayout.ALIGNMENTS[line["align"]]
	if line["wrap"]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", int(line["size"]))
	label.add_theme_color_override("font_color", Color(line["color"]))
	_add_glow(label, line["glow"])
	_add_shadow(label, line["shadow"])
	return label


# A Label cannot blur. The glow is drawn as an outline in its color, as wide as the
# glow reaches from the text, which is half of its blur. At strength 10 the original's
# glow is close to solid out to that reach.
func _add_glow(label: Label, glow: Dictionary) -> void:
	label.add_theme_color_override("font_outline_color", _filter_color(glow))
	label.add_theme_constant_override("outline_size", roundi(glow["blur_x"] / 2.0))


# The shadow is drawn as one copy of the text in its color, moved by its distance along
# its angle. Its blur and strength are not drawn.
func _add_shadow(label: Label, shadow: Dictionary) -> void:
	label.add_theme_color_override("font_shadow_color", _filter_color(shadow))
	var offset: Vector2 = Vector2.from_angle(shadow["angle"]) * shadow["distance"]
	label.add_theme_constant_override("shadow_offset_x", roundi(offset.x))
	label.add_theme_constant_override("shadow_offset_y", roundi(offset.y))


func _filter_color(filter: Dictionary) -> Color:
	var color := Color(filter["color"])
	color.a = filter["alpha"]
	return color
