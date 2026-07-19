# hotbar.gd
# The bottom hotbar (scenes/ui/hotbar.tscn), matching the original layout:
# left panel = menu buttons, middle = world-map toggle, right = zone name +
# story progress bar + stage counter. Zone info follows
# ZoneManager.zone_changed; progress reads the live save's quest progress
# (ZoneProgression) and refreshes after battles via GameData.save_loaded and
# ZoneManager.zone_unlocked.
#
# Menu buttons open the full-screen overlays (group "menu_screen"); while a
# screen is open, its button's white icon glows green like the original.
extends Control

# button unique name -> the menu-screen group it opens.
const MENU_BUTTON_GROUPS = {
	"InventoryButton": "inventory_window",
	"AbilitiesButton": "abilities_window",
	"AchievementsButton": "achievements_window",
}
const GLOW_COLOR = Color(0.45, 1.0, 0.35, 0.9)
const ACTIVE_ICON_COLOR = Color(0.7, 1.0, 0.6)
# Every button hovers in its own color, per the live-game captures in
# references/hotbar/ (*_glow_with_tooltip.png).
const HOVER_COLORS = {
	"InventoryButton": Color(1.0, 0.4, 0.8),      # pink
	"AbilitiesButton": Color(0.45, 1.0, 0.35),    # green
	"SaveButton": Color(0.35, 0.6, 1.0),          # blue
	"OptionsButton": Color(1.0, 0.9, 0.3),        # yellow
	"RespecButton": Color(0.7, 0.4, 1.0),         # violet
	"AchievementsButton": Color(1.0, 0.55, 0.2),  # burnt orange
}
const BUTTON_TOOLTIPS = {
	"InventoryButton": "Inventory\nClick here to manage equipment.",
	"AbilitiesButton": "Abilities\nClick here to manage abilities and attributes.",
	"SaveButton": "Save Game\nClick here to save your progress.",
	"AchievementsButton": "Achievements\nClick here to view your achievements.",
}

@onready var zone_title: Label = %ZoneTitle
@onready var zone_subtitle: Label = %ZoneSubtitle
@onready var progress_bar: ProgressBar = %ZoneProgress
@onready var stage_label: Label = %StageLabel

var _button_glows: Dictionary = {}  # button name -> {glow, icon}


func _ready():
	ZoneManager.zone_changed.connect(_on_zone_changed)
	ZoneManager.zone_unlocked.connect(func(_zone): _refresh(ZoneManager.current_zone))
	GameData.save_loaded.connect(func(_slot): _refresh(ZoneManager.current_zone))
	%SaveButton.pressed.connect(_on_save_pressed)
	for button_name in HOVER_COLORS:
		var button: Button = get_node("%" + button_name)
		_setup_icon_glow(button)
		if BUTTON_TOOLTIPS.has(button_name):
			button.tooltip_text = BUTTON_TOOLTIPS[button_name]
	for button_name in MENU_BUTTON_GROUPS:
		var button: Button = get_node("%" + button_name)
		button.pressed.connect(_on_menu_button_pressed.bind(str(MENU_BUTTON_GROUPS[button_name])))
	for button_name in ["OptionsButton", "RespecButton"]:
		var button: Button = get_node("%" + button_name)
		button.tooltip_text = "Coming soon"
		button.modulate = Color(1, 1, 1, 0.5)
	_wire_screen_visibility.call_deferred()
	_refresh(ZoneManager.current_zone)


# Replaces the Button's built-in icon with two stacked TextureRects: a green
# oversized glow copy (hidden until active) under the white icon. Children
# draw over the button's own icon, so the icon property has to move here.
func _setup_icon_glow(button: Button) -> void:
	var texture: Texture2D = button.icon
	if texture == null:
		return
	button.icon = null
	var glow = TextureRect.new()
	glow.texture = texture
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_CENTER)
	glow.position = Vector2(-19, -19)
	glow.size = Vector2(38, 38)
	glow.modulate = GLOW_COLOR
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.visible = false
	button.add_child(glow)
	var icon = TextureRect.new()
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.set_anchors_preset(Control.PRESET_CENTER)
	icon.position = Vector2(-14, -14)
	icon.size = Vector2(28, 28)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	_button_glows[button.name] = {"glow": glow, "icon": icon}
	# Per-button hover tint (references/hotbar/): the white icon takes the
	# button's own color while hovered; the active green state wins.
	var hover_color: Color = HOVER_COLORS.get(button.name, Color.WHITE)
	button.mouse_entered.connect(func():
		if not glow.visible:
			icon.modulate = hover_color)
	button.mouse_exited.connect(func():
		if not glow.visible:
			icon.modulate = Color.WHITE)


# The screens can close themselves (their X button) - follow their
# visibility to keep the glows honest. Deferred: the screens live in the
# game scene, which finishes building after the hotbar.
func _wire_screen_visibility() -> void:
	for group in MENU_BUTTON_GROUPS.values():
		var screen = get_tree().get_first_node_in_group(str(group))
		if screen != null:
			screen.visibility_changed.connect(_update_glows)
	_update_glows()


func _on_menu_button_pressed(group: String) -> void:
	toggle_menu_screen(group)


# Opens/closes one of the full-screen menu overlays (all in group
# "menu_screen"); opening one closes the others, like the original's single
# KRINMENU clip that could only show one frame at a time.
func toggle_menu_screen(group: String) -> void:
	var target = get_tree().get_first_node_in_group(group)
	if target == null:
		return
	var opening = not target.visible
	for screen in get_tree().get_nodes_in_group("menu_screen"):
		screen.visible = false
	target.visible = opening
	_update_glows()


func _update_glows() -> void:
	for button_name in MENU_BUTTON_GROUPS:
		var parts: Dictionary = _button_glows.get(button_name, {})
		if parts.is_empty():
			continue
		var screen = get_tree().get_first_node_in_group(str(MENU_BUTTON_GROUPS[button_name]))
		var active: bool = screen != null and screen.visible
		parts["glow"].visible = active
		parts["icon"].modulate = ACTIVE_ICON_COLOR if active else Color.WHITE


func _on_zone_changed(zone_id: int) -> void:
	_refresh(zone_id)


func _refresh(zone_id: int) -> void:
	var zone: Dictionary = ZoneManager.ZONES.get(zone_id, {})
	zone_title.text = "Zone %d" % zone_id
	zone_subtitle.text = "%s: %s" % [zone.get("name", "?"), zone.get("subtitle", "?")]
	var progress = 0
	var progress_max = int(ZoneProgression.QUEST_HUB.get(zone_id, {}).get("progress_max", 1))
	if GameData.current_save != null:
		progress = ZoneProgression.quest_progress(GameData.current_save, zone_id)
	progress_bar.max_value = progress_max
	progress_bar.value = min(progress, progress_max)
	stage_label.text = "Stage %d" % (min(progress, progress_max) + 1)


func _on_save_pressed() -> void:
	if GameData.save_game():
		zone_subtitle.text = "Game saved."
		await get_tree().create_timer(1.2).timeout
		_refresh(ZoneManager.current_zone)