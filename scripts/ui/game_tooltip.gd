# game_tooltip.gd
# Shared rich tooltip, replacing both the abilities-screen's old single-panel
# AbilityTooltip and every other tooltip's plain Godot tooltip_text (which
# can only render one uniform box, one text color - it can't reproduce the
# original's title-bar/colored-info-bar/body look at all). A tooltip is a
# stack of sections (scripts/ui/tooltip_theme.gd's colors); each section is
# its own background box holding one or more independently-colored lines -
# see spec/old/2026-08-20-rich-tooltip-rework-design.md.
extends CanvasLayer

# Every text field KrinToolTipper draws a backer behind has border = true, and
# no script sets borderColor, so Flash draws a 1 px black line at the field's
# edges (DefineSprite_2717/frame_4/DoAction.as:36 and 54,
# DefineSprite_2717/frame_13/DoAction.as:28, 88 and 98, and
# DefineSprite_2717/frame_17/DoAction.as:24, 41, 65 and 83). Each section
# stands in for one bordered field.
const BORDER_WIDTH: int = 1
const BORDER_COLOR: Color = Color.BLACK
# A Flash text field keeps 2 px between its edges and its text. Each line
# stands in for one of KrinToolTipper's text fields, so every line pads its
# own text by 2 px on each side and a section's backing adds nothing around
# its lines.
const TEXT_GUTTER: float = 2.0
# KrinToolTipper starts each text field 2 px below the one above it
# (DefineSprite_2717/frame_13/DoAction.as:48 and
# DefineSprite_2717/frame_17/DoAction.as:38), so lines sit 2 px apart whether
# or not they share a section.
const FIELD_SPACING: int = 2

@onready var _root: HBoxContainer = $Root
@onready var _icon_backing: ColorRect = $Root/IconBacking
@onready var _icon: TextureRect = $Root/IconBacking/Icon
@onready var _sections: VBoxContainer = $Root/Sections

# Where the mouse is, in Stage px. Tests swap it for a fixed point, because a
# headless run has no mouse to move.
var mouse_source: Callable = func() -> Vector2: return get_viewport().get_mouse_position()
var _anchor: Control = null
var _layout: Dictionary = {}
# Seconds left before the sections under the title show, for an ability icon's
# tooltip.
var _detail_wait: float = 0.0


func _ready() -> void:
	_sections.add_theme_constant_override("separation", FIELD_SPACING)


