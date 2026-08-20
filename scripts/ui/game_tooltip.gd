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
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lines_box: VBoxContainer = VBoxContainer.new()
		lines_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_position_near.call_deferred(anchor)


func hide_tooltip() -> void:
	_root.visible = false


# Deferred so the just-built section Labels' autowrap has actually resolved
# a real minimum size before tooltip_size is read below - reading it in the
# same frame the Labels were built measures each wrapping Label at ~0 width
# (one word per line), producing a wildly-tall bogus size that clamps the
# tooltip to the top of the screen regardless of where the anchor is.
# anchor is untyped (not `: Control`) on purpose: call_deferred marshals its
# argument through Godot's message queue, and if the anchor is freed between
# the deferred call being queued and it actually running, the engine can't
# even check a *typed* Control parameter's class against a dead instance -
# that fails at the engine level with "Cannot convert argument 1 from Object
# to Object" before this function's own is_instance_valid() guard ever runs.
# An untyped parameter skips that engine-side check, so the guard below is
# what actually catches a freed anchor.
func _position_near(anchor) -> void:
	if not _root.visible or not is_instance_valid(anchor):
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var pos: Vector2 = anchor.global_position + Vector2(anchor.size.x + 8.0, 0.0)
	# get_combined_minimum_size(), not _root.size: a Control only ever grows
	# to fit a bigger minimum size, it never shrinks back down on its own -
	# so after a long tooltip, _root.size stays stuck at that old, larger
	# size even once a shorter tooltip's Labels report a smaller minimum.
	# get_combined_minimum_size() recomputes fresh from the current content
	# every time, instead of trusting that stale, sticky property. Assigning
	# it back to _root.size below is what actually shrinks the tooltip's own
	# rendered box to match - without this line the box itself stays stuck
	# at whatever the largest tooltip shown so far needed.
	var tooltip_size: Vector2 = _root.get_combined_minimum_size()
	_root.size = tooltip_size
	pos.x = clampf(pos.x, EDGE_MARGIN, maxf(EDGE_MARGIN, viewport_size.x - tooltip_size.x - EDGE_MARGIN))
	pos.y = clampf(pos.y, EDGE_MARGIN, maxf(EDGE_MARGIN, viewport_size.y - tooltip_size.y - EDGE_MARGIN))
	_root.position = pos
