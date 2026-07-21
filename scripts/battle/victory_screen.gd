# victory_screen.gd
# The post-battle victory overlay (references/2026_07_18_flashpoint/16-18):
# - left panel "Character Experience": portrait + level + XP bar per fighter
# - middle: "Victory! Items that dropped:" with the drop slots - CLICK a
#   drop to keep it (moves into the first free inventory cell), gold
#   call-out text, money/exp gained, and the green Proceed! button
# - right: the shared InventoryPanel
# Reuses the menu chrome (MenuTheme) - the original showed this inside the
# same red menu shell.
extends Control
class_name VictoryScreen

signal proceed_pressed

const ItemSlotScene: PackedScene = preload("res://scenes/ui/item_slot.tscn")

const LEFT_PANEL: Rect2 = Rect2(47.5, 86.6, 249.1, 267.1)
const MIDDLE_PANEL: Rect2 = Rect2(309.0, 82.2, 183.1, 326.5)
const INVENTORY_AT: Vector2 = Vector2(503.5, 81.6)
const DROP_ORIGIN: Vector2 = Vector2(321.0, 130.0)
const DROP_COLUMNS: int = 4

const PORTRAITS: Dictionary[int, String] = {
	0: "portraits/sonny.png",
	1: "portraits/veradux.png",
	2: "portraits/roald.png",
	3: "portraits/felicity.png",
	4: "portraits/wolfgang.png",
	5: "portraits/amber.png",
}

var inventory_panel: InventoryPanel

var _drop_slots: Array[ItemSlot] = []
var _money_value: Label
var _exp_value: Label


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop: TextureRect = MenuTheme.add_texture_rect(self, "menu_backdrop.png", MenuTheme.BACKDROP_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	MenuTheme.add_texture_rect(self, "panel_large.png", LEFT_PANEL)
	MenuTheme.add_label(
		self, "Character Experience", Rect2(LEFT_PANEL.position.x, 92, LEFT_PANEL.size.x, 20),
		14, Color(0.55, 0.55, 0.55), HORIZONTAL_ALIGNMENT_CENTER
	)
	MenuTheme.add_texture_rect(self, "panel_center.png", MIDDLE_PANEL)
	MenuTheme.add_label(
		self, "Victory! Items that dropped:", Rect2(316, 92, 170, 30), 12,
		Color(0.75, 0.75, 0.75), HORIZONTAL_ALIGNMENT_LEFT, true
	)
	MenuTheme.add_label(
		self, "CLICK on the items that you wish to keep!", Rect2(318, 230, 166, 40),
		12, Color(0.95, 0.75, 0.2), HORIZONTAL_ALIGNMENT_CENTER, true
	)
	MenuTheme.add_label(self, "Money gained:", Rect2(318, 276, 100, 16), 12, Color(0.95, 0.75, 0.2))
	_money_value = MenuTheme.add_label(
		self, "", Rect2(390, 276, 94, 16), 12, Color(0.95, 0.75, 0.2), HORIZONTAL_ALIGNMENT_RIGHT
	)
	MenuTheme.add_label(self, "Exp. gained:", Rect2(318, 294, 100, 16), 12, Color.WHITE)
	_exp_value = MenuTheme.add_label(
		self, "", Rect2(390, 294, 94, 16), 12, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT
	)
	MenuTheme.add_label(
		self, "Once you are finished, press below to proceed:",
		Rect2(318, 318, 166, 40), 11, Color(0.6, 0.6, 0.6), HORIZONTAL_ALIGNMENT_CENTER, true
	)
	var proceed: Button = Button.new()
	proceed.text = "Proceed!"
	proceed.position = Vector2(342, 362)
	proceed.size = Vector2(118, 30)
	proceed.add_theme_font_size_override("font_size", 17)
	proceed.add_theme_color_override("font_color", Color(0.35, 0.95, 0.25))
	proceed.add_theme_color_override("font_hover_color", Color(0.6, 1.0, 0.5))
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.06)
	style.set_corner_radius_all(4)
	proceed.add_theme_stylebox_override("normal", style)
	var hover_style: Resource = style.duplicate()
	hover_style.bg_color = Color(0.1, 0.12, 0.1)
	proceed.add_theme_stylebox_override("hover", hover_style)
	proceed.pressed.connect(func(): proceed_pressed.emit())
	add_child(proceed)

	inventory_panel = preload("res://scenes/ui/inventory.tscn").instantiate()
	inventory_panel.position = INVENTORY_AT
	add_child(inventory_panel)
	inventory_panel.show_sell_button(false)


