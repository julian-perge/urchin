# victory_screen_prototype.gd
# PROTOTYPE for julian-perge/urchin#108, throwaway. It lives on the branch
# prototype/victory-containers and is never merged.
#
# Question: can the victory screen be rebuilt on native containers whose
# separation, margins and minimum sizes come from the SWF, and still land
# where the original draws KRINMENU's win frame? What can't containers
# express?
#
# Run from the repo root:
#   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/battle/victory_screen_prototype.tscn
#
# Three variants of the screen over a static battle hall, switched with the
# yellow bar at the bottom or the Left and Right keys:
#   A  the current scenes/battle/victory_screen.tscn, unchanged
#   B  every panel a PanelContainer at its win frame rect with StyleBoxFlat
#      panels built from the shape records, VBox, HBox and Grid containers
#      inside, and every separation and minimum size rounded to a whole pixel
#      before a box gets it
#   C  the same tree, with the extracted panel art in zero-margin
#      StyleBoxTextures, and FloatBox, below, where B rounds
# O cycles the ffdec render of the win frame over the screen: off, 50%, then
# a difference view. M cycles the mode: live shows a real-looking win, ref
# shows the SWF's own placeholder strings and empty slots, the state ffdec
# draws, chrome hides every text, and panels shows only the backdrop and the
# panels. Every switch prints each piece's rect against its SWF rect.
#
# Arguments after "--": --variant=A|B|C, --mode=live|ref|chrome|panels,
# --overlay=0|1|2, --clean hides the bar, --sentinel also hides the hall and
# clears to magenta so a capture shows what the screen draws, --shift=<piece>:<dx>
# moves one panel, --panel-art=shadow|plain picks C's panel art,
# --b-ceil hands B the unrounded sizes so BoxContainer rounds them up itself,
# --flat-backdrop draws B's backdrop as a flat fill, --no-snap turns off the
# viewport's control and 2D transform pixel snapping, and --dump=<path> saves
# the full window framebuffer once the screen has settled.
#
# Numbers come from dev/prototypes/victory_containers/win_layout.json and
# art.json, written by win_layout.py and render_art.py from the SWF.
extends Control

const PROTO_DIR: String = "res://dev/prototypes/victory_containers"
const VARIANTS: Array[String] = ["A", "B", "C"]
const VARIANT_NAMES: Dictionary = {
	"A": "current screen",
	"B": "containers, flat panels",
	"C": "containers, texture panels, float pitches",
}
const MODES: Array[String] = ["live", "ref", "chrome", "panels"]
const OVERLAY_NAMES: Array[String] = ["off", "ref 50%", "difference x4"]
const PANEL_ORDER: Array[String] = ["left", "centre", "right", "bar"]
const ROW_ORDER: Array[String] = ["player", "friend1", "friend2"]
const HALL: String = "JAIL"

# The live win: Sonny with Veradux and Roald, four drops and a part-full
# inventory. Strings are the ones the current screen already shows.
const LIVE_TEXT: Dictionary = {
	"vbbc1": "Character Experience",
	"vbbc0": "Your Inventory",
	"vb1": "Victory! Items that dropped:",
	"vb2": "CLICK on the items that you wish to keep!",
	"vb3": "Money gained:",
	"vb4": "Exp. gained:",
	"vb5": "€312",
	"vb6": "38%",
	"vb7": "Once you are finished, press below to proceed:",
	"vb8": "Proceed!",
	"vb99": "",
	"euro_sign": "€",
	"dumbEuro": "12345",
}
const LIVE_ROWS: Dictionary = {
	"player": {"face": "mainPlayer", "name": "Sonny", "level": 12, "exp": 64.0},
	"friend1": {"face": "Veradux", "name": "Veradux", "level": 11, "exp": 40.0},
	"friend2": {"face": "Roald", "name": "Roald", "level": 10, "exp": 87.0},
}
# ffdec draws the face sheet's frame 1, Veradux, in every row, so A shows
# that portrait in the ref, chrome and panels modes.
const PORTRAITS_A: Dictionary = {"Veradux": "portraits/veradux.png"}
const LIVE_DROPS: Array[int] = [102, 108, 113, 116]
const LIVE_INVENTORY: Array[int] = [100, 101, 103, 104, 105, 106, 107, 109, 110, 111, 112, 114, 115, 117, 118, 119]

var _layout: Dictionary
var _art: Dictionary
var _textures: Dictionary = {}
var _variant_index: int = 1
var _mode: String = "live"
var _overlay_state: int = 0
var _clean: bool = false
var _sentinel: bool = false
var _shift_piece: String = ""
var _shift_dx: float = 0.0
var _panel_art: String = "shadow"
var _b_ceil: bool = false
var _flat_backdrop: bool = false
var _dump_path: String = ""

var _context: Control
var _host: Control
var _overlay: TextureRect
var _diff_material: ShaderMaterial
var _switcher: PanelContainer
var _switch_label: Label
# Every piece the rect printout reports, with its node, its SWF rect and
# whether it is a panel, a box or a text.
var _pieces: Array[Dictionary] = []
# Every node a mode hides, with whether it is art, text, or a button whose
# backing is art and whose label is text.
var _layered: Array[Dictionary] = []
var _last_summary: String = ""


