# victory_experience_row.gd
# One row of the victory screen's "Character Experience" list (portrait,
# name, level, and an experience bar) - instanced once per fighter by
# victory_screen.gd's _build_experience_rows(), which sets its position
# and calls setup() with that fighter's data.
extends Control
class_name VictoryExperienceRow

@onready var face: TextureRect = $Face
@onready var name_label: Label = $NameLabel
@onready var level_label: Label = $LevelLabel
@onready var exp_fill: TextureRect = $ExpFill
@onready var percent_label: Label = $PercentLabel


func setup(portrait_file: String, display_name: String, level: int, experience: float) -> void:
	face.texture = MenuTheme.texture(portrait_file)
	name_label.text = display_name
	level_label.text = "Lvl. %d" % level
	var fraction: float = clamp(experience / 100.0, 0.0, 1.0)
	exp_fill.size.x = 150.0 * fraction
	percent_label.text = "%d%%" % int(experience)
