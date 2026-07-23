# inventory_window.gd
# The player inventory screen, rebuilt from frame 1 of the original menu
# clip (DefineSprite 3142 at stage 400.5, 222.4):
# - left panel: name + level/class, the dressed paper doll with the 7 equip
#   slots around it, and the experience bar
# - center panel: the five stats plus the Piercing/Defense element bars
#   (fill math from the frame-1 DoAction, see MenuTheme.bar_fill_fraction)
# - right: the shared InventoryPanel (6x6 grid + money bar + sell/drop)
# - bottom-left bar: party portrait frames (art from sprite 2979 is a
#   backlog item - frames show names for now)
#
# Click an inventory item to equip it into its natural slot; click an equip
# slot to send the item back to the first free inventory cell.
extends Control

const CLASS_NAMES: Array[String] = ["Biological", "Psychological", "Hydraulic"]

const INVENTORY_AT: Vector2 = Vector2(503.5, 81.6)
# playerSlot0-6 centers from the frame-1 dump.
const EQUIP_SLOT_CENTERS: Dictionary[int, Vector2] = {
	0: Vector2(82.2, 172.2),
	2: Vector2(82.2, 212.2),
	6: Vector2(82.2, 252.2),
	5: Vector2(122.2, 252.2),
	1: Vector2(263.1, 172.2),
	3: Vector2(263.1, 212.2),
	4: Vector2(263.1, 252.2),
}
const DOLL_POSITION: Vector2 = Vector2(192.5, 214.4)
const DOLL_SCALE: float = 1.2
const PARTY_BAR: Rect2 = Rect2(47.5, 358.2, 249.1, 50.9)
const BAR_BLOCK_CENTERS_Y: Dictionary[Variant, Variant] = {"per": 256.0, "def": 360.5}
const BAR_TRACK_HEIGHT: float = 78.0
const BAR_WIDTH: float = 10.0
const BAR_STEP: float = 17.1
# Experience row (texts 2869/2863, shapes 2864/2868, fill sprite 2867) - only
# EXP_FILL survives here: refresh() still reads EXP_FILL.size.x as the full
# width the fraction-scaled fill is computed against.
const EXP_FILL: Rect2 = Rect2(172.6, 283.3, 95.1, 18.7)

var inventory_panel: InventoryPanel
var equip_view: EquipDollView

@onready var _status_label: Label = $StatusLabel
@onready var _name_label: Label = $NameLabel
@onready var _level_label: Label = $LevelLabel
@onready var _exp_fill: TextureRect = $ExpFill
@onready var _exp_percent: Label = $ExpPercent
@onready var _stat_values: Array[Label] = [$StatValue0, $StatValue1, $StatValue2, $StatValue3, $StatValue4]
var _per_fills: Array[ColorRect] = []
var _def_fills: Array[ColorRect] = []
var _portrait_frames: Array[ItemSlot] = []


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_left_panel()
	_build_center_panel()
	_build_party_bar()
	_build_inventory()
	GameData.inventory_changed.connect(_refresh_if_visible)
	GameData.gold_changed.connect(func(_amount): _refresh_if_visible())
	visibility_changed.connect(func():
		if visible:
			refresh())


func _build_left_panel() -> void:
	equip_view = EquipDollView.new()
	equip_view.name = "EquipDollView"
	add_child(equip_view)
	equip_view.setup(EQUIP_SLOT_CENTERS, DOLL_POSITION, DOLL_SCALE)
	equip_view.equip_slot_clicked.connect(_on_equip_slot_clicked)


func _build_center_panel() -> void:
	_per_fills = _build_bar_block(BAR_BLOCK_CENTERS_Y["per"])
	_def_fills = _build_bar_block(BAR_BLOCK_CENTERS_Y["def"])


# One block of 8 element bars (called once for "per", once for "def" - see
# _build_center_panel()) - fetches the pre-built track/fill pairs for that
# block instead of constructing them; fill heights/positions are set every
# refresh() by _update_bar(), unchanged below.
func _build_bar_block(center_y: float) -> Array[ColorRect]:
	var prefix: String = "Per" if center_y == BAR_BLOCK_CENTERS_Y["per"] else "Def"
	var fills: Array[ColorRect] = []
	for k in 8:
		fills.append(get_node("%sFill%d" % [prefix, k]))
	return fills


# Portrait face art extracted from the SWF face clip (DefineSprite 2978,
# labeled frame per character). Party ids 1-5; index 0 is the player.
const PORTRAIT_FILES: Dictionary[Variant, Variant] = {
	0: "portraits/sonny.png",
	1: "portraits/veradux.png",
	2: "portraits/roald.png",
	3: "portraits/felicity.png",
	4: "portraits/wolfgang.png",
	5: "portraits/amber.png",
}


