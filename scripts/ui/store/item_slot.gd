# item_slot.gd
# One inventory/store grid cell. Holds a GameItem (or nothing), shows its
# icon (slot_image preferred, sprite_image fallback), and reports clicks.
extends Control
class_name ItemSlot

signal slot_clicked(slot: ItemSlot)

const HIGHLIGHT_TEXTURE = preload("res://assets/ui/menu/slot_highlight.png")

@onready var item_icon: TextureRect = $ItemIcon

var item: GameItem = null
var selected: bool = false
# Price line in the tooltip - only store catalog slots show it (equipped/
# inventory items don't price-tag themselves in the original).
var show_price: bool = false

var _highlight: TextureRect


func _ready():
	gui_input.connect(_on_gui_input)
	# The original slot buttons' hover state (shape 2857, a white frame).
	_highlight = TextureRect.new()
	_highlight.texture = HIGHLIGHT_TEXTURE
	_highlight.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_highlight.stretch_mode = TextureRect.STRETCH_SCALE
	_highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight.visible = false
	add_child(_highlight)
	mouse_entered.connect(func(): _highlight.visible = true)
	mouse_exited.connect(func(): _highlight.visible = false)
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
		tooltip_text = ""
		return
	if item.slot_image != null:
		item_icon.texture = item.slot_image
	elif item.sprite_image != null:
		item_icon.texture = item.sprite_image
	else:
		item_icon.texture = null
	# Name, price (catalog only), stat bonus lines, flavor text.
	var lines = [item.display_name]
	if show_price and item.price > 0:
		lines.append("Cost: %d Euros" % int(item.price))
	for stat_line in item.tooltipAlt:
		lines.append(str(stat_line))
	if item.tooltip is String and str(item.tooltip) != "":
		lines.append(str(item.tooltip))
	tooltip_text = "\n".join(lines)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slot_clicked.emit(self)
