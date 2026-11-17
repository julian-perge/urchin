# status_bar.gd
# One fighter's entry in the Battle screen's top status bar, the original's
# p1BAR to p6BAR (DefineSprite 3414): the name, the life and Focus numbers, and
# the life and Focus fills. FighterPresenter writes to it where it used to write
# to its UnitOverlay, so a bar changes when the event that changes it plays.
#
# Nothing here types a position, a width or a color. extract_top_bar reads them
# out of the SWF into top_bar.json, and _ready() lays the bar out from that file
# for the slot it is on: the placement, the mirror that the right-hand bars give
# `inner2`, the frame of `inner` that holds the text, and each part's rect.
extends Control
class_name StatusBar

const RECORD_PATH: String = "res://assets/ui/battle/top_bar/top_bar.json"
const TEXTURE_DIR: String = "res://assets/ui/battle/top_bar/"
# The life bar's color clip has one frame for each whole percent from 0 to 100,
# and the clip's frame number is the percent plus 1 (lifeBarUpdate,
# frame_42/DoAction_8.as:339-340).
const FULL_PERCENT: float = 100.0

# The fighter's slot, 1 to 6. The battle frame names the bar p<slot>BAR.
@export var slot: int = 1

# What the bar shows, as the last show_status() left it.
var life: float = 0.0
var life_max: float = 0.0
var focus: float = 0.0
var focus_max: float = 0.0

static var _record: Dictionary = {}

# The widths that the fills have at full, which the original's script reads as
# `wsaver` when each bar loads.
var _life_width: float = 0.0
var _focus_width: float = 0.0
var _life_colors: Array = []

@onready var inner: Control = $Inner
@onready var inner2: Control = $Inner2
@onready var name_label: Label = $Inner/PlayerName
@onready var life_now_label: Label = $Inner/LifeNow
@onready var life_max_label: Label = $Inner/LifeMax
@onready var focus_now_label: Label = $Inner/FocusNow
@onready var focus_max_label: Label = $Inner/FocusMax
@onready var life_fill: TextureRect = $Inner2/LifeFill
@onready var life_back: TextureRect = $Inner2/LifeBack
@onready var focus_fill: TextureRect = $Inner2/FocusFill
@onready var focus_back: TextureRect = $Inner2/FocusBack


# Returns what top_bar.json holds. It reads the file once, the first time
# anything asks.
static func record() -> Dictionary:
	if _record.is_empty():
		_record = JSON.parse_string(FileAccess.get_file_as_string(RECORD_PATH))
	return _record


func _ready() -> void:
	var bar: Dictionary = record()
	var placement: Dictionary = bar["placements"]["p%dBAR" % slot]
	position = Vector2(float(placement["x"]), float(placement["y"]))
	scale = Vector2(float(placement["scale"][0]), float(placement["scale"][1]))
	# The right-hand bars' load scripts send `inner` to its `second` frame and
	# set inner2._xscale to -100 (frame_217/PlaceObject3_3414_396 and two more).
	var mirror = placement["inner2_xscale"]
	inner2.scale.x = float(mirror) / FULL_PERCENT if mirror != null else 1.0
	var frame: Dictionary = bar["inner"]["frames"][placement["inner_frame"] if placement["inner_frame"] != null else "first"]
	_place_art($Inner/Backing, frame["art"])
	var fields: Dictionary = {}
	for field: Dictionary in frame["fields"]:
		fields[field["variable"]] = field
	_place_field(name_label, fields["playerName"], bar["shadow"])
	_place_field(life_now_label, fields["lifeNow"], bar["shadow"])
	_place_field(life_max_label, fields["lifeMax"], bar["shadow"])
	_place_field(focus_now_label, fields["focusNow"], bar["shadow"])
	_place_field(focus_max_label, fields["focusMax"], bar["shadow"])
	for part: String in ["Shade", "Black", "Frame"]:
		_place_art(inner2.get_node(part), bar["inner2"]["art"][part])
	_life_width = _place_fill([life_fill, life_back], bar["bars"]["life"], bar["art"])
	_focus_width = _place_fill([focus_fill, focus_back], bar["bars"]["focus"], bar["art"])
	_life_colors = bar["life_colors"]
	_show_fills(1.0, 1.0)


# Sets the bar's name. The original fills the field from the unit's playerName
# each time lifeBarUpdate runs (frame_42/DoAction_8.as:278).
func setup(unit_name: String) -> void:
	name_label.text = unit_name


