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

const TalentNodeScene: PackedScene = preload("res://scenes/ui/menu/talent_node.tscn")
const ICON_DIR: String = "res://assets/ui/abilities/"

const TREE_ORIGIN: Vector2 = Vector2(45.4, 74.2)
const TREE_COLUMNS_X: Array[float] = [41.4, 93.4, 145.4, 197.4]
const TREE_ROWS_Y: Array[float] = [49.9, 89.8, 129.8, 169.8, 209.8, 249.8, 289.9]
const NODE_SIZE: Vector2 = Vector2(32, 32)

const WHEEL_CENTER: Vector2 = Vector2(630.6, 172.2)
# thing0-7 offsets inside the 'selector' clip.
const WHEEL_OFFSETS: Array[Vector2] = [
	Vector2(0.0, -49.2), Vector2(34.8, -34.9), Vector2(49.5, 0.0),
	Vector2(35.0, 35.3), Vector2(0.0, 49.8), Vector2(-35.2, 35.1),
	Vector2(-49.5, 0.0), Vector2(-35.0, -34.7),
]
const SOCKET_SIZE: Vector2 = Vector2(30, 30)

const POOL_VISIBLE_ROWS: int = 5


var _tree_buttons: Array[Button] = []
var _tree_rank_labels: Array[Label] = []
@onready var _tree_lines: Control = $TreeLines
var _socket_buttons: Array[Button] = []
@onready var _pool_rows: Array[AbilityPoolRow] = [
	$PoolRows/PoolRow0, $PoolRows/PoolRow1, $PoolRows/PoolRow2, $PoolRows/PoolRow3, $PoolRows/PoolRow4,
]
var _pool_scroll: int = 0
var _pool_move_ids: Array = []

@onready var _name_label: Label = $NameLabel
@onready var _level_label: Label = $LevelLabel
@onready var _ability_points_value: Label = $AbilityPointsValue
@onready var _attribute_points_value: Label = $AttributePointsValue
@onready var _attribute_values: Array[Label] = [$VitalityValue, $StrengthValue, $InstinctValue, $SpeedValue]
@onready var _status_label: Label = $StatusLabel


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_tree_panel()
	_build_wheel_panel()
	for i in _pool_rows.size():
		_pool_rows[i].pressed.connect(_on_pool_row_pressed.bind(i))
		_pool_rows[i].mouse_entered.connect(_on_pool_row_hovered.bind(i))
		_pool_rows[i].mouse_exited.connect(GameTooltip.hide_tooltip)
	visibility_changed.connect(func():
		if visible:
			refresh())


