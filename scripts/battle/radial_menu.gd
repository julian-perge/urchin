# radial_menu.gd
# The ring of ability orbs that fans out around a clicked unit while the player
# decides. battle_scene.gd keeps one for the whole battle, hands it the units
# and the two lookups through setup(), opens it when a unit is clicked, and sets
# decision_open as the turn loop opens and closes the decision.
#
# The eight orbs are fixed children, one per bar slot, the way the original's
# selector clip holds thing0 to thing7. Opening dresses them for the current bar
# and closing hides them, so no orb is ever created or freed.
#
# advance() plays the original ring's enterFrame once per SWF frame, from a clock
# the menu keeps itself, rather than through a Timer and a Tween. With neither
# of those, nothing can outlive a menu. A Tween that outlived its menu once
# closed the next menu to open (08dc6a7).
extends Control
class_name RadialMenu

signal move_picked(bar_index: int, move_id: int, target_slot: int)
# A click on an orb whose move the player cannot pick, with the message the
# Combat text banner shows for its Refusal. The menu stays open.
signal pick_refused(message: String)

# extract_battle_screen writes the Radial menu clip's scale, the rects of its
# thingo0 to thingo7 buttons that the orbs are built from, and the box of
# everything it draws into the radial_menu entry, and the SWF's frame rate into
# the fade entry.
const BATTLE_LAYOUT_PATH: String = "res://assets/backgrounds/battle/battle_layout.json"
# The ring's enterFrame adds 50 to the clip's alpha each frame while it fades in
# and takes 10 each frame the mouse is off it (frame_217/PlaceObject3_3382_500
# enterFrame, lines 32-35 and 50). The alpha is in Flash's 1/256 steps
# (FlashAlpha).
const FADE_IN_STEP: int = 50
const FADE_OUT_STEP: int = 10
# Render deltas that add up to a whole SWF frame can fall short of it by a float
# rounding error, so a frame counts as passed within this margin.
const FRAME_EPSILON: float = 0.000001
# extract_ability_icons writes the black disc a darkened orb is covered with and
# where it and the cooldown count sit on the orb.
const COOLDOWN_LAYOUT_PATH: String = "res://assets/ui/abilities/cooldown.json"
const COVER_PATH: String = "res://assets/ui/abilities/cooldown_cover.png"
# The ring's enterFrame sets the disc's _alpha to 75 while the ring fades in and
# to 85 once it has (frame_217/PlaceObject3_3382_500 enterFrame, lines 16 and
# 42). Flash stores 85 as 217/256 (FlashAlpha).
const COVER_PERCENT_FADING_IN: float = 75.0
const COVER_PERCENT: float = 85.0

# Setting this false closes any menu that is up, and open() does nothing until
# it is true again.
var decision_open: bool = false:
	set(value):
		decision_open = value
		if not decision_open:
			_close()

var _units: Dictionary = {}
var _moves_by_id: Dictionary = {}
var _buffs_by_id: Dictionary = {}
var _target_slot: int = -1
var _tooltip_up: bool = false
var _frame_time: float = 0.0
var _frame_clock: float = 0.0
var _alpha: int = 0
# The original's "clicker" flag: true from the click until the fade-in ends.
var _fading_in: bool = false
# The Radial menu clip's box in the menu's own coordinates, already scaled.
var _box: Rect2

@onready var orbs: Array[Button] = [$Orb0, $Orb1, $Orb2, $Orb3, $Orb4, $Orb5, $Orb6, $Orb7]


func _ready() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(COOLDOWN_LAYOUT_PATH))
	var battle_layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BATTLE_LAYOUT_PATH))
	var ring: Dictionary = battle_layout["radial_menu"]
	var ring_scale: float = float(ring["scale"])
	var box: Dictionary = ring["box"]
	_box = Rect2(Vector2(box["x"], box["y"]) * ring_scale, Vector2(box["w"], box["h"]) * ring_scale)
	_frame_time = 1.0 / float(battle_layout["fade"]["fps"])
	var cover_texture: Texture2D = load(COVER_PATH)
	for bar_index in orbs.size():
		var orb: Button = orbs[bar_index]
		var rect: Dictionary = ring["orb_rects"][bar_index]
		orb.custom_minimum_size = Vector2(rect["w"], rect["h"]) * ring_scale
		orb.size = orb.custom_minimum_size
		orb.position = Vector2(rect["x"], rect["y"]) * ring_scale
		orb.expand_icon = true
		orb.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		orb.add_child(_make_cover(cover_texture, layout["cover"], orb.size / 2.0))
		orb.add_child(_make_count(layout["count"], orb.size / 2.0))
		orb.pressed.connect(_on_orb_pressed.bind(bar_index))
		orb.mouse_entered.connect(_on_orb_entered.bind(bar_index))
		orb.mouse_exited.connect(_on_orb_exited)


