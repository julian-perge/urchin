# character_visual.gd
# 2D paper-doll character, the replacement for the abandoned Skeleton2D + IK
# rig. Ported from the original Flash model clips (MODEL1, and MODEL4 for the
# female units) + dressChar() (frame217_KRIN_BATTLE_SCENE/2_dressing_chars.txt):
#
# - The doll is a flat set of Sprite2D "parts" (head/chest/arms/legs/weapons),
#   whose rest pose is frame 1 of the model's timeline (the exact affine matrix
#   from the SWF, twips -> px). No bones, no IK - the original was nested
#   MovieClips with keyframe tweens, which maps to plain Node2D transforms.
# - Each part composites up to three texture layers: the base skin
#   (<G>_S<CODE>_<skin>), the equipped-item art (<G>_<CODE>_<looks> for armor,
#   M_<CODE>_<looks> for weapons), and hair on the head. dress() rebuilds them.
# - Animation plays the model's original keyframe timeline directly (stand/
#   run/Attack*/runback/cast/stun/stun2/outofstun/hit/dead); only the melee
#   run-to-target motion is code-driven (the original's krinMelee/krinBoltMake
#   were code too, not a skeletal solve) - see DECODED_ALGORITHMS.md.
#
# No autoload references - textures load from res:// paths directly.
class_name CharacterVisual
extends Node2D

# Emitted at the swing's Impact.
signal attack_connected
signal state_finished(state: int)
# Emitted once the Runback has brought the doll home.
signal melee_finished
# Emitted on the frame of a swing whose script in the model's clip plays a sound,
# with that sound's name for the audio manager, such as "sfx_swing".
signal sound_cue(cue: String)

enum State { IDLE, MELEE, CAST, STUN, HIT, DEAD }
enum MeleePhase { NONE, DASH, STRIKE, RUNBACK }

const SPRITE_ROOT: String = "res://resources/sprites"
# Per-art render bounds extracted from the SWF (extract_doll_art writes this
# alongside the PNGs, because only the renderer knows how far a part's filters
# grew it): name -> {x, y, w, h} in px. A name absent from the file is
# placeholder art for a part the original left empty.
# The PNGs are exported at 2x design size;
# each layer is positioned at (x, y) and scaled to w/h - without this every
# part draws top-left-at-joint at export resolution (the giant-blob bug).
const OFFSETS_FILE: String = SPRITE_ROOT + "/doll_offsets.json"
# The models whose own clip the doll plays, as extract_model_animations and
# convert_model_sound_cues write them. dressChar attaches the unit's model[0]
# clip (frame_217/DoAction_2.as:17). Every other model plays MODEL1's clip,
# because MODEL5 to MODEL8 have fewer named parts than the doll's 15 and MODEL2
# and MODEL9 name none.
const CLIP_MODELS: Array[String] = ["MODEL1", "MODEL4"]
const DEFAULT_MODEL: String = "MODEL1"
# Each model's keyframe animations (animations_file): per-frame full affine
# matrices per part, 30 fps, labeled segments (stand/run/Attack/runback/hit/
# dead/... - see DECODED_ALGORITHMS.md), and each part's depth.
const ANIMATIONS_PATTERN: String = SPRITE_ROOT + "/%s_animations.json"
# The sounds each model's frame scripts play (sound_cues_file): the 1-based
# frame as a string -> the cue names of that frame. Only the swing labels hold
# a cue, "sfx_swing".
const SOUND_CUES_PATTERN: String = "res://dev/converted_json/%s_sound_cues.json"

# krinMelee (frame_42/DoAction_4.as:36-135) moves the fighter on every frame of
# its swing:
# - Each step moves the fighter a sixth of the way from where it stood when the
#   swing started to where the target stands that frame, times a coefficient.
#   The sixth is krinBodyMove (10) over krinBoltTime (60) (lines 38-39, 112-116
#   and 213-216).
# - The dash's coefficient is min(1.5 - 1.45 * goRat, 1), where goRat is the
#   share of the dash's x distance covered so far. The dash ends on the first
#   frame that covers it all, and the strike label cuts the run label off. The
#   dash runs to the target's x less both fighters' half-widths, read once when
#   the swing starts (lines 46-56). So it takes 13 frames with no half-widths,
#   11 at 300 px with 60 px of half-widths and 4 at 150 px with 100 px.
# - Impact comes krinMeleeAttackCD (15) frames after the strike label starts.
#   krinMeleeAttackEndCD is 15 too, but its count starts on the frame that
#   raised the impact flag (lines 87-95), so the Runback starts 14 frames
#   after Impact.
# - The Runback steps back toward home with the coefficient min(1.45 * goRat,
#   1). It puts the fighter home on the first frame that leaves it no more
#   than MELEE_HOME_TOLERANCE px from home along x, on the target's side
#   (lines 117-123). The original's home is where the swing started. The
#   port's is the doll's own, and the port measures the Runback from it (see
#   play_melee).
const MELEE_STEP_SHARE: float = 10.0 / 60.0
const MELEE_IMPACT_FRAMES: float = 15.0
const MELEE_RUNBACK_FRAMES: float = 14.0
const MELEE_HOME_TOLERANCE: float = 0.000001