# A container that lays its children out in a row or a column like
# BoxContainer, but at float positions and float sizes, where BoxContainer
# rounds each child's minimum size up and offsets in whole pixels.
class FloatBox extends Container:
	var vertical: bool = true
	var separation: float = 0.0

	func _notification(what: int) -> void:
		if what != NOTIFICATION_SORT_CHILDREN:
			return
		var offset: float = 0.0
		for child in get_children():
			var c := child as Control
			if c == null or not c.visible or c.top_level:
				continue
			var minimum: Vector2 = c.get_combined_minimum_size()
			if vertical:
				fit_child_in_rect(c, Rect2(0.0, offset, size.x, minimum.y))
				offset += minimum.y + separation
			else:
				fit_child_in_rect(c, Rect2(offset, 0.0, minimum.x, size.y))
				offset += minimum.x + separation

	func _get_minimum_size() -> Vector2:
		var along: float = 0.0
		var cross: float = 0.0
		var count: int = 0
		for child in get_children():
			var c := child as Control
			if c == null or not c.visible or c.top_level:
				continue
			var minimum: Vector2 = c.get_combined_minimum_size()
			along += minimum.y if vertical else minimum.x
			cross = maxf(cross, minimum.x if vertical else minimum.y)
			count += 1
		along += separation * maxi(count - 1, 0)
		return Vector2(cross, along) if vertical else Vector2(along, cross)


func _ready() -> void:
	_parse_args()
	_layout = _read_json(PROTO_DIR + "/win_layout.json")
	_art = _read_json(PROTO_DIR + "/art.json")
	_context = _build_context()
	add_child(_context)
	_host = Control.new()
	_host.name = "VariantHost"
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_host)
	_build_overlay()
	_build_switcher()
	if _sentinel:
		_context.hide()
		RenderingServer.set_default_clear_color(Color.MAGENTA)
	if _clean or _sentinel or not OS.is_debug_build():
		_switcher.hide()
	await _show_variant()
	if not _dump_path.is_empty():
		await _dump_framebuffer()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		var key: String = parts[0]
		var value: String = parts[1] if parts.size() > 1 else ""
		match key:
			"variant":
				_variant_index = maxi(VARIANTS.find(value.to_upper()), 0)
			"mode":
				if value in MODES:
					_mode = value
			"overlay":
				_overlay_state = clampi(int(value), 0, 2)
			"clean":
				_clean = true
			"sentinel":
				_sentinel = true
			"shift":
				var shift: PackedStringArray = value.split(":")
				_shift_piece = shift[0]
				_shift_dx = float(shift[1]) if shift.size() > 1 else 20.0
			"panel-art":
				_panel_art = value
			"b-ceil":
				_b_ceil = true
			"flat-backdrop":
				_flat_backdrop = true
			"dump":
				_dump_path = value
			"no-snap":
				get_viewport().gui_snap_controls_to_pixels = false
				get_viewport().snap_2d_transforms_to_pixel = false


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("prototype: missing %s, run the scripts in %s first" % [path, PROTO_DIR])
		return {}
	return JSON.parse_string(file.get_as_text())


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_LEFT:
			_cycle(-1)
		KEY_RIGHT:
			_cycle(1)
		KEY_O:
			_overlay_state = (_overlay_state + 1) % OVERLAY_NAMES.size()
			_apply_overlay()
			_update_switch_label()
		KEY_M:
			_mode = MODES[(MODES.find(_mode) + 1) % MODES.size()]
			_show_variant()
		_:
			return
	get_viewport().set_input_as_handled()


func _cycle(step: int) -> void:
	_variant_index = wrapi(_variant_index + step, 0, VARIANTS.size())
	_show_variant()


func _show_variant() -> void:
	for child in _host.get_children():
		_host.remove_child(child)
		child.queue_free()
	_pieces.clear()
	_layered.clear()
	var variant: String = VARIANTS[_variant_index]
	match variant:
		"A":
			_build_current()
		"B":
			_host.add_child(_build_containers(false, false))
		"C":
			_host.add_child(_build_containers(true, true))
	_apply_mode()
	# Containers sort on the frame after their children change.
	await get_tree().process_frame
	await get_tree().process_frame
	_apply_shift()
	_apply_overlay()
	_print_rects()
	_update_switch_label()


# --- context -----------------------------------------------------------------


# The battle hall the victory screen opens over, built the way battle_scene.gd
# loads it: black above the sky strip, the sky at its battle_layout.json rect,
# the hall covering the window, and the bottom bar's art at the scene's own
# offsets.
func _build_context() -> Control:
	var context := Control.new()
	context.name = "BattleHall"
	context.mouse_filter = Control.MOUSE_FILTER_IGNORE
	context.set_anchors_preset(Control.PRESET_FULL_RECT)
	var battle_layout: Dictionary = _read_json("res://assets/backgrounds/battle/battle_layout.json")
	var sky_rect: Dictionary = battle_layout["skies"][HALL]
	var fill := ColorRect.new()
	fill.color = Color.BLACK
	fill.size = Vector2(800, float(sky_rect["y"]) + 2.0)
	context.add_child(fill)
	var sky := TextureRect.new()
	sky.texture = load("res://assets/backgrounds/sky/SKY_%s.png" % HALL)
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.position = Vector2(float(sky_rect["x"]), float(sky_rect["y"]))
	sky.size = Vector2(float(sky_rect["w"]), float(sky_rect["h"]))
	context.add_child(sky)
	var hall := TextureRect.new()
	hall.texture = load("res://assets/backgrounds/battle/%s.png" % HALL)
	hall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hall.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	hall.set_anchors_preset(Control.PRESET_FULL_RECT)
	context.add_child(hall)
	var bar := Control.new()
	bar.position = Vector2(0, 470)
	context.add_child(bar)
	var bar_art := TextureRect.new()
	bar_art.texture = load("res://assets/ui/battle/hotbar_background.png")
	bar_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar_art.size = Vector2(800, 130)
	bar.add_child(bar_art)
	for rect in [Rect2(12, 10, 320, 110), Rect2(340, 10, 120, 110), Rect2(468, 10, 320, 110)]:
		var panel := TextureRect.new()
		panel.texture = load("res://assets/ui/hotbar/background.png")
		panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		panel.position = rect.position
		panel.size = rect.size
		bar.add_child(panel)
	for child in context.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return context