# rewards = BattleRewards.apply_victory result; drops = rolled item ids;
# party_ids = deployed companion party ids that fought.
func setup(save: PlayerSave, rewards: Dictionary, drops: Array, party_ids: Array) -> void:
	_money_value.text = "€%d" % int(rewards.get("money_gained", 0))
	_exp_value.text = "%d%%" % int(rewards.get("xp_gained", 0))
	_build_experience_rows(save, party_ids)
	_build_drop_slots(save, drops)
	inventory_panel.populate_from_save(save, ItemManagerAuto.items_by_id)
	inventory_panel.set_gold(save.euro)


func _build_experience_rows(save: PlayerSave, party_ids: Array) -> void:
	var fighters: Array[int] = [0]
	for party_id in party_ids:
		fighters.append(int(party_id))
	var y: float = 120.0
	for party_id in fighters:
		var face: TextureRect = TextureRect.new()
		face.texture = MenuTheme.texture(PORTRAITS.get(party_id, PORTRAITS[0]))
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.position = Vector2(58, y)
		face.size = Vector2(34, 44)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(face)
		var display_name: String
		var level: int
		var experience: float
		if party_id == 0:
			display_name = save.name_user
			level = save.level
			experience = save.experience
		else:
			display_name = str(Party.COMPANIONS.get(party_id, {}).get("name", "?"))
			level = int(save.party_levels[party_id]) if party_id < save.party_levels.size() else 1
			experience = float(save.party_exp[party_id]) if party_id < save.party_exp.size() else 0.0
		MenuTheme.add_label(self, display_name, Rect2(100, y, 150, 16), 13)
		MenuTheme.add_label(self, "Lvl. %d" % level, Rect2(100, y + 16, 150, 14), 11, Color(0.8, 0.8, 0.8))
		MenuTheme.add_texture_rect(self, "exp_track.png", Rect2(100, y + 32, 150, 12))
		var fraction = clamp(experience / 100.0, 0.0, 1.0)
		MenuTheme.add_texture_rect(self, "exp_fill.png", Rect2(100, y + 32, 150 * fraction, 12))
		var percent: Label = MenuTheme.add_label(
			self, "%d%%" % int(experience), Rect2(104, y + 31, 60, 13), 9
		)
		percent.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
		y += 62.0


func _build_drop_slots(save: PlayerSave, drops: Array) -> void:
	for i in drops.size():
		var slot: ItemSlot = ItemSlotScene.instantiate()
		slot.position = DROP_ORIGIN + Vector2(
			(i % DROP_COLUMNS) * MenuTheme.SLOT_STEP,
			floorf(i / float(DROP_COLUMNS)) * MenuTheme.SLOT_STEP
		)
		add_child(slot)
		slot.set_item(ItemManagerAuto.get_item(int(drops[i])))
		slot.slot_clicked.connect(_on_drop_clicked.bind(save))
		_drop_slots.append(slot)


func _on_drop_clicked(slot: ItemSlot, save: PlayerSave) -> void:
	if slot.item == null:
		return
	var empty: int = save.item_array.find(0)
	if empty == -1:
		return  # inventory full - the drop stays claimable
	save.item_array[empty] = slot.item.id
	slot.set_item(null)
	inventory_panel.populate_from_save(save, ItemManagerAuto.items_by_id)
