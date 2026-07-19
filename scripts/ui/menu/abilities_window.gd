# abilities_window.gd
# The abilities screen, rebuilt from frame 25 of the original menu clip
# (DefineSprite 3142 at stage 400.5, 222.4):
# - left: the class ability tree ('talenttreefull' sprite 3100 - 28 nodes,
#   4 columns x 7 rows on a 52 x 40 pitch at stage 45.4, 74.2), learn with
#   a click (TalentTree.learn rules: prerequisites, level tiers, 1 point)
# - middle: name/level, Ability Points (skill points) and Attribute Points
#   (stat points), plus the four attribute rows with '+' spend buttons
#   (frame-25 buttons 3068/3071/3070/3069 - no Focus row in the original)
# - right: the Combat Action Bar wheel ('selector' sprite 3109 - 8 sockets
#   on a 49.5 px ring at stage 630.6, 172.2) and the Ability Pool list
#   ('talentPool' sprite 3120 at stage 523.6, 274.2)
#
# Click a pool ability to place it in the first free socket; click a socket
# to send its ability back to the pool.
extends Control

const TREE_ORIGIN = Vector2(45.4, 74.2)
const TREE_COLUMNS_X = [41.4, 93.4, 145.4, 197.4]
const TREE_ROWS_Y = [49.9, 89.8, 129.8, 169.8, 209.8, 249.8, 289.9]
const NODE_SIZE = Vector2(32, 32)

const LEFT_PANEL = Rect2(44.9, 112.9, 249.1, 267.1)
const RIGHT_PANEL = Rect2(506.3, 112.9, 249.1, 267.1)
const MIDDLE_TOP_PANEL = Rect2(308.6, 74.0, 183.1, 238.0)
const MIDDLE_BOTTOM_PANEL = Rect2(308.6, 322.0, 183.1, 108.0)

const WHEEL_CENTER = Vector2(630.6, 172.2)
# thing0-7 offsets inside the 'selector' clip.
const WHEEL_OFFSETS = [
	Vector2(0.0, -49.2), Vector2(34.8, -34.9), Vector2(49.5, 0.0),
	Vector2(35.0, 35.3), Vector2(0.0, 49.8), Vector2(-35.2, 35.1),
	Vector2(-49.5, 0.0), Vector2(-35.0, -34.7),
]
const SOCKET_SIZE = Vector2(30, 30)

const POOL_RECT = Rect2(523.6, 274.2, 214.0, 128.0)
const POOL_VISIBLE_ROWS = 5
const POOL_ROW_HEIGHT = 25.0

const ATTRIBUTE_ROWS = [
	{"label": "Vitality:", "stat": Leveling.Stat.LIFE},
	{"label": "Strength:", "stat": Leveling.Stat.STRENGTH},
	{"label": "Instinct:", "stat": Leveling.Stat.MAGIC},
	{"label": "Speed:", "stat": Leveling.Stat.SPEED},
]
const ATTRIBUTE_ROWS_Y = [340.4, 357.9, 376.1, 394.2]
const CLASS_NAMES = ["Biological", "Psychological", "Hydraulic"]

var _tree_buttons: Array[Button] = []
var _tree_rank_labels: Array[Label] = []
var _tree_lines: Control
var _socket_buttons: Array[Button] = []
var _pool_rows: Array[Button] = []
var _pool_scroll: int = 0
var _pool_move_ids: Array = []

var _name_label: Label
var _level_label: Label
var _ability_points_value: Label
var _attribute_points_value: Label
var _attribute_values: Array[Label] = []
var _status_label: Label


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_chrome()
	_build_tree_panel()
	_build_middle()
	_build_wheel_panel()
	visibility_changed.connect(func():
		if visible:
			refresh())


