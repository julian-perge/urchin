# WindowShell (scripts/ui/window/window_shell.gd): the close button and its
# visibility. test_screen_rects.gd checks where each piece sits.
extends GutTest

const SHELL: PackedScene = preload("res://scenes/ui/window/window_shell.tscn")


func _shell() -> WindowShell:
	var shell: WindowShell = SHELL.instantiate()
	add_child_autofree(shell)
	return shell


func test_the_close_button_emits_close_pressed() -> void:
	var shell: WindowShell = _shell()
	watch_signals(shell)
	(shell.get_node("CloseButton") as BaseButton).pressed.emit()
	assert_signal_emit_count(shell, "close_pressed", 1)


func test_close_visible_false_hides_the_button_and_the_art() -> void:
	var shell: WindowShell = _shell()
	shell.close_visible = false
	assert_false((shell.get_node("CloseButton") as CanvasItem).visible)
	assert_false((shell.get_node("CloseArt") as CanvasItem).visible)
	assert_true((shell.get_node("Backdrop") as CanvasItem).visible)
	shell.close_visible = true
	assert_true((shell.get_node("CloseButton") as CanvasItem).visible)
	assert_true((shell.get_node("CloseArt") as CanvasItem).visible)


# The Victory host sets the property before the shell enters the tree.
func test_close_visible_set_before_ready_hides_both() -> void:
	var shell: WindowShell = SHELL.instantiate()
	shell.close_visible = false
	add_child_autofree(shell)
	assert_false((shell.get_node("CloseButton") as CanvasItem).visible)
	assert_false((shell.get_node("CloseArt") as CanvasItem).visible)
