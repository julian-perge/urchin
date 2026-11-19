# game_tooltip.gd
# Shared rich tooltip, replacing both the abilities-screen's old single-panel
# AbilityTooltip and every other tooltip's plain Godot tooltip_text (which
# can only render one uniform box, one text color - it can't reproduce the
# original's title-bar/colored-info-bar/body look at all). A tooltip is a
# stack of sections (scripts/ui/tooltip_theme.gd's colors); each section is
# its own background box holding one or more independently-colored lines -
# see spec/old/2026-08-20-rich-tooltip-rework-design.md.
extends CanvasLayer

const EDGE_MARGIN: float = 4.0
const ANCHOR_GAP: float = 8.0
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


func _ready() -> void:
	_sections.add_theme_constant_override("separation", FIELD_SPACING)


# sections: Array[Dictionary], each {"bg_color": Color, "lines":
# Array[Dictionary]} where a line is {"text": String, "color": Color}.
# anchor: the hovered control, used to position this tooltip beside it.
# icon/icon_color are optional - only the abilities screen uses them today.
# text_width: the width every line wraps at, one of TooltipTheme's
# TEXT_WIDTH_* for the original layout the tooltip stands in for.
# rarity: the original's name for an item's rarity, such as "Rare", which tints
# the title's gradient. Only item slots pass one, so every other tooltip's
# title is untinted (ADR 0005).
func show_sections(
	sections: Array,
	anchor: Control,
	icon: Texture2D = null,
	icon_color: Color = Color.WHITE,
	text_width: float = TooltipTheme.TEXT_WIDTH_PLAIN,
	rarity: String = ""
) -> void:
	for child in _sections.get_children():
		child.free()
	_sections.custom_minimum_size.x = text_width + 2.0 * TEXT_GUTTER
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
	_root.visible = true
	_position_near.call_deferred(anchor)


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
	var pos: Vector2 = anchor.global_position + Vector2(anchor.size.x + ANCHOR_GAP, 0.0)
	# To the anchor's right is the first choice. Clamping a tooltip that
	# overruns the right edge slides it back over the very thing it describes,
	# which is what the rightmost class-select card hit, so flip to the
	# anchor's left side when the right does not fit and the left does. The
	# clamp below still catches an anchor with room on neither side.
	if pos.x + tooltip_size.x > viewport_size.x - EDGE_MARGIN:
		var flipped: float = anchor.global_position.x - tooltip_size.x - ANCHOR_GAP
		if flipped >= EDGE_MARGIN:
			pos.x = flipped
	pos.x = clampf(pos.x, EDGE_MARGIN, maxf(EDGE_MARGIN, viewport_size.x - tooltip_size.x - EDGE_MARGIN))
	pos.y = clampf(pos.y, EDGE_MARGIN, maxf(EDGE_MARGIN, viewport_size.y - tooltip_size.y - EDGE_MARGIN))
	_root.position = pos