# Shows what an event left on the unit. The state comes from FighterPresenter
# rather than from the unit, because the runner has already resolved the rest of
# the half-turn on the unit when an event plays.
func show_status(state: UnitSnapshot) -> void:
	life = state.life
	life_max = state.life_max
	focus = state.focus
	focus_max = state.focus_max
	life_now_label.text = str(int(life))
	life_max_label.text = str(int(life_max))
	focus_now_label.text = str(int(focus))
	focus_max_label.text = str(int(focus_max))
	_show_fills(_share(life, life_max), _share(focus, focus_max))


# Does what LifeBarSmoother's frame 18 does to a dead unit's bar
# (DefineSprite_57_LifeBarSmoother/frame_18/DoAction.as): it sends `inner` to its
# empty "third" frame, which takes the name, the numbers and the divider away.
# The fills stay to fade. show_status() fills these nodes but never shows them,
# so later redraws leave them hidden.
func clear_for_death() -> void:
	inner.hide()


# Returns the fill's share of its full width, from 0 to 1. A max of 0 gives 0,
# which is what Flash's width of NaN comes to.
func _share(now: float, maximum: float) -> float:
	if maximum <= 0.0:
		return 0.0
	return clampf(now / maximum, 0.0, 1.0)


func _show_fills(life_share: float, focus_share: float) -> void:
	life_fill.size.x = _life_width * life_share
	focus_fill.size.x = _focus_width * focus_share
	var frame: int = roundi(life_share * FULL_PERCENT)
	var color := Color.html(_life_colors[frame])
	life_fill.modulate = color
	life_back.modulate = color


# Sets a TextureRect to an art entry of the record: the PNG and its rect.
func _place_art(node: TextureRect, entry: Dictionary) -> void:
	node.texture = load(TEXTURE_DIR + str(entry["file"]))
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.position = Vector2(float(entry["rect"][0]), float(entry["rect"][1]))
	node.size = Vector2(float(entry["rect"][2]), float(entry["rect"][3]))


# Places the fills of one bar, which all show the one art, at the width of the
# original's `wsaver`. The record gives the art's rect in the bar clip's own
# space and the clip's placement in `inner2`. Returns that full width.
func _place_fill(nodes: Array, bar: Dictionary, art: Dictionary) -> float:
	var entry: Dictionary = art[bar["art"]]
	var scale_x: float = float(bar["scale_x"])
	for node: TextureRect in nodes:
		_place_art(node, entry)
		node.position = Vector2(
			float(bar["x"]) + float(entry["rect"][0]) * scale_x,
			float(bar["y"]) + float(entry["rect"][1]),
		)
		node.size = Vector2(float(entry["rect"][2]) * scale_x, float(entry["rect"][3]))
	return float(entry["rect"][2]) * scale_x


# Lays out one text field: its rect, size, color and alignment. The bar's
# DropShadow shadows every field in it. A Label's shadow is a whole number of px
# and has no blur, so the offset is rounded.
func _place_field(label: Label, field: Dictionary, shadow: Dictionary) -> void:
	label.position = Vector2(float(field["rect"][0]), float(field["rect"][1]))
	label.size = Vector2(float(field["rect"][2]), float(field["rect"][3]))
	label.horizontal_alignment = {
		"left": HORIZONTAL_ALIGNMENT_LEFT,
		"right": HORIZONTAL_ALIGNMENT_RIGHT,
		"center": HORIZONTAL_ALIGNMENT_CENTER,
	}[field["align"]]
	label.add_theme_font_size_override("font_size", roundi(float(field["font_size"])))
	label.add_theme_color_override("font_color", Color.html(field["color"]))
	var angle: float = deg_to_rad(float(shadow["angle"]))
	label.add_theme_constant_override("shadow_offset_x", roundi(float(shadow["distance"]) * cos(angle)))
	label.add_theme_constant_override("shadow_offset_y", roundi(float(shadow["distance"]) * sin(angle)))
	# A Label has no strength either, so it goes into the shadow's alpha, rounded
	# to a whole 8-bit value as Flash's color transform is.
	var shadow_color := Color.html(shadow["color"])
	shadow_color.a = minf(roundf(shadow_color.a * 255.0 * float(shadow["strength"])), 255.0) / 255.0
	label.add_theme_color_override("font_shadow_color", shadow_color)