# --- variant A ----------------------------------------------------------------


func _build_current() -> void:
	var screen: VictoryScreen = preload("res://scenes/battle/victory_screen.tscn").instantiate()
	screen.name = "VariantA"
	var save := _live_save()
	var rewards := {"money_gained": 312, "xp_gained": 38}
	var drops: Array = LIVE_DROPS.duplicate()
	if _mode != "live":
		drops = []
		for i in 15:
			drops.append(0)
	# battle_scene.gd adds the screen before calling setup(), so its onready
	# nodes and its inventory panel exist by then.
	_host.add_child(screen)
	screen.setup(save, rewards, drops, [1, 2])
	var rows: Array[Node] = screen.get_children().filter(func(n): return n is VictoryExperienceRow)
	var slots: Array[Node] = screen.get_children().filter(func(n): return n is ItemSlot)
	var inventory: InventoryPanel = screen.inventory_panel
	if _mode != "live":
		for slot in slots:
			slot.set_item(null)
		for i in inventory.inventory_grid.get_child_count():
			(inventory.inventory_grid.get_child(i) as ItemSlot).set_item(null)
		var texts: Dictionary = _ref_texts()
		screen.get_node("ExperienceLabel").text = texts["vbbc1"]
		screen.get_node("DropsLabel").text = texts["vb1"]
		screen.get_node("ClickHintLabel").text = texts["vb2"]
		screen.get_node("MoneyLabel").text = texts["vb3"]
		screen.get_node("MoneyValue").text = texts["vb5"]
		screen.get_node("ExpLabel").text = texts["vb4"]
		screen.get_node("ExpValue").text = texts["vb6"]
		screen.get_node("ProceedHintLabel").text = texts["vb7"]
		screen.get_node("ProceedButton").text = texts["vb8"]
		inventory.get_node("TitleLabel").text = texts["vbbc0"]
		inventory.gold_label.text = texts["dumbEuro"]
		for row in rows:
			var r := row as VictoryExperienceRow
			r.setup(PORTRAITS_A["Veradux"], _layout["row_pieces"]["name"]["initial_text"], 0, 100.0)
			r.level_label.text = _layout["row_pieces"]["level"]["initial_text"]
			r.percent_label.text = _layout["row_pieces"]["percent"]["initial_text"]

	_track("backdrop", screen.get_node("Backdrop"), _rect(_layout["backdrop"]["rect"]), "panel")
	_track("panel left", screen.get_node("LeftPanel"), _rect(_layout["panels"]["left"]["rect"]), "panel")
	_track("panel centre", screen.get_node("MiddlePanel"), _rect(_layout["panels"]["centre"]["rect"]), "panel")
	_track("panel right", inventory.get_node("PanelBackground"), _rect(_layout["panels"]["right"]["rect"]), "panel")
	_track("panel bar", inventory.get_node("BarBackground"), _rect(_layout["panels"]["bar"]["rect"]), "panel")
	for i in mini(rows.size(), ROW_ORDER.size()):
		var row := rows[i] as VictoryExperienceRow
		var role: String = ROW_ORDER[i]
		_track("row %s face" % role, row.face, _face_rect(role), "box")
		_track("row %s bar track" % role, row.get_node("ExpTrack"), _row_rect(role, _layout["row_pieces"]["overlay"]["rect"]), "box")
		_track("row %s name" % role, row.name_label, _row_rect(role, _layout["row_pieces"]["name"]["rect"]), "text")
		_track("row %s level" % role, row.level_label, _row_rect(role, _layout["row_pieces"]["level"]["rect"]), "text")
		_track("row %s percent" % role, row.percent_label, _row_rect(role, _layout["row_pieces"]["percent"]["rect"]), "text")
	if not slots.is_empty():
		_track("drop grid", null, _drop_rect(slots.size()), "box", _union_rect(slots))
	_track("item grid", inventory.inventory_grid, _rect(_layout["item_grid"]["rect"]), "box")
	var text_nodes: Dictionary = {
		"vbbc1": screen.get_node("ExperienceLabel"),
		"vb1": screen.get_node("DropsLabel"),
		"vb2": screen.get_node("ClickHintLabel"),
		"vb3": screen.get_node("MoneyLabel"),
		"vb5": screen.get_node("MoneyValue"),
		"vb4": screen.get_node("ExpLabel"),
		"vb6": screen.get_node("ExpValue"),
		"vb7": screen.get_node("ProceedHintLabel"),
		"vbbc0": inventory.get_node("TitleLabel"),
		"dumbEuro": inventory.gold_label,
	}
	for key in text_nodes:
		_track("text " + key, text_nodes[key], _rect(_layout["texts"][key]["rect"]), "text")
	_track("proceed button", screen.get_node("ProceedButton"), _rect(_layout["proceed"]["rect"]), "box")

	for node in text_nodes.values():
		_layer(node, "text")
	_layer(screen.get_node("ProceedButton"), "button")
	for row in rows:
		var r := row as VictoryExperienceRow
		_layer(r, "art")
		for label in [r.name_label, r.level_label, r.percent_label]:
			_layer(label, "text")
	for slot in slots:
		_layer(slot, "art")
	_layer(inventory.inventory_grid, "art")
	_layer(inventory.get_node("SellItemButton"), "art")
	_layer(inventory.get_node("DeleteItemButton"), "art")