const BODY_SHADER: Shader = preload("res://scenes/doll_body.gdshader")
# The stage px the body draws past the reach of the Result flash's colored
# glows, so that their soft edge is not cut. The port chose it. The original
# has no such number.
const RESULT_FLASH_FIT_SPARE: float = 1.0

# The Ground shadow's art and each model's matrix for it (extract_doll_shadow).
const SHADOW_ART: String = SPRITE_ROOT + "/doll_shadow.png"
const SHADOW_FILE: String = SPRITE_ROOT + "/doll_shadow.json"

static var _shadow_layout: Dictionary = {}
static var _shadow_layout_loaded: bool = false
static var _offsets: Dictionary = {}
static var _offsets_loaded: bool = false
# model -> the parsed animations_file and sound_cues_file of that model.
static var _animations: Dictionary = {}
static var _sound_cues: Dictionary = {}

# dressChar's dollPartsArray. skin_code is the base-skin part code
# (dollPartsCores2); equip_slot indexes the 7-slot equip_array
# (dollPartsCores). Thighs (leg1/leg2) reuse the ARM art, exactly as the
# original does. Each part's place and draw order come from the model's
# timeline.
const DOLL_PARTS: Dictionary[String, Dictionary] = {
	"head":     {"skin_code": "HEAD",     "equip_slot": 0},
	"chest":    {"skin_code": "CHEST",    "equip_slot": 1},
	"arm1":     {"skin_code": "ARM",      "equip_slot": 1},
	"arm2":     {"skin_code": "ARM",      "equip_slot": 1},
	"hand1":    {"skin_code": "HAND",     "equip_slot": 2},
	"hand2":    {"skin_code": "HAND",     "equip_slot": 2},
	"leg1":     {"skin_code": "ARM",      "equip_slot": 3},
	"leg2":     {"skin_code": "ARM",      "equip_slot": 3},
	"leg3":     {"skin_code": "LEG2",     "equip_slot": 4},
	"leg4":     {"skin_code": "LEG2",     "equip_slot": 4},
	"foot1":    {"skin_code": "FOOT",     "equip_slot": 4},
	"foot2":    {"skin_code": "FOOT",     "equip_slot": 4},
	"weapon1":  {"skin_code": "WEAPON",   "equip_slot": 5},
	"weapon2":  {"skin_code": "WEAPON",   "equip_slot": 6},
	"shoulder": {"skin_code": "SHOULDER", "equip_slot": 1},
}

# Menus show the doll as a static mannequin (the original only animates in
# battle and cutscenes) - flip this off to freeze the rest pose.
@export var animate: bool = true

var _parts: Dictionary = {}  # name -> Node2D holding the layered sprites
# The model whose clip the doll plays, one of CLIP_MODELS.
var _model: String = DEFAULT_MODEL
var _body: CanvasGroup
var _body_material: ShaderMaterial
# The look the doll's buffs give it (show_buff_look): the color offsets and the
# glows of the filter list, which are empty while the doll has no such look.
var _buff_offsets: Array = []
var _buff_glows: Array = []
# The fit and clear margins, in stage px, that the Result flash and the buff
# glows each need around the body. The body takes the larger of each.
var _flash_margins: Vector2 = Vector2.ZERO
var _buff_margins: Vector2 = Vector2.ZERO
var _state: int = State.IDLE
var _attack_fired: bool = false