func _build_chrome() -> void:
	var backdrop = MenuTheme.add_texture_rect(self, "menu_backdrop.png", MenuTheme.BACKDROP_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	var close = TextureButton.new()
	close.name = "CloseButton"
	close.texture_normal = MenuTheme.texture("close_x.png")
	close.ignore_texture_size = true
	close.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close.position = MenuTheme.CLOSE_RECT.position
	close.size = MenuTheme.CLOSE_RECT.size
	close.pressed.connect(hide)
	add_child(close)
	_status_label = MenuTheme.add_label(
		self, "", Rect2(44.9, 414, 700, 20), 12, Color(1, 0.85, 0.3)
	)


func _build_tree_panel() -> void:
	MenuTheme.add_label(
		self, "Ability Tree", Rect2(53.6, 80.1, 231.8, 22), 15,
		Color(0.55, 0.55, 0.55), HORIZONTAL_ALIGNMENT_CENTER
	)
	MenuTheme.add_texture_rect(self, "panel_large.png", LEFT_PANEL)
	_tree_lines = Control.new()
	_tree_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree_lines.draw.connect(_draw_tree_lines)
	add_child(_tree_lines)
	var tree: Array = TalentTree.TREES.get(_player_class(), TalentTree.TREES[0])
	for node_index in tree.size():
		var button = Button.new()
		button.custom_minimum_size = NODE_SIZE
		button.size = NODE_SIZE
		button.position = _node_center(node_index) - NODE_SIZE / 2.0
		button.pressed.connect(_on_tree_node_pressed.bind(node_index))
		_style_circle_button(button, Color(0.1, 0.1, 0.11), Color(0.3, 0.3, 0.32))
		add_child(button)
		_tree_buttons.append(button)
		var rank = MenuTheme.add_label(
			self, "", Rect2(button.position + Vector2(18, 20), Vector2(30, 14)), 9,
			Color(0.9, 0.9, 0.6)
		)
		_tree_rank_labels.append(rank)


func _build_middle() -> void:
	MenuTheme.add_texture_rect(self, "panel_center.png", MIDDLE_TOP_PANEL)
	_name_label = MenuTheme.add_label(
		self, "", Rect2(MIDDLE_TOP_PANEL.position.x, 79.7, MIDDLE_TOP_PANEL.size.x, 22),
		16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER
	)
	_level_label = MenuTheme.add_label(
		self, "", Rect2(MIDDLE_TOP_PANEL.position.x, 99.5, MIDDLE_TOP_PANEL.size.x, 18),
		12, Color(0.8, 0.8, 0.8), HORIZONTAL_ALIGNMENT_CENTER
	)
	MenuTheme.add_label(self, "Ability Points:", Rect2(314.3, 122.2, 110, 16), 12)
	_ability_points_value = MenuTheme.add_label(
		self, "0", Rect2(400, 122.2, 83, 16), 12, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT
	)
	MenuTheme.add_label(self, "Attribute Points:", Rect2(314.3, 141.2, 110, 16), 12)
	_attribute_points_value = MenuTheme.add_label(
		self, "0", Rect2(400, 141.2, 83, 16), 12, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT
	)
	MenuTheme.add_texture_rect(self, "panel_center.png", MIDDLE_BOTTOM_PANEL)
	MenuTheme.add_label(
		self, "Your Attributes", Rect2(MIDDLE_BOTTOM_PANEL.position.x, 324, MIDDLE_BOTTOM_PANEL.size.x, 16),
		12, Color(0.55, 0.55, 0.55), HORIZONTAL_ALIGNMENT_CENTER
	)
	for i in ATTRIBUTE_ROWS.size():
		var row: Dictionary = ATTRIBUTE_ROWS[i]
		var y = ATTRIBUTE_ROWS_Y[i]
		var plus = Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(26, 14)
		plus.size = Vector2(26, 14)
		plus.position = Vector2(318, y + 1)
		plus.add_theme_font_size_override("font_size", 11)
		var style = StyleBoxFlat.new()
		style.bg_color = MenuTheme.STAT_COLORS[i]
		style.set_corner_radius_all(4)
		plus.add_theme_stylebox_override("normal", style)
		var hover_style = style.duplicate()
		hover_style.bg_color = MenuTheme.STAT_COLORS[i].lightened(0.25)
		plus.add_theme_stylebox_override("hover", hover_style)
		plus.add_theme_color_override("font_color", Color.BLACK)
		plus.pressed.connect(_on_attribute_plus_pressed.bind(int(row["stat"])))
		add_child(plus)
		MenuTheme.add_label(self, str(row["label"]), Rect2(352, y, 80, 16), 12, MenuTheme.STAT_COLORS[i])
		var value = MenuTheme.add_label(
			self, "0", Rect2(400, y, 80, 16), 12, MenuTheme.STAT_COLORS[i], HORIZONTAL_ALIGNMENT_RIGHT
		)
		_attribute_values.append(value)


func _build_wheel_panel() -> void:
	MenuTheme.add_label(
		self, "Combat Action Bar", Rect2(516.3, 80.1, 231.8, 22), 15,
		Color(0.55, 0.55, 0.55), HORIZONTAL_ALIGNMENT_CENTER
	)
	MenuTheme.add_texture_rect(self, "panel_large.png", RIGHT_PANEL)
	MenuTheme.add_label(
		self, "Ability Pool", Rect2(516.3, 250.1, 231.8, 20), 14,
		Color(0.55, 0.55, 0.55), HORIZONTAL_ALIGNMENT_CENTER
	)
	for i in WHEEL_OFFSETS.size():
		var socket = Button.new()
		socket.custom_minimum_size = SOCKET_SIZE
		socket.size = SOCKET_SIZE
		socket.position = WHEEL_CENTER + WHEEL_OFFSETS[i] - SOCKET_SIZE / 2.0
		socket.pressed.connect(_on_socket_pressed.bind(i))
		_style_circle_button(socket, Color(0.09, 0.09, 0.1), Color(0.22, 0.22, 0.24))
		add_child(socket)
		_socket_buttons.append(socket)
	var pool_backdrop = ColorRect.new()
	pool_backdrop.color = Color(0.06, 0.06, 0.065)
	pool_backdrop.position = POOL_RECT.position
	pool_backdrop.size = POOL_RECT.size
	pool_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pool_backdrop)
	for i in POOL_VISIBLE_ROWS:
		var row = Button.new()
		row.custom_minimum_size = Vector2(POOL_RECT.size.x - 28, POOL_ROW_HEIGHT - 3)
		row.size = row.custom_minimum_size
		row.position = POOL_RECT.position + Vector2(3, 3 + i * POOL_ROW_HEIGHT)
		row.add_theme_font_size_override("font_size", 11)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.5, 0.5, 0.52)
		style.set_corner_radius_all(9)
		style.content_margin_left = 10
		row.add_theme_stylebox_override("normal", style)
		var hover_style = style.duplicate()
		hover_style.bg_color = Color(0.65, 0.65, 0.67)
		row.add_theme_stylebox_override("hover", hover_style)
		row.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08))
		row.pressed.connect(_on_pool_row_pressed.bind(i))
		add_child(row)
		_pool_rows.append(row)
	var scroll_up = _make_scroll_button("^", POOL_RECT.position + Vector2(POOL_RECT.size.x - 22, 3))
	scroll_up.pressed.connect(_on_pool_scrolled.bind(-1))
	var scroll_down = _make_scroll_button("v", POOL_RECT.position + Vector2(POOL_RECT.size.x - 22, POOL_RECT.size.y - 63))
	scroll_down.pressed.connect(_on_pool_scrolled.bind(1))


