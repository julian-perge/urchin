# item_slot.gd
# One inventory/store grid cell. Holds a GameItem (or nothing), shows its
# icon (slot_image preferred, sprite_image fallback), and reports clicks.
extends Control
class_name ItemSlot

signal slot_clicked(slot: ItemSlot)

@onready var item_icon: TextureRect = $ItemIcon
# The original slot buttons' hover state (shape 2857, a white frame) - now a
# real scene child instead of built at runtime.
@onready var _highlight: TextureRect = $Highlight

var item: GameItem = null
var selected: bool = false
# Price line in the tooltip - only store catalog slots show it (equipped/
# inventory items don't price-tag themselves in the original).
var show_price: bool = false


func _ready():
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(func():
		_highlight.visible = true
		if item != null:
			GameTooltip.show_sections(_tooltip_sections(), self))
	mouse_exited.connect(func():
		_highlight.visible = false
		GameTooltip.hide_tooltip())
	_refresh()


func set_item(new_item: GameItem) -> void:
	item = new_item
	selected = false
	_refresh()


func set_selected(value: bool) -> void:
	selected = value
	modulate = Color(1.3, 1.3, 0.9) if selected else Color.WHITE


func _refresh() -> void:
	if item_icon == null:
		return
	if item == null:
		item_icon.texture = null
		return
	if item.slot_image != null:
		item_icon.texture = item.slot_image
	elif item.sprite_image != null:
		item_icon.texture = item.sprite_image
	else:
		item_icon.texture = null


# Built fresh on hover rather than kept in sync on every _refresh() - the
# tooltip only needs to exist while the mouse is actually over this slot.
func _tooltip_sections() -> Array:
	var sections: Array = [
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": item.display_name, "color": TooltipTheme.TEXT_TITLE}]},
	]
	if item.item_type != GameItem.ItemType.NONE:
		sections.append({
			"bg_color": TooltipTheme.BG_HEADER,
			"lines": [{
				"text": "Lvl. %d %s" % [item.required_level, item.slot_type_display_name()],
				"color": TooltipTheme.TEXT_SUBHEADER,
			}],
		})
	var body_lines: Array = []
	if show_price and item.price > 0:
		body_lines.append({"text": "Cost: %d Euros" % int(item.price), "color": TooltipTheme.TEXT_STAT})
	for stat_line in item.tooltipAlt:
		body_lines.append({"text": str(stat_line), "color": TooltipTheme.TEXT_STAT})
	if item.tooltip is String and str(item.tooltip) != "":
		body_lines.append({"text": str(item.tooltip), "color": TooltipTheme.TEXT_FLAVOR})
	if not body_lines.is_empty():
		sections.append({"bg_color": TooltipTheme.BG_BODY, "lines": body_lines})
	return sections


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slot_clicked.emit(self)


# Drag source (Godot's built-in Control drag API - see
# .claude/plan_item_drag_and_drop.md). "drag_source"/"drag_index" are set
# by whichever host owns this slot (inventory_panel.gd: "inventory" +
# save_index; equip_doll_view.gd: "equip" + equip_index) - ItemSlot itself
# has no opinion on which kind of slot it is. A dragged-from empty slot
# (item == null) starts no drag at all, same as Godot's default when this
# isn't overridden.
func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null:
		return null
	set_drag_preview(_build_drag_preview())
	return _drag_payload()


# Split out from _get_drag_data() so it's callable in a test without hitting
# set_drag_preview()'s "must be called during an active drag" engine
# precondition - Godot itself only ever invokes _get_drag_data() when a real
# drag is already in progress, but a direct test call isn't a real drag.
func _drag_payload() -> Dictionary:
	return {
		"item": item,
		"source": str(get_meta("drag_source", "inventory")),
		"index": int(get_meta("drag_index", -1)),
	}


func _build_drag_preview() -> Control:
	var preview := TextureRect.new()
	preview.texture = item_icon.texture
	preview.custom_minimum_size = MenuTheme.SLOT_SIZE
	preview.size = MenuTheme.SLOT_SIZE
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1, 1, 1, 0.75)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return preview


# Drop target: inventory<->inventory swaps, inventory<->equip
# equips/unequips. An inventory slot accepts a drop from either kind of
# source; an equip slot only accepts one from inventory (equip<->equip
# makes no sense - a two-slot swap of different item kinds would just fail
# both ways).
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not data.has("item"):
		return false
	var source: String = str(data.get("source", ""))
	var my_source: String = str(get_meta("drag_source", "inventory"))
	if my_source == "inventory":
		return source in ["inventory", "equip"]
	if my_source == "equip":
		return source == "inventory"
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var source: String = str(data.get("source", ""))
	var src_index: int = int(data.get("index", -1))
	var my_source: String = str(get_meta("drag_source", "inventory"))
	var my_index: int = int(get_meta("drag_index", -1))
	if my_source == "inventory" and source == "inventory":
		GameData.swap_inventory_slots(src_index, my_index)
	elif my_source == "inventory" and source == "equip":
		GameData.unequip_to_slot(src_index, my_index)
	elif my_source == "equip" and source == "inventory":
		GameData.equip_from_inventory(src_index, my_index)