# sections: Array[Dictionary], each {"bg_color": Color, "lines":
# Array[Dictionary]} where a line is {"text": String, "color": Color}.
# anchor: the hovered control. The tooltip hides when it leaves the tree.
# icon/icon_color are optional - only the abilities screen uses them today.
# text_width: the width every line wraps at, one of TooltipTheme's
# TEXT_WIDTH_* for the original layout the tooltip stands in for.
# rarity: the original's name for an item's rarity, such as "Rare", which tints
# the title's gradient. Only item slots pass one, so every other tooltip's
# title is untinted (ADR 0005).
# detail_delay: show the title alone for the original's ability icon delay
# first, as the icons of the Abilities window and the battle's orbs do.
func show_sections(
	sections: Array,
	anchor: Control,
	icon: Texture2D = null,
	icon_color: Color = Color.WHITE,
	text_width: float = TooltipTheme.TEXT_WIDTH_PLAIN,
	rarity: String = "",
	detail_delay: bool = false
) -> void:
	for child in _sections.get_children():
		child.free()
	var line_width: float = text_width + 2.0 * TEXT_GUTTER
	_sections.custom_minimum_size.x = line_width
	var gutter: StyleBoxEmpty = StyleBoxEmpty.new()
	gutter.set_content_margin_all(TEXT_GUTTER)
	for section_index in sections.size():
		var section: Dictionary = sections[section_index]
		var panel: PanelContainer = PanelContainer.new()
		var gloss_add: Variant = _gloss_add(section, section_index, rarity)
		if gloss_add == null:
			var style: StyleBoxFlat = StyleBoxFlat.new()
			style.bg_color = section["bg_color"]
			panel.add_theme_stylebox_override("panel", style)
		else:
			panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lines_box: VBoxContainer = VBoxContainer.new()
		lines_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines_box.add_theme_constant_override("separation", FIELD_SPACING)
		for line in section["lines"]:
			var label: Label = Label.new()
			label.text = line["text"]
			# The original also indents the first line of every field, the
			# title by 3 px and the rest by 2
			# (DefineSprite_2717/frame_4/DoAction.as:44 and 63).
			# Label has no first-line indent, so the port leaves it out.
			label.add_theme_stylebox_override("normal", gutter)

			# The original's tooltip clip, DefineSprite 2717, makes only its
			# title field bold and draws every other field in regular _sans
			# (DefineSprite_2717/frame_4/DoAction.as:40-64). Every caller puts
			# the title in the first section, so that section keeps the
			# project theme's bold face and every later section switches to
			# RegularLabel.
			if section_index > 0:
				label.theme_type_variation = &"RegularLabel"
			label.add_theme_font_size_override("font_size", TooltipTheme.FONT_SIZE)
			label.add_theme_color_override("font_color", line["color"])
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			# A wrapping Label is as tall as its text wrapped at its own width, and
			# a new Label is 0 px wide. A container sets a child's width only when
			# it sorts, at the end of the frame, and it skips a hidden child. So
			# each Label starts at the width that the sort gives it. Without this,
			# the tooltip took the height of text wrapped at 0 px for one frame, on
			# the frame it showed or on the frame its details showed (#491).
			label.size.x = line_width
			lines_box.add_child(label)
		panel.add_child(lines_box)
		if gloss_add != null:
			panel.add_child(_gloss_rect(gloss_add))
		panel.add_child(_border())
		_sections.add_child(panel)
	_icon_backing.visible = icon != null
	if icon != null:
		_icon.texture = icon
		_icon_backing.color = icon_color
	_anchor = anchor
	_layout = TooltipTheme.layout_for_width(text_width)
	_detail_wait = 0.0
	if detail_delay:
		_detail_wait = float(TooltipTheme.look()["detail_delay_frames"]) / float(TooltipTheme.look()["frame_rate"])
		_show_details(false)
	_root.visible = true
	# The sections move right of the icon only when Root sorts, at the end of
	# this frame, so the first placement waits until then.
	_follow.call_deferred()


# This shows the GO layout of the original's KrinToolTipper, the title field tt
# over the text field t. The hotbar buttons, the orbs and the World map's zones
# all set the tooltip this way.
func show_title_and_body(title: String, body: String, anchor: Control) -> void:
	show_sections([
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": title, "color": TooltipTheme.TEXT_TITLE}]},
		{"bg_color": TooltipTheme.BG_BODY, "lines": [{"text": body, "color": TooltipTheme.TEXT_BODY}]},
	], anchor)


func hide_tooltip() -> void:
	_root.visible = false


func is_showing() -> bool:
	return _root.visible


# -> the section boxes, title first, as show_sections() built them.
func sections() -> Array[Node]:
	return _sections.get_children()


# -> the Label that shows one line of one section.
func line_label(section_index: int, line_index: int = 0) -> Label:
	return _sections.get_child(section_index).get_child(0).get_child(line_index)


# -> every line's Label, title first.
func labels() -> Array[Node]:
	return _sections.find_children("*", "Label", true, false)


func icon_texture() -> Texture2D:
	return _icon.texture


# -> the top left corner of the sections, where the text column starts, in
# Stage px. The icon, when there is one, sits to its left.
func sections_position() -> Vector2:
	return _sections.global_position


# -> the top left corner of the whole tooltip, icon included, in Stage px.
func box_position() -> Vector2:
	return _root.global_position


# -> the size of the whole tooltip, icon included, in Stage px.
func box_size() -> Vector2:
	return _root.size


