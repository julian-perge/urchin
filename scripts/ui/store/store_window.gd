# store_window.gd
# Store screen, rebuilt from frame 16 of the original menu clip
# (DefineSprite 3142 at stage 400.5, 222.4) on WindowShell, three ShellPanels
# and FloatBox containers (spec/107-store.md). test_screen_rects.gd checks each
# piece against the SWF.
# - left: the zone's shop keeper art (sprite 3036, via StoreManager) and the
#   keeper's line, SHOP[shopId] from strings.json
# - middle: the dressed player doll with the 7 equip slots (top panel, typed
#   here until #235 draws them from the SWF) and the hint and the 15 ware
#   slots on a 5x3 grid (bottom panel)
# - right: the shared RightColumn, with its sell slot shown
#
# Click a catalog item to buy it; click an inventory item to equip it;
# click an equip slot to unequip. Sell pays 15% of list price (button 3015).
extends Control

signal store_closed

const ItemSlotScene: PackedScene = preload("res://scenes/ui/item_slot.tscn")

# playerSlot0-6 centers from the frame-16 dump.
const EQUIP_SLOT_CENTERS: Dictionary[int, Vector2] = {
	0: Vector2(301.1, 117.6),
	2: Vector2(301.1, 152.0),
	6: Vector2(301.1, 186.4),
	5: Vector2(335.5, 186.4),
	1: Vector2(456.7, 117.6),
	3: Vector2(456.7, 152.0),
	4: Vector2(456.7, 186.4),
}
const DOLL_POSITION: Vector2 = Vector2(396.5, 162.4)
const DOLL_SCALE: float = 0.85
# The wares are 3 rows of 5, as the original's dropSlot0 to dropSlot14.
const WARES_PER_ROW: int = 5

@onready var keeper_art: TextureRect = $LeftPanel/Content/KeeperArt
@onready var keeper_line: Label = $LeftPanel/Content/KeeperLine
@onready var hint_label: Label = $CentreBottomPanel/Content/Hint
@onready var _status_label: Label = $CentreBottomPanel/Content/StatusLabel
@onready var right_column: RightColumn = $RightColumn

var equip_view: EquipDollView
# The 15 ware slots in grid order, row by row.
var ware_slots: Array[ItemSlot] = []


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_label.text = Strings.menu(6)
	_build_middle()
	right_column.show_sell_button(true)
	GameData.gold_changed.connect(func(_amount):
		if visible:
			right_column.set_gold(GameData.get_player_gold()))
	GameData.inventory_changed.connect(func():
		if visible:
			refresh_store())
	refresh_store()


func _build_middle() -> void:
	equip_view = EquipDollView.new()
	equip_view.name = "EquipDollView"
	add_child(equip_view)
	equip_view.setup(EQUIP_SLOT_CENTERS, DOLL_POSITION, DOLL_SCALE, true)
	equip_view.equip_slot_clicked.connect(_on_equip_slot_clicked)
	for row: Node in $CentreBottomPanel/Content/Wares.get_children():
		for column in WARES_PER_ROW:
			var slot: ItemSlot = ItemSlotScene.instantiate()
			slot.name = "Slot%d" % column
			slot.show_price = true
			slot.slot_clicked.connect(_on_store_slot_clicked)
			row.add_child(slot)
			ware_slots.append(slot)


func open_store():
	show()
	refresh_store()


func refresh_store():
	_status_label.text = ""
	var backdrop: Texture2D = StoreManager.get_current_shop_backdrop()
	if backdrop != null:
		keeper_art.texture = backdrop
	keeper_line.text = StoreManager.get_current_shop_dialogue()
	right_column.set_gold(GameData.get_player_gold())
	_load_store_items()
	var save: PlayerSave = GameData.current_save
	if save != null:
		right_column.populate_from_save(save, ItemManagerAuto.items_by_id)
		equip_view.refresh(save, ItemManagerAuto.items_by_id)


# A ware slot with no ware is hidden, as the original does with _visible = false
# (DefineSprite_3142/frame_16/DoAction.as). It keeps its place: `visible = false`
# would make FloatBox pull the slots after it forward.
func _load_store_items() -> void:
	var catalog: Array[GameItem] = GameData.get_store_inventory()
	for i in ware_slots.size():
		var slot: ItemSlot = ware_slots[i]
		var stocked: bool = i < catalog.size()
		slot.set_item(catalog[i] if stocked else null)
		slot.modulate.a = 1.0 if stocked else 0.0
		slot.mouse_filter = Control.MOUSE_FILTER_STOP if stocked else Control.MOUSE_FILTER_IGNORE


func _on_store_slot_clicked(slot: ItemSlot) -> void:
	_status_label.text = ""
	if slot.item == null:
		return
	if GameData.purchase_item(slot.item):
		refresh_store()
	else:
		_status_label.text = "You cannot afford that item." if not GameData.can_afford_item(slot.item) else "Your inventory is full."


func _on_inventory_item_selected(slot: ItemSlot) -> void:
	_status_label.text = ""
	if not slot.has_meta("save_index"):
		return
	var result: int = GameData.equip_from_inventory(int(slot.get_meta("save_index")))
	if result != Equipment.EquipResult.OK:
		_status_label.text = Equipment.EQUIP_RESULT_MESSAGES.get(result, "")


func _on_equip_slot_clicked(equip_index: int) -> void:
	_status_label.text = ""
	if not GameData.unequip_to_inventory(equip_index):
		_status_label.text = "Inventory is full." if GameData.current_save != null else ""


func _on_sell_pressed(item: GameItem) -> void:
	if GameData.sell_item(item):
		refresh_store()


func _on_delete_pressed(slot: ItemSlot) -> void:
	var save: PlayerSave = GameData.current_save
	if save == null or not slot.has_meta("save_index"):
		return
	save.item_array[int(slot.get_meta("save_index"))] = 0
	GameData.inventory_changed.emit()


func _on_exit_pressed() -> void:
	StoreManager.close_store()
	store_closed.emit()
