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
#
# The battle frame puts a DropShadow on each p#BAR placement, so the shadow
# falls under everything the bar draws: the art, the fills, the text and the
# buff icons, which buffTicker attaches into p#BAR itself
# (frame_42/DoAction_10.as:362). Clip is a CanvasGroup over all of them, and
# scenes/drop_shadow.gdshader draws that one filter on it with the values in
# top_bar.json. It runs while the game draws, because the fills, the mirror,
# the buff icons and the death change what the shadow falls from.
#
# show_status() ports lifeBarUpdate (frame_42/DoAction_8.as:271-356). The first
# call sets the life fill and its color with no smoother and leaves the Focus fill
# at full, as the original does while its firstUpdate is true. Every later call
# moves a fill when its number changed. A loss moves the fill at once, and a gain
# moves it when its smoother ends. Each change plays the smoother clip of that bar
# as a band that trails the change: LifeBarSmoother (sprite 57) on the life and
# LifeBarSmoother2 (sprite 56) on the Focus. The bar runs them, and its death,
# on the original's frames at the SWF's frame rate.
extends Control
class_name StatusBar

const RECORD_PATH: String = "res://assets/ui/battle/top_bar/top_bar.json"
const TEXTURE_DIR: String = "res://assets/ui/battle/top_bar/"
# The smoothers' own names in top_bar.json. Each smoother's record holds what its
# frame scripts do, by frame number, and the record's `death` holds the frames and
# the alpha of the death (DefineSprite_57_LifeBarSmoother/frame_18 and frame_38).
const LIFE_SMOOTHER: String = "LifeBarSmoother"
const FOCUS_SMOOTHER: String = "LifeBarSmoother2"
# The life bar's color clip has one frame for each whole percent from 0 to 100,
# and the clip's frame number is the percent plus 1 (lifeBarUpdate,
# frame_42/DoAction_8.as:339-340).
const FULL_PERCENT: float = 100.0
# Flash keeps _alpha in steps of 1/256 and drops what is left over on each write,
# so frame 38's "_alpha -= 5" takes 13/256 off. Traced runs in the Flash debug
# player and in Ruffle measured that (references/traced_runs/death_fade_web_flash.txt).
const FLASH_ALPHA_STEPS: int = 256

# Emitted on each frame from the clear on, with the alpha the bar fades to, and
# once more when it hides.
signal death_faded(alpha: float)
signal death_hidden

# The box that each buff icon is drawn in, centered on the original's icon
# origin. The port's choice: the original draws vector art of its own there.
const BUFF_ICON_SIZE: Vector2 = Vector2(16, 16)
const ALIGNMENTS: Dictionary[String, HorizontalAlignment] = {
	"left": HORIZONTAL_ALIGNMENT_LEFT,
	"right": HORIZONTAL_ALIGNMENT_RIGHT,
	"center": HORIZONTAL_ALIGNMENT_CENTER,
}


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
# lifeBarUpdate's firstUpdate, and its BarHolder arrays: the life, the rounded
# percent of life and the Focus that the last update saw.
var _first_update: bool = true
var _held_life: float = 0.0
var _held_life_percent: int = 0
var _held_focus: float = 0.0
# The band each smoother is playing, or {} when it has none. attachMovie puts
# every smoother at depth 1 of its holder, so a new one replaces the old.
var _bands: Dictionary = {"life": {}, "focus": {}}
# The active buff slots as of the last refresh_buffs() call, so a refresh that lands
# with the same buffs and durations as last time (this is called for every event
# shown on the fighter and at every half-turn's end, not only when buffs actually
# change) can skip tearing down and rebuilding the row, which would otherwise
# flicker and kill an open tooltip out from under a player mid-hover for no reason.
var _last_signature: Array = []
# The alpha the death fade has left the bar at. The fade goes to Clip's shader
# and not to modulate, because the original fades p#BAR as one picture with its
# shadow, and a modulate would fade each part on its own.
var fade: float = 1.0
var _frames_due: float = 0.0
var _dead: bool = false
var _frames_since_death: int = 0
# The bar's death alpha in Flash's 1/256 steps.
var _death_alpha: int = FLASH_ALPHA_STEPS

