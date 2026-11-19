# abilities_window.gd
# The abilities screen, rebuilt from frame 25 of the original menu clip
# (spec/107-abilities.md). abilities_window.tscn holds the shell, the panels,
# the titles, the points, the hint box and the attribute rows. This script
# places the tree nodes and the ring sockets. test_screen_rects.gd checks all
# of them against the SWF.
# - left: the class ability tree ('talenttreefull' sprite 3100), 28 nodes in
#   4 columns and 7 rows. A click learns a talent by the TalentTree.learn
#   rules: prerequisites, level tiers and 1 point.
# - middle: name and level, the ability points and attribute points, the hint
#   box with a random tip or the tutorial steps (HintSteps), and the four
#   attribute rows with '+' spend buttons. The original has no Focus row.
# - right: the Combat Action Bar wheel ('selector' sprite 3109) with 8
#   sockets, and the Ability Pool list ('talentPool' sprite 3120).
#
# A press on a pool ability holds it, and its icon follows the mouse. A click
# on a ring socket puts the held ability there, unless the ring already holds
# its limit of copies, and a click with nothing held empties the socket. A
# mouse-down anywhere but on a socket drops the held ability.
extends Control

const TalentNodeScene: PackedScene = preload("res://scenes/ui/menu/talent_node.tscn")

# Where the frame places 'talenttreefull', and the st0 to st27 placements
# inside it, row by row.
const TREE_ORIGIN: Vector2 = Vector2(45.4, 74.15)
const TREE_COLUMNS_X: Array[float] = [41.4, 93.4, 145.4, 197.4]
const TREE_ROWS_Y: Array[float] = [49.85, 89.85, 129.85, 169.85, 209.85, 249.85, 289.85]
const NODE_SIZE: Vector2 = Vector2(32, 32)

# Where the frame places the ring, sprite 3109, and its scale, which also
# scales the thing0 to thing7 offsets inside it.
const WHEEL_CENTER: Vector2 = Vector2(630.6, 172.2)
const WHEEL_SCALE: float = 1.0383
const WHEEL_OFFSETS: Array[Vector2] = [
	Vector2(0.0, -49.2), Vector2(34.8, -34.9), Vector2(49.5, 0.0),
	Vector2(35.0, 35.3), Vector2(0.0, 49.8), Vector2(-35.2, 35.1),
	Vector2(-49.5, 0.0), Vector2(-35.0, -34.7),
]
const SOCKET_SIZE: Vector2 = Vector2(30, 30)

# The DropShadows of 'talenttreefull' and the ring 3109. Flash draws each under
# everything its sprite holds, and the port draws it under each node and each
# socket. The offset is the distance at 45 degrees, and the alpha is the
# strength.
const TREE_SHADOW: Dictionary = {"size": 3, "offset": Vector2(2.1213, 2.1213), "color": Color(0, 0, 0, 1)}
const WHEEL_SHADOW: Dictionary = {"size": 6, "offset": Vector2(2.8284, 2.8284), "color": Color(0, 0, 0, 173.0 / 255.0)}

const POOL_VISIBLE_ROWS: int = 5

# The Hub's Combat text banner, which shows SKILLERROR. hotbar.gd reaches it
# through the same group.
const BANNER_GROUP: StringName = &"combat_text_banner"


var _tree_buttons: Array[Button] = []
var _tree_rank_labels: Array[Label] = []
@onready var _tree_lines: Control = $TreeLines
var _socket_buttons: Array[Button] = []
# The colour each socket's disc took when the socket last went from empty to an
# ability, or null while it is empty. A socket that goes from one ability
# straight to another keeps its disc, because the icon clip stays on frames
# that hold it and the disc's load script does not run again. Measured in the
# Flash debug player for #439. Opening the window makes the ring again, which
# clears every colour.
var _socket_disc_colors: Array = []
@onready var _pool_rows: Array[AbilityPoolRow] = [
	$Pool/Mask/Rows/PoolRow0, $Pool/Mask/Rows/PoolRow1, $Pool/Mask/Rows/PoolRow2, $Pool/Mask/Rows/PoolRow3, $Pool/Mask/Rows/PoolRow4,
]
var _pool_scroll: int = 0
var _pool_move_ids: Array = []
# The original's UITmouseHold: the ability a pool press holds, or 0.
var _held_move_id: int = 0
# The original's UITdrop: true while the mouse is over a ring socket.
var _over_socket: bool = false
var _held_icon_offset: Vector2 = Vector2.ZERO
@onready var _held_icon: TextureRect = $HeldIcon

@onready var _name_label: Label = $NameLabel
@onready var _level_label: Label = $LevelLabel
@onready var _ability_points_value: Label = $AbilityPointsValue
@onready var _attribute_points_value: Label = $AttributePointsValue
@onready var _attribute_values: Array[Label] = [
	$AttributeRows/VitalityRow/VitalityValue, $AttributeRows/StrengthRow/StrengthValue,
	$AttributeRows/InstinctRow/InstinctValue, $AttributeRows/SpeedRow/SpeedValue,
]
@onready var _attribute_names: Array[Label] = [
	$AttributeRows/VitalityRow/VitalityLabel, $AttributeRows/StrengthRow/StrengthLabel,
	$AttributeRows/InstinctRow/InstinctLabel, $AttributeRows/SpeedRow/SpeedLabel,
]
@onready var _plus_buttons: Array[Button] = [
	$PlusColumn/VitalitySlot/VitalityPlus, $PlusColumn/StrengthSlot/StrengthPlus,
	$PlusColumn/InstinctSlot/InstinctPlus, $PlusColumn/SpeedSlot/SpeedPlus,
]
@onready var _hint_steps: HintSteps = $HintSteps
@onready var _status_label: Label = $StatusLabel


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_static_text()
	_style_plus_buttons()
	_build_tree_panel()
	_build_wheel_panel()
	# The original places the hint box at depth 675, above the tree and the
	# ring, and its arrows reach over both. The sockets are added above, so the
	# box moves back on top.
	move_child(_hint_steps, -1)
	_hint_steps.open(GameData.current_save)
	# The sockets are added after the scene's own nodes, so the held icon moves
	# back to the end to draw over them, as the tooltip clip draws over the menu.
	move_child(_held_icon, -1)
	var held_rect: Dictionary = TooltipTheme.look()["held_icon"]
	_held_icon_offset = Vector2(held_rect["x"], held_rect["y"])
	_held_icon.size = Vector2(held_rect["w"], held_rect["h"])
	_set_held(0)
	for i in _pool_rows.size():
		_pool_rows[i].button_down.connect(_on_pool_row_held.bind(i))
		_pool_rows[i].mouse_entered.connect(_on_pool_row_hovered.bind(i))
		_pool_rows[i].mouse_exited.connect(GameTooltip.hide_tooltip)
	visibility_changed.connect(func():
		_set_held(0)
		if visible:
			_socket_disc_colors.fill(null)
			_hint_steps.open(GameData.current_save)
			refresh())


# DefineSprite_3142/frame_25/DoAction.as:2-5 and 10-15.
func _set_static_text() -> void:
	$TreeTitle.text = Strings.text("K_TITLE1")
	$AttributesTitle.text = Strings.text("K_TITLE2")
	$ActionBarTitle.text = Strings.text("K_TITLE3")
	$PoolTitle.text = Strings.menu(16)
	$AbilityPointsLabel.text = Strings.text("SKLOAD") + ":"
	$AttributePointsLabel.text = Strings.text("SPLOAD") + ":"
	for i in _attribute_names.size():
		_attribute_names[i].text = Strings.system(i) + ":"


# The SWF tints the gradient plate of shape 3064 per row, and its button 3068
# swaps the black plus glyph and its outline (3065) for the white shape 3066 on
# hover and press. The port fills each native Button with its row's name
# colour instead, which ADR 0007 records.
func _style_plus_buttons() -> void:
	for i in _plus_buttons.size():
		var color: Color = _attribute_names[i].get_theme_color("font_color")
		var fills: Dictionary[String, Color] = {
			"normal": color,
			"hover": color.lightened(0.25),
			"pressed": color.darkened(0.25),
		}
		for state: String in fills:
			var style := StyleBoxFlat.new()
			style.bg_color = fills[state]
			_plus_buttons[i].add_theme_stylebox_override(state, style)
		# Godot draws the focus style over the state style, and a click gives
		# the button focus, so a filled focus style would hide the hover and
		# pressed fills after the first click.
		_plus_buttons[i].add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _build_tree_panel() -> void:
	var tree: Array = TalentTree.TREES.get(_player_class(), TalentTree.TREES[PlayerSave.PlayerClass.BIOLOGICAL])
	for node_index in tree.size():
		var node_button: Button = TalentNodeScene.instantiate()
		node_button.name = "Node%d" % node_index
		node_button.position = _node_center(node_index) - NODE_SIZE / 2.0
		node_button.pressed.connect(_on_tree_node_pressed.bind(node_index))
		node_button.mouse_entered.connect(_on_tree_node_hovered.bind(node_index))
		node_button.mouse_exited.connect(GameTooltip.hide_tooltip)
		_style_circle_button(node_button, Color(0.1, 0.1, 0.11), Color(0.3, 0.3, 0.32), TREE_SHADOW)
		$TreeNodes.add_child(node_button)
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
		# The rect test names each port only node, so a socket needs a stable name.
		socket.name = "Socket%d" % i
		socket.custom_minimum_size = SOCKET_SIZE
		socket.size = SOCKET_SIZE
		socket.position = WHEEL_CENTER + WHEEL_OFFSETS[i] * WHEEL_SCALE - SOCKET_SIZE / 2.0
		socket.pressed.connect(_on_socket_pressed.bind(i))
		socket.mouse_entered.connect(_on_socket_hovered.bind(i))
		socket.mouse_entered.connect(func(): _over_socket = true)
		socket.mouse_exited.connect(GameTooltip.hide_tooltip)
		socket.mouse_exited.connect(func(): _over_socket = false)
		_style_circle_button(socket, Color(0.09, 0.09, 0.1), Color(0.22, 0.22, 0.24), WHEEL_SHADOW)
		add_child(socket)
		_socket_buttons.append(socket)
		_socket_disc_colors.append(null)