# Timeline playback (labels from the model's animations file).
var _label: String = ""
var _label_frames: float = 0.0
var _label_finished: bool = false
# These run the melee swing. krinMelee moves the fighter's clip whatever its
# inner doll plays (frame_42/DoAction_4.as:67-135), so the swing goes on through
# any set_state(), and the doll shows the swing's labels only while its state is
# MELEE. The strike and runback play the timeline continuously from _playhead,
# because the original clip flows Attack -> attack2 -> runback on its own.
# _strike_frames counts the SWF frames since the strike started.
var _melee_phase: MeleePhase = MeleePhase.NONE
var _home_position: Vector2 = Vector2.ZERO
var _attack_label: String = "Attack"
var _playhead: float = 0.0  # continuous 0-based frame position
var _strike_frames: float = 0.0
var _impact_fired: bool = false
# These hold krinMelee's targetMC, faceing, endPoint, boltx and bolty,
# slowPoint and relX. _target_spot returns where the target stands now, as a
# spot for this doll. _facing is 1 when the target is to the right of where the
# swing started, and _end_x is where the dash ends. The swing measures itself
# from _origin, which is where the doll stood when the swing started, and the
# doll's home once the Runback starts. _slow_point is the x distance from
# _origin to _end_x, and _rel_x and _rel_y are how far the doll stands from
# _origin.
var _target_spot: Callable = Callable()
var _facing: float = 1.0
var _end_x: float = 0.0
var _origin: Vector2 = Vector2.ZERO
var _slow_point: float = 0.0
var _rel_x: float = 0.0
var _rel_y: float = 0.0
# Stun sub-phase: 0 "stun" entry (one-shot), 1 "stun2" hold (loop, entered
# automatically when the entry finishes - baked into the clip itself, no
# code needed), 2 "outofstun" exit (one-shot, ends back at idle).
var _stun_phase: int = 0


func _ready():
	# The parts draw into one picture, so a filter can read the whole doll at
	# once, the way Flash filters the original's whole `inner` clip. The body
	# keeps its shader on at all times, because a CanvasGroup's own shader would
	# apply the doll's modulate a second time (see doll_body.gdshader).
	_body = CanvasGroup.new()
	_body.name = "Body"
	_body_material = ShaderMaterial.new()
	_body_material.shader = BODY_SHADER
	_body.material = _body_material
	add_child(_body)
	# A glow measures its blur in stage px, so a window that changes size changes
	# what the buff glows ask of the shader.
	get_viewport().size_changed.connect(_apply_buff_look)
	_apply_buff_look()
	for part_name in DOLL_PARTS:
		var part: Node2D = Node2D.new()
		part.name = part_name
		_body.add_child(part)
		_parts[part_name] = part
	_order_parts()
	# Animated dolls start on the original stand loop; static mannequins
	# (menus) keep MODEL1's rest pose.
	_apply_frame_index(0)
	if animate:
		set_state(State.IDLE)


# Redraws the doll in `form`, one of the forms of buff_looks.json, as
# changeForm's dressChar call does. dressChar passes "" as the armor set, so the
# doll wears its skin set alone, with the form's weapons. A weapon of "" takes the
# weapon of `equip_looks`, the unit's own looks. `stunned` is whether the unit
# holds any stun.
func wear_form(form: Dictionary, equip_looks: Array, stunned: bool) -> void:
	var equip: Array = ["", "", "", "", "", form["weapon1"], form["weapon2"]]
	for slot in [5, 6]:
		if equip[slot] == "":
			equip[slot] = equip_looks[slot]
	dress(form["gender"], form["skin"], form["hair"], equip)
	start_clip(form["model"], stunned)


# Redraws the doll as its unit's own form, which changeForm does for "STANDARD".
func wear_own_form(model: Array, equip_looks: Array, stunned: bool) -> void:
	dress_from_model(model, equip_looks)
	start_clip(str(model[0]), stunned)


# Moves the doll `dy` px down inside its rig, and its saved home with it, so a
# swing that is under way still ends at the doll's new home.
func shift_down(dy: float) -> void:
	position.y += dy
	_home_position.y += dy


# dressChar removes the doll's clip and attaches a new clip of `model`, which
# starts on its first frame, and the shadow is a part of that clip. From then on
# the doll draws its parts in the model's depth order and plays the model's
# labels and sound cues, or MODEL1's for a model outside CLIP_MODELS. changeForm
# then puts a stunned unit's new clip in the stun loop
# (frame_42/DoAction_10.as:533-536).
func start_clip(model: String, stunned: bool = false) -> void:
	show_shadow(model)
	_model = model if CLIP_MODELS.has(model) else DEFAULT_MODEL
	_order_parts()
	set_state(State.IDLE)
	if stunned:
		_state = State.STUN
		_stun_phase = 1
		_start_label("stun2")


# Draws the Ground shadow that `model` places under its parts, at depth 1 of
# the model clip. The shadow is part of the body, so the doll's modulate, fade
# and Result flash reach it as they reach the original's whole `inner` clip.
# A model with no placement in doll_shadow.json gets none.
func show_shadow(model: String) -> void:
	var old: Node = _body.get_node_or_null("Shadow")
	if old != null:
		_body.remove_child(old)
		old.queue_free()
	var layout: Dictionary = _load_shadow_layout()
	var matrix: Array = layout.get("models", {}).get(model, [])
	if matrix.is_empty():
		return
	var rect: Dictionary = layout["rect"]
	var shadow := Sprite2D.new()
	shadow.name = "Shadow"
	shadow.texture = load(SHADOW_ART)
	shadow.centered = false
	var size: Vector2 = shadow.texture.get_size()
	var placed := Transform2D(Vector2(matrix[0], matrix[1]), Vector2(matrix[2], matrix[3]), Vector2(matrix[4], matrix[5]))
	shadow.transform = placed * Transform2D(0.0, Vector2(rect["w"] / size.x, rect["h"] / size.y), 0.0, Vector2(rect["x"], rect["y"]))
	_body.add_child(shadow)
	_body.move_child(shadow, 0)