@onready var clip: CanvasGroup = $Clip
@onready var inner: Control = $Clip/Inner
@onready var inner2: Control = $Clip/Inner2
@onready var name_label: Label = $Clip/Inner/PlayerName
@onready var life_now_label: Label = $Clip/Inner/LifeNow
@onready var life_max_label: Label = $Clip/Inner/LifeMax
@onready var focus_now_label: Label = $Clip/Inner/FocusNow
@onready var focus_max_label: Label = $Clip/Inner/FocusMax
@onready var life_fill: TextureRect = $Clip/Inner2/LifeFill
@onready var life_back: TextureRect = $Clip/Inner2/LifeBack
@onready var focus_fill: TextureRect = $Clip/Inner2/FocusFill
@onready var focus_back: TextureRect = $Clip/Inner2/FocusBack
@onready var life_band: TextureRect = $Clip/Inner2/LifeSmoother
@onready var focus_band: TextureRect = $Clip/Inner2/FocusSmoother
@onready var buff_row: Control = $Clip/BuffRow


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
	_place_art($Clip/Inner/Backing, frame["art"])
	var fields: Dictionary = {}
	for field: Dictionary in frame["fields"]:
		fields[field["variable"]] = field
	_place_field(name_label, fields["playerName"])
	_place_field(life_now_label, fields["lifeNow"])
	_place_field(life_max_label, fields["lifeMax"])
	_place_field(focus_now_label, fields["focusNow"])
	_place_field(focus_max_label, fields["focusMax"])
	_set_shadow(bar["shadow"])
	get_viewport().size_changed.connect(_fit_shadow)
	for part: String in ["Shade", "Black", "Frame"]:
		_place_art(inner2.get_node(part), bar["inner2"]["art"][part])
	_life_width = _place_fill([life_fill, life_back], bar["bars"]["life"], bar["art"])
	_focus_width = _place_fill([focus_fill, focus_back], bar["bars"]["focus"], bar["art"])
	_life_colors = bar["life_colors"]
	for band: TextureRect in [life_band, focus_band]:
		_place_art(band, bar["art"]["life_fill"])
		band.hide()
	life_fill.size.x = _life_width
	focus_fill.size.x = _focus_width
	_color_life(1.0)
	set_process(false)


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
	if _first_update:
		_first_update = false
		_held_life = life
		_held_focus = focus
		_held_life_percent = _percent(life, life_max)
		var share: float = _share(life, life_max)
		life_fill.size.x = _life_width * share
		_color_life(share)
		return
	_update_focus()
	_update_life()


# Does what the end of lifeBarUpdate does for the life (lines 292-296 and
# 303-356). It leaves the fill alone when the rounded percent is the same.
func _update_life() -> void:
	var percent: int = _percent(life, life_max)
	var change: float = life - _held_life
	if percent == _held_life_percent:
		change = 0.0
	_held_life = life
	_held_life_percent = percent
	if change == 0.0:
		return
	var share: float = _share(life, life_max)
	if change < 1.0:
		life_fill.size.x = _life_width * share
	_color_life(share)
	_play_band("life", change, life_max, share, _life_width)


# Does what lifeBarUpdate does for the Focus (lines 297-312).
func _update_focus() -> void:
	var change: float = focus - _held_focus
	_held_focus = focus
	if change == 0.0:
		return
	var share: float = _share(focus, focus_max)
	if change < 1.0:
		focus_fill.size.x = _focus_width * share
	_play_band("focus", change, focus_max, share, _focus_width)