func _build_party_bar() -> void:
	MenuTheme.add_texture_rect(self, "panel_bar.png", PARTY_BAR)
	for i in 6:
		var frame: ItemSlot = preload("res://scenes/ui/item_slot.tscn").instantiate()
		frame.position = Vector2(72.2 + 40.0 * i, 384.9) - MenuTheme.SLOT_SIZE / 2.0
		add_child(frame)
		var face: TextureRect = TextureRect.new()
		face.texture = MenuTheme.texture(PORTRAIT_FILES[i])
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.set_anchors_preset(Control.PRESET_FULL_RECT)
		face.offset_left = 2
		face.offset_top = 2
		face.offset_right = -2
		face.offset_bottom = -2
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(face)
		_portrait_frames.append(frame)


func _build_inventory() -> void:
	inventory_panel = preload("res://scenes/ui/inventory.tscn").instantiate()
	inventory_panel.position = INVENTORY_AT
	add_child(inventory_panel)
	inventory_panel.item_selected.connect(_on_inventory_item_selected)
	inventory_panel.sell_pressed.connect(_on_sell_pressed)
	inventory_panel.delete_pressed.connect(_on_delete_pressed)
	inventory_panel.show_sell_button(true)


func refresh() -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	_status_label.text = ""
	_name_label.text = save.name_user
	_level_label.text = "Lvl. %d %s" % [save.level, CLASS_NAMES[save.player_class]]
	var stats: Array[Variant] = [save.life, save.strength, save.magic, save.speed, save.focus]
	for i in _stat_values.size():
		_stat_values[i].text = str(int(stats[i]))
	for k in 8:
		var element = CombatUnit.ELEMENT_ORDER[k]
		_update_bar(_per_fills[k], float(save.per.get(element, 0.0)), save.level, element, "piercing")
		_update_bar(_def_fills[k], float(save.def.get(element, 0.0)), save.level, element, "defense")
	var exp_fraction = clamp(save.experience / 100.0, 0.0, 1.0)
	_exp_fill.size.x = EXP_FILL.size.x * exp_fraction
	_exp_percent.text = "%d%%" % int(save.experience)
	equip_view.refresh(save, ItemManagerAuto.items_by_id)
	inventory_panel.populate_from_save(save, ItemManagerAuto.items_by_id)
	inventory_panel.set_gold(save.euro)
	_refresh_portraits(save)


# Fill grows upward from the track bottom, like the original bars.
func _update_bar(fill: ColorRect, allocation: float, level: int, element: String, kind: String) -> void:
	var value: int = MenuTheme.element_display_value(allocation, level)
	var fraction: float = MenuTheme.bar_fill_fraction(float(value), level)
	var bottom = BAR_BLOCK_CENTERS_Y["per" if kind == "piercing" else "def"] + BAR_TRACK_HEIGHT / 2.0
	fill.size.y = BAR_TRACK_HEIGHT * fraction
	fill.position.y = bottom - fill.size.y
	fill.tooltip_text = "%s %s: %d" % [element, kind, value]


func _refresh_portraits(save: PlayerSave) -> void:
	for i in _portrait_frames.size():
		var frame: ItemSlot = _portrait_frames[i]
		if i == 0:
			frame.tooltip_text = save.name_user
			frame.modulate = Color(0.7, 1.1, 0.7)
		else:
			var companion: Dictionary = Party.COMPANIONS.get(i, {})
			frame.tooltip_text = str(companion.get("name", ""))
			var unlocked: bool = Party.is_in_roster(save, i)
			frame.modulate = Color(1, 1, 1) if unlocked else Color(0.45, 0.45, 0.45)


func _refresh_if_visible() -> void:
	if visible:
		refresh()


func _on_inventory_item_selected(slot: ItemSlot) -> void:
	if not slot.has_meta("save_index"):
		return
	var result: int = GameData.equip_from_inventory(int(slot.get_meta("save_index")))
	if result != Equipment.EquipResult.OK:
		_status_label.text = Equipment.EQUIP_RESULT_MESSAGES.get(result, "")
	# success refreshes via GameData.inventory_changed


func _on_equip_slot_clicked(equip_index: int) -> void:
	if not GameData.unequip_to_inventory(equip_index):
		_status_label.text = "Inventory is full." if GameData.current_save != null else ""


func _on_sell_pressed(slot: ItemSlot) -> void:
	GameData.sell_item(slot.item)


func _on_delete_pressed(slot: ItemSlot) -> void:
	var save: PlayerSave = GameData.current_save
	if save == null or not slot.has_meta("save_index"):
		return
	save.item_array[int(slot.get_meta("save_index"))] = 0
	GameData.inventory_changed.emit()
