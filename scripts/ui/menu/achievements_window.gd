# achievements_window.gd
# The achievements screen, rebuilt from frame 45 of the original menu clip
# (DefineSprite 3142 at stage 400.5, 222.4): a heading, the center panel,
# and 10 achievement plates (achPlate0-9, sprite 3141: frame 1 = locked,
# frame 2 = unlocked) in two columns of five. Descriptions ride tooltips.
extends Control

# The Steam build widens this screen's panel and drops the heading inside
# it in gold (see assets/references/sonny2_achievements_screen.png); the
# plate grid itself matches the web SWF's extracted centers.
const PANEL = Rect2(76.0, 86.0, 649.0, 311.0)
const PLATE_SIZE = Vector2(140, 32)
const PLATE_COLUMNS_X = [318.0, 483.0]
const PLATE_ROWS_Y = [161.0, 207.0, 253.0, 299.0, 345.0]

var _plates: Array[PanelContainer] = []
var _plate_labels: Array[Label] = []


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop = MenuTheme.add_texture_rect(self, "menu_backdrop.png", MenuTheme.BACKDROP_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	var close = TextureButton.new()
	close.name = "CloseButton"
	close.texture_normal = MenuTheme.texture("close_x.png")
	close.ignore_texture_size = true
	close.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close.position = MenuTheme.CLOSE_RECT.position
	close.size = MenuTheme.CLOSE_RECT.size
	close.pressed.connect(hide)
	add_child(close)
	MenuTheme.add_texture_rect(self, "panel_large.png", PANEL)
	MenuTheme.add_label(
		self, "Achievements", Rect2(PANEL.position.x, 105, PANEL.size.x, 28), 19,
		Color(0.94, 0.73, 0.23), HORIZONTAL_ALIGNMENT_CENTER
	)
	for i in Achievements.ACHIEVEMENT_COUNT:
		var plate = PanelContainer.new()
		plate.position = Vector2(
			PLATE_COLUMNS_X[floori(i / float(PLATE_ROWS_Y.size()))],
			PLATE_ROWS_Y[i % PLATE_ROWS_Y.size()]
		) - PLATE_SIZE / 2.0
		plate.size = PLATE_SIZE
		plate.custom_minimum_size = PLATE_SIZE
		plate.tooltip_text = Achievements.DESCRIPTIONS[i]
		add_child(plate)
		_plates.append(plate)
		var label = Label.new()
		label.text = Achievements.NAMES[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 11)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(label)
		_plate_labels.append(label)
	visibility_changed.connect(func():
		if visible:
			refresh())
	refresh()


func refresh() -> void:
	var unlocked: Array = Achievements.load_unlocked()
	for i in _plates.size():
		var got: bool = i < unlocked.size() and unlocked[i]
		var style = StyleBoxFlat.new()
		style.set_corner_radius_all(4)
		style.set_border_width_all(2)
		if got:
			style.bg_color = Color(0.2, 0.42, 0.8)  # the reference's blue plate
			style.border_color = Color(0.75, 0.85, 0.95)
		else:
			style.bg_color = Color(0.12, 0.14, 0.19)
			style.border_color = Color(0.55, 0.58, 0.62)
		_plates[i].add_theme_stylebox_override("panel", style)
		_plate_labels[i].add_theme_color_override(
			"font_color", Color.WHITE if got else Color(0.45, 0.45, 0.45)
		)