# Refreshes the buff-icon row the way the original draws it at the end of
# applyChangesKrin (frame_42/DoAction_10.as:355-379): one KrinBuffShower for
# each of the first buff_row.slots slots of the record (7) whose cd isn't 0, in
# slot order. The row deliberately doesn't sort, because
# CombatUnit.apply_changes() already keeps buff_slots in the order
# applyChangesKrin's sortOn leaves them (line 344), and sort_custom would move
# tied buffs once more than 16 have turns left. Each icon is modulate-tinted by the buff's element color (Godot tints
# at runtime - no per-element art baked into the extracted PNGs), with the
# remaining-turns count and the tooltip built below. buff_id 0 is a real buff
# (TWINGUARDIANS, dev/converted_json/buffs.json), not an empty-slot sentinel;
# empty slots use buff_id -1 (see CombatUnit's slot init) but always carry
# cd == 0 too, so checking cd alone already excludes them.
func refresh_buffs(buff_slots: Array, buffs_by_id: Dictionary) -> void:
	var row: Dictionary = record()["buff_row"]
	var active_slots: Array = []
	for index in mini(buff_slots.size(), int(row["slots"])):
		var entry: Dictionary = buff_slots[index]
		if int(entry.get("cd", 0)) != 0:
			active_slots.append({"index": index, "buff_id": int(entry["buff_id"]), "cd": int(entry["cd"])})
	var signature: Array = active_slots.duplicate()
	if signature == _last_signature:
		return
	_last_signature = signature
	for child in buff_row.get_children():
		child.queue_free()
	for entry in active_slots:
		var buff: Buff = buffs_by_id.get(int(entry["buff_id"]))
		if buff == null:
			continue
		var icon_texture: Texture2D = BuffIcons.icon_for(buff)
		if icon_texture == null:
			continue
		# KrinBuffShower, DefineSprite 104, places buffColor, the icon and the
		# counter as siblings at depths 1, 4 and 8, and tints only buffColor
		# (frame_42/DoAction_10.as:373-374). The port has no buffColor and
		# tints the icon instead, so the counter is the icon's sibling here
		# and keeps its own white.
		var shower: Control = Control.new()
		shower.size = BUFF_ICON_SIZE
		# The icon's center sits at `(offset + space * h) * side` in the bar's
		# space, on the line between the two fills, where h is the slot's index
		# (frame_42/DoAction_10.as:352-358). An empty slot leaves its place empty.
		shower.position = Vector2((float(row["offset"]) + float(row["space"]) * float(entry["index"])) * _buff_side(), 0.0) - BUFF_ICON_SIZE / 2.0
		var icon_rect: TextureRect = TextureRect.new()
		icon_rect.name = "Icon"
		icon_rect.texture = icon_texture
		icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var element_index: CombatUnit.Element = buff.element_type
		if element_index != -1:
			icon_rect.modulate = MenuTheme.ELEMENT_COLORS[element_index]
		shower.add_child(icon_rect)
		# The original titles a buff's tooltip with its name alone and shows
		# the turns left only on the icon's counter below
		# (frame_42/DoAction_10.as:364 and 375).
		var sections: Array = [
			{"bg_color": TooltipTheme.BG_HEADER, "lines": [{
				"text": buff.display_name,
				"color": TooltipTheme.TEXT_TITLE,
			}]},
		]
		if not buff.tooltip_description.is_empty():
			sections.append({"bg_color": TooltipTheme.BG_BODY, "lines": [{"text": buff.tooltip_description, "color": TooltipTheme.TEXT_BODY}]})
		shower.mouse_entered.connect(func(): GameTooltip.show_sections(sections, shower))
		shower.mouse_exited.connect(GameTooltip.hide_tooltip)
		# The counter is KrinBuffShower's edit text 66, which the record places from
		# the icon's origin. It is bold _sans, the face the project theme gives
		# Labels.
		var counter_field: Dictionary = row["counter"]
		var counter: Label = Label.new()
		counter.name = "Counter"
		counter.text = str(int(entry["cd"]))
		counter.add_theme_font_size_override("font_size", roundi(float(counter_field["font_size"])))
		counter.add_theme_color_override("font_color", Color.html(counter_field["color"]))
		counter.horizontal_alignment = ALIGNMENTS[counter_field["align"]]
		counter.position = BUFF_ICON_SIZE / 2.0 + Vector2(float(counter_field["rect"][0]), float(counter_field["rect"][1]))
		counter.size.x = float(counter_field["rect"][2])
		counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shower.add_child(counter)
		buff_row.add_child(shower)


# Returns the sign that puts the icons on the inside of the bar: 1 on the
# player's side and -1 on the enemy's (buffMultiGF, frame_42/DoAction_10.as:346-351).
# The right-hand bars, which mirror inner2, are the enemy's.
func _buff_side() -> float:
	var mirror = record()["placements"]["p%dBAR" % slot]["inner2_xscale"]
	var side: float = record()["buff_row"]["enemy_side"] if mirror != null and mirror < 0 else record()["buff_row"]["player_side"]
	return side


# Does what LifeBarSmoother's frame 18 does to a dead unit's bar
# (DefineSprite_57_LifeBarSmoother/frame_18/DoAction.as): it sends `inner` to its
# empty "third" frame, which takes the name, the numbers and the divider away,
# and removes the buff icons. The fills stay to fade. show_status() fills these
# nodes but never shows them, so later redraws leave them hidden.
func clear_for_death() -> void:
	inner.hide()
	buff_row.hide()