# dressChar port. gender "M"/"F", skin/hair keys, equip = 7-slot Array of
# item "looks" strings (0 or "" = bare). Rebuilds every part's texture layers.
func dress(gender: String, skin: String, hair: String, equip: Array) -> void:
	for part_name in _parts:
		var part: Node2D = _parts[part_name]
		for child in part.get_children():
			child.queue_free()
		var pose: Dictionary = DOLL_PARTS[part_name]
		# Base skin layer (weapons have no skin layer - only equipped art).
		if pose["skin_code"] != "WEAPON":
			_add_layer(part, "%s/%s_S%s_%s.png" % [SPRITE_ROOT, gender, pose["skin_code"], skin])
		# Equipped-item layer.
		var looks: String = _equip_looks(equip, pose["equip_slot"])
		if looks != "":
			if pose["skin_code"] == "WEAPON":
				_add_layer(part, "%s/M_WEAPON_%s.png" % [SPRITE_ROOT, looks])
			else:
				# Prefer gender-specific art, fall back to the male sheet
				# (female characters share male equipment art in the original).
				var path: String = "%s/%s_%s_%s.png" % [SPRITE_ROOT, gender, pose["skin_code"], looks]
				if not ResourceLoader.exists(path):
					path = "%s/M_%s_%s.png" % [SPRITE_ROOT, pose["skin_code"], looks]
				_add_layer(part, path)
		# Hair sits on the head, above the skin - but only when no helmet is
		# equipped (females always show hair; their helmets render over it).
		var show_hair: bool = _equip_looks(equip, 0) == "" or gender == "F"
		if part_name == "head" and show_hair and hair != "" and hair != "0":
			_add_layer(part, "%s/HAIR_%s.png" % [SPRITE_ROOT, hair])


# Convenience: dress straight from a CombatUnit-style model array
# (["MODELx", skin, hair, gender]) plus its 7-slot equip looks.
func dress_from_model(model: Array, equip_looks: Array) -> void:
	var gender = model[3] if model.size() > 3 else "M"
	var skin = model[1] if model.size() > 1 else "ONE"
	var hair = model[2] if model.size() > 2 else ""
	dress(gender, skin, hair, equip_looks)


func set_state(new_state: State) -> void:
	_state = new_state
	_attack_fired = false
	_label_frames = 0.0
	_label_finished = false
	# Reset the transient transforms the previous state left behind (hit
	# recoil x-offset, stun tilt, cast tint) - without this the doll keeps
	# rocking/tilting after the state ends.
	if _body != null:
		_body.position = Vector2.ZERO
		_body.rotation = 0.0
	modulate = Color.WHITE
	match new_state:
		State.IDLE:
			_start_label("stand")
		State.HIT:
			_start_label("hit")
		State.DEAD:
			_start_label("dead")
			_playhead = _label_start_frame("dead")
		State.CAST:
			_start_label("cast")
		State.STUN:
			_enter_stun_animation()


# Melee with the original run -> strike -> runback motion. target_spot returns
# where the target stands now, as a spot for this doll, and the swing reads it
# on every frame of the run there and back. The dash stops short of where the
# target stands as the swing starts by target_half_width plus half this doll's
# own width in its run pose, because the conductor sends the doll to its run
# label just before krinMelee reads both widths (frame_217/PlaceObject2_3389_480
# enterFrame, lines 409-410). attack_label picks the swing (Attack /
# Attack_Upper / Attack_Stab / attack2, per the move's addNewMove param 12).
# Emits attack_connected at Impact and melee_finished once the Runback has
# brought the doll home.
func play_melee(target_spot: Callable, target_half_width: float, attack_label: String = "Attack") -> void:
	# A swing that starts while the doll is still in its Runback keeps the doll's
	# home. The original takes the clip's position at that moment as its new
	# home (krinMelee's boltx, frame_42/DoAction_4.as:38-39), which leaves the
	# fighter short of its slot for the rest of the battle. ADR 0005 counts that
	# as an Original bug. The dash still starts from where the doll stands, as
	# the original's does.
	if _melee_phase != MeleePhase.RUNBACK:
		_home_position = position
	set_state(State.MELEE)
	_melee_phase = MeleePhase.DASH
	_attack_label = _valid_attack_label(attack_label)
	_strike_frames = 0.0
	_impact_fired = false
	_playhead = _label_start_frame("run")
	_apply_frame_index(int(_playhead))
	_target_spot = target_spot
	var target_x: float = target_spot.call().x
	var reach: float = target_half_width + get_bounds().size.x / 2.0
	_facing = 1.0 if position.x < target_x else -1.0
	_end_x = target_x - _facing * reach
	_measure_from(position)