# --- variants B and C -------------------------------------------------------


func _build_containers(texture_panels: bool, float_pitches: bool) -> Control:
	var root := Control.new()
	root.name = "VariantC" if texture_panels else "VariantB"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	var backdrop := PanelContainer.new()
	backdrop.name = "Backdrop"
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.add_theme_stylebox_override("panel", _backdrop_style(texture_panels))
	_place(backdrop, _rect(_layout["backdrop"]["rect"]))
	root.add_child(backdrop)
	_track("backdrop", backdrop, _rect(_layout["backdrop"]["rect"]), "panel")

	for panel_name in PANEL_ORDER:
		var spec: Dictionary = _layout["columns"][panel_name]
		var style: StyleBox = _panel_style(panel_name, texture_panels)
		var margins: Array = spec["content_margins"]
		style.content_margin_left = margins[0]
		style.content_margin_top = margins[1]
		style.content_margin_right = margins[2]
		style.content_margin_bottom = margins[3]
		var panel := PanelContainer.new()
		panel.name = "Panel_" + panel_name
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", style)
		_place(panel, _rect(_layout["panels"][panel_name]["rect"]))
		root.add_child(panel)
		_track("panel " + panel_name, panel, _rect(_layout["panels"][panel_name]["rect"]), "panel")
		var box: Container = _box(spec, float_pitches)
		panel.add_child(box)
		for child in spec["children"]:
			box.add_child(_slot(spec, child, float_pitches))
	return root


func _box(spec: Dictionary, float_pitches: bool) -> Container:
	var vertical: bool = spec["axis"] == "y"
	var box: Container
	if float_pitches:
		var floating := FloatBox.new()
		floating.vertical = vertical
		floating.separation = float(spec["separation"])
		box = floating
	else:
		if vertical:
			box = VBoxContainer.new()
		else:
			box = HBoxContainer.new()
		box.add_theme_constant_override("separation", roundi(float(spec["separation"])))
	box.name = "Column" if vertical else "Row"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


# One child of a panel's column: a plain Control whose size along the column
# is the pitch to the next child, holding its pieces at their SWF offsets
# from where the column should put it. The pieces' own SWF rects overlap the
# next child's in several places, so they can't be the box's direct children.
func _slot(spec: Dictionary, child: Dictionary, float_pitches: bool) -> Control:
	var vertical: bool = spec["axis"] == "y"
	var box: Array = spec["box"]
	var extent: float = float(child["extent"])
	if not float_pitches and not _b_ceil:
		extent = roundf(extent)
	var origin := Vector2(box[0], box[1] + float(child["offset"])) if vertical else Vector2(box[0] + float(child["offset"]), box[1])
	var id: String = child["id"]
	var slot: Control
	if id in ROW_ORDER:
		slot = _row(id)
	else:
		slot = Control.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.name = "Slot_" + id
	slot.custom_minimum_size = Vector2(0.0, extent) if vertical else Vector2(extent, 0.0)
	match id:
		"vbbc1", "vbbc0", "vb1", "vb2", "vb7", "euro_sign", "dumbEuro":
			slot.add_child(_text(id, origin))
		"drops":
			_drops(slot, origin)
		"money":
			slot.add_child(_text("vb3", origin))
			slot.add_child(_text("vb5", origin))
		"exp":
			slot.add_child(_text("vb4", origin))
			slot.add_child(_text("vb6", origin))
		"proceed":
			slot.add_child(_text("vb8", origin))
			var hit := Button.new()
			hit.name = "ProceedHit"
			hit.flat = true
			hit.focus_mode = Control.FOCUS_NONE
			for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
				hit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
			var rect := _rect(_layout["proceed"]["rect"])
			hit.position = rect.position - origin
			hit.size = rect.size
			hit.pressed.connect(func(): print("prototype: Proceed pressed"))
			slot.add_child(hit)
			_track("proceed button", hit, rect, "box")
		"items":
			_items(slot, origin)
		"delete":
			var art := _art_rect("delete_art", Vector2.ZERO, origin, 1.0)
			slot.add_child(art)
			_layer(art, "art")
	return slot


