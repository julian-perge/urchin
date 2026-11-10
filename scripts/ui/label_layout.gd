# label_layout.gd
# Godot's alignment for each name dev/urchin_dev/swf/label_layout.py writes for
# an edit text's line.
class_name LabelLayout
extends RefCounted

const ALIGNMENTS: Dictionary = {
	"left": HORIZONTAL_ALIGNMENT_LEFT,
	"center": HORIZONTAL_ALIGNMENT_CENTER,
	"right": HORIZONTAL_ALIGNMENT_RIGHT,
	"justify": HORIZONTAL_ALIGNMENT_FILL,
}
