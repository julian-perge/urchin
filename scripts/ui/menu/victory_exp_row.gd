# victory_exp_row.gd
# One experience row of the victory frame (sprite 3002 on KRINMENU's "win"
# label). It shows a fighter's face, name, level, experience bar and percent,
# and animates the bar from the fighter's experience before the win to the
# value after it, as the row's clip scripts do
# (DefineSprite_3142/frame_9/PlaceObject3_3002_*). The frame count, the full
# bar width, the level cap and the frame rate come from menu_math.json, which
# uv run convert_menu_math reads out of those scripts and the SWF header.
#
# The save already holds the values after the win, so the row changes nothing
# but what it draws.
class_name VictoryExpRow
extends Control

# The bar's two frames: the normal fill (2865) and the fill of its "level"
# frame (2866), which a row jumps to when it levels up.
const FILL: Texture2D = preload("res://assets/ui/window/xp_bar.png")
const LEVEL_FILL: Texture2D = preload("res://assets/ui/window/xp_bar_level.png")

var experience: float = 0.0
var level: int = 0
# True once the row has added a level. The player's row sets the original's
# playerLeveled from it.
var leveled: bool = false

var _frames: int = 0
var _frame: int = 0
var _bar_width: float = 0.0
var _level_cap: int = 0
var _frame_time: float = 0.0
var _per_frame: float = 0.0
var _elapsed: float = 0.0

@onready var face: TextureRect = $Face
@onready var name_label: Label = $NameLabel
@onready var level_label: Label = $LevelLabel
@onready var bar: TextureRect = $Bar
@onready var percent_label: Label = $PercentLabel


# Shows the fighter as it was before the win and starts the animation. The
# row adds a 1 / frames share of the gain on each frame.
func setup(portrait_file: String, display_name: String, fighter: BattleSettlement.FighterExperience, math: Dictionary = MenuMath.load_math()) -> void:
	var rows: Dictionary = math["victory_rows"]
	_frames = int(rows["frames"])
	_bar_width = float(rows["bar_width"])
	_level_cap = int(rows["level_cap"])
	_frame_time = 1.0 / float(rows["frame_rate"])
	_frame = 0
	_elapsed = 0.0
	experience = fighter.experience_before
	level = fighter.level_before
	leveled = false
	_per_frame = fighter.xp_gained / _frames
	face.texture = MenuTheme.texture(portrait_file)
	name_label.text = display_name
	_show_level()
	bar.texture = FILL
	percent_label.text = "%d%%" % roundi(experience)
	_set_bar_fraction(experience / 100.0)


# Plays the frames that `delta` seconds hold, at the SWF's frame rate.
func advance(delta: float) -> void:
	_elapsed += delta
	while _elapsed >= _frame_time and not is_finished():
		_elapsed -= _frame_time
		step()


# One frame of the original's onClipEvent(enterFrame). A fighter at the level
# cap does not move, and the original checks the cap on every frame.
func step() -> void:
	if is_finished():
		return
	_frame += 1
	experience += _per_frame
	percent_label.text = "%d%%" % roundi(experience)
	_set_bar_fraction(experience / 100.0)
	if experience >= 100.0:
		experience -= 100.0
		percent_label.text = "100%"
		level += 1
		leveled = true
		bar.texture = LEVEL_FILL
		_set_bar_fraction(1.0)
		_show_level()


# Finished once every frame has played, or at once for a fighter at the level
# cap, whose row never moves.
func is_finished() -> bool:
	return _frame >= _frames or level >= _level_cap


func _process(delta: float) -> void:
	if _frames > 0:
		advance(delta)


func _show_level() -> void:
	level_label.text = Strings.menu(0) + str(level)


func _set_bar_fraction(fraction: float) -> void:
	bar.size.x = fraction * _bar_width
