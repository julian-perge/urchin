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

const ItemSlotScene = preload("res://scenes/ui/item_slot.tscn")

# Panel alignment per the live game: every column tops out at 81.6 and
# bottoms out at 409.1 (the inventory column's extent) - left panel full
# height, middle split into doll (top) and catalog (bottom-aligned with the
# money bar).
const LEFT_PANEL = Rect2(22.9, 81.6, 249.1, 327.5)
const SHOP_BACKDROP_RECT = Rect2(34.0, 92.0, 227.0, 150.0)
const DIALOGUE_RECT = Rect2(36.0, 252.0, 223.0, 150.0)
const MIDDLE_TOP_PANEL = Rect2(285.6, 81.6, 186.6, 133.4)
const MIDDLE_BOTTOM_PANEL = Rect2(285.6, 225.0, 186.6, 184.1)
const PURCHASE_HINT_RECT = Rect2(290.2, 237.6, 177.0, 30.0)
const INVENTORY_AT = Vector2(503.5, 81.6)
# dropSlot0-14 top-left corners (centers 305.1/291.9 on the 38 px pitch).
const CATALOG_ORIGIN = Vector2(289.6, 276.4)
const CATALOG_COLUMNS = 5
const CATALOG_SLOTS = 15
# playerSlot0-6 centers from the frame-16 dump.
const EQUIP_SLOT_CENTERS = {
	0: Vector2(301.1, 117.6),
	2: Vector2(301.1, 152.0),
	6: Vector2(301.1, 186.4),
	5: Vector2(335.5, 186.4),
	1: Vector2(456.7, 117.6),
	3: Vector2(456.7, 152.0),
	4: Vector2(456.7, 186.4),
}
const DOLL_POSITION = Vector2(396.5, 162.4)
const DOLL_SCALE = 0.85

var store_items: Control
var inventory_panel: InventoryPanel
var shop_backdrop: TextureRect
var shop_dialogue: Label
var equip_view: EquipDollView

var selected_store_slot: ItemSlot = null
var _status_label: Label


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_chrome()
	_build_left_panel()
	_build_middle()
	_build_inventory()
	GameData.gold_changed.connect(func(_amount):
		if visible:
			inventory_panel.set_gold(GameData.get_player_gold()))
	GameData.inventory_changed.connect(func():
		if visible:
			refresh_store())
	refresh_store()


func _build_chrome() -> void:
	var backdrop = MenuTheme.add_texture_rect(self, "menu_backdrop.png", MenuTheme.BACKDROP_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	var close = TextureButton.new()
	close.name = "CloseButton"
	close.texture_normal = MenuTheme.texture("close_x.png")
	close.ignore_texture_size = true
	close.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close.position = MenuTheme.CLOSE_RECT.position
	close.size = MenuTheme.CLOSE_RECT.size
	close.pressed.connect(_on_exit_pressed)
	add_child(close)
	_status_label = MenuTheme.add_label(
		self, "", Rect2(47.5, 414, 700, 20), 12, Color(1, 0.85, 0.3)
	)


func _build_left_panel() -> void:
	MenuTheme.add_texture_rect(self, "panel_large.png", LEFT_PANEL)
	shop_backdrop = TextureRect.new()
	shop_backdrop.name = "ShopBackdrop"
	shop_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Natural crop, no squish - the backdrop bitmaps are wider than the
	# viewport (the source masks them the same way).
	shop_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	shop_backdrop.clip_contents = true
	shop_backdrop.position = SHOP_BACKDROP_RECT.position
	shop_backdrop.size = SHOP_BACKDROP_RECT.size
	shop_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shop_backdrop)
	shop_dialogue = MenuTheme.add_label(
		self, "...", Rect2(DIALOGUE_RECT.position, DIALOGUE_RECT.size), 11,
		Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, true
	)
	shop_dialogue.name = "DescriptionLabel"


func _build_middle() -> void:
	MenuTheme.add_texture_rect(self, "panel_center.png", MIDDLE_TOP_PANEL)
	equip_view = EquipDollView.new()
	equip_view.name = "EquipDollView"
	add_child(equip_view)
	equip_view.setup(EQUIP_SLOT_CENTERS, DOLL_POSITION, DOLL_SCALE, true)
	equip_view.equip_slot_clicked.connect(_on_equip_slot_clicked)
	MenuTheme.add_texture_rect(self, "panel_center.png", MIDDLE_BOTTOM_PANEL)
	MenuTheme.add_label(
		self, "Click on the items to purchase them.",
		Rect2(PURCHASE_HINT_RECT.position, PURCHASE_HINT_RECT.size), 10,
		Color(0.6, 0.6, 0.6), HORIZONTAL_ALIGNMENT_CENTER, true
	)
	store_items = Control.new()
	store_items.name = "StoreItems"
	store_items.position = CATALOG_ORIGIN
	store_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(store_items)
	for i in CATALOG_SLOTS:
		var slot: ItemSlot = ItemSlotScene.instantiate()
		slot.show_price = true
		slot.position = Vector2(
			(i % CATALOG_COLUMNS) * MenuTheme.SLOT_STEP,
			floorf(i / float(CATALOG_COLUMNS)) * MenuTheme.SLOT_STEP
		)
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
	var backdrop = StoreManager.get_current_shop_backdrop()
	if backdrop != null:
		shop_backdrop.texture = backdrop
	var dialogue = StoreManager.get_current_shop_dialogue()
	shop_dialogue.text = dialogue if dialogue != "" else "..."
	inventory_panel.set_gold(GameData.get_player_gold())
	_load_store_items()
	var save = GameData.current_save
	if save != null:
		inventory_panel.populate_from_save(save, ItemManagerAuto.items_by_id)
		equip_view.refresh(save, ItemManagerAuto.items_by_id)


func _load_store_items():
	var catalog: Array[GameItem] = GameData.get_store_inventory()
	var index = 0
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
	var result = GameData.equip_from_inventory(int(slot.get_meta("save_index")))
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
	var save = GameData.current_save
	if save == null or not slot.has_meta("save_index"):
		return
	save.item_array[int(slot.get_meta("save_index"))] = 0
	GameData.inventory_changed.emit()


func _on_exit_pressed() -> void:
	StoreManager.close_store()
	store_closed.emit()