# The original's "bfilter", the black disc over a darkened orb.
func _make_cover(texture: Texture2D, rect: Dictionary, centre: Vector2) -> TextureRect:
	var cover := TextureRect.new()
	cover.name = "Cover"
	cover.texture = texture
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.position = centre + Vector2(rect["x"], rect["y"])
	cover.size = Vector2(rect["w"], rect["h"])
	cover.modulate.a = FlashAlpha.multiplier(FlashAlpha.from_percent(COVER_PERCENT))
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.visible = false
	return cover


# The original's "ACD" field, the turns left on a cooldown. It keeps the font
# the project theme gives every Label, which is the Stand-in font for the bold
# _sans the field names, as the Combat text banner's line does.
func _make_count(text_layout: Dictionary, centre: Vector2) -> Label:
	var count := Label.new()
	count.name = "Count"
	var rect: Dictionary = text_layout["rect"]
	count.position = centre + Vector2(rect["x"], rect["y"])
	count.size = Vector2(rect["w"], rect["h"])
	count.horizontal_alignment = LabelLayout.ALIGNMENTS[text_layout["align"]]
	count.add_theme_font_size_override("font_size", int(text_layout["size"]))
	count.add_theme_color_override("font_color", Color(text_layout["color"]))
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return count


func _process(delta: float) -> void:
	advance(delta, get_global_mouse_position())


func setup(units: Dictionary, moves_by_id: Dictionary, buffs_by_id: Dictionary) -> void:
	_units = units
	_moves_by_id = moves_by_id
	_buffs_by_id = buffs_by_id


# A click shows the clip at alpha 0 and starts its fade-in
# (frame_217/DoAction_3.as:46-48).
func open(target_slot: int, centre: Vector2) -> void:
	if not decision_open:
		return
	var target: CombatUnit = _units.get(target_slot)
	if target == null or not target.active:
		return
	_close()
	var player: CombatUnit = _units.get(BattleRunner.PLAYER_SLOT)
	if player == null:
		return
	var any_orb_shown: bool = false
	for bar_index in orbs.size():
		if _dress_orb(bar_index, player, target):
			any_orb_shown = true
	if not any_orb_shown:
		return
	_target_slot = target_slot
	position = centre
	_alpha = 0
	_fading_in = true
	_set_cover_alpha(COVER_PERCENT_FADING_IN)
	modulate.a = 0.0
	visible = true


# Plays one enterFrame of the ring for each whole SWF frame that delta completes,
# with the mouse at pointer. _process() passes the real mouse, and a test calls
# this directly after set_process(false) to pass a known point.
func advance(delta: float, pointer: Vector2) -> void:
	if not visible:
		return
	_frame_clock += delta
	while visible and _frame_clock >= _frame_time - FRAME_EPSILON:
		_frame_clock -= _frame_time
		_play_frame(pointer)


# One enterFrame of the ring (frame_217/PlaceObject3_3382_500 enterFrame). The
# fade-in runs to 100 and ends on the frame after, and only then does the mouse
# count. Off the clip alpha falls until the clip hides at 0, and over it alpha
# goes straight back to 100.
func _play_frame(pointer: Vector2) -> void:
	if _fading_in:
		if FlashAlpha.to_percent(_alpha) < 100.0:
			_alpha = FlashAlpha.add(_alpha, FADE_IN_STEP)
		else:
			_alpha = FlashAlpha.from_percent(100.0)
			_fading_in = false
			_set_cover_alpha(COVER_PERCENT)
	elif not _is_over_menu(pointer):
		_alpha = FlashAlpha.add(_alpha, -FADE_OUT_STEP)
		if _alpha <= 0:
			_close()
			return
	else:
		_alpha = FlashAlpha.from_percent(100.0)
	modulate.a = FlashAlpha.multiplier(_alpha)


func _set_cover_alpha(percent: float) -> void:
	for orb in orbs:
		(orb.get_node("Cover") as TextureRect).modulate.a = FlashAlpha.multiplier(FlashAlpha.from_percent(percent))


func _close() -> void:
	visible = false
	_fading_in = false
	_frame_clock = 0.0
	if _tooltip_up:
		_tooltip_up = false
		GameTooltip.hide_tooltip()


# The original tests the mouse with hitTest and no shape flag, which tests the
# clip's bounding box, so the gaps between orbs, an empty slot and the unit
# inside the ring all count as over it (enterFrame line 48).
func _is_over_menu(point: Vector2) -> bool:
	return (get_global_transform() * _box).has_point(point)


