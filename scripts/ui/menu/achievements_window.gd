# achievements_window.gd
# The achievements screen, rebuilt from frame 45 of the original menu clip
# (DefineSprite 3142 at stage 400.5, 222.4): a heading, the center panel,
# and 10 achievement plates (achPlate0-9, sprite 3141: frame 1 = locked,
# frame 2 = unlocked) in two columns of five. Descriptions ride tooltips.
extends Control

@onready var _plates: Array[PanelContainer] = [
	$Plate0, $Plate1, $Plate2, $Plate3, $Plate4,
	$Plate5, $Plate6, $Plate7, $Plate8, $Plate9,
]
@onready var _plate_labels: Array[Label] = [
	$Plate0/NameLabel, $Plate1/NameLabel, $Plate2/NameLabel, $Plate3/NameLabel, $Plate4/NameLabel,
	$Plate5/NameLabel, $Plate6/NameLabel, $Plate7/NameLabel, $Plate8/NameLabel, $Plate9/NameLabel,
]


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(func():
		if visible:
			refresh())
	refresh()


func refresh() -> void:
	var unlocked: Array = Achievements.load_unlocked()
	for i in _plates.size():
		var got: bool = i < unlocked.size() and unlocked[i]
		var style: StyleBoxFlat = StyleBoxFlat.new()
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
