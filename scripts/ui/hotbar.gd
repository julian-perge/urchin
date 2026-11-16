# hotbar.gd
# The Hub's hotbar on the bottom bar (scenes/ui/hotbar.tscn). Each button is a
# slot at its SWF rect: the square, the icon, and a hit button over them. The
# zone name, the story progress bar and the stage counter are on the right. The
# hub builds a new hotbar every time it opens, after a load and after every
# battle, so _ready() paints the zone progress from the save's zone, which
# game.gd's _enter_tree() has just restored. After that, picking a zone on the
# world map repaints it through ZoneManager.zone_changed, and so does the Save
# button once its "Game saved." message is gone.
#
# Three buttons open a Window (group "menu_screen"). The original has no
# open-Window state on the hotbar, so nothing here follows a Window's
# visibility.
extends Control

# Tooltip captions per button: [title] for a single-line caption, or
# [title, body] for a 2-section tooltip.
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

# extract_hotbar_icons writes this record: each icon's hover Glow colors, the
# inner one first, and the frames of the hover clip's START and STOP runs.
const ICONS_PATH: String = "res://assets/ui/hotbar/hotbar_icons.json"
# Each slot with an icon, and the icon's name in the record. Quit has no icon
# and no hover.
const ICON_SLOTS: Dictionary[String, String] = {
	"Inventory": "inventory",
	"Abilities": "abilities",
	"Save": "save",
	"Options": "options",
	"Respec": "respec",
	"Achievements": "achievements",
	"ZoneMap": "world_map",
}
const GLOW_SHADER: Shader = preload("res://scenes/ui/hotbar_glow.gdshader")
# The blur of the two Glow layers in Stage px, the near one first, and their
# strength. The record holds no blur, so these were chosen by eye for #219.
const GLOW_RADII: Array[float] = [4.0, 9.0]
const GLOW_STRENGTH: float = 2.5
# A layer is this many radii larger than the icon on each side, which is where
# the blur has faded out.
const GLOW_PAD: float = 1.5

@onready var zone_title: Label = %ZoneTitle
@onready var zone_subtitle: Label = %ZoneSubtitle
@onready var progress_bar: ProgressBar = %ZoneProgress
@onready var stage_label: Label = %StageLabel

var _fade_in_seconds: float
var _fade_out_seconds: float
var _hover_tweens: Dictionary[String, Tween] = {}


func _ready():
	ZoneManager.zone_changed.connect(_on_zone_changed)
	_setup_hover()
	for button_name in TOOLTIP_CAPTIONS:
		_setup_tooltip(get_node("%" + button_name), TOOLTIP_CAPTIONS[button_name])
	_refresh(ZoneManager.current_zone)


# The SWF draws the hover as one or two Glow filters on the icon, which grow
# over the clip's START frames and fall over its STOP frames. The port draws
# each icon's Glow node as two blurred copies of the icon, the outer color wide
# and the inner color near, and fades the node. An icon with one Glow color
# draws both layers in it.
func _setup_hover() -> void:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ICONS_PATH))
	var hover: Dictionary = record["hover"]
	_fade_in_seconds = _run_seconds(hover["start"], hover["frame_rate"])
	_fade_out_seconds = _run_seconds(hover["stop"], hover["frame_rate"])
	for slot: String in ICON_SLOTS:
		var colors: Array = record["icons"][ICON_SLOTS[slot]]["glow"]
		var icon: TextureRect = get_node(slot + "Slot/Icon")
		var glow: Control = get_node(slot + "Slot/Glow")
		for layer: int in [1, 0]:
			var color: String = colors[mini(layer, colors.size() - 1)]
			glow.add_child(_glow_layer(icon, Color.html(color), GLOW_RADII[layer]))
		var button: BaseButton = get_node("%" + slot + "Button")
		button.mouse_entered.connect(_fade_glow.bind(slot, 1.0))
		button.mouse_exited.connect(_fade_glow.bind(slot, 0.0))


# A run of the hover clip shows its first frame at once, so it lasts one frame
# time less than its frame count.
func _run_seconds(frames: Array, frame_rate: float) -> float:
	return (float(frames[1]) - float(frames[0])) / frame_rate


func _glow_layer(icon: TextureRect, color: Color, radius: float) -> TextureRect:
	var pad := Vector2(radius, radius) * GLOW_PAD
	var layer := TextureRect.new()
	layer.texture = icon.texture
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.position = -pad
	layer.size = icon.size + pad * 2.0
	layer.modulate = color
	var material := ShaderMaterial.new()
	material.shader = GLOW_SHADER
	material.set_shader_parameter("grow", layer.size / icon.size)
	material.set_shader_parameter("radius", Vector2(radius, radius) / icon.size)
	material.set_shader_parameter("strength", GLOW_STRENGTH)
	layer.material = material
	return layer


func _fade_glow(slot: String, alpha: float) -> void:
	var glow: Control = get_node(slot + "Slot/Glow")
	if _hover_tweens.has(slot):
		_hover_tweens[slot].kill()
	var tween: Tween = create_tween()
	tween.tween_property(glow, "modulate:a", alpha, _fade_in_seconds if alpha > 0.0 else _fade_out_seconds)
	_hover_tweens[slot] = tween


# The tween that fades the Glow of `slot`, or null before its first hover.
func hover_tween(slot: String) -> Tween:
	return _hover_tweens.get(slot)


func _on_quit_pressed() -> void:
	AudioManagerAuto.play_menu_music()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _setup_tooltip(button: BaseButton, caption: Array) -> void:
	var sections: Array = [
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": caption[0], "color": TooltipTheme.TEXT_TITLE}]},
	]
	if caption.size() > 1:
		sections.append({"bg_color": TooltipTheme.BG_BODY, "lines": [{"text": caption[1], "color": TooltipTheme.TEXT_BODY}]})
	button.mouse_entered.connect(func(): GameTooltip.show_sections(sections, button))
	button.mouse_exited.connect(GameTooltip.hide_tooltip)


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
	# The original caps the bar at progress_max but not the stage text
	# (frame_181/DoAction.as:7-14), so a beaten zone reads one stage past its boss.
	stage_label.text = "Stage %d" % (progress + 1)


func _on_save_pressed() -> void:
	if GameData.save_game():
		zone_subtitle.text = "Game saved."
		await get_tree().create_timer(1.2).timeout
		_refresh(ZoneManager.current_zone)
