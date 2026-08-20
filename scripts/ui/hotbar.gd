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
const MENU_BUTTON_GROUPS: Dictionary[String, String] = {
	"InventoryButton": "inventory_window",
	"AbilitiesButton": "abilities_window",
	"AchievementsButton": "achievements_window",
}
const ACTIVE_ICON_COLOR: Color = Color(0.7, 1.0, 0.6)
# Every button hovers in its own color, per the live-game captures in
# references/hotbar/ (*_glow_with_tooltip.png).
const HOVER_COLORS: Dictionary[String, Color] = {
	"InventoryButton": Color(1.0, 0.4, 0.8),      # pink
	"AbilitiesButton": Color(0.45, 1.0, 0.35),    # green
	"SaveButton": Color(0.35, 0.6, 1.0),          # blue
	"OptionsButton": Color(1.0, 0.9, 0.3),        # yellow
	"RespecButton": Color(0.7, 0.4, 1.0),         # violet
	"AchievementsButton": Color(1.0, 0.55, 0.2),  # burnt orange
}
# Tooltip captions per button: [title] for a single-line caption, or
# [title, body] for a 2-section tooltip. These are the same strings the
# scene file used to carry as plain tooltip_text - kept here now that
# GameTooltip needs sections, not a joined string.
const TOOLTIP_CAPTIONS: Dictionary[String, Array] = {
	"InventoryButton": ["Inventory", "Click here to manage equipment."],
	"AbilitiesButton": ["Abilities", "Click here to manage abilities and attributes."],
	"SaveButton": ["Save Game", "Click here to save your progress."],
	"OptionsButton": ["Coming soon"],
	"RespecButton": ["Coming soon"],
	"AchievementsButton": ["Achievements", "Click here to view your achievements."],
	"ZoneMapButton": ["World map"],
	"QuitButton": ["Quit", "Click here to return to the save select screen."],
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
	for button_name in HOVER_COLORS:
		_setup_icon_glow(get_node("%" + button_name))
	for button_name in TOOLTIP_CAPTIONS:
		_setup_tooltip(get_node("%" + button_name), TOOLTIP_CAPTIONS[button_name])
	_wire_screen_visibility.call_deferred()
	_refresh(ZoneManager.current_zone)


func _on_quit_pressed() -> void:
	AudioManagerAuto.play_menu_music()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# Fetches the pre-built glow/icon overlay children (see hotbar.tscn) and
# wires the per-button hover tint - the active (menu-open) state always
# wins over hover, matching the original's single green-glow priority.
func _setup_icon_glow(button: Button) -> void:
	var glow: TextureRect = button.get_node("Glow")
	var icon: TextureRect = button.get_node("Icon")
	_button_glows[button.name] = {"glow": glow, "icon": icon}
	var hover_color: Color = HOVER_COLORS.get(button.name, Color.WHITE)
	button.mouse_entered.connect(func():
		if not glow.visible:
			icon.modulate = hover_color)
	button.mouse_exited.connect(func():
		if not glow.visible:
			icon.modulate = Color.WHITE)


func _setup_tooltip(button: Button, caption: Array) -> void:
	var sections: Array = [
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": caption[0], "color": TooltipTheme.TEXT_TITLE}]},
	]
	if caption.size() > 1:
		sections.append({"bg_color": TooltipTheme.BG_BODY, "lines": [{"text": caption[1], "color": TooltipTheme.TEXT_BODY}]})
	button.mouse_entered.connect(func(): GameTooltip.show_sections(sections, button))
	button.mouse_exited.connect(GameTooltip.hide_tooltip)


# The screens can close themselves (their X button) - follow their
# visibility to keep the glows honest. Deferred: the screens live in the
# game scene, which finishes building after the hotbar.
func _wire_screen_visibility() -> void:
	for group in MENU_BUTTON_GROUPS.values():
		var screen: Node = get_tree().get_first_node_in_group(str(group))
		if screen != null:
			screen.visibility_changed.connect(_update_glows)
	_update_glows()


func _on_menu_button_pressed(group: String) -> void:
	toggle_menu_screen(group)


# Opens/closes one of the full-screen menu overlays (all in group
# "menu_screen"); opening one closes the others, like the original's single
# KRINMENU clip that could only show one frame at a time.
func toggle_menu_screen(group: String) -> void:
	var target: Node = get_tree().get_first_node_in_group(group)
	if target == null:
		return
	var opening: bool = not target.visible
	for screen in get_tree().get_nodes_in_group("menu_screen"):
		screen.visible = false
	target.visible = opening
	_update_glows()


func _update_glows() -> void:
	for button_name in MENU_BUTTON_GROUPS:
		var parts: Dictionary = _button_glows.get(button_name, {})
		if parts.is_empty():
			continue
		var screen: Node = get_tree().get_first_node_in_group(str(MENU_BUTTON_GROUPS[button_name]))
		var active: bool = screen != null and screen.visible
		parts["glow"].visible = active
		parts["icon"].modulate = ACTIVE_ICON_COLOR if active else Color.WHITE


func _on_zone_changed(zone_id: int) -> void:
	_refresh(zone_id)


func _refresh(zone_id: int) -> void:
	var zone: Dictionary = ZoneManager.ZONES.get(zone_id, {})
	zone_title.text = "Zone %d" % zone_id
	zone_subtitle.text = "%s: %s" % [zone.get("name", "?"), zone.get("subtitle", "?")]
	var progress: int = 0
	var progress_max: int = int(ZoneProgression.QUEST_HUB.get(zone_id, {}).get("progress_max", 1))
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