func _style_circle_button(button: Button, bg: Color, border: Color, shadow: Dictionary) -> void:
	for state in ["normal", "hover", "pressed"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = bg.lightened(0.12) if state != "normal" else bg
		style.border_color = border
		style.set_border_width_all(2)
		style.set_corner_radius_all(99)
		style.shadow_size = shadow["size"]
		style.shadow_offset = shadow["offset"]
		style.shadow_color = shadow["color"]
		button.add_theme_stylebox_override(state, style)
	button.add_theme_font_size_override("font_size", 9)


func refresh() -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	_status_label.text = ""
	_name_label.text = Party.PLAYER_NAME
	# DefineSprite_3142/frame_25/DoAction.as:17. ClassStats counts from 1, and
	# PlayerClass counts from 0.
	_level_label.text = "%s%d %s" % [Strings.menu(0), save.level, Strings.text("CLASS", save.player_class)]
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
			color if learned else Color(0.3, 0.3, 0.32),
			TREE_SHADOW
		)
		_tree_rank_labels[node_index].text = "%d/%d" % [rank, int(node["max_rank"])]
		var icon_rect: TextureRect = button.get_node("IconRect")
		icon_rect.texture = _tree_node_icon(node)


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
		return AbilityIcon.key(str(node["buff_family"]))
	var move: Ability = MoveManagerAuto.get_move(int(node["move_id"]))
	return AbilityIcon.key(move.display_name) if move != null else ""


# krinRemakeTree gives a node's disc the element of its ID's move. A passive
# node's ID is 0, so its disc takes move 0's element
# (DefineSprite_3142/frame_25/PlaceObject3_3100_153 load, lines 51-57).
func _tree_node_icon(node: Dictionary) -> Texture2D:
	var move: Ability = MoveManagerAuto.get_move(int(node["move_id"]))
	return AbilityIcon.texture(_tree_node_icon_key(node), AbilityIcon.element_color(move))


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
	var next_move: Ability = null
	if not TalentTree.is_passive(node):
		# Rank-aware: show the CURRENTLY GRANTED move's text once learned,
		# otherwise the move rank 1 would grant. A passive needs no lookup
		# here - the builder reads its text from TalentTree.
		var rank: int = TalentTree.get_rank(save, node_index)
		move = MoveManagerAuto.get_move(TalentTree.granted_move_id(node, max(rank, 1)))
		if rank < int(node["max_rank"]):
			next_move = MoveManagerAuto.get_move(TalentTree.granted_move_id(node, rank + 1))
	var button: Button = _tree_buttons[node_index]
	var result: Dictionary = AbilityTooltipBuilder.build_sections(node, save, move, next_move)
	GameTooltip.show_sections(result["sections"], button, _tree_node_icon(node), result["icon_color"], TooltipTheme.TEXT_WIDTH_ABILITY, "", true)


func _refresh_wheel(save: PlayerSave) -> void:
	for i in _socket_buttons.size():
		var socket: Button = _socket_buttons[i]
		var move_id: int = int(save.move_matrix[i]) if i < save.move_matrix.size() else 0
		if move_id == 0:
			socket.icon = null
			_socket_disc_colors[i] = null
			_style_circle_button(socket, Color(0.09, 0.09, 0.1), Color(0.22, 0.22, 0.24), WHEEL_SHADOW)
			continue
		var move: Ability = MoveManagerAuto.get_move(move_id)
		var color: Color = _move_color(move)
		if move != null and _socket_disc_colors[i] == null:
			_socket_disc_colors[i] = AbilityIcon.element_color(move)
		socket.icon = AbilityIcon.texture(AbilityIcon.key(move.display_name), _socket_disc_colors[i]) if move != null else null
		socket.expand_icon = true
		socket.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_style_circle_button(socket, color.darkened(0.45), color, WHEEL_SHADOW)


