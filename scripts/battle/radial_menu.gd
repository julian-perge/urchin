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
# The time the mouse has been away is one number that advance() steps, rather
# than a Timer and a Tween. With neither of those, nothing can outlive a menu.
# A Tween that outlived its menu once closed the next menu to open (08dc6a7).
extends Control
class_name RadialMenu

signal move_picked(bar_index: int, move_id: int, target_slot: int)
# A click on an orb whose move the player cannot pick, with the message the
# Combat text banner shows for its Refusal. The menu stays open.
signal pick_refused(message: String)

const ORB_RADIUS: float = 15.0
const ICON_DIR: String = "res://assets/ui/abilities/"
# The 8 fixed positions of the original's "selector" clip (thing0-7) - the
# same real extracted offsets as abilities_window.gd's WHEEL_OFFSETS (that
# clip is placed on the battle scene itself too, per
# frame_217/PlaceObject3_3382_500/.../onClipEvent(load).as's refreshOrbs()).
# Duplicated here rather than imported since abilities_window.gd has no
# class_name to reach its consts from.
const ORB_OFFSETS: Array[Vector2] = [
	Vector2(0.0, -49.2), Vector2(34.8, -34.9), Vector2(49.5, 0.0),
	Vector2(35.0, 35.3), Vector2(0.0, 49.8), Vector2(-35.2, 35.1),
	Vector2(-49.5, 0.0), Vector2(-35.0, -34.7),
]
# How long the mouse may be away before the menu starts to fade, and how long
# the fade takes. Both are the port's own numbers. The original fades the clip
# out over 10 frames with no grace (frame_217/PlaceObject3_3382_500 enterFrame).
const LEAVE_GRACE: float = 0.15
const FADE_TIME: float = 0.67
# extract_ability_icons writes the black disc a darkened orb is covered with and
# where it and the cooldown count sit on the orb.
const COOLDOWN_LAYOUT_PATH: String = "res://assets/ui/abilities/cooldown.json"
const COVER_PATH: String = "res://assets/ui/abilities/cooldown_cover.png"
# The ring's enterFrame sets the disc to 85% alpha once the ring has faded in.
# It uses 75% only on the two frames the fade-in takes, and the port's ring opens
# whole with no fade-in (frame_217/PlaceObject3_3382_500 enterFrame, lines 16
# and 42).
const COVER_ALPHA: float = 0.85

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
var _hold_area: Control = null
var _away_seconds: float = 0.0
var _tooltip_up: bool = false

@onready var orbs: Array[Button] = [$Orb0, $Orb1, $Orb2, $Orb3, $Orb4, $Orb5, $Orb6, $Orb7]


func _ready() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(COOLDOWN_LAYOUT_PATH))
	var cover_texture: Texture2D = load(COVER_PATH)
	for bar_index in orbs.size():
		var orb: Button = orbs[bar_index]
		orb.custom_minimum_size = Vector2(ORB_RADIUS * 2, ORB_RADIUS * 2)
		orb.size = orb.custom_minimum_size
		orb.position = ORB_OFFSETS[bar_index] - orb.size / 2.0
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
	cover.modulate.a = COVER_ALPHA
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


# hold_area is the clicked unit's hit area, which keeps the menu open along with
# the orbs. The orbs fan out about 62px from the unit, well outside that area,
# so the unit alone would close the menu as the player moved toward an orb.
func open(target_slot: int, centre: Vector2, hold_area: Control) -> void:
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
	_hold_area = hold_area
	position = centre
	modulate.a = 1.0
	visible = true


# Steps the leave fade by one frame. _process() passes the real mouse, and a test
# calls this directly after set_process(false) to pass a known point.
func advance(delta: float, pointer: Vector2) -> void:
	if not visible:
		return
	_away_seconds = 0.0 if _is_over_menu(pointer) else _away_seconds + delta
	modulate.a = clampf(1.0 - (_away_seconds - LEAVE_GRACE) / FADE_TIME, 0.0, 1.0)
	if _away_seconds >= LEAVE_GRACE + FADE_TIME:
		_close()


func _close() -> void:
	visible = false
	_hold_area = null
	_away_seconds = 0.0
	if _tooltip_up:
		_tooltip_up = false
		GameTooltip.hide_tooltip()


func _is_over_menu(point: Vector2) -> bool:
	if _hold_area != null and _hold_area.get_global_rect().has_point(point):
		return true
	for orb in orbs:
		if orb.visible and orb.get_global_rect().has_point(point):
			return true
	return false


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
	var icon_path: String = "%s%s.png" % [ICON_DIR, _sanitize_icon_key(move.display_name)]
	orb.icon = load(icon_path) if ResourceLoader.exists(icon_path) else null
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
		_tooltip_sections(move), orbs[bar_index], null, Color.WHITE, TooltipTheme.TEXT_WIDTH_ABILITY
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


# Mirrors abilities_window.gd's own _sanitize_icon_key() - the same
# assets/ui/abilities/ lookup key, built the same way, so a display name
# with punctuation resolves to the file the extractor actually wrote.
func _sanitize_icon_key(label: String) -> String:
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
