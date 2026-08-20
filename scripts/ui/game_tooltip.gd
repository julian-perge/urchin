# game_tooltip.gd
# Shared rich tooltip, replacing both the abilities-screen's old single-panel
# AbilityTooltip and every other tooltip's plain Godot tooltip_text (which
# can only render one uniform box, one text color - it can't reproduce the
# original's title-bar/colored-info-bar/body look at all). A tooltip is a
# stack of sections (scripts/ui/tooltip_theme.gd's colors); each section is
# its own background box holding one or more independently-colored lines -
# see docs/superpowers/specs/2026-08-20-rich-tooltip-rework-design.md.
extends CanvasLayer

const EDGE_MARGIN: float = 4.0

@onready var _root: HBoxContainer = $Root
@onready var _icon_backing: ColorRect = $Root/IconBacking
@onready var _icon: TextureRect = $Root/IconBacking/Icon
@onready var _sections: VBoxContainer = $Root/Sections


# sections: Array[Dictionary], each {"bg_color": Color, "lines":
# Array[Dictionary]} where a line is {"text": String, "color": Color}.
# anchor: the hovered control, used to position this tooltip beside it.
# icon/icon_color are optional - only the abilities screen uses them today.
func show_sections(sections: Array, anchor: Control, icon: Texture2D = null, icon_color: Color = Color.WHITE) -> void:
	for child in _sections.get_children():
		child.free()
	for section in sections:
		var panel: PanelContainer = PanelContainer.new()
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = section["bg_color"]
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		panel.add_theme_stylebox_override("panel", style)
		var lines_box: VBoxContainer = VBoxContainer.new()
		for line in section["lines"]:
			var label: Label = Label.new()
			label.text = line["text"]
			label.add_theme_color_override("font_color", line["color"])
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lines_box.add_child(label)
		panel.add_child(lines_box)
		_sections.add_child(panel)
	_icon_backing.visible = icon != null
	if icon != null:
		_icon.texture = icon
		_icon_backing.color = icon_color
	_root.visible = true
	_position_near(anchor)


func hide_tooltip() -> void:
	_root.visible = false


func _position_near(anchor: Control) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var pos: Vector2 = anchor.global_position + Vector2(anchor.size.x + 8.0, 0.0)
	var tooltip_size: Vector2 = _root.size
	pos.x = clampf(pos.x, EDGE_MARGIN, maxf(EDGE_MARGIN, viewport_size.x - tooltip_size.x - EDGE_MARGIN))
	pos.y = clampf(pos.y, EDGE_MARGIN, maxf(EDGE_MARGIN, viewport_size.y - tooltip_size.y - EDGE_MARGIN))
	_root.position = pos