# One experience row, clip 3002: a PanelContainer drawing the extracted 3001
# outline and its drop shadow, with the face, the XP bar and the three texts
# at their offsets in the clip. The face is sized to the sheet's 1.6532 scale
# and keeps that size because it sits in a plain Control, not a container.
func _row(role: String) -> Control:
	var row := PanelContainer.new()
	var pieces: Dictionary = _layout["row_pieces"]
	var style := _texture_style("row_backing_shadow", Vector2.ONE)
	row.add_theme_stylebox_override("panel", style)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner := Control.new()
	inner.name = "Pieces"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(inner)
	var data: Dictionary = _row_data(role)
	var face_key: String = "face_" + data["face"]
	var face_offset := Vector2(pieces["face"]["offset"][0], pieces["face"]["offset"][1])
	var face := _art_rect(face_key, face_offset, Vector2.ZERO, float(pieces["face"]["scale"]))
	face.name = "Face"
	inner.add_child(face)
	var bar_rect: Array = pieces["bar"]["rect"]
	var fraction: float = clampf(float(data["exp"]) / 100.0, 0.0, 1.0)
	var fill := _art_rect("bar_fill", Vector2(bar_rect[0], bar_rect[1] - _art["bar_fill"]["shape_rect"][1]), Vector2.ZERO, 1.0)
	fill.name = "BarFill"
	fill.position.x = bar_rect[0] + float(_art["bar_fill"]["rect"][0]) * fraction
	fill.size.x = float(_art["bar_fill"]["rect"][2]) * fraction
	inner.add_child(fill)
	var overlay := _art_rect("bar_overlay", Vector2(pieces["overlay"]["rect"][0], pieces["overlay"]["rect"][1]) - Vector2(_art["bar_overlay"]["shape_rect"][0], _art["bar_overlay"]["shape_rect"][1]), Vector2.ZERO, 1.0)
	overlay.name = "BarOverlay"
	inner.add_child(overlay)
	for key in ["name", "level", "percent"]:
		var label := _label(pieces[key], data[key])
		var r: Array = pieces[key]["rect"]
		label.position = Vector2(r[0], r[1])
		label.name = key.capitalize()
		inner.add_child(label)
		_track("row %s %s" % [role, key], label, _row_rect(role, r), "text")
		_layer(label, "text")
	_track("row " + role, row, _rect(_layout["rows"][role]["rect"]), "box")
	_track("row %s face" % role, face, _face_rect(role), "box")
	_track("row %s bar track" % role, overlay, _row_rect(role, pieces["overlay"]["rect"]), "box", Rect2(), _art_offset("bar_overlay", 1.0))
	_layer(row, "art")
	return row


func _drops(slot: Control, origin: Vector2) -> void:
	var grid_spec: Dictionary = _layout["drop_grid"]
	var grid := _grid(grid_spec)
	grid.name = "DropGrid"
	grid.position = _rect(grid_spec["rect"]).position - origin
	var count: int = 15 if _mode != "live" else LIVE_DROPS.size()
	for i in int(grid_spec["columns"]) * int(grid_spec["rows"]):
		var item_slot: ItemSlot = preload("res://scenes/ui/item_slot.tscn").instantiate()
		grid.add_child(item_slot)
		item_slot.visible = i < count
		if _mode == "live" and i < LIVE_DROPS.size():
			item_slot.set_item(ItemManagerAuto.get_item(LIVE_DROPS[i]))
	slot.add_child(grid)
	_track("drop grid", grid, _drop_rect(count), "box")
	_layer(grid, "art")
	var none := _text("vb99", origin)
	slot.add_child(none)


# The original keeps all 15 drop slots at fixed places and hides the empty
# ones, which are always the last, so n drops fill the first n places.
func _drop_rect(count: int) -> Rect2:
	var grid_spec: Dictionary = _layout["drop_grid"]
	var columns: int = int(grid_spec["columns"])
	var used_columns: int = mini(count, columns)
	var used_rows: int = ceili(count / float(columns))
	var pitch := Vector2(grid_spec["pitch"][0], grid_spec["pitch"][1])
	var slot_size := Vector2(_layout["slot_size"][0], _layout["slot_size"][1])
	var r := _rect(grid_spec["rect"])
	return Rect2(r.position, Vector2((used_columns - 1) * pitch.x, (used_rows - 1) * pitch.y) + slot_size)


func _items(slot: Control, origin: Vector2) -> void:
	var grid_spec: Dictionary = _layout["item_grid"]
	var grid := _grid(grid_spec)
	grid.name = "ItemGrid"
	grid.position = _rect(grid_spec["rect"]).position - origin
	for i in int(grid_spec["columns"]) * int(grid_spec["rows"]):
		var item_slot: ItemSlot = preload("res://scenes/ui/item_slot.tscn").instantiate()
		grid.add_child(item_slot)
		if _mode == "live" and i < LIVE_INVENTORY.size():
			item_slot.set_item(ItemManagerAuto.get_item(LIVE_INVENTORY[i]))
	slot.add_child(grid)
	_track("item grid", grid, _rect(grid_spec["rect"]), "box")
	_layer(grid, "art")


func _grid(spec: Dictionary) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = int(spec["columns"])
	grid.add_theme_constant_override("h_separation", roundi(float(spec["separation"][0])))
	grid.add_theme_constant_override("v_separation", roundi(float(spec["separation"][1])))
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return grid