# Measures the swing from `origin`, as krinMelee measures it from boltx and
# bolty.
func _measure_from(origin: Vector2) -> void:
	_origin = origin
	_rel_x = position.x - origin.x
	_rel_y = position.y - origin.y
	_slow_point = _end_x - origin.x


# krinBuff STUN is a running total across active stun-inflicting buffs (see
# DECODED_ALGORITHMS.md) - the original replays the "stun" entry animation on
# ANY increase, including while already stunned/stacked (re-triggers from
# frame 220 rather than being ignored). Callers should invoke this whenever
# the unit's total stun value goes up.
func enter_stun() -> void:
	if _state != State.STUN:
		set_state(State.STUN)
	else:
		_enter_stun_animation()


func _enter_stun_animation() -> void:
	_stun_phase = 0
	_start_label("stun")


# Fires on ANY decrease in the unit's total stun value - even a partial one
# that leaves the unit still stunned by a shorter-lived buff still plays the
# full "outofstun" wake-up before falling back to idle (matches the source:
# the comparison is value-based, not a STUN == 0 check). No-op outside STUN.
func exit_stun() -> void:
	if _state != State.STUN:
		return
	_stun_phase = 2
	_start_label("outofstun")


func _valid_attack_label(label: String) -> String:
	var animations: Dictionary = _timeline()
	if animations.get("labels", {}).has(label):
		return label
	return "Attack"


func is_idle() -> bool:
	return _state == State.IDLE


# Puts the Result flash's filter on the whole doll in `color`. `white_glow` and
# `color_glow` each hold the `blur` and the `strength` of a glow, as
# result_flash.json gives them. Flash measures a blur in stage px, and the
# window can draw the stage at any size, so this reads the stage's scale on
# screen each time. A CanvasGroup's margins are in screen px too.
#
# A glow reads a box as wide as its blur around each px, so it reaches half its
# blur. The body draws that far past the doll for the colored glows, and
# RESULT_FLASH_FIT_SPARE more. The white glow reads its box around each px the
# body draws, so the body clears the screen texture half the white blur past
# that, which is where a CanvasGroup measures clear_margin from.
func show_result_flash(color: Color, white_glow: Dictionary, color_glow: Dictionary) -> void:
	var stage_scale: float = get_viewport().get_final_transform().get_scale().x
	_body_material.set_shader_parameter("result_flash", true)
	_body_material.set_shader_parameter("color", color)
	_body_material.set_shader_parameter("stage_scale", stage_scale)
	_body_material.set_shader_parameter("white_blur", white_glow["blur"])
	_body_material.set_shader_parameter("white_strength", white_glow["strength"])
	_body_material.set_shader_parameter("color_blur", color_glow["blur"])
	_body_material.set_shader_parameter("color_strength", color_glow["strength"])
	_flash_margins = Vector2(color_glow["blur"] / 2.0 + RESULT_FLASH_FIT_SPARE, white_glow["blur"] / 2.0)
	_apply_margins(stage_scale)


# BATTLEFLASH puts back the filter and the color the unit's buffs give its doll,
# so the doll goes back to the look that show_buff_look() set.
func hide_result_flash() -> void:
	_body_material.set_shader_parameter("result_flash", false)
	_flash_margins = Vector2.ZERO
	_apply_margins(get_viewport().get_final_transform().get_scale().x)


# Gives the doll the look its buffs give it: `color_offsets` are the red, green
# and blue offsets of the ColorTransform that krinChangeColor sets, each from
# -255 to 255, and `glows` are the GlowFilters of the filter list that
# applyChangesKrin sets, as buff_looks.json holds them. Empty arguments give the
# doll back its plain look.
#
# A glow reaches half its blur past the px it reads. The body draws the outer
# glows' reach and 1 px more past the doll, and clears the screen texture half
# the largest blur past that, as the Result flash does for its glows.
func show_buff_look(color_offsets: Array, glows: Array) -> void:
	_buff_offsets = color_offsets
	_buff_glows = glows
	_apply_buff_look()


