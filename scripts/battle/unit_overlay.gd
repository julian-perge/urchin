# unit_overlay.gd
# The unmirrored per-unit HUD overlay shown over each battling character's
# paper doll: name, health bar + value, focus bar, and a hover/click zone.
# FighterPresenter owns one per fighter, positions it at the doll and draws the
# hover ring onto its Ring node, whose color depends on the unit's relation to
# the player. show_status() is the one place the bars are written.
extends Control
class_name UnitOverlay

const MAX_BUFF_ICONS: int = 7
const BUFF_ICON_SIZE: Vector2 = Vector2(16, 16)
# The counter is KrinBuffShower's edit text 66, placed at (-10.3, -0.8) from
# the icon's center. Inside its 2 px gutter its text runs 20.55 px wide and
# centered, which centers the turns left over the lower half of the icon.
const BUFF_COUNTER_OFFSET: Vector2 = Vector2(-10.3, -0.8)
const BUFF_COUNTER_WIDTH: float = 20.55

@onready var ring: Control = $Ring
@onready var name_label: Label = $NameLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_value: Label = $HealthValue
@onready var focus_bar: ProgressBar = $FocusBar
@onready var hit_button: Button = $HitButton
@onready var buff_row: HBoxContainer = $BuffRow

# The rendered active-slot set as of the last refresh_buffs() call, so a
# refresh that lands with the same buffs/durations as last time (this is
# called after every combat event, not only when buffs actually change) can
# skip tearing down and rebuilding the row - which would otherwise flicker
# and kill an open tooltip out from under a player mid-hover for no reason.
var _last_signature: Array = []


func setup(unit_name: String) -> void:
	name_label.text = unit_name


# displayed_hp comes from the caller because the health bar only follows the
# unit's life as each hit lands on screen. Focus and buffs show the unit's true
# state every time.
func show_status(unit: CombatUnit, displayed_hp: float, buffs_by_id: Dictionary) -> void:
	health_bar.max_value = unit.life_u
	health_bar.value = displayed_hp
	health_value.text = str(int(displayed_hp))
	focus_bar.max_value = max(unit.focus_u, 1)
	focus_bar.value = unit.focus_n
	refresh_buffs(unit, buffs_by_id)


# Refreshes the buff-icon row the way the original draws it at the end of
# applyChangesKrin (frame_42/DoAction_10.as:355-379): one KrinBuffShower for
# each of slots 0 to MAX_BUFF_ICONS - 1 whose cd isn't 0, in slot order. The
# row deliberately doesn't sort, because CombatUnit.apply_changes() already
# keeps buff_slots in the order applyChangesKrin's sortOn leaves them (line
# 344), and sort_custom would move tied buffs once more than 16 have turns
# left. Each icon is modulate-tinted by the buff's element color (Godot tints
# at runtime - no per-element art baked into the extracted PNGs), with the
# remaining-turns count and the tooltip built below. buff_id 0 is a real buff
# (TWINGUARDIANS, dev/converted_json/buffs.json), not an empty-slot sentinel;
# empty slots use buff_id -1 (see CombatUnit's slot init) but always carry
# cd == 0 too, so checking cd alone already excludes them.
func refresh_buffs(unit: CombatUnit, buffs_by_id: Dictionary) -> void:
	if unit == null:
		_clear_row()
		return
	var active_slots: Array = []
	for slot in unit.buff_slots.slice(0, MAX_BUFF_ICONS):
		if int(slot.get("cd", 0)) != 0:
			active_slots.append(slot)
	var signature: Array = []
	for slot in active_slots:
		signature.append({"buff_id": int(slot["buff_id"]), "cd": int(slot["cd"])})
	if signature == _last_signature:
		return
	_last_signature = signature
	for child in buff_row.get_children():
		child.queue_free()
	for slot in active_slots:
		var buff: Buff = buffs_by_id.get(int(slot["buff_id"]))
		if buff == null:
			continue
		var icon_texture: Texture2D = BuffIcons.icon_for(buff)
		if icon_texture == null:
			continue
		# KrinBuffShower, DefineSprite 104, places buffColor, the icon and the
		# counter as siblings at depths 1, 4 and 8, and tints only buffColor
		# (frame_42/DoAction_10.as:373-374). The port has no buffColor and
		# tints the icon instead, so the counter is the icon's sibling here
		# and keeps its own white.
		var shower: Control = Control.new()
		shower.custom_minimum_size = BUFF_ICON_SIZE
		var icon_rect: TextureRect = TextureRect.new()
		icon_rect.name = "Icon"
		icon_rect.texture = icon_texture
		icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var element_index: CombatUnit.Element = buff.element_type
		if element_index != -1:
			icon_rect.modulate = MenuTheme.ELEMENT_COLORS[element_index]
		shower.add_child(icon_rect)
		# The original titles a buff's tooltip with its name alone and shows
		# the turns left only on the icon's counter below
		# (frame_42/DoAction_10.as:364 and 375).
		var sections: Array = [
			{"bg_color": TooltipTheme.BG_HEADER, "lines": [{
				"text": buff.display_name,
				"color": TooltipTheme.TEXT_TITLE,
			}]},
		]
		if not buff.tooltip_description.is_empty():
			sections.append({"bg_color": TooltipTheme.BG_BODY, "lines": [{"text": buff.tooltip_description, "color": TooltipTheme.TEXT_BODY}]})
		shower.mouse_entered.connect(func(): GameTooltip.show_sections(sections, shower))
		shower.mouse_exited.connect(GameTooltip.hide_tooltip)
		# Edit text 66 sets the turns left in 10 px bold _sans, the face the
		# project theme gives Labels.
		var counter: Label = Label.new()
		counter.name = "Counter"
		counter.text = str(int(slot["cd"]))
		counter.add_theme_font_size_override("font_size", 10)
		counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		counter.position = BUFF_ICON_SIZE / 2.0 + BUFF_COUNTER_OFFSET
		counter.size.x = BUFF_COUNTER_WIDTH
		counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shower.add_child(counter)
		buff_row.add_child(shower)


func _clear_row() -> void:
	if _last_signature.is_empty():
		return
	for child in buff_row.get_children():
		child.queue_free()
	_last_signature = []
