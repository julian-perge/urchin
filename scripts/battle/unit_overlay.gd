# unit_overlay.gd
# The unmirrored per-unit HUD overlay shown over each battling character's
# paper doll: name, health bar + value, focus bar, and a hover/click zone.
# battle_scene.gd instances one per unit slot, positions it at the unit's
# world position, and wires the hover/click signals itself (the slot each
# instance represents is only known at instance time, not authoring time).
# The hover ring's actual `_draw()` callback also stays in battle_scene.gd
# (its color depends on the unit's live relation to the player) - this
# script only exposes the ring node for that connection.
extends Control
class_name UnitOverlay

const MAX_BUFF_ICONS: int = 7

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


# Refreshes the buff-icon row from the unit's own buff_slots, sorted by
# remaining duration (cd) descending, capped at MAX_BUFF_ICONS - matches
# frame42/sonny2_addNewBuffKrin.txt's BUFFARRAYK.sortOn("CD", DESCENDING)
# + the 7-slot cap exactly. Each icon is modulate-tinted by the buff's
# element color (Godot tints at runtime - no per-element art baked into
# the extracted PNGs), with the remaining-turns count and a
# name+description tooltip. A slot is active purely by cd > 0, same as
# every other buff_slots consumer (CombatUnit.tick_buffs(),
# BattleRunner._resolve_dispels()) - buff_id 0 is a real buff
# (TWINGUARDIANS, dev/converted_json/buffs.json), not an empty-slot
# sentinel; empty slots use buff_id -1 (see CombatUnit's slot init) but
# always carry cd == 0 too, so checking cd alone already excludes them.
func refresh_buffs(unit: CombatUnit, buffs_by_id: Dictionary) -> void:
	if unit == null:
		_clear_row()
		return
	var active_slots: Array = []
	for slot in unit.buff_slots:
		if int(slot.get("cd", 0)) > 0:
			active_slots.append(slot)
	active_slots.sort_custom(func(a, b): return int(a["cd"]) > int(b["cd"]))
	active_slots = active_slots.slice(0, mini(active_slots.size(), MAX_BUFF_ICONS))
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
		var icon_rect: TextureRect = TextureRect.new()
		icon_rect.texture = icon_texture
		icon_rect.custom_minimum_size = Vector2(16, 16)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var element_index: CombatUnit.Element = buff.element_type
		if element_index != -1:
			icon_rect.modulate = MenuTheme.ELEMENT_COLORS[element_index]
		icon_rect.tooltip_text = "%s (%d turns)\n%s" % [buff.display_name, int(slot["cd"]), buff.tooltip_description]
		var counter: Label = Label.new()
		counter.text = str(int(slot["cd"]))
		counter.add_theme_font_size_override("font_size", 8)
		counter.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_rect.add_child(counter)
		buff_row.add_child(icon_rect)


func _clear_row() -> void:
	if _last_signature.is_empty():
		return
	for child in buff_row.get_children():
		child.queue_free()
	_last_signature = []
