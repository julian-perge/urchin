# filter_switcher.gd
# PROTOTYPE for julian-perge/urchin#130, throwaway. It lives on the branch
# prototype/texture-filter and is never merged.
#
# Question: should the port keep NEAREST as its default texture filter, or draw
# scaled art with LINEAR?
#
# This autoload puts a yellow bar over the real game and switches how the whole
# game is drawn:
#   A  NEAREST everywhere, which is what the game does today
#   B  LINEAR everywhere
#   C  LINEAR for art and NEAREST for text
#   D  LINEAR with mipmaps for art and NEAREST for text
#
# Left and Right (or the bar's arrows) cycle the variants and 1 to 4 pick one.
# W cycles the window through 1x, 1.5x, 2x and 3x, counted in framebuffer pixels
# against the 800x600 design size. H hides the bar.
#
# Arguments after "--": --variant=A|B|C|D picks the first variant, and --clean
# starts with the bar hidden so a capture shows only the game.
#
# Every texture on this branch is imported with mipmaps so D can work. A and B
# draw the same pixels as they do without them.
extends CanvasLayer

const VARIANTS: Array[Dictionary] = [
	{
		"key": "A",
		"name": "NEAREST everywhere (today)",
		"art": Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST,
		"nearest_text": false,
	},
	{
		"key": "B",
		"name": "LINEAR everywhere",
		"art": Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR,
		"nearest_text": false,
	},
	{
		"key": "C",
		"name": "LINEAR art, NEAREST text",
		"art": Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR,
		"nearest_text": true,
	},
	{
		"key": "D",
		"name": "LINEAR + mipmaps art, NEAREST text",
		"art": Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
		"nearest_text": true,
	},
]
const WINDOW_SCALES: Array[float] = [1.0, 1.5, 2.0, 3.0]
const DESIGN_SIZE := Vector2(800, 600)
const BAR_HEIGHT := 20.0
const MIPMAP_SAMPLE := "res://assets/backgrounds/hub/PRISON.png"

var _index := 0
var _window_index := 2
var _text_nodes := 0
var _has_mipmaps := false
var _bar: PanelContainer
var _label: Label


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_bar()
	var sample: Texture2D = load(MIPMAP_SAMPLE)
	_has_mipmaps = sample != null and sample.get_image().has_mipmaps()
	get_tree().node_added.connect(_on_node_added)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="):
			_index = maxi(0, "ABCD".find(arg.trim_prefix("--variant=")))
		if arg == "--clean":
			_bar.visible = false
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.timeout.connect(_refresh)
	add_child(timer)
	timer.start()
	_apply.call_deferred()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: Key = event.keycode
	if key == KEY_LEFT:
		_cycle(-1)
	elif key == KEY_RIGHT:
		_cycle(1)
	elif key >= KEY_1 and key < KEY_1 + VARIANTS.size():
		_index = key - KEY_1
		_apply()
	elif key == KEY_W:
		_window_index = (_window_index + 1) % WINDOW_SCALES.size()
		DisplayServer.window_set_size(Vector2i(DESIGN_SIZE * WINDOW_SCALES[_window_index]))
		_refresh.call_deferred()
	elif key == KEY_H:
		_bar.visible = not _bar.visible
	else:
		return
	get_viewport().set_input_as_handled()


func _cycle(step: int) -> void:
	_index = posmod(_index + step, VARIANTS.size())
	_apply()


func _apply() -> void:
	var variant: Dictionary = VARIANTS[_index]
	get_tree().root.canvas_item_default_texture_filter = variant["art"]
	_text_nodes = 0
	_mark_tree(get_tree().root)
	_refresh()
	print("filter_switcher: %s %s, window %s, text nodes kept NEAREST %d, mipmaps imported %s" % [
		variant["key"], variant["name"], get_window().size, _text_nodes, _has_mipmaps,
	])


func _mark_tree(node: Node) -> void:
	_mark(node)
	for child in node.get_children():
		_mark_tree(child)


func _on_node_added(node: Node) -> void:
	_mark(node)


func _mark(node: Node) -> void:
	if not _draws_text(node):
		return
	if VARIANTS[_index]["nearest_text"]:
		node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_text_nodes += 1
	else:
		node.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE


func _draws_text(node: Node) -> bool:
	if node is Label or node is RichTextLabel or node is LineEdit or node is TextEdit:
		return true
	return node is Button and node.text != ""


func _refresh() -> void:
	var variant: Dictionary = VARIANTS[_index]
	var window: Vector2i = get_window().size
	_label.text = "%s  %s    window %dx%d = %.2fx    text nodes kept NEAREST: %d    mipmaps: %s    (arrows / 1-4, W size, H hide)" % [
		variant["key"], variant["name"], window.x, window.y, float(window.x) / DESIGN_SIZE.x, _text_nodes,
		"yes" if _has_mipmaps else "NOT IMPORTED",
	]


func _build_bar() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#ffd400")
	_bar = PanelContainer.new()
	_bar.add_theme_stylebox_override("panel", style)
	_bar.position = Vector2(0, DESIGN_SIZE.y - BAR_HEIGHT)
	_bar.size = Vector2(DESIGN_SIZE.x, BAR_HEIGHT)
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bar)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_bar.add_child(row)
	row.add_child(_arrow("<", -1))
	_label = Label.new()
	_label.add_theme_color_override("font_color", Color.BLACK)
	_label.add_theme_font_size_override("font_size", 10)
	row.add_child(_label)
	row.add_child(_arrow(">", 1))


func _arrow(text: String, step: int) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", Color.BLACK)
	button.add_theme_color_override("font_hover_color", Color.BLACK)
	button.add_theme_color_override("font_pressed_color", Color.BLACK)
	button.add_theme_font_size_override("font_size", 10)
	button.pressed.connect(_cycle.bind(step))
	return button
