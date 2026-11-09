# Art draws LINEAR, the project's default texture filter, because NEAREST drops
# texels and stair-steps scaled art. Text stays NEAREST because LINEAR softens it
# at the fractional positions the game draws it at. A Theme can't carry
# texture_filter, so this autoload sets it on each text node as that node enters
# the tree. It is the first autoload in project.godot so that it also catches
# the text nodes of every later autoload.
extends Node


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if _draws_text(node):
		(node as CanvasItem).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


# A Button with no text only draws its icon, and icons are art, so it stays on
# the LINEAR default. This runs once as the Button enters the tree, so a Button
# that gets its first text after that stays LINEAR too.
func _draws_text(node: Node) -> bool:
	if node is Label or node is RichTextLabel or node is LineEdit or node is TextEdit:
		return true
	return node is Button and (node as Button).text != ""
