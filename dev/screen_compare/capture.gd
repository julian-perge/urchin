# Draws one Screen or Window for a capture that the compare tool scores
# (dev/urchin_dev/checks/screen_compare.py). It reads the entry from
# screens.json, the file the tool reads.
#
# It freezes the scene's run-time state by never starting it. The scene is
# instantiated alone, with no save, no battle and no host, so it shows what its
# .tscn holds, and then its processing is turned off so nothing moves.
#
# Run it with the godot-mcp run_scene tool, embedded, with these arguments,
# then capture_screenshot:
#   --entry=<name>             an entry of screens.json
#   --mode=chrome|panels|alpha chrome hides every Label, and panels hides
#                              every node that the entry's `nodes` does not name.
#                              A chrome mode with "hide_names" also hides every
#                              node with one of those names, and what is under
#                              it: art that the game sets from its data, such
#                              as item icons and the doll. alpha hides every
#                              Label and every node that is not one of the
#                              entry's `nodes` or under one of them
#   --background=magenta|green the colour behind the scene
#   --control                  in alpha mode, takes the material off each of
#                              the entry's `nodes`, for the control capture
extends Node

const CONFIG: String = "res://dev/screen_compare/screens.json"
const BACKGROUNDS: Dictionary[String, Color] = {
	"magenta": Color(1.0, 0.0, 1.0),
	"green": Color(0.0, 1.0, 0.0),
}


func _ready() -> void:
	var options: Dictionary[String, String] = {}
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	var entry_name: String = options.get("entry", "")
	var mode: String = options.get("mode", "")
	var background: String = options.get("background", "")
	DisplayServer.window_set_title("AGENT RENDER - screen compare %s %s" % [entry_name, mode])

	var entries: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	assert(entries.has(entry_name), "screens.json has no entry '%s'" % entry_name)
	var entry: Dictionary = entries[entry_name]
	assert(entry["modes"].has(mode), "entry '%s' has no mode '%s'" % [entry_name, mode])
	assert(BACKGROUNDS.has(background), "unknown background '%s'" % background)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = BACKGROUNDS[background]
	backdrop.size = get_viewport().get_visible_rect().size
	add_child(backdrop)

	var scene: PackedScene = load(entry["scene"])
	var screen: Node = scene.instantiate()
	add_child(screen)
	await get_tree().process_frame
	screen.process_mode = Node.PROCESS_MODE_DISABLED

	var keep: Array[Node] = []
	for path: String in entry["modes"][mode].get("nodes", []):
		keep.append(screen.get_node(path))
	var hide_names: Array = entry["modes"][mode].get("hide_names", [])
	_hide(screen, mode, keep, hide_names)
	if mode == "alpha" and "--control" in OS.get_cmdline_user_args():
		for node: Node in keep:
			node.material = null


# A hidden node keeps its place in the layout, because only what it draws
# itself turns clear. Setting `visible` would take it out of a FloatBox.
func _hide(node: Node, mode: String, keep: Array[Node], hide_names: Array, under_hidden_name: bool = false, under_kept: bool = false) -> void:
	var is_named: bool = under_hidden_name or hide_names.has(str(node.name))
	var is_kept: bool = under_kept or node in keep
	if node is CanvasItem:
		var is_text: bool = node is Label or node is RichTextLabel
		if (
			(mode == "chrome" and (is_text or is_named))
			or (mode == "panels" and node not in keep)
			or (mode == "alpha" and (is_text or not is_kept))
		):
			node.self_modulate.a = 0.0
	for child: Node in node.get_children():
		_hide(child, mode, keep, hide_names, is_named, is_kept)
