# One flat KRINMENU Panel built to PanelRecipe, with one of the three fills
# the Windows use (spec/107-window-shell.md, ShellPanel). The host sets the
# rect, the border width and the content margins. test_screen_rects.gd checks
# each fill against its SWF sprite through
# test/fixtures/screen_rects/shell_panel_fills.tscn.
class_name ShellPanel
extends PanelContainer

enum Fill { TALL, BAR, CENTRE }

const FILLS: Dictionary[Fill, Color] = {
	Fill.TALL: Color("#373737"),
	Fill.BAR: Color("#404040"),
	Fill.CENTRE: Color("#1a1a1a"),
}

@export var fill: Fill = Fill.TALL:
	set(value):
		fill = value
		_style.bg_color = FILLS[fill]

# The recipe's mean scale stroke for the placement, in whole pixels.
@export var border: int = 1:
	set(value):
		border = value
		for side: Side in PanelRecipe.SIDES:
			_style.set_border_width(side, border)

# The left, top, right and bottom content margins, in that order.
@export var content_margins: Vector4 = Vector4.ZERO:
	set(value):
		content_margins = value
		_style.content_margin_left = value.x
		_style.content_margin_top = value.y
		_style.content_margin_right = value.z
		_style.content_margin_bottom = value.w

var _style: StyleBoxFlat = StyleBoxFlat.new()


func _init() -> void:
	_style.border_color = Color.BLACK
	_style.anti_aliasing = false
	for corner: Corner in PanelRecipe.CORNERS:
		_style.set_corner_radius(corner, 0)
	fill = fill
	border = border
	content_margins = content_margins
	add_theme_stylebox_override("panel", _style)