static func _sanitize_icon_key(label: String) -> String:
	var result: String = ""
	var last_was_sep: bool = false
	for c in label:
		if (c >= "A" and c <= "Z") or (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			result += c
			last_was_sep = false
		elif not last_was_sep:
			result += "_"
			last_was_sep = true
	return result.strip_edges().lstrip("_").rstrip("_")


func _build_tree_panel() -> void:
	var tree: Array = TalentTree.TREES.get(_player_class(), TalentTree.TREES[PlayerSave.PlayerClass.BIOLOGICAL])
	for node_index in tree.size():
		var node_button: Button = TalentNodeScene.instantiate()
		node_button.position = _node_center(node_index) - NODE_SIZE / 2.0
		node_button.pressed.connect(_on_tree_node_pressed.bind(node_index))
		node_button.mouse_entered.connect(_on_tree_node_hovered.bind(node_index))
		node_button.mouse_exited.connect(GameTooltip.hide_tooltip)
		_style_circle_button(node_button, Color(0.1, 0.1, 0.11), Color(0.3, 0.3, 0.32))
		add_child(node_button)
		_tree_buttons.append(node_button)
		_tree_rank_labels.append(node_button.get_node("RankLabel"))


# The wheel's 8 sockets sit on a circular (non-uniform) pitch and their style
# is 100% data-dependent - recomputed every refresh() from whichever move is
# currently equipped, with no reusable child structure (a bare Button, no
# label overlay) - unlike the talent tree nodes, there is no static content
# here to extract into the scene, so this stays code-driven by design.
func _build_wheel_panel() -> void:
	for i in WHEEL_OFFSETS.size():
		var socket: Button = Button.new()
		socket.custom_minimum_size = SOCKET_SIZE
		socket.size = SOCKET_SIZE
		socket.position = WHEEL_CENTER + WHEEL_OFFSETS[i] - SOCKET_SIZE / 2.0
		socket.pressed.connect(_on_socket_pressed.bind(i))
		socket.mouse_entered.connect(_on_socket_hovered.bind(i))
		socket.mouse_exited.connect(GameTooltip.hide_tooltip)
		_style_circle_button(socket, Color(0.09, 0.09, 0.1), Color(0.22, 0.22, 0.24))
		add_child(socket)
		_socket_buttons.append(socket)


func _style_circle_button(button: Button, bg: Color, border: Color) -> void:
	for state in ["normal", "hover", "pressed"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = bg.lightened(0.12) if state != "normal" else bg
		style.border_color = border
		style.set_border_width_all(2)
		style.set_corner_radius_all(99)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_font_size_override("font_size", 9)


func refresh() -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	_status_label.text = ""
	_name_label.text = save.name_user
	_level_label.text = "Lvl. %d %s" % [save.level, PlayerSave.CLASS_NAMES[save.player_class]]
	_ability_points_value.text = str(save.skill_points)
	_attribute_points_value.text = str(save.stat_points)
	var stats: Array[Variant] = [save.life, save.strength, save.magic, save.speed]
	for i in _attribute_values.size():
		_attribute_values[i].text = str(int(stats[i]))
	_refresh_tree(save)
	_refresh_wheel(save)
	_refresh_pool(save)
	_tree_lines.queue_redraw()


func _refresh_tree(save: PlayerSave) -> void:
	var tree: Array = TalentTree.TREES.get(save.player_class, TalentTree.TREES[PlayerSave.PlayerClass.BIOLOGICAL])
	for node_index in _tree_buttons.size():
		if node_index >= tree.size():
			break
		var node: Dictionary = tree[node_index]
		var button: Button = _tree_buttons[node_index]
		var rank: int = TalentTree.get_rank(save, node_index)
		var color: Color = _node_color(save, node_index, node)
		var learned: bool = rank > 0
		_style_circle_button(
			button,
			color.darkened(0.55) if learned else Color(0.1, 0.1, 0.11),
			color if learned else Color(0.3, 0.3, 0.32)
		)
		_tree_rank_labels[node_index].text = "%d/%d" % [rank, int(node["max_rank"])]
		var icon_rect: TextureRect = button.get_node("IconRect")
		var icon_path: String = "%s%s.png" % [ICON_DIR, _tree_node_icon_key(node)]
		icon_rect.texture = load(icon_path) if ResourceLoader.exists(icon_path) else null


func _node_color(_save: PlayerSave, _node_index: int, node: Dictionary) -> Color:
	var move_id: int = int(node["move_id"])
	if move_id == 0:
		return Color(0.7, 0.7, 0.4)  # passive - gold
	var move: Ability = MoveManagerAuto.get_move(move_id)
	if move == null:
		return Color(0.5, 0.5, 0.5)
	var element_index: CombatUnit.Element = move.damage_element_type
	if element_index == -1:
		return Color(0.5, 0.5, 0.5)
	return MenuTheme.ELEMENT_COLORS[element_index]


# Icon lookup key for a tree node: buff family name for passives (one icon
# covers every rank of that family), the granted move's display name for
# actives (shared across a move family's ranks - only the tooltip TEXT
# differs by rank, not the icon or display name).
func _tree_node_icon_key(node: Dictionary) -> String:
	if TalentTree.is_passive(node):
		return _sanitize_icon_key(str(node["buff_family"]))
	var move: Ability = MoveManagerAuto.get_move(int(node["move_id"]))
	return _sanitize_icon_key(move.display_name) if move != null else ""


func _on_tree_node_hovered(node_index: int) -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	var tree: Array = TalentTree.TREES.get(save.player_class, TalentTree.TREES[PlayerSave.PlayerClass.BIOLOGICAL])
	if node_index >= tree.size():
		return
	var node: Dictionary = tree[node_index].duplicate()
	node["_node_index"] = node_index
	var move: Ability = null
	if not TalentTree.is_passive(node):
		# Rank-aware: show the CURRENTLY GRANTED move's text once learned,
		# otherwise preview what learning rank 1 would grant. A passive needs
		# no lookup here - the builder reads its text from TalentTree.
		var rank: int = TalentTree.get_rank(save, node_index)
		move = MoveManagerAuto.get_move(TalentTree.granted_move_id(node, max(rank, 1)))
	var button: Button = _tree_buttons[node_index]
	var result: Dictionary = AbilityTooltipBuilder.build_sections(node, save, move)
	var icon_path: String = "%s%s.png" % [ICON_DIR, _tree_node_icon_key(node)]
	var icon: Texture2D = load(icon_path) if ResourceLoader.exists(icon_path) else null
	GameTooltip.show_sections(result["sections"], button, icon, result["icon_color"])


func _refresh_wheel(save: PlayerSave) -> void:
	for i in _socket_buttons.size():
		var socket: Button = _socket_buttons[i]
		var move_id: int = int(save.move_matrix[i]) if i < save.move_matrix.size() else 0
		if move_id == 0:
			socket.icon = null
			socket.tooltip_text = "Empty slot"
			_style_circle_button(socket, Color(0.09, 0.09, 0.1), Color(0.22, 0.22, 0.24))
			continue
		var move: Ability = MoveManagerAuto.get_move(move_id)
		var color: Color = _move_color(move)
		var icon_path: String = "%s%s.png" % [ICON_DIR, _sanitize_icon_key(move.display_name if move != null else "")]
		socket.icon = load(icon_path) if ResourceLoader.exists(icon_path) else null
		socket.expand_icon = true
		socket.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		socket.tooltip_text = ""
		_style_circle_button(socket, color.darkened(0.45), color)


func _on_socket_hovered(socket_index: int) -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	var move_id: int = int(save.move_matrix[socket_index]) if socket_index < save.move_matrix.size() else 0
	if move_id == 0:
		return
	var move: Ability = MoveManagerAuto.get_move(move_id)
	if move == null:
		return
	var button: Button = _socket_buttons[socket_index]
	var result: Dictionary = AbilityTooltipBuilder.build_sections({}, save, move)
	var icon_path: String = "%s%s.png" % [ICON_DIR, _sanitize_icon_key(move.display_name)]
	var icon: Texture2D = load(icon_path) if ResourceLoader.exists(icon_path) else null
	GameTooltip.show_sections(result["sections"], button, icon, result["icon_color"])


func _refresh_pool(save: PlayerSave) -> void:
	_pool_move_ids = []
	# JSON-loaded saves hold floats - compare as ints.
	var bar_ids: Array[Variant] = []
	for bar_move in save.move_matrix:
		bar_ids.append(int(bar_move))
	for move_id in save.move_matrix2:
		if int(move_id) != 0 and not bar_ids.has(int(move_id)):
			_pool_move_ids.append(int(move_id))
	_pool_scroll = clamp(_pool_scroll, 0, max(0, _pool_move_ids.size() - POOL_VISIBLE_ROWS))
	for i in _pool_rows.size():
		var row: AbilityPoolRow = _pool_rows[i]
		var pool_index: int = _pool_scroll + i
		if pool_index >= _pool_move_ids.size():
			row.clear()
			continue
		var move: Ability = MoveManagerAuto.get_move(_pool_move_ids[pool_index])
		var icon_key: String = _sanitize_icon_key(move.display_name if move != null else "")
		row.populate(move, "%s%s.png" % [ICON_DIR, icon_key])


func _on_pool_row_hovered(row_index: int) -> void:
	var pool_index: int = _pool_scroll + row_index
	if pool_index >= _pool_move_ids.size():
		return
	var move: Ability = MoveManagerAuto.get_move(_pool_move_ids[pool_index])
	if move == null:
		return
	var save: PlayerSave = GameData.current_save
	var row: Button = _pool_rows[row_index]
	var result: Dictionary = AbilityTooltipBuilder.build_sections({}, save, move)
	var icon_path: String = "%s%s.png" % [ICON_DIR, _sanitize_icon_key(move.display_name)]
	var icon: Texture2D = load(icon_path) if ResourceLoader.exists(icon_path) else null
	GameTooltip.show_sections(result["sections"], row, icon, result["icon_color"])


func _move_color(move: Ability) -> Color:
	if move == null:
		return Color(0.5, 0.5, 0.5)
	var element_index: CombatUnit.Element = move.damage_element_type
	return MenuTheme.ELEMENT_COLORS[element_index] if element_index != -1 else Color(0.5, 0.5, 0.5)


func _node_center(node_index: int) -> Vector2:
	var column: int = node_index % TREE_COLUMNS_X.size()
	var row: int = floori(node_index / float(TREE_COLUMNS_X.size()))
	return TREE_ORIGIN + Vector2(TREE_COLUMNS_X[column], TREE_ROWS_Y[row])


func _draw_tree_lines() -> void:
	var save: PlayerSave = GameData.current_save
	var player_class: PlayerSave.PlayerClass = save.player_class as PlayerSave.PlayerClass if save != null else PlayerSave.PlayerClass.BIOLOGICAL
	var tree: Array = TalentTree.TREES.get(player_class, TalentTree.TREES[PlayerSave.PlayerClass.BIOLOGICAL])
	for node_index in tree.size():
		for prerequisite in tree[node_index]["prerequisites"]:
			var learned: bool = save != null and TalentTree.is_prerequisite_learned(save, int(prerequisite))
			var color: Color = Color(0.85, 0.72, 0.2) if learned else Color(0.16, 0.16, 0.17)
			_tree_lines.draw_line(
				_node_center(node_index), _node_center(int(prerequisite)),
				color, 4.0
			)


func _player_class() -> PlayerSave.PlayerClass:
	return GameData.current_save.player_class as PlayerSave.PlayerClass if GameData.current_save != null else PlayerSave.PlayerClass.BIOLOGICAL


func _on_tree_node_pressed(node_index: int) -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	var result = TalentTree.learn(save, node_index)
	if result != TalentTree.LearnResult.OK:
		_status_label.text = TalentTree.LEARN_RESULT_MESSAGES.get(result, "")
	refresh()


func _on_attribute_plus_pressed(stat_index: Leveling.Stat) -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	if not Leveling.spend_stat_point(save, stat_index):
		_status_label.text = "You do not have any Attribute Points."
	refresh()


func _on_socket_pressed(socket_index: int) -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	if int(save.move_matrix[socket_index]) != 0:
		save.move_matrix[socket_index] = 0
	refresh()


func _on_pool_row_pressed(row_index: int) -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	var pool_index: int = _pool_scroll + row_index
	if pool_index >= _pool_move_ids.size():
		return
	var empty_socket: int = save.move_matrix.find(0)
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
	var save: PlayerSave = GameData.current_save
	if save != null:
		_refresh_pool(save)