func _text(key: String, origin: Vector2) -> Label:
	var spec: Dictionary = _layout["texts"][key]
	var label := _label(spec, _texts()[key])
	var r := _rect(spec["rect"])
	label.name = "Text_" + key
	label.position = r.position - origin
	_track("text " + key, label, r, "text")
	_layer(label, "text")
	return label


# A Label in a DefineEditText's format. The field's bounds include Flash's
# 2 px gutter, so the label gets the bounds and a 2 px content margin.
func _label(spec: Dictionary, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", roundi(float(spec["font_height"])))
	label.add_theme_color_override("font_color", Color(spec["color"]))
	var gutter := StyleBoxEmpty.new()
	gutter.set_content_margin_all(2.0)
	label.add_theme_stylebox_override("normal", gutter)
	match spec.get("align", "left"):
		"center":
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		"right":
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if spec.get("word_wrap", false):
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if spec.get("font_id", 65) == 295:
		label.theme_type_variation = &"RegularLabel"
	for f in spec.get("filters", []):
		if f["type"] == "Glow":
			label.add_theme_color_override("font_outline_color", Color(f["color"]))
			label.add_theme_constant_override("outline_size", 4)
		elif f["type"] == "DropShadow" and not f["inner"]:
			label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
			label.add_theme_constant_override("shadow_offset_x", 1)
			label.add_theme_constant_override("shadow_offset_y", 1)
			label.add_theme_constant_override("shadow_outline_size", 4)
	# The size goes on last. A Control never shrinks back once it has grown,
	# so a label sized before its wrap mode is set stays as wide as its
	# unwrapped text.
	var r: Array = spec["rect"]
	label.size = Vector2(r[2], r[3])
	return label


func _texts() -> Dictionary:
	return LIVE_TEXT if _mode == "live" else _ref_texts()


# The SWF's own initial strings, which are what ffdec draws, since the
# frame's DoAction never runs there.
func _ref_texts() -> Dictionary:
	var result: Dictionary = {}
	for key in _layout["texts"]:
		result[key] = String(_layout["texts"][key]["initial_text"]).strip_edges()
	return result


func _row_data(role: String) -> Dictionary:
	if _mode == "live":
		var live: Dictionary = LIVE_ROWS[role]
		return {
			"face": live["face"],
			"name": live["name"],
			"level": "Lvl. %d" % live["level"],
			"percent": "%d%%" % int(live["exp"]),
			"exp": live["exp"],
		}
	var pieces: Dictionary = _layout["row_pieces"]
	# ffdec draws the face sheet's frame 1, Veradux, and the bar at its full
	# authored width.
	return {
		"face": "Veradux",
		"name": pieces["name"]["initial_text"],
		"level": pieces["level"]["initial_text"],
		"percent": pieces["percent"]["initial_text"],
		"exp": 100.0,
	}


func _live_save() -> PlayerSave:
	var save := PlayerSave.new()
	save.level = LIVE_ROWS["player"]["level"]
	save.experience = LIVE_ROWS["player"]["exp"]
	save.party_levels = [0, LIVE_ROWS["friend1"]["level"], LIVE_ROWS["friend2"]["level"], 1, 1, 1]
	save.party_exp = [0.0, LIVE_ROWS["friend1"]["exp"], LIVE_ROWS["friend2"]["exp"], 0.0, 0.0, 0.0]
	var items: Array = []
	for i in 37:
		items.append(LIVE_INVENTORY[i] if i < LIVE_INVENTORY.size() else 0)
	save.item_array = items
	save.euro = 12345.0
	return save


# --- styles and art -----------------------------------------------------------


func _panel_style(panel_name: String, texture_panels: bool) -> StyleBox:
	var panel: Dictionary = _layout["panels"][panel_name]
	var factor := Vector2(panel["scale"][0], panel["scale"][1])
	if texture_panels:
		return _texture_style("panel_%s_%s" % [panel_name, _panel_art], factor)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(panel["fills"][0]["color"])
	var line: Dictionary = panel["lines"][0]
	style.border_color = Color(line["color"])
	# StyleBoxFlat border widths are whole pixels. The SWF scales the 1 px
	# stroke with the panel, so it is the x scale wide on the sides and the y scale
	# on the top and bottom.
	style.border_width_left = maxi(roundi(float(line["width"]) * factor.x), 1)
	style.border_width_right = style.border_width_left
	style.border_width_top = maxi(roundi(float(line["width"]) * factor.y), 1)
	style.border_width_bottom = style.border_width_top
	return style


func _backdrop_style(texture_panels: bool) -> StyleBox:
	if _flat_backdrop and not texture_panels:
		var flat := StyleBoxFlat.new()
		flat.bg_color = _mean_color("backdrop")
		flat.border_color = Color.BLACK
		flat.set_border_width_all(1)
		return flat
	return _texture_style("backdrop", Vector2.ONE)


# A zero-margin StyleBoxTexture: the whole art stretches over the control,
# the way Flash scales a placed shape. The expand margins put the art's own
# anti-aliased or filtered edge where it sat around the shape in the render,
# scaled like the shape.
func _texture_style(key: String, factor: Vector2) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _texture(key)
	var art: Dictionary = _art[key]
	var a: Array = art["rect"]
	var s: Array = art["shape_rect"]
	style.expand_margin_left = (float(s[0]) - float(a[0])) * factor.x
	style.expand_margin_top = (float(s[1]) - float(a[1])) * factor.y
	style.expand_margin_right = ((float(a[0]) + float(a[2])) - (float(s[0]) + float(s[2]))) * factor.x
	style.expand_margin_bottom = ((float(a[1]) + float(a[3])) - (float(s[1]) + float(s[3]))) * factor.y
	return style


# A TextureRect showing one piece of art: `at` is where the art's own (0, 0)
# goes in the parent, before `origin` is taken off, and `factor` is the
# placement's scale.
func _art_rect(key: String, at: Vector2, origin: Vector2, factor: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = _texture(key)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a: Array = _art[key]["rect"]
	rect.position = at + Vector2(a[0], a[1]) * factor - origin
	rect.size = Vector2(a[2], a[3]) * factor
	return rect


# How far a TextureRect drawn by _art_rect sits from the shape it stands for,
# so its tracked rect can be compared with the shape's SWF rect.
func _art_offset(key: String, factor: float) -> Rect2:
	var a: Array = _art[key]["rect"]
	var s: Array = _art[key]["shape_rect"]
	return Rect2(
		(float(s[0]) - float(a[0])) * factor,
		(float(s[1]) - float(a[1])) * factor,
		(float(s[2]) - float(a[2])) * factor,
		(float(s[3]) - float(a[3])) * factor
	)


func _texture(key: String) -> Texture2D:
	if not _textures.has(key):
		var image := Image.load_from_file("%s/images/art/%s.png" % [PROTO_DIR, key])
		_textures[key] = ImageTexture.create_from_image(image)
	return _textures[key]


func _mean_color(key: String) -> Color:
	var image: Image = (_texture(key) as ImageTexture).get_image()
	var small := image.duplicate() as Image
	small.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	var color: Color = small.get_pixel(0, 0)
	color.a = 1.0
	return color


# --- geometry -------------------------------------------------------------------


func _rect(a: Array) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


func _place(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


func _row_rect(role: String, local: Array) -> Rect2:
	var row := _rect(_layout["rows"][role]["rect"])
	return Rect2(row.position + Vector2(local[0], local[1]), Vector2(local[2], local[3]))


# Where the face art sits on the stage: the row's corner, the face sheet's
# offset in the row, and the art's own rect scaled by the sheet's placement.
func _face_rect(role: String) -> Rect2:
	var row := _rect(_layout["rows"][role]["rect"])
	var face: Dictionary = _layout["row_pieces"]["face"]
	var a: Array = _art["face_Veradux"]["rect"]
	var factor: float = float(face["scale"])
	return Rect2(
		row.position + Vector2(face["offset"][0], face["offset"][1]) + Vector2(a[0], a[1]) * factor,
		Vector2(a[2], a[3]) * factor
	)


func _union_rect(nodes: Array) -> Rect2:
	var result := Rect2()
	var first := true
	for node in nodes:
		var r: Rect2 = (node as Control).get_global_rect()
		result = r if first else result.merge(r)
		first = false
	return result


# --- tracking, modes, overlay -------------------------------------------------


func _track(piece_name: String, node: Control, swf: Rect2, kind: String, fixed := Rect2(), adjust := Rect2()) -> void:
	_pieces.append({"name": piece_name, "node": node, "swf": swf, "kind": kind, "fixed": fixed, "adjust": adjust})


func _layer(node: CanvasItem, layer: String) -> void:
	_layered.append({"node": node, "layer": layer})


func _apply_mode() -> void:
	for entry in _layered:
		var node: CanvasItem = entry["node"]
		var layer: String = entry["layer"]
		if layer == "button":
			# A's Proceed button is a dark backing with its text on it, so
			# chrome keeps the backing and drops the text.
			var clear: bool = _mode in ["chrome", "panels"]
			for color in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
				if clear:
					node.add_theme_color_override(color, Color(0, 0, 0, 0))
			layer = "art"
		var hide_it: bool = (
			(_mode == "chrome" and layer == "text")
			or (_mode == "panels" and layer in ["text", "art"])
		)
		# Hidden with alpha, not visibility, so no box reflows.
		node.modulate.a = 0.0 if hide_it else 1.0


func _apply_shift() -> void:
	if _shift_piece.is_empty():
		return
	for piece in _pieces:
		if piece["name"] == "panel " + _shift_piece and piece["node"] != null:
			(piece["node"] as Control).position.x += _shift_dx
			print("prototype: shifted panel %s by %.1f px" % [_shift_piece, _shift_dx])


func _build_overlay() -> void:
	_overlay = TextureRect.new()
	_overlay.name = "ReferenceOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_overlay.position = Vector2.ZERO
	_overlay.size = Vector2(800, 600)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float gain = 4.0;
void fragment() {
	vec4 ref = texture(TEXTURE, UV);
	vec3 shown = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	COLOR = vec4(abs(shown - ref.rgb) * gain * ref.a, 1.0);
}
"""
	_diff_material = ShaderMaterial.new()
	_diff_material.shader = shader
	add_child(_overlay)


func _apply_overlay() -> void:
	var ref_mode: String = {"live": "full", "ref": "full", "chrome": "chrome", "panels": "panels"}[_mode]
	var key: String = "ref_" + ref_mode
	if not _textures.has(key):
		var image := Image.load_from_file("%s/images/ref/win_%s_2x.png" % [PROTO_DIR, ref_mode])
		_textures[key] = ImageTexture.create_from_image(image)
	_overlay.texture = _textures[key]
	_overlay.visible = _overlay_state != 0
	_overlay.material = _diff_material if _overlay_state == 2 else null
	_overlay.modulate.a = 0.5 if _overlay_state == 1 else 1.0


func _build_switcher() -> void:
	_switcher = PanelContainer.new()
	_switcher.name = "PrototypeSwitcher"
	var style := StyleBoxFlat.new()
	style.bg_color = Color("ffd84a")
	style.border_color = Color.BLACK
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 6
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	_switcher.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_switcher.add_child(row)
	row.add_child(_switch_button("<", -1))
	_switch_label = Label.new()
	_switch_label.theme_type_variation = &"RegularLabel"
	_switch_label.add_theme_color_override("font_color", Color.BLACK)
	_switch_label.add_theme_font_size_override("font_size", 11)
	_switch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_switch_label)
	row.add_child(_switch_button(">", 1))
	add_child(_switcher)


func _switch_button(text: String, step: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(26, 22)
	var style := StyleBoxFlat.new()
	style.bg_color = Color.BLACK
	style.set_corner_radius_all(10)
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color("ffd84a"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.pressed.connect(_cycle.bind(step))
	return button


func _update_switch_label() -> void:
	var variant: String = VARIANTS[_variant_index]
	_switch_label.text = "%s (%s)\nmode %s [M], overlay %s [O], %s" % [
		variant, VARIANT_NAMES[variant], _mode, OVERLAY_NAMES[_overlay_state], _last_summary
	]
	# Bottom centre, in the 25 px band under the SWF's 800x575 stage.
	_switcher.reset_size()
	_switcher.position = Vector2(roundf((800.0 - _switcher.size.x) / 2.0), 600.0 - _switcher.size.y - 3.0)


# --- reporting ------------------------------------------------------------------


# Where a control is drawn. Both gui/common/snap_controls_to_pixels and
# rendering/2d/snap/snap_2d_transforms_to_pixel round every canvas item's own
# offset from its parent to a whole design pixel before drawing
# (control.cpp:760-761 and renderer_canvas_cull.cpp:361-364 at 4.7.2-stable),
# so the drawn corner is the sum of each ancestor's rounded offset.
func _drawn_position(control: Control) -> Vector2:
	var at := Vector2.ZERO
	var node: Node = control
	while node is Control and node != self:
		at += ((node as Control).position + Vector2(0.5, 0.5)).floor()
		node = node.get_parent()
	return at


func _print_rects() -> void:
	var variant: String = VARIANTS[_variant_index]
	print("")
	print("== variant %s (%s), mode %s ==" % [variant, VARIANT_NAMES[variant], _mode])
	print("%-26s %-32s %-32s %8s %8s" % ["piece", "godot x, y, w, h", "swf x, y, w, h", "layout", "drawn"])
	var worst := {"panel": [0.0, ""], "box": [0.0, ""], "text": [0.0, ""]}
	var worst_drawn := {"panel": [0.0, ""], "box": [0.0, ""], "text": [0.0, ""]}
	for piece in _pieces:
		var swf: Rect2 = piece["swf"]
		var node: Control = piece["node"]
		var got: Rect2
		var drawn: Rect2
		if node == null:
			got = piece["fixed"]
			drawn = got
		else:
			var adjust: Rect2 = piece["adjust"]
			got = node.get_global_rect()
			got = Rect2(got.position + adjust.position, got.size + adjust.size)
			drawn = Rect2(_drawn_position(node) + adjust.position, got.size)
		var kind: String = piece["kind"]
		var off: float = _offset(got, swf, kind)
		var off_drawn: float = _offset(drawn, swf, kind)
		if off > worst[kind][0]:
			worst[kind] = [off, piece["name"]]
		if off_drawn > worst_drawn[kind][0]:
			worst_drawn[kind] = [off_drawn, piece["name"]]
		print("%-26s %-32s %-32s %8.2f %8.2f" % [piece["name"], _fmt(got), _fmt(swf), off, off_drawn])
	for kind in ["panel", "box", "text"]:
		print("largest %s offset: layout %.2f px (%s), drawn %.2f px (%s)" % [
			kind, worst[kind][0], worst[kind][1], worst_drawn[kind][0], worst_drawn[kind][1]
		])
	_last_summary = "panels off by up to %.2f px" % worst["panel"][0]


# Panels and boxes compare all four edges. Texts compare the top-left corner
# only, because a Label grows to its font's line height where a Flash field
# keeps its authored box.
func _offset(got: Rect2, swf: Rect2, kind: String) -> float:
	var d: float = maxf(absf(got.position.x - swf.position.x), absf(got.position.y - swf.position.y))
	if kind != "text":
		d = maxf(d, absf(got.end.x - swf.end.x))
		d = maxf(d, absf(got.end.y - swf.end.y))
	return d


func _fmt(r: Rect2) -> String:
	return "%.2f, %.2f, %.2f, %.2f" % [r.position.x, r.position.y, r.size.x, r.size.y]


func _dump_framebuffer() -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(_dump_path)
	print("prototype: saved %dx%d framebuffer to %s" % [image.get_width(), image.get_height(), _dump_path])