func _apply_buff_look() -> void:
	if _body_material == null:
		return
	var stage_scale: float = get_viewport().get_final_transform().get_scale().x
	var offsets: Vector3 = Vector3.ZERO
	if _buff_offsets.size() == 3:
		offsets = Vector3(_buff_offsets[0], _buff_offsets[1], _buff_offsets[2]) / 255.0
	_body_material.set_shader_parameter("buff_offset", offsets)
	_body_material.set_shader_parameter("buff_glows", _buff_glows.size())
	_body_material.set_shader_parameter("stage_scale", stage_scale)
	var reach: float = 0.0
	var clear: float = 0.0
	for index in _buff_glows.size():
		var glow: Dictionary = _buff_glows[index]
		var slot: String = "a" if index == 0 else "b"
		_body_material.set_shader_parameter("buff_color_" + slot, Color.html(glow["color"]))
		_body_material.set_shader_parameter("buff_params_" + slot, Vector4(glow["blur_x"], glow["strength"], 1.0 if glow["inner"] else 0.0, 1.0 if glow["knockout"] else 0.0))
		if not glow["inner"]:
			reach += glow["blur_x"] / 2.0
		clear = maxf(clear, glow["blur_x"] / 2.0)
	_buff_margins = Vector2(reach + RESULT_FLASH_FIT_SPARE, clear) if not _buff_glows.is_empty() else Vector2.ZERO
	_apply_margins(stage_scale)


func _apply_margins(stage_scale: float) -> void:
	_body.fit_margin = maxf(_flash_margins.x, _buff_margins.x) * stage_scale
	_body.clear_margin = maxf(_flash_margins.y, _buff_margins.y) * stage_scale


# The box around every part the doll draws in its current pose, in its parent's
# space, which is where Flash measures a clip's _width and _height. Flash
# measures the parts' shapes without their filters, and some part PNGs carry a
# filter's glow, so this box can come out bigger than the original's.
func get_bounds() -> Rect2:
	var bounds := Rect2()
	var found: bool = false
	for part in _parts.values():
		if not part.visible:
			continue
		for layer in part.get_children():
			if not layer is Sprite2D or layer.is_queued_for_deletion():
				continue
			var to_parent: Transform2D = transform * _body.transform * part.transform * layer.transform
			var rect: Rect2 = to_parent * layer.get_rect()
			bounds = bounds.merge(rect) if found else rect
			found = true
	return bounds


func _process(delta: float) -> void:
	if not animate:
		return
	_animate_melee(delta)
	match _state:
		State.IDLE:
			_advance_label(delta, true)
		State.CAST:
			_advance_label(delta, false)
			if _label_finished:
				set_state(State.IDLE)
		State.STUN:
			_animate_stun(delta)
		State.HIT:
			_advance_label(delta, false)
			if _label_finished:
				set_state(State.IDLE)
		State.DEAD:
			_play_death(delta)


# --- timeline playback (the model's animations file) --------------------------

func _start_label(label: String) -> void:
	_label = label
	_label_frames = 0.0
	_label_finished = false
	_apply_label_frame(label, 0.0)


# Returns how many SWF frames `label` lasts.
func _label_length(label: String) -> float:
	var animations: Dictionary = _timeline()
	var segment: Dictionary = animations.get("labels", {}).get(label, {})
	if segment.is_empty():
		return 15.0
	return float(segment["end"]) - float(segment["start"]) + 1.0


# The label's playhead counts frames, not seconds, for the reason _play_death
# gives: a sum of 1/30 s steps drifts off whole frames, and a one-shot label
# would then end a frame late.
func _advance_label(delta: float, loop: bool) -> void:
	_label_frames += delta * BattleScreenClip.fps()
	var length: float = _label_length(_label)
	if loop:
		_label_frames = fmod(_label_frames, length)
	elif _label_frames >= length:
		_label_frames = length
		_label_finished = true
	_apply_label_frame(_label, _label_frames)


# Applies the pose `frames` SWF frames into a labeled segment: every part gets
# the original frame's full affine matrix (rotation, scale, AND skew).
func _apply_label_frame(label: String, frames: float) -> void:
	var animations: Dictionary = _timeline()
	var segment: Dictionary = animations.get("labels", {}).get(label, {})
	if segment.is_empty():
		return
	var start: int = int(segment["start"]) - 1
	var end: int = int(segment["end"]) - 1
	_apply_frame_index(clampi(start + int(frames), start, end))


func _apply_frame_index(index: int) -> void:
	var animations: Dictionary = _timeline()
	var frames: Array = animations.get("frames", [])
	if frames.is_empty():
		return
	var frame: int = clampi(index, 0, frames.size() - 1)
	var pose: Dictionary = frames[frame]
	var alphas: Dictionary = animations["alphas"][frame]
	for part_name in _parts:
		var part: Node2D = _parts[part_name]
		var matrix = pose.get(part_name)
		if matrix == null:
			part.visible = false
			continue
		part.visible = true
		part.transform = Transform2D(
			Vector2(matrix[0], matrix[1]),
			Vector2(matrix[2], matrix[3]),
			Vector2(matrix[4], matrix[5])
		)
		part.modulate.a = alphas.get(part_name, 1.0)