# -> the add terms to draw a section's 2715 gradient with, or null for a section
# with a flat fill. BG_HEADER and BG_COST name the two gradient bars
# (scripts/ui/tooltip_theme.gd). The title takes the rarity's terms, as
# krinChangeColor tints fontBacker2 in the GO and GO4 layouts
# (DefineSprite_2717/frame_4/DoAction.as:6-9).
func _gloss_add(section: Dictionary, section_index: int, rarity: String) -> Variant:
	var color: Color = section["bg_color"]
	if color == TooltipTheme.BG_COST:
		return TooltipTheme.look()["subheader_add"]["GO2"]
	if color != TooltipTheme.BG_HEADER:
		return null
	if section_index == 0 and rarity != "":
		return TooltipTheme.look()["rarity_add"][rarity]
	return [0, 0, 0]


# The gradient runs from the field's top edge to its bottom edge whatever the
# field's height, because the frame scripts stretch the backer to the field.
# It draws behind its section's lines through show_behind_parent, so the lines
# stay the section's first child.
func _gloss_rect(add: Array) -> TextureRect:
	var gradient: Gradient = Gradient.new()
	var offsets: PackedFloat32Array = PackedFloat32Array()
	var colors: PackedColorArray = PackedColorArray()
	for stop: Array in TooltipTheme.gloss_stops(add):
		offsets.append(stop[0])
		colors.append(stop[1])
	gradient.offsets = offsets
	gradient.colors = colors
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	texture.width = 1
	texture.height = 256
	var rect: TextureRect = TextureRect.new()
	rect.name = "Gloss"
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.show_behind_parent = true
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


# The border draws over the section's fill and inside its 2 px text gutter, so
# it changes no size.
func _border() -> Panel:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(BORDER_WIDTH)
	style.border_color = BORDER_COLOR
	var border: Panel = Panel.new()
	border.name = "Border"
	border.add_theme_stylebox_override("panel", style)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return border


func _process(delta: float) -> void:
	if not _root.visible:
		return
	if not is_instance_valid(_anchor) or not _anchor.is_inside_tree():
		hide_tooltip()
		return
	if _detail_wait > 0.0:
		_detail_wait -= delta
		if _detail_wait <= 0.0:
			_show_details(true)
	_follow()


# The ability icon plays GO3, the title alone, until its hitter count reaches
# the threshold, then GO7 or GO2 with every field
# (DefineSprite_2427/frame_1/PlaceObject2_2241_11/CLIPACTIONRECORD
# onClipEvent(enterFrame).as:17-32).
func _show_details(shown: bool) -> void:
	for i in range(1, _sections.get_child_count()):
		_sections.get_child(i).visible = shown


# KrinToolTipper drags its origin to the mouse on every frame, and its frame
# scripts put the fields' left edge at near_x from the origin, or at far_x when
# the mouse is at mouse_x_limit or further right. The GO layout also moves
# every field by low_shift_y when the mouse is below mouse_y_limit
# (DefineSprite_2717/frame_4/DoAction.as:17-32). The title's top is at the
# origin. Then the tooltip is kept inside the Stage (ADR 0012).
func _follow() -> void:
	if not _root.visible:
		return
	var mouse: Vector2 = mouse_source.call()
	# A Control never shrinks back to a smaller minimum size by itself, so a
	# short tooltip after a long one sets its size from its content.
	var tooltip_size: Vector2 = _root.get_combined_minimum_size()
	_root.size = tooltip_size
	var offset_x: float = float(_layout["near_x"])
	if mouse.x >= float(_layout["mouse_x_limit"]):
		offset_x = float(_layout["far_x"])
	var offset_y: float = 0.0
	if _layout.has("low_shift_y") and mouse.y > float(_layout["mouse_y_limit"]):
		offset_y = float(_layout["low_shift_y"])
	var pos: Vector2 = Vector2(mouse.x + offset_x - _sections.position.x, mouse.y + offset_y)
	var stage: Vector2 = get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 0.0, maxf(0.0, stage.x - tooltip_size.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, stage.y - tooltip_size.y))
	_root.position = pos