# Returns whether this bar slot shows an orb.
func _dress_orb(bar_index: int, player: CombatUnit, target: CombatUnit) -> bool:
	var orb: Button = orbs[bar_index]
	var move: Ability = _move_on_bar(player, bar_index)
	orb.visible = move != null
	if move == null:
		return false
	# The ring darkens an orb for a bad target or a cooldown and for nothing else,
	# and it tests the cooldown on its own, so a cooldown darkens its orb even when
	# another check names the message (frame_217/PlaceObject3_3382_500
	# enterFrame, lines 15-29). refusal() tests the target before anything else,
	# so it names BAD_TARGET whenever the target is wrong.
	var bad_target: bool = MoveLegality.refusal(player, move, bar_index, target, _buffs_by_id) == MoveLegality.Refusal.BAD_TARGET
	var turns_left: int = int(player.ability_cooldowns[bar_index]) if bar_index < player.ability_cooldowns.size() else 0
	(orb.get_node("Cover") as TextureRect).visible = bad_target or turns_left > 0
	(orb.get_node("Count") as Label).text = str(turns_left) if turns_left > 0 else ""
	orb.icon = AbilityIcon.for_move(move)
	_style_orb(orb, _move_color(move))
	return true


# An empty ("None") slot is the only thing that hides an orb - the source's
# refreshOrbs() never renumbers around a temporarily-unusable one, it only hides
# move id 0.
func _move_on_bar(player: CombatUnit, bar_index: int) -> Ability:
	if bar_index >= player.equipped_moves.size():
		return null
	var move_id: int = int(player.equipped_moves[bar_index])
	return null if move_id == 0 else _moves_by_id.get(move_id)


# The original's orb buttons call addMoveForPlayer with no gate of their own, so
# every orb takes the click, darkened or not. Only a pick that passes every
# check closes the menu (frame_42/DoAction_11.as:60-104).
func _on_orb_pressed(bar_index: int) -> void:
	var player: CombatUnit = _units[BattleRunner.PLAYER_SLOT]
	var move: Ability = _move_on_bar(player, bar_index)
	var refusal: MoveLegality.Refusal = MoveLegality.refusal(player, move, bar_index, _units.get(_target_slot), _buffs_by_id)
	if refusal != MoveLegality.Refusal.NONE:
		pick_refused.emit(MoveLegality.message(refusal))
		return
	var move_id: int = int(player.equipped_moves[bar_index])
	_close()
	move_picked.emit(bar_index, move_id, _target_slot)


func _on_orb_entered(bar_index: int) -> void:
	var move: Ability = _move_on_bar(_units[BattleRunner.PLAYER_SLOT], bar_index)
	GameTooltip.show_sections(
		_tooltip_sections(move), orbs[bar_index], null, Color.WHITE, TooltipTheme.TEXT_WIDTH_ABILITY, "", true
	)
	_tooltip_up = true


func _on_orb_exited() -> void:
	_tooltip_up = false
	GameTooltip.hide_tooltip()


func _tooltip_sections(move: Ability) -> Array:
	var cost_line: String = "This move costs nothing"
	if move.focus_cost > 0:
		cost_line = "This move costs %d Focus" % int(move.focus_cost)
	var sections: Array = [
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": move.display_name, "color": TooltipTheme.TEXT_TITLE}]},
		{"bg_color": TooltipTheme.BG_COST, "lines": [{"text": cost_line, "color": TooltipTheme.TEXT_SUBHEADER}]},
	]
	var body_lines: Array = []
	if not move.tooltip_description.is_empty():
		body_lines.append({"text": move.tooltip_description, "color": TooltipTheme.TEXT_BODY})
	if move.cooldown_turns > 0:
		body_lines.append({"text": "Cooldown: %d turns" % move.cooldown_turns, "color": TooltipTheme.TEXT_BODY})
	if not body_lines.is_empty():
		sections.append({"bg_color": TooltipTheme.BG_BODY, "lines": body_lines})
	return sections


func _move_color(move: Ability) -> Color:
	var element_index: CombatUnit.Element = move.damage_element_type
	return MenuTheme.ELEMENT_COLORS[element_index] if element_index != -1 else Color(0.5, 0.5, 0.5)


func _style_orb(orb: Button, color: Color) -> void:
	for state in ["normal", "hover", "pressed"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		var bg: Color = Color(0.08, 0.08, 0.1)
		style.bg_color = bg.lightened(0.1) if state == "hover" else bg
		style.border_color = color
		style.set_border_width_all(2)
		style.set_corner_radius_all(99)
		orb.add_theme_stylebox_override(state, style)
	orb.add_theme_font_size_override("font_size", 9)