# Starts the death, which attachMovie starts for a dead unit's smoother. From the
# clear on, advance_frame() hides the name and the numbers and fades the bar.
func die() -> void:
	_dead = true
	_frames_since_death = 0
	set_process(true)


# Runs the bar's clips on by `delta` seconds at the SWF's frame rate.
func _process(delta: float) -> void:
	_frames_due += delta * BattleScreenClip.fps()
	while _frames_due >= 1.0:
		_frames_due -= 1.0
		advance_frame()


# Plays one frame of each running smoother and of the death.
func advance_frame() -> void:
	_advance_band("life")
	_advance_band("focus")
	if _dead:
		_advance_death()
	if _bands["life"].is_empty() and _bands["focus"].is_empty() and not _dead:
		set_process(false)


func _advance_death() -> void:
	_frames_since_death += 1
	var death: Dictionary = record()["death"]
	var frames_since_clear: int = _frames_since_death - int(death["clear_frame"])
	if frames_since_clear < 0:
		return
	clear_for_death()
	if frames_since_clear == 0:
		_death_alpha = FLASH_ALPHA_STEPS
	elif _death_alpha > 0:
		var percent: float = _death_alpha * 100.0 / FLASH_ALPHA_STEPS - float(death["fade_per_frame"])
		_death_alpha = int(percent * FLASH_ALPHA_STEPS / 100.0)
	else:
		hide()
		_dead = false
		death_hidden.emit()
		return
	fade = maxi(_death_alpha, 0) / float(FLASH_ALPHA_STEPS)
	(clip.material as ShaderMaterial).set_shader_parameter("fade", fade)
	death_faded.emit(fade)


# Attaches the smoother of `kind` ("life" or "focus") for a change of `change`
# out of `maximum`, which has left the fill at `share` of `full` width. It does
# what lines 308-325 and 340-354 do: the band starts at the fill's end, is as wide
# as the change, and a gain starts at the clip's healSmooth label, with the width
# the fill ends on.
func _play_band(kind: String, change: float, maximum: float, share: float, full: float) -> void:
	var bar: Dictionary = record()
	var fill: TextureRect = life_fill if kind == "life" else focus_fill
	var factors: Dictionary = bar["smoother_factors"]
	var clip: Dictionary = bar["smoothers"][LIFE_SMOOTHER if kind == "life" else FOCUS_SMOOTHER]
	var band := {
		"clip": clip,
		"frame": 1,
		"anchor": fill.size.x * float(factors["x_factor"]) - float(factors["x_offset"]),
		"scale": absf(change) / maximum if maximum > 0.0 else 0.0,
		"color": _life_color(share) if kind == "life" else Color.WHITE,
		"scripts": _scripts_of(clip),
		"target": full * share,
	}
	if change > 0.0:
		band["frame"] = int(clip["labels"]["healSmooth"])
	_bands[kind] = band
	set_process(true)
	_show_band(kind)
	_run_band_script(kind)


# Returns the frames that run a script, with what each one does.
func _scripts_of(clip: Dictionary) -> Dictionary:
	var scripts: Dictionary = {}
	for frame: String in clip["scripts"]:
		scripts[int(frame)] = clip["scripts"][frame]
	return scripts


func _advance_band(kind: String) -> void:
	var band: Dictionary = _bands[kind]
	if band.is_empty():
		return
	band["frame"] = int(band["frame"]) + 1
	if band["frame"] > int(band["clip"]["frames"]):
		_end_band(kind)
		return
	_show_band(kind)
	_run_band_script(kind)


# Does what the frame script of the smoother's current frame does.
func _run_band_script(kind: String) -> void:
	var band: Dictionary = _bands[kind]
	match band["scripts"].get(int(band["frame"]), ""):
		"loss_end":
			_end_band(kind)
		"gain_end":
			(life_fill if kind == "life" else focus_fill).size.x = float(band["target"])
			_end_band(kind)


func _end_band(kind: String) -> void:
	_bands[kind] = {}
	(life_band if kind == "life" else focus_band).hide()


