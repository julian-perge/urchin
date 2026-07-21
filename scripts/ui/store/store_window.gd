# store_window.gd
# Store screen, rebuilt from frame 16 of the original menu clip
# (DefineSprite 3142 at stage 400.5, 222.4):
# - left: the zone's shop backdrop (sprite 3036 frame, via StoreManager)
#   over the large panel, shopkeeper dialogue beneath it
# - middle: the dressed player doll with the 7 equip slots (top panel) and
#   the 15-item shop catalog on a 5x3 grid (bottom panel)
# - right: the shared InventoryPanel (6x6 grid + money bar + sell/drop)
#
# Click a catalog item to buy it; click an inventory item to equip it;
# click an equip slot to unequip. Sell pays 15% of list price (button 3015).
extends Control

signal store_closed

const ItemSlotScene: PackedScene = preload("res://scenes/ui/item_slot.tscn")

const INVENTORY_AT: Vector2 = Vector2(503.5, 81.6)
# 15 catalog slots, 5 columns (3 rows) - keep in sync with StoreItems'
# `columns` property in store_window.tscn.
const CATALOG_SLOTS: int = 15
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

@onready var shop_backdrop: TextureRect = $ShopBackdrop
@onready var shop_dialogue: Label = $DescriptionLabel
@onready var store_items: GridContainer = $StoreItems
@onready var _status_label: Label = $StatusLabel

var inventory_panel: InventoryPanel
var equip_view: EquipDollView

var selected_store_slot: ItemSlot = null


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_middle()
	_build_inventory()
	GameData.gold_changed.connect(func(_amount):
		if visible:
			inventory_panel.set_gold(GameData.get_player_gold()))
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
	for i in CATALOG_SLOTS:
		var slot: ItemSlot = ItemSlotScene.instantiate()
		slot.show_price = true
		slot.slot_clicked.connect(_on_store_slot_clicked)
		store_items.add_child(slot)


func _build_inventory() -> void:
	inventory_panel = preload("res://scenes/ui/inventory.tscn").instantiate()
	inventory_panel.position = INVENTORY_AT
	add_child(inventory_panel)
	inventory_panel.show_sell_button(true)
	inventory_panel.item_selected.connect(_on_inventory_item_selected)
	inventory_panel.sell_pressed.connect(_on_sell_pressed)
	inventory_panel.delete_pressed.connect(_on_delete_pressed)


func open_store():
	show()
	refresh_store()


func refresh_store():
	_status_label.text = ""
	var backdrop: Texture2D = StoreManager.get_current_shop_backdrop()
	if backdrop != null:
		shop_backdrop.texture = backdrop
	var dialogue: String = StoreManager.get_current_shop_dialogue()
	shop_dialogue.text = dialogue if dialogue != "" else "..."
	inventory_panel.set_gold(GameData.get_player_gold())
	_load_store_items()
	var save: PlayerSave = GameData.current_save
	if save != null:
		inventory_panel.populate_from_save(save, ItemManagerAuto.items_by_id)
		equip_view.refresh(save, ItemManagerAuto.items_by_id)


func _load_store_items():
	var catalog: Array[GameItem] = GameData.get_store_inventory()
	var index: int = 0
	for child in store_items.get_children():
		if child is ItemSlot:
			child.set_item(catalog[index] if index < catalog.size() else null)
			index += 1


func _on_store_slot_clicked(slot: ItemSlot) -> void:
	_status_label.text = ""
	if slot.item == null:
		return
	if selected_store_slot != null:
		selected_store_slot.set_selected(false)
	selected_store_slot = slot
	slot.set_selected(true)
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


func _on_sell_pressed(slot: ItemSlot) -> void:
	if GameData.sell_item(slot.item):
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