func _label_start_frame(label: String) -> float:
	var segment: Dictionary = _timeline().get("labels", {}).get(label, {})
	return float(int(segment.get("start", 1)) - 1)


func _label_end_frame(label: String) -> float:
	var segment: Dictionary = _timeline().get("labels", {}).get(label, {})
	return float(int(segment.get("end", 1)) - 1)


static func animations_file(model: String) -> String:
	return ANIMATIONS_PATTERN % model.to_lower()


static func sound_cues_file(model: String) -> String:
	return SOUND_CUES_PATTERN % model.to_lower()


# Puts the parts in the model's depth order, back to front, after the shadow.
func _order_parts() -> void:
	var depths: Dictionary = _timeline().get("depths", {})
	var ordered: Array = DOLL_PARTS.keys()
	ordered.sort_custom(func(a, b): return depths.get(a, 0) < depths.get(b, 0))
	var first: int = 1 if _body.get_node_or_null("Shadow") != null else 0
	for index in ordered.size():
		_body.move_child(_parts[ordered[index]], first + index)


func _timeline() -> Dictionary:
	return _load_json(_animations, _model, animations_file(_model))


func _cues() -> Dictionary:
	return _load_json(_sound_cues, _model, sound_cues_file(_model))


static func _load_json(cache: Dictionary, model: String, path: String) -> Dictionary:
	if not cache.has(model):
		cache[model] = {}
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				cache[model] = parsed
	return cache[model]