# Shows the smoother's current frame: the colour clip under the frame's x and x
# scale, in the holder of the bar. The band's rect is the clip's shape, scaled by
# the smoother's width, set at its anchor in the holder, and put through the
# holder's placement.
func _show_band(kind: String) -> void:
	var band: Dictionary = _bands[kind]
	var node: TextureRect = life_band if kind == "life" else focus_band
	var frame: Dictionary = band["clip"]["shown"][int(band["frame"]) - 1]
	if not frame["shown"]:
		node.hide()
		return
	var bar: Dictionary = record()
	var holder: Dictionary = bar["bars"]["life" if kind == "life" else "focus"]
	var art: Dictionary = bar["art"]["life_fill"]
	# The shape's rect around the clip's origin, then the clip's x and x scale in
	# the smoother, the smoother's own scale and anchor in the holder, and the
	# holder's placement in inner2.
	var shape := Rect2(
		float(art["rect"][0]) - float(art["origin"][0]),
		float(art["rect"][1]) - float(art["origin"][1]),
		float(art["rect"][2]),
		float(art["rect"][3]),
	)
	var clip_x: float = float(frame["x"])
	var clip_scale: float = float(frame["x_scale"])
	var left: float = float(band["anchor"]) + float(band["scale"]) * (clip_x + clip_scale * shape.position.x)
	var width: float = float(band["scale"]) * clip_scale * shape.size.x
	var scale_x: float = float(holder["scale_x"])
	node.position = Vector2(float(holder["x"]) + scale_x * left, float(holder["y"]) + shape.position.y)
	node.size = Vector2(scale_x * width, shape.size.y)
	node.modulate = band["color"] if kind == "life" else Color.html(frame["color"])
	node.show()


# Returns the life bar's color for a share, which is the colour clip's frame for
# the rounded percent.
func _life_color(share: float) -> Color:
	return Color.html(_life_colors[roundi(share * FULL_PERCENT)])


func _color_life(share: float) -> void:
	life_fill.modulate = _life_color(share)
	life_back.modulate = _life_color(share)


# Returns the rounded percent of life, which lifeBarUpdate compares between updates.
func _percent(now: float, maximum: float) -> int:
	if maximum <= 0.0:
		return 0
	return roundi(now / maximum * FULL_PERCENT)


# Returns the fill's share of its full width, from 0 to 1. A max of 0 gives 0,
# which is what Flash's width of NaN comes to.
func _share(now: float, maximum: float) -> float:
	if maximum <= 0.0:
		return 0.0
	return clampf(now / maximum, 0.0, 1.0)


# Gives Clip's shader the bar's DropShadow, in the uniforms that
# screen_rects.bar_filter_record() names for the rect test.
func _set_shadow(shadow: Dictionary) -> void:
	var material := clip.material as ShaderMaterial
	material.set_shader_parameter("shadow_color", Color.html(shadow["color"]))
	material.set_shader_parameter("blur", Vector2(float(shadow["blur_x"]), float(shadow["blur_y"])))
	material.set_shader_parameter("distance", float(shadow["distance"]))
	material.set_shader_parameter("angle", float(shadow["angle"]))
	material.set_shader_parameter("strength", float(shadow["strength"]))
	material.set_shader_parameter("fade", fade)
	_fit_shadow()


# Sets what depends on the window's scale. Flash measures a filter in stage px,
# so the shader needs the screen px for each stage px. A CanvasGroup's margins
# are in screen px (docs/agents/godot.md). The shadow reaches its distance plus
# half its blur past the art, so fit_margin grows the group's rect that far,
# and clear_margin clears as far again around it, where the shader's samples
# for the rect's outer pixels land.
func _fit_shadow() -> void:
	var shadow: Dictionary = record()["shadow"]
	var stage_scale: float = get_viewport().get_final_transform().get_scale().x
	var reach: float = float(shadow["distance"]) + maxf(float(shadow["blur_x"]), float(shadow["blur_y"])) / 2.0
	(clip.material as ShaderMaterial).set_shader_parameter("stage_scale", stage_scale)
	clip.fit_margin = ceilf(reach * stage_scale) + 1.0
	clip.clear_margin = ceilf(reach * stage_scale) + 1.0


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


# Lays out one text field: its rect, size, color and alignment. The Label draws
# no shadow of its own, because Clip's DropShadow falls under the text too.
func _place_field(label: Label, field: Dictionary) -> void:
	label.position = Vector2(float(field["rect"][0]), float(field["rect"][1]))
	label.size = Vector2(float(field["rect"][2]), float(field["rect"][3]))
	label.horizontal_alignment = ALIGNMENTS[field["align"]]
	label.add_theme_font_size_override("font_size", roundi(float(field["font_size"])))
	label.add_theme_color_override("font_color", Color.html(field["color"]))