func _on_socket_hovered(socket_index: int) -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	var move_id: int = int(save.move_matrix[socket_index]) if socket_index < save.move_matrix.size() else 0
	var button: Button = _socket_buttons[socket_index]
	if move_id == 0:
		GameTooltip.show_sections(AbilityTooltipBuilder.empty_socket_sections(), button, null, Color.WHITE, TooltipTheme.TEXT_WIDTH_ABILITY, "", true)
		return
	var move: Ability = MoveManagerAuto.get_move(move_id)
	if move == null:
		return
	var result: Dictionary = AbilityTooltipBuilder.build_sections({}, save, move)
	GameTooltip.show_sections(result["sections"], button, button.icon, result["icon_color"], TooltipTheme.TEXT_WIDTH_ABILITY, "", true)


func _refresh_pool(save: PlayerSave) -> void:
	_pool_move_ids = []
	# KrinCreateAbilityMatrix lists every owned ability, the ones on the ring
	# too, so the player can take another copy up to the ability's limit
	# (DefineSprite_3142/frame_25/DoAction.as:35-44). Its for..in walks the
	# push-built moveMatrix2 from the last index down, in a new game and in a
	# loaded one (DECODED_ALGORITHMS.md "for..in order over arrays").
	for i in range(save.move_matrix2.size() - 1, -1, -1):
		var move_id: int = int(save.move_matrix2[i])
		if move_id != 0:
			_pool_move_ids.append(move_id)
	_pool_scroll = clamp(_pool_scroll, 0, max(0, _pool_move_ids.size() - POOL_VISIBLE_ROWS))
	for i in _pool_rows.size():
		var row: AbilityPoolRow = _pool_rows[i]
		var pool_index: int = _pool_scroll + i
		if pool_index >= _pool_move_ids.size():
			row.clear()
			continue
		var move: Ability = MoveManagerAuto.get_move(_pool_move_ids[pool_index])
		row.populate(move, AbilityIcon.for_move(move) if move != null else null)


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
	GameTooltip.show_sections(result["sections"], row, AbilityIcon.for_move(move), result["icon_color"], TooltipTheme.TEXT_WIDTH_ABILITY, "", true)


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


# A socket's pressed signal comes on a release over the socket that took the
# press, as the original's on(release) does, so the player presses a pool
# ability, then clicks a socket. This ports addMoveForPlayer's menu branch: the
# count of copies on the ring includes the one in the target socket, and a
# refusal shows SKILLERROR with a bare play() (frame_42/DoAction_11.as:4-44).
func _on_socket_pressed(socket_index: int) -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	if _held_move_id == 0:
		save.move_matrix[socket_index] = 0
	else:
		var copies: int = 0
		for move_id in save.move_matrix:
			if int(move_id) == _held_move_id:
				copies += 1
		if copies < MoveManagerAuto.get_move(_held_move_id).hotbar_slot_limit:
			save.move_matrix[socket_index] = _held_move_id
		else:
			_show_combat_text(Strings.text("SKILLERROR"))
		_set_held(0)
	refresh()


func _show_combat_text(text: String) -> void:
	var banner: CombatTextBanner = get_tree().get_first_node_in_group(BANNER_GROUP)
	if banner == null:
		push_error("abilities_window: no Combat text banner in the scene to show %s" % text)
		return
	banner.show_if_idle(text)


# DefineButton2_2437 on(press), which a Button's button_down matches.
func _on_pool_row_held(row_index: int) -> void:
	var pool_index: int = _pool_scroll + row_index
	if pool_index < _pool_move_ids.size():
		_set_held(_pool_move_ids[pool_index])


func _set_held(move_id: int) -> void:
	_held_move_id = move_id
	var move: Ability = MoveManagerAuto.get_move(move_id) if move_id != 0 else null
	_held_icon.texture = AbilityIcon.for_move(move) if move != null else null
	_held_icon.visible = move != null
	set_process(move != null)
	if move != null:
		_place_held_icon(get_global_mouse_position())


func _process(_delta: float) -> void:
	_place_held_icon(get_global_mouse_position())


# The tooltip clip moves its origin to the mouse on every frame, and its inner2
# shows the held ability's icon at that origin. tooltip_look.json has the
# icon's rect from the origin.
func _place_held_icon(mouse: Vector2) -> void:
	_held_icon.global_position = mouse + _held_icon_offset


# The menu frame's onMouseDown drops a held ability unless UITdrop says the
# mouse is over a ring socket (frame_181/DoAction_2.as:10-14). This reads the
# press before the Buttons do, so a press on another pool ability drops the
# first and then holds the second, as in the original.
func _input(event: InputEvent) -> void:
	if _held_move_id == 0 or not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _over_socket:
		_set_held(0)


func _on_pool_scrolled(direction: int) -> void:
	_pool_scroll = clamp(
		_pool_scroll + direction, 0,
		max(0, _pool_move_ids.size() - POOL_VISIBLE_ROWS)
	)
	var save: PlayerSave = GameData.current_save
	if save != null:
		_refresh_pool(save)