static func _load_shadow_layout() -> Dictionary:
	if not _shadow_layout_loaded:
		_shadow_layout_loaded = true
		var file: FileAccess = FileAccess.open(SHADOW_FILE, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_shadow_layout = parsed
	return _shadow_layout


# Moves the doll through one frame of krinMelee's swing. The dash eases out
# while the run label plays, and the label holds its last frame if the doll has
# not arrived by then. The strike plays straight through the clip's
# follow-through frames, and the Runback eases the doll home. The Runback takes its first step on the
# frame it starts, because the original turns the clip round and moves it in
# the same onEnterFrame (frame_42/DoAction_4.as:87-116).
func _animate_melee(delta: float) -> void:
	var frames: float = delta * BattleScreenClip.fps()
	match _melee_phase:
		MeleePhase.DASH:
			if _state == State.MELEE:
				_playhead = minf(_playhead + frames, _label_end_frame("run"))
				_apply_frame_index(int(_playhead))
			_step_toward_target(minf(1.5 - 1.45 * _go_rat(), 1.0), frames)
			if _go_rat() >= 1.0:
				_melee_phase = MeleePhase.STRIKE
				_strike_frames = 0.0
				_show_swing_frame(_label_start_frame(_attack_label), true)
		MeleePhase.STRIKE:
			_strike_frames += frames
			_show_swing_frame(_playhead + frames)
			if not _impact_fired and _strike_frames >= MELEE_IMPACT_FRAMES:
				_impact_fired = true
				attack_connected.emit()
			if _strike_frames >= MELEE_IMPACT_FRAMES + MELEE_RUNBACK_FRAMES:
				_melee_phase = MeleePhase.RUNBACK
				_measure_from(_home_position)
				_show_swing_frame(_label_start_frame("runback"), true)
				_step_home(frames)
		MeleePhase.RUNBACK:
			_play_runback_label(frames)
			_step_home(frames)
		MeleePhase.NONE:
			_play_runback_label(frames)


# Returns krinMelee's goRat, the share of the x distance from _origin to the
# dash's end that the doll has covered.
func _go_rat() -> float:
	return _rel_x / _slow_point


# Moves the doll `coefficient` steps toward where its target stands now, over
# `frames` SWF frames. A step is a sixth of the way from _origin to the target,
# so it grows when the target moves away from _origin. A negative coefficient
# steps back toward _origin.
func _step_toward_target(coefficient: float, frames: float) -> void:
	var target: Vector2 = _target_spot.call()
	var share: float = coefficient * MELEE_STEP_SHARE * frames
	_rel_x += share * (target.x - _origin.x)
	_rel_y += share * (target.y - _origin.y)
	position = _origin + Vector2(_rel_x, _rel_y)


# Shows the swing's `frame` while the doll's state is MELEE. In any other state
# it leaves _playhead alone, because _play_death plays the dead label on the
# same playhead. Every frame the playhead goes through plays its sound cues, as
# the clip's frame scripts do. With `jumped` true the playhead lands on `frame`
# from another label, as gotoAndPlay does, and only that frame's cues play. The
# run and runback labels hold no cue, so only the strike calls this with a
# playhead that crosses one.
func _show_swing_frame(frame: float, jumped: bool = false) -> void:
	if _state != State.MELEE:
		return
	var before: int = int(frame) - 1 if jumped else int(_playhead)
	_playhead = frame
	_apply_frame_index(int(_playhead))
	for index in range(before + 1, int(_playhead) + 1):
		for cue in _cues().get(str(index + 1), []):
			sound_cue.emit(cue)


# The runback label plays to its end and then falls into stand, as its last
# frame's script does (DefineSprite_166_MODEL1/frame_188 and
# DefineSprite_2668_MODEL4/frame_123), whether or not the
# doll is home yet.
func _play_runback_label(frames: float) -> void:
	if _state != State.MELEE:
		return
	_playhead += frames
	if _playhead > _label_end_frame("runback"):
		set_state(State.IDLE)
	else:
		_apply_frame_index(int(_playhead))


func _step_home(frames: float) -> void:
	_step_toward_target(-minf(1.45 * _go_rat(), 1.0), frames)
	if _rel_x * _facing <= MELEE_HOME_TOLERANCE:
		position = _home_position
		_melee_phase = MeleePhase.NONE
		melee_finished.emit()


# The dead label plays through once, and the script on its last frame removes
# the doll before Flash draws that frame (MODEL1's frame 371,
# DefineSprite_166_MODEL1/frame_371/DoAction.as, and MODEL4's frame 306). The
# playhead counts frames, not seconds, because a sum of 1/30 s steps drifts off whole frames and would
# remove the doll a frame early or late.
func _play_death(delta: float) -> void:
	if _label_finished:
		return
	_playhead += delta * BattleScreenClip.fps()
	if _playhead >= _label_end_frame("dead"):
		_label_finished = true
		visible = false
		state_finished.emit(State.DEAD)
		return
	_apply_frame_index(int(_playhead))


# stun(one-shot, MODEL1's 220-239) -> stun2(loop, MODEL1's 240-279 - the clip
# flows into this on its own via the goto on the label's last frame, so phase 1
# just keeps looping the label) -> outofstun(one-shot, MODEL1's 280-295)
# triggered by exit_stun().
func _animate_stun(delta: float) -> void:
	match _stun_phase:
		0:
			_advance_label(delta, false)
			if _label_finished:
				_stun_phase = 1
				_start_label("stun2")
		1:
			_advance_label(delta, true)
		2:
			_advance_label(delta, false)
			if _label_finished:
				set_state(State.IDLE)


func _add_layer(part: Node2D, path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var entry: Dictionary = _load_offsets().get(path.get_file().get_basename(), {})
	if entry.is_empty():
		return  # 1x1 placeholder art (empty part in the original)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load(path)
	sprite.centered = false
	sprite.position = Vector2(entry["x"], entry["y"])
	var texture_size: Vector2 = sprite.texture.get_size()
	sprite.scale = Vector2(entry["w"] / texture_size.x, entry["h"] / texture_size.y)
	part.add_child(sprite)


static func _load_offsets() -> Dictionary:
	if not _offsets_loaded:
		_offsets_loaded = true
		var file: FileAccess = FileAccess.open(OFFSETS_FILE, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_offsets = parsed
	return _offsets


# krinAddNewUnit's equip fill: skinSetter (a looks key like "ZPCI") clothes
# armor slots 0-4 wholesale for uniformed enemies; otherwise each equipped
# item id resolves to its GameItem.looks key. Returns the 7-slot looks array
# dress() consumes. items_by_id is passed in (no autoload references here).
static func resolve_equip_looks(unit: CombatUnit, items_by_id: Dictionary) -> Array:
	var looks: Array[Variant] = ["", "", "", "", "", "", ""]
	var start_slot: int = 0
	if unit.skin_setter != "":
		for i in 5:
			looks[i] = unit.skin_setter
		start_slot = 5
	for i in range(start_slot, 7):
		if i >= unit.equipment_ids.size():
			break
		var item_id: int = int(unit.equipment_ids[i])
		if item_id == 0:
			continue
		var item = items_by_id.get(item_id)
		if item != null and item.looks != "":
			looks[i] = item.looks
	return looks


# equip entries are Variants (looks String, or int 0 for empty) - never
# compare String to int directly, GDScript errors on mixed-type '=='.
func _equip_looks(equip: Array, slot: int) -> String:
	if slot < 0 or slot >= equip.size():
		return ""
	var value = equip[slot]
	if value == null:
		return ""
	var text: String = str(value)
	if text == "" or text == "0":
		return ""
	return text