func _make_scroll_button(glyph: String, at: Vector2) -> Button:
	var button = Button.new()
	button.text = glyph
	button.custom_minimum_size = Vector2(19, 60)
	button.size = button.custom_minimum_size
	button.position = at
	add_child(button)
	return button


func _style_circle_button(button: Button, bg: Color, border: Color) -> void:
	for state in ["normal", "hover", "pressed"]:
		var style = StyleBoxFlat.new()
		style.bg_color = bg.lightened(0.12) if state != "normal" else bg
		style.border_color = border
		style.set_border_width_all(2)
		style.set_corner_radius_all(99)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_font_size_override("font_size", 9)


func refresh() -> void:
	var save = GameData.current_save
	if save == null:
		return
	_status_label.text = ""
	_name_label.text = save.name_user
	_level_label.text = "Lvl. %d %s" % [save.level, CLASS_NAMES[save.player_class]]
	_ability_points_value.text = str(save.skill_points)
	_attribute_points_value.text = str(save.stat_points)
	var stats = [save.life, save.strength, save.magic, save.speed]
	for i in _attribute_values.size():
		_attribute_values[i].text = str(int(stats[i]))
	_refresh_tree(save)
	_refresh_wheel(save)
	_refresh_pool(save)
	_tree_lines.queue_redraw()


func _refresh_tree(save: PlayerSave) -> void:
	var tree: Array = TalentTree.TREES.get(save.player_class, TalentTree.TREES[0])
	for node_index in _tree_buttons.size():
		if node_index >= tree.size():
			break
		var node: Dictionary = tree[node_index]
		var button = _tree_buttons[node_index]
		var rank = TalentTree.get_rank(save, node_index)
		var color = _node_color(save, node_index, node)
		var learned = rank > 0
		_style_circle_button(
			button,
			color.darkened(0.55) if learned else Color(0.1, 0.1, 0.11),
			color if learned else Color(0.3, 0.3, 0.32)
		)
		button.tooltip_text = _node_tooltip(node, rank)
		_tree_rank_labels[node_index].text = "%d/%d" % [rank, int(node["max_rank"])]


func _node_color(save: PlayerSave, _node_index: int, node: Dictionary) -> Color:
	var move_id = int(node["move_id"])
	if move_id == 0:
		return Color(0.7, 0.7, 0.4)  # passive - gold
	var move: Ability = MoveManagerAuto.get_move(move_id)
	if move == null:
		return Color(0.5, 0.5, 0.5)
	var element_index = CombatUnit.ELEMENT_ORDER.find(move.damage_element_type)
	if element_index == -1:
		return Color(0.5, 0.5, 0.5)
	return MenuTheme.ELEMENT_COLORS[element_index]


func _node_tooltip(node: Dictionary, rank: int) -> String:
	var title: String
	if node["buff_family"] != "":
		title = str(node["buff_family"]).capitalize()
	else:
		var move: Ability = MoveManagerAuto.get_move(int(node["move_id"]))
		title = move.display_name if move != null else "?"
	return "%s (%d/%d)" % [title, rank, int(node["max_rank"])]


