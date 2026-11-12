# The chrome every KRINMENU Window shares (spec/107-window-shell.md): the
# backdrop, the close X art and the close hit button. Each node's rect is in
# window_shell.tscn, and test_screen_rects.gd checks it against the SWF.
class_name WindowShell
extends Control

signal close_pressed

# The Victory Window sets this to false, because its "win" label has no close X.
@export var close_visible: bool = true:
	set(value):
		close_visible = value
		if is_node_ready():
			_show_close()


func _ready() -> void:
	_show_close()


func _show_close() -> void:
	$CloseButton.visible = close_visible
	$CloseArt.visible = close_visible


func _on_close_button_pressed() -> void:
	close_pressed.emit()
