# The Inventory shell and left panel follow spec/107-inventory.md.
# test_screen_rects.gd checks their placement against the SWF.
extends Control


var equip_view: EquipDollView
# The width of the experience fill in the scene, which is the full bar. The
# original scales the fill clip to experience / 100 of it.
var _exp_full_width: float = 0.0

@onready var right_column: RightColumn = $RightColumn
@onready var _status_label: Label = $LeftPanel/Content/StatusLabel
@onready var _name_label: Label = $LeftPanel/Content/Header/NameRow/NameLabel
@onready var _level_label: Label = $LeftPanel/Content/Header/InfoRow/LevelLabel
@onready var _exp_fill: TextureRect = $ExpFill
@onready var _exp_percent: Label = $ExpPercent
@onready var _stat_names: Array[Label] = _row_labels($CenterPanel/Content/StatNames)
@onready var _stat_values: Array[Label] = _row_labels($CenterPanel/Content/StatValues)
var _per_bars: Array[ElementBar] = []
var _def_bars: Array[ElementBar] = []
var _party_faces: Array[PartyFace] = []


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	$ExperienceLabel.text = Strings.menu(17)
	for i in _stat_names.size():
		_stat_names[i].text = Strings.system(i) + ":"
	_exp_full_width = _exp_fill.size.x
	_build_left_panel()
	_build_element_bars()
	_build_party_bar()
	GameData.inventory_changed.connect(_refresh_if_visible)
	GameData.gold_changed.connect(func(_amount): _refresh_if_visible())
	visibility_changed.connect(func():
		if visible:
			refresh())


# Each stat is a fixed-height Row slot that holds one Label.
func _row_labels(column: Node) -> Array[Label]:
	var labels: Array[Label] = []
	for row: Node in column.get_children():
		labels.append(row.get_node("Label") as Label)
	return labels


func _build_left_panel() -> void:
	equip_view = $LeftPanel/Content/EquipDollView
	equip_view.setup({})
	equip_view.equip_slot_clicked.connect(_on_equip_slot_clicked)


# The element bars are in the scene, eight for piercing and eight for defense.
# setup() gives each its element and its tooltip, and refresh() gives it the
# value.
func _build_element_bars() -> void:
	for k in 8:
		var piercing: ElementBar = get_node("PerBars/Bars/Bar%d" % k)
		piercing.setup(k, ElementBar.Kind.PIERCING)
		_per_bars.append(piercing)
		var defense: ElementBar = get_node("DefBars/Bars/Bar%d" % k)
		defense.setup(k, ElementBar.Kind.DEFENSE)
		_def_bars.append(defense)


func _build_party_bar() -> void:
	for face: Node in $PartyFaces.get_children():
		_party_faces.append(face as PartyFace)


func refresh() -> void:
	var save: PlayerSave = GameData.current_save
	if save == null:
		return
	_status_label.text = ""
	_name_label.text = Party.PLAYER_NAME
	_level_label.text = "%s%d %s" % [Strings.menu(0), save.level, Strings.text("CLASS", save.player_class)]
	var stats: Array[Variant] = [save.life, save.strength, save.magic, save.speed, save.focus]
	for i in _stat_values.size():
		_stat_values[i].text = str(int(stats[i]))
	for k in 8:
		_per_bars[k].show_value(float(save.per.get(k, 0.0)), save.level)
		_def_bars[k].show_value(float(save.def.get(k, 0.0)), save.level)
	var exp_fraction: float = clampf(save.experience / 100.0, 0.0, 1.0)
	_exp_fill.size.x = _exp_full_width * exp_fraction
	# The original rounds the percent with Math.round, in the enterFrame script of
	# PlaceObject2_2867_1419.
	_exp_percent.text = "%d%%" % roundi(save.experience)
	equip_view.refresh(save, ItemManagerAuto.items_by_id)
	right_column.populate_from_save(save, ItemManagerAuto.items_by_id)
	right_column.set_gold(save.euro)
	_refresh_portraits(save)


# Each face shows the member of its roster slot, as the original does
# (DefineSprite_3142/frame_1/DoAction.as:195-206). The player is the selected
# member until #11 lets a click move the selection. A member is deployed when
# party_deployed holds the id.
func _refresh_portraits(save: PlayerSave) -> void:
	for slot in _party_faces.size():
		var id: int = int(save.party_roster[slot]) if slot < save.party_roster.size() else -1
		_party_faces[slot].show_member(id, id == Party.PLAYER_PARTY_ID, save.party_deployed.has(id))


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


func _on_delete_pressed(slot: ItemSlot) -> void:
	var save: PlayerSave = GameData.current_save
	if save == null or not slot.has_meta("save_index"):
		return
	save.item_array[int(slot.get_meta("save_index"))] = 0
	GameData.inventory_changed.emit()