func _refresh_wheel(save: PlayerSave) -> void:
	for i in _socket_buttons.size():
		var socket = _socket_buttons[i]
		var move_id = int(save.move_matrix[i]) if i < save.move_matrix.size() else 0
		if move_id == 0:
			socket.text = ""
			socket.tooltip_text = "Empty slot"
			_style_circle_button(socket, Color(0.09, 0.09, 0.1), Color(0.22, 0.22, 0.24))
			continue
		var move: Ability = MoveManagerAuto.get_move(move_id)
		var color = _move_color(move)
		socket.text = _move_initials(move)
		socket.tooltip_text = move.display_name if move != null else str(move_id)
		_style_circle_button(socket, color.darkened(0.45), color)


func _refresh_pool(save: PlayerSave) -> void:
	_pool_move_ids = []
	# JSON-loaded saves hold floats - compare as ints.
	var bar_ids = []
	for bar_move in save.move_matrix:
		bar_ids.append(int(bar_move))
	for move_id in save.move_matrix2:
		if int(move_id) != 0 and not bar_ids.has(int(move_id)):
			_pool_move_ids.append(int(move_id))
	_pool_scroll = clamp(_pool_scroll, 0, max(0, _pool_move_ids.size() - POOL_VISIBLE_ROWS))
	for i in _pool_rows.size():
		var row = _pool_rows[i]
		var pool_index = _pool_scroll + i
		if pool_index >= _pool_move_ids.size():
			row.visible = false
			continue
		row.visible = true
		var move: Ability = MoveManagerAuto.get_move(_pool_move_ids[pool_index])
		row.text = move.display_name if move != null else str(_pool_move_ids[pool_index])
		row.tooltip_text = row.text


func _move_color(move: Ability) -> Color:
	if move == null:
		return Color(0.5, 0.5, 0.5)
	var element_index = CombatUnit.ELEMENT_ORDER.find(move.damage_element_type)
	return MenuTheme.ELEMENT_COLORS[element_index] if element_index != -1 else Color(0.5, 0.5, 0.5)


func _move_initials(move: Ability) -> String:
	if move == null:
		return "?"
	var words = move.display_name.split(" ", false)
	if words.size() >= 2:
		return words[0].substr(0, 1) + words[1].substr(0, 1)
	return move.display_name.substr(0, 2)


func _node_center(node_index: int) -> Vector2:
	var column = node_index % TREE_COLUMNS_X.size()
	var row = floori(node_index / float(TREE_COLUMNS_X.size()))
	return TREE_ORIGIN + Vector2(TREE_COLUMNS_X[column], TREE_ROWS_Y[row])


func _draw_tree_lines() -> void:
	var save = GameData.current_save
	var player_class = save.player_class if save != null else 0
	var tree: Array = TalentTree.TREES.get(player_class, TalentTree.TREES[0])
	for node_index in tree.size():
		for prerequisite in tree[node_index]["prerequisites"]:
			_tree_lines.draw_line(
				_node_center(node_index), _node_center(int(prerequisite)),
				Color(0.16, 0.16, 0.17), 4.0
			)


func _player_class() -> int:
	return GameData.current_save.player_class if GameData.current_save != null else 0


func _on_tree_node_pressed(node_index: int) -> void:
	var save = GameData.current_save
	if save == null:
		return
	var result = TalentTree.learn(save, node_index)
	if result != TalentTree.LearnResult.OK:
		_status_label.text = TalentTree.LEARN_RESULT_MESSAGES.get(result, "")
	refresh()


func _on_attribute_plus_pressed(stat_index: int) -> void:
	var save = GameData.current_save
	if save == null:
		return
	if not Leveling.spend_stat_point(save, stat_index):
		_status_label.text = "You do not have any Attribute Points."
	refresh()


func _on_socket_pressed(socket_index: int) -> void:
	var save = GameData.current_save
	if save == null:
		return
	if int(save.move_matrix[socket_index]) != 0:
		save.move_matrix[socket_index] = 0
	refresh()


func _on_pool_row_pressed(row_index: int) -> void:
	var save = GameData.current_save
	if save == null:
		return
	var pool_index = _pool_scroll + row_index
	if pool_index >= _pool_move_ids.size():
		return
	var empty_socket = save.move_matrix.find(0)
	if empty_socket == -1:
		_status_label.text = "Your Combat Action Bar is full."
		return
	save.move_matrix[empty_socket] = _pool_move_ids[pool_index]
	refresh()


func _on_pool_scrolled(direction: int) -> void:
	_pool_scroll = clamp(
		_pool_scroll + direction, 0,
		max(0, _pool_move_ids.size() - POOL_VISIBLE_ROWS)
	)
	var save = GameData.current_save
	if save != null:
		_refresh_pool(save)
