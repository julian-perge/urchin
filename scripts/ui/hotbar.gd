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

# extract_hotbar_icons writes this record: the Glows of every frame of each
# icon's hover clip, and the frames of the clip's START and STOP runs.
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

@onready var zone_title: Label = %ZoneTitle
@onready var zone_subtitle: Label = %ZoneSubtitle
@onready var zone_fill: Control = %ZoneFill
@onready var stage_label: Label = %StageLabel

# The record's "hover": the frame rate, and the first and last frame of the
# START run and of the STOP run.
var _hover: Dictionary
# Each slot's Glows on every frame of its hover clip, frame 1 first.
var _hover_frames: Dictionary[String, Array] = {}
# The hover frame each slot shows now.
var _hover_frame: Dictionary[String, int] = {}
# Each slot's layers: for each Glow of its filter list, the layer under the
# icon that draws it as an outer Glow and the layer over the icon that draws it
# as an inner Glow.
var _glow_layers: Dictionary[String, Array] = {}
var _hover_tweens: Dictionary[String, Tween] = {}
var _inert: bool = false


func _ready():
	ZoneManager.zone_changed.connect(_on_zone_changed)
	_setup_hover()
	for button_name in TOOLTIP_CAPTIONS:
		_setup_tooltip(get_node("%" + button_name), TOOLTIP_CAPTIONS[button_name])
	_refresh(ZoneManager.current_zone)


# The SWF draws the hover as one or two Glow filters on the icon, and every
# frame of the icon's clip holds its own strength, blur and color for each. The
# port keeps one layer under the icon and one over it for each Glow, and
# show_hover_frame() sets them from the record. Each button plays its clip from
# START on roll over and from STOP on roll out
# (DefineButton2_3185/BUTTONCONDACTION on(rollOver).as:3, on(rollOut).as:3).
func _setup_hover() -> void:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ICONS_PATH))
	_hover = record["hover"]
	for slot: String in ICON_SLOTS:
		var frames: Array = record["icons"][ICON_SLOTS[slot]]["frames"]
		var icon: TextureRect = get_node(slot + "Slot/Icon")
		# A blur box reaches half its width past the icon.
		var reach: float = 0.0
		for glows: Array in frames:
			for glow: Dictionary in glows:
				reach = maxf(reach, float(glow["blur"]) / 2.0)
		var layers: Array = []
		for glow: Dictionary in frames[0]:
			var under: TextureRect = _glow_layer(icon, reach)
			get_node(slot + "Slot/Glow").add_child(under)
			var over: TextureRect = _glow_layer(icon, 0.0)
			get_node(slot + "Slot/InnerGlow").add_child(over)
			layers.append([under, over])
		_hover_frames[slot] = frames
		_glow_layers[slot] = layers
		show_hover_frame(slot, 1)
		var button: BaseButton = get_node("%" + slot + "Button")
		button.mouse_entered.connect(_play_hover.bind(slot, "start"))
		button.mouse_exited.connect(_play_hover.bind(slot, "stop"))


# A hidden layer of the icon's texture, `pad` px larger than the icon on each
# side. The Glow and InnerGlow nodes sit on the icon's rect.
func _glow_layer(icon: TextureRect, pad: float) -> TextureRect:
	var layer := TextureRect.new()
	layer.texture = icon.texture
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.position = -Vector2(pad, pad)
	layer.size = icon.size + Vector2(pad, pad) * 2.0
	layer.visible = false
	var material := ShaderMaterial.new()
	material.shader = GLOW_SHADER
	material.set_shader_parameter("grow", layer.size / icon.size)
	layer.material = material
	return layer


# Shows the Glows of frame `frame` of the hover clip of `slot`. A Glow with no
# strength hides its layers, so an icon at rest draws no shader.
func show_hover_frame(slot: String, frame: int) -> void:
	_hover_frame[slot] = frame
	var icon_size: Vector2 = (get_node(slot + "Slot/Icon") as Control).size
	var glows: Array = _hover_frames[slot][frame - 1]
	for index: int in glows.size():
		var glow: Dictionary = glows[index]
		for inner: bool in [false, true]:
			var layer: TextureRect = _glow_layers[slot][index][int(inner)]
			layer.visible = glow["inner"] == inner and float(glow["strength"]) > 0.0
			if not layer.visible:
				continue
			var low: Color
			var high: Color
			if glow.has("gradient"):
				var stops: Array = glow["gradient"]
				low = Color(Color.html(stops[0]["color"]), float(stops[0]["alpha"]) / 255.0)
				high = Color(Color.html(stops[1]["color"]), float(stops[1]["alpha"]) / 255.0)
			else:
				low = Color(Color.html(glow["color"]), 0.0)
				high = Color(Color.html(glow["color"]), 1.0)
			var material: ShaderMaterial = layer.material
			material.set_shader_parameter("low", low)
			material.set_shader_parameter("high", high)
			material.set_shader_parameter("blur", Vector2.ONE * float(glow["blur"]) / icon_size)
			material.set_shader_parameter("strength", float(glow["strength"]))
			material.set_shader_parameter("inner", inner)


# Plays the hover clip of `slot` through its "start" or "stop" run at the
# clip's frame rate. As in the SWF, the run starts on its first frame whatever
# frame the clip shows now, so leaving in the middle of START jumps to the full
# Glow and falls from there.
func _play_hover(slot: String, run: String) -> void:
	if _hover_tweens.has(slot):
		_hover_tweens[slot].kill()
	var first: int = int(_hover[run][0])
	var last: int = int(_hover[run][1])
	show_hover_frame(slot, first)
	var tween: Tween = create_tween()
	# The small amount keeps a step that ends on a frame's time on that frame.
	tween.tween_method(
		func(frame: float) -> void: show_hover_frame(slot, floori(frame + 0.001)),
		float(first), float(last), float(last - first) / float(_hover["frame_rate"]))
	_hover_tweens[slot] = tween


# The tween that plays the hover clip of `slot`, or null before its first hover.
func hover_tween(slot: String) -> Tween:
	return _hover_tweens.get(slot)


# The frame of its hover clip that `slot` shows now.
func hover_frame(slot: String) -> int:
	return _hover_frame[slot]


# The port's form of the original's Krin.PauseForScreen. While it is set, a
# click on a hotbar button or on an orb does nothing
# (DefineButton2_3178/BUTTONCONDACTION on(release).as:2 for Quit,
# DefineButton2_3188/BUTTONCONDACTION on(press).as:2 for an orb). The roll over
# still plays. An orb reads is_inert() on each click (orb_base.gd), so an orb
# made while it is set is inert too. Nothing sets it until the Victory Window
# does (#241).
func set_inert(inert: bool) -> void:
	_inert = inert
	for button: BaseButton in find_children("*", "BaseButton"):
		button.disabled = inert


func is_inert() -> bool:
	return _inert


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
	# The original sets the fill's width to this share of its full width, which
	# scales the fill from its left edge. It caps the bar at progress_max but not
	# the stage text (frame_181/DoAction.as:7-14), so a beaten zone reads one
	# stage past its boss. With no save the fill keeps the scene's full width,
	# which is the state the rect record measures.
	if GameData.current_save != null:
		progress = ZoneProgression.quest_progress(GameData.current_save, zone_id)
		zone_fill.scale.x = float(mini(progress, progress_max)) / float(progress_max)
	stage_label.text = "Stage %d" % (progress + 1)


func _on_save_pressed() -> void:
	if GameData.save_game():
		zone_subtitle.text = "Game saved."
		await get_tree().create_timer(1.2).timeout
		_refresh(ZoneManager.current_zone)
