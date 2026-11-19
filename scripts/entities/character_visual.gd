# character_visual.gd
# 2D paper-doll character, the replacement for the abandoned Skeleton2D + IK
# rig. Ported from the original Flash model clips (MODEL1, MODEL2 and MODEL4 to
# MODEL9) + dressChar() (frame217_KRIN_BATTLE_SCENE/2_dressing_chars.txt):
#
# - The doll is a flat set of Sprite2D "parts" (head/chest/arms/legs/weapons),
#   whose rest pose is frame 1 of the model's timeline (the exact affine matrix
#   from the SWF, twips -> px). No bones, no IK - the original was nested
#   MovieClips with keyframe tweens, which maps to plain Node2D transforms.
# - Each part composites up to three texture layers: the base skin
#   (<G>_S<CODE>_<skin>), the equipped-item art (<G>_<CODE>_<looks> for armor,
#   M_<CODE>_<looks> for weapons), and hair on the head. dress() rebuilds them.
#   A part that the model's frame does not place is hidden.
# - The art a model places with no part name, such as MODEL8's body,
#   MODEL2's orb and the swing trails, cast glow and stun mark of every model,
#   draws as "pieces" between the parts in the model's depth order
#   (extract_model_pieces).
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
# Flash draws a filter's blur in stage px at any scale, and a PNG carries its
# glow baked at one scale. So extract_doll_art renders each art with a filter
# once per scale the game can draw it at, and this file lists those renders:
# name -> [{scale, art, x, y, w, h}], the render made for scale 1 first.
# _fit_glow_renders() shows the render made for the scale nearest the one each
# part is drawn at.
const GLOW_FILE: String = SPRITE_ROOT + "/glow_scales.json"
# The models whose own clip the doll plays, as extract_model_animations and
# convert_model_sound_cues write them, which is every model the SWF exports.
# dressChar attaches the unit's model[0] clip (frame_217/DoAction_2.as:17). A
# model outside this list plays MODEL1's clip.
const CLIP_MODELS: Array[String] = ["MODEL1", "MODEL2", "MODEL4", "MODEL5", "MODEL6", "MODEL7", "MODEL8", "MODEL9"]
const DEFAULT_MODEL: String = "MODEL1"
# Each model's keyframe animations (animations_file): per-frame full affine
# matrices per part, 30 fps, labeled segments (stand/run/Attack/runback/hit/
# dead/... - see DECODED_ALGORITHMS.md), and each part's depth.
const ANIMATIONS_PATTERN: String = SPRITE_ROOT + "/%s_animations.json"
# The sounds each model's frame scripts play (sound_cues_file): the 1-based
# frame as a string -> the cue names of that frame. Only the swing labels hold
# a cue, "sfx_swing".
const SOUND_CUES_PATTERN: String = "res://dev/converted_json/%s_sound_cues.json"
# The art each model places with no part name (pieces_file), and its PNGs. A
# model with no such art has no file.
const PIECES_PATTERN: String = SPRITE_ROOT + "/%s_pieces.json"
const PIECE_ART: String = SPRITE_ROOT + "/model_pieces/%s.png"
const PIECE_SHADER: Shader = preload("res://scenes/doll_piece.gdshader")

# krinMelee (frame_42/DoAction_4.as:36-135) moves the fighter on every frame of
# its swing:
# - Each step moves the fighter a sixth of the way from where it stood when the
#   swing started to where the target stands that frame, times a coefficient.
#   The sixth is krinBodyMove (10) over krinBoltTime (60) (lines 38-39, 112-116
#   and 213-216).
# - The dash's coefficient is krinMeleeDashBase - krinMeleeDashSlope * goRat,
#   at most krinMeleeStepCap, where goRat is the share of the dash's x distance
#   covered so far (lines 99-111). The dash ends on the first frame that covers
#   it all, and the strike label cuts the run label off. The dash runs to the
#   target's x less both fighters' half-widths, read once when the swing starts
#   (lines 46-56), so half-widths that take up more of the distance make the
#   dash shorter.
# - Impact comes krinMeleeAttackCD (15) frames after the strike label starts.
#   krinMeleeAttackEndCD is 15 too, but its count starts on the frame that
#   raised the impact flag (lines 87-95), so the Runback starts 14 frames
#   after Impact.
# - The Runback steps back toward home with the coefficient
#   krinMeleeRunbackSlope * goRat, at most krinMeleeStepCap. It puts the
#   fighter home on the first frame that leaves it no more than
#   krinMeleeHomeTolerance px from home along x, on the target's side
#   (lines 117-123). The original's home is where the swing started. The
#   port's is the doll's own, and the port measures the Runback from it (see
#   play_melee).
# The label that set_state() starts for each one-shot state, which a model's
# clip can lack.
const STATE_LABELS: Dictionary = {State.HIT: "hit", State.CAST: "cast", State.STUN: "stun"}
# krinMelee reads krinBodyMove, krinBoltTime, krinMeleeAttackCD and
# krinMeleeAttackEndCD, which frame_42/DoAction_4.as sets at lines 213-218. It
# also writes the numbers that extract_krin_settings names krinMeleeDashBase,
# krinMeleeDashSlope, krinMeleeRunbackSlope, krinMeleeStepCap and
# krinMeleeHomeTolerance as literals at lines 102-117. extract_krin_settings
# writes them all to this file.
const KRIN_SETTINGS_PATH: String = "res://assets/battle/krin_settings.json"
static var _krin: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(KRIN_SETTINGS_PATH))
static var _melee_step_share: float = float(_krin["krinBodyMove"]) / float(_krin["krinBoltTime"])
static var _melee_impact_frames: float = float(_krin["krinMeleeAttackCD"])
# The end counter counts the frame of Impact, so the Runback starts one frame
# before krinMeleeAttackEndCD frames have passed after Impact.
static var _melee_runback_frames: float = float(_krin["krinMeleeAttackEndCD"]) - 1.0
static var _melee_dash_base: float = float(_krin["krinMeleeDashBase"])
static var _melee_dash_slope: float = float(_krin["krinMeleeDashSlope"])
static var _melee_runback_slope: float = float(_krin["krinMeleeRunbackSlope"])
static var _melee_step_cap: float = float(_krin["krinMeleeStepCap"])
static var _melee_home_tolerance: float = float(_krin["krinMeleeHomeTolerance"])

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
static var _glow_renders: Dictionary = {}
static var _glow_renders_loaded: bool = false
# model -> the parsed animations_file and sound_cues_file of that model.
static var _animations: Dictionary = {}
static var _sound_cues: Dictionary = {}
static var _pieces: Dictionary = {}
# The PIECE_SHADER material that every doll sprite with no colour transform of
# its own shares, so that it samples its mipmaps with the shader's bias. Every
# doll on screen draws with it, so a sprite that needs its own shader
# parameters gets its own material first, as _apply_pieces does.
static var _plain_piece_material: ShaderMaterial

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
# The model whose clip the doll plays until start_clip() picks another. The
# Inventory's female doll is MODEL4, because the original menu's _f part clips
# hold MODEL4's first frame, as its male clips hold MODEL1's.
@export var rest_model: String = DEFAULT_MODEL

var _parts: Dictionary = {}  # name -> Node2D holding the layered sprites
# The model's depth as a String -> the Sprite2D that draws its piece there.
var _piece_nodes: Dictionary = {}
# The model's depth as a String -> the clip piece that plays there: its "clip"
# and "since" from the pieces file, the _clip_frames value it was placed on,
# which starts its own clock, and the "tint" its tinted part took then.
var _piece_runs: Dictionary = {}
# The original's colortobe on the doll's clip. A clip piece's tinted part takes
# it as its colour when the model places the clip, as its onClipEvent(load) runs
# setRGB(colortobe) (DefineSprite_162/frame_1/PlaceObject2_161_1). The
# conductor sets it to the move's param 11 before a cast's goto, and krinMelee
# after a swing's goto (frame_217/PlaceObject2_3389_480 enterFrame, lines 417
# and 450, and frame_42/DoAction_4.as:130-131).
var colortobe: Color = Color.WHITE
# The 0-based model frame the doll shows, and the SWF frames since the clip
# started. A clip piece shows the frame of its own clip that this count has
# reached since the model placed it.
var _frame_index: int = 0
var _clip_frames: float = 0.0
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
# The move's colour, which the strike sets as colortobe.
var _attack_color: Color = Color.WHITE
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
	if not CLIP_MODELS.has(rest_model):
		push_error("%s: rest_model %s is not one of %s" % [get_path(), rest_model, CLIP_MODELS])
	_model = rest_model if CLIP_MODELS.has(rest_model) else DEFAULT_MODEL
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
	# (menus) keep the first frame of rest_model.
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
# the doll draws its parts and pieces in the model's depth order and plays the
# model's labels and sound cues, or MODEL1's for a model outside CLIP_MODELS.
# changeForm then puts a stunned unit's new clip in the stun loop
# (frame_42/DoAction_10.as:533-536).
func start_clip(model: String, stunned: bool = false) -> void:
	show_shadow(model)
	_model = model if CLIP_MODELS.has(model) else DEFAULT_MODEL
	_clip_frames = 0.0
	_build_pieces()
	_order_parts()
	set_state(State.IDLE)
	if stunned and _has_label("stun2"):
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
	var art := Transform2D(0.0, Vector2(rect["w"] / size.x, rect["h"] / size.y), 0.0, Vector2(rect["x"], rect["y"]))
	shadow.set_meta("art", art)
	shadow.transform = placed * art
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
	_fit_glow_renders()


# Convenience: dress straight from a CombatUnit-style model array
# (["MODELx", skin, hair, gender]) plus its 7-slot equip looks.
func dress_from_model(model: Array, equip_looks: Array) -> void:
	var gender = model[3] if model.size() > 3 else "M"
	var skin = model[1] if model.size() > 1 else "ONE"
	var hair = model[2] if model.size() > 2 else ""
	dress(gender, skin, hair, equip_looks)


# A state whose label the model's clip lacks changes nothing, such as a hit on
# MODEL2, which has no hit label, because Flash ignores a goto to a label the
# clip does not have and the clip plays on.
func set_state(new_state: State) -> void:
	if STATE_LABELS.has(new_state) and not _has_label(STATE_LABELS[new_state]):
		return
	_state = new_state
	_attack_fired = false
	_label_frames = 0.0
	_label_finished = false
	# Reset the transient transforms the previous state left behind (hit
	# recoil x-offset, stun tilt) - without this the doll keeps
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
# The strike sets colortobe to attack_color, the move's param 11, which tints
# the swing trail. Emits attack_connected at Impact and melee_finished once the
# Runback has brought the doll home.
func play_melee(target_spot: Callable, target_half_width: float, attack_label: String = "Attack", attack_color: Color = Color.WHITE) -> void:
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
	_attack_color = attack_color
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
	if not _has_label("stun"):
		return
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


# krinMelee sends the clip to the move's label with gotoAndPlay
# (frame_42/DoAction_4.as:130). Flash ignores a goto to a label the clip does
# not have, as Ruffle's goto_frame does (core/src/avm1/globals/movie_clip.rs),
# so Gregor's Attack_Stab on MODEL7 leaves the doll in its run label. This
# returns "" for such a label.
func _valid_attack_label(label: String) -> String:
	return label if _has_label(label) else ""


func _has_label(label: String) -> bool:
	return _timeline().get("labels", {}).has(label)


func current_state() -> State:
	return _state as State


# -> the label the doll plays now, such as "stun" or "outofstun".
func current_label() -> String:
	return _label


# -> how many frames of the current label have played.
func label_frames() -> float:
	return _label_frames


func home_position() -> Vector2:
	return _home_position


func melee_phase() -> MeleePhase:
	return _melee_phase


# -> the swing label the doll plays for the melee that play_melee() started.
func attack_label() -> String:
	return _attack_label


# -> the Node2D that holds one body part's layered sprites, such as "head".
func part(part_name: String) -> Node2D:
	return _parts[part_name]


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


# The box around every part and piece the doll draws in its current pose, in
# its parent's space, which is where Flash measures a clip's _width and _height.
# Flash measures the parts' shapes without their filters, and some part PNGs
# carry a filter's glow, so this box can come out bigger than the original's.
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
	for piece in _piece_nodes.values():
		if not piece.visible:
			continue
		for sprite in [piece, piece.get_node_or_null("Tint")]:
			if sprite == null or not sprite.visible or sprite.texture == null:
				continue
			var to_parent: Transform2D = transform * _body.transform * piece.transform
			if sprite != piece:
				to_parent *= sprite.transform
			var rect: Rect2 = to_parent * sprite.get_rect()
			bounds = bounds.merge(rect) if found else rect
			found = true
	return bounds


func _process(delta: float) -> void:
	if animate:
		_animate(delta)
	_fit_glow_renders()


func _animate(delta: float) -> void:
	_clip_frames += delta * BattleScreenClip.fps()
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
	_apply_label_frame(_label, _label_frames, true)


# Applies the pose `frames` SWF frames into a labeled segment: every part gets
# the original frame's full affine matrix (rotation, scale, AND skew).
func _apply_label_frame(label: String, frames: float, played: bool = false) -> void:
	var animations: Dictionary = _timeline()
	var segment: Dictionary = animations.get("labels", {}).get(label, {})
	if segment.is_empty():
		return
	var start: int = int(segment["start"]) - 1
	var end: int = int(segment["end"]) - 1
	_apply_frame_index(clampi(start + int(frames), start, end), played)


# Shows the model's frame `index`. `played` is true when the playhead plays on to
# it, and false when a goto lands on it.
func _apply_frame_index(index: int, played: bool = false) -> void:
	var animations: Dictionary = _timeline()
	var frames: Array = animations.get("frames", [])
	if frames.is_empty():
		return
	var frame: int = clampi(index, 0, frames.size() - 1)
	var previous: int = _frame_index
	_frame_index = frame
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
	_apply_shadow(animations.get("shadow", []), frame)
	_apply_pieces(previous if played else -1)


# Puts the shadow on `frame`'s matrix for it, or hides it on a frame that does
# not place it. A timeline with no shadow list leaves it where show_shadow put
# it.
func _apply_shadow(shadows: Array, frame: int) -> void:
	var shadow: Node2D = _body.get_node_or_null("Shadow")
	if shadow == null or frame >= shadows.size():
		return
	var matrix = shadows[frame]
	shadow.visible = matrix != null
	if matrix != null:
		shadow.transform = Transform2D(Vector2(matrix[0], matrix[1]), Vector2(matrix[2], matrix[3]), Vector2(matrix[4], matrix[5])) * shadow.get_meta("art")


# Makes one Sprite2D for each depth at which the model places a piece, in place
# of the last model's.
func _build_pieces() -> void:
	for node in _piece_nodes.values():
		_body.remove_child(node)
		node.queue_free()
	_piece_nodes.clear()
	_piece_runs.clear()
	var depths: Dictionary = {}
	for shown in _piece_data().get("frames", []):
		for depth in shown:
			depths[depth] = true
	for depth in depths:
		var sprite := Sprite2D.new()
		sprite.name = "Piece%s" % depth
		sprite.centered = false
		sprite.visible = false
		_sample_mipmaps(sprite)
		_body.add_child(sprite)
		_piece_nodes[depth] = sprite


# Shows each piece as the model's frame _frame_index places it. A clip piece
# shows the frame of its own clip that its clock has reached, with the model
# frame's matrix and colour transform. Its clock runs on while the frame shows
# the same placement, so a goto that lands on that placement, such as stun2's
# goto back to its own first frame, does not restart it. `played_from` is the
# 0-based frame the playhead played on from, or -1 after a goto. A clip that
# the playhead played past the placing frame of, as a slow frame does, has played
# one frame for each frame since, and a goto starts a clip on its frame 1.
func _apply_pieces(played_from: int = -1) -> void:
	if _piece_nodes.is_empty():
		return
	var data: Dictionary = _piece_data()
	var frames: Array = data["frames"]
	var shown: Dictionary = frames[mini(_frame_index, frames.size() - 1)]
	for depth in _piece_nodes:
		var sprite: Sprite2D = _piece_nodes[depth]
		var entry = shown.get(depth)
		sprite.visible = entry != null
		if not entry is Dictionary:
			_piece_runs.erase(depth)
		if entry == null:
			continue
		if entry is String:
			sprite.material = _plain_material()
			_show_piece_art(sprite, entry, Transform2D.IDENTITY)
			_show_tint(sprite, "", Transform2D.IDENTITY, [], Color.WHITE)
			continue
		var run: Dictionary = _piece_runs.get(depth, {})
		if run.get("clip") != entry["clip"] or run.get("since") != entry["since"]:
			var skipped: int = 0
			if played_from >= 0 and played_from + 1 < int(entry["since"]):
				skipped = _frame_index + 1 - int(entry["since"])
			run = {"clip": entry["clip"], "since": entry["since"], "start": _clip_frames - skipped, "tint": colortobe}
			_piece_runs[depth] = run
		var clip: Dictionary = data["clips"][entry["clip"]]
		var frame: int = _clip_frame(clip, int(_clip_frames - run["start"]))
		var m: Array = entry["matrix"]
		var c: Array = entry["color"]
		var placed := Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5]))
		_show_piece_art(sprite, clip["frames"][frame], placed)
		if sprite.material == _plain_material():
			sprite.material = ShaderMaterial.new()
			sprite.material.shader = PIECE_SHADER
		sprite.material.set_shader_parameter("multiplier", Vector4(c[0], c[1], c[2], c[3]))
		sprite.material.set_shader_parameter("offset", Vector4(c[4], c[5], c[6], c[7]))
		_show_tint(sprite, clip["tints"][frame] if clip.has("tints") else "", placed, c, run["tint"])


# Returns the 0-based frame a clip piece shows `age` SWF frames after the
# model placed it. It holds its "hold" frame, and loops when it has none.
static func _clip_frame(clip: Dictionary, age: int) -> int:
	if clip.has("hold"):
		return mini(age, int(clip["hold"]) - 1)
	return age % (clip["frames"] as Array).size()


# Draws the PNG `art` at its rect, under `placed`. A frame of a clip that drew
# nothing has no rect and shows no texture, and the sprite keeps `placed` so
# its tinted part can still draw.
func _show_piece_art(sprite: Sprite2D, art: String, placed: Transform2D) -> void:
	var rect: Dictionary = _piece_data()["art"].get(art, {})
	if rect.is_empty():
		sprite.texture = null
		sprite.transform = placed
		return
	var path: String = PIECE_ART % art
	if sprite.texture == null or sprite.texture.resource_path != path:
		sprite.texture = load(path)
	sprite.transform = placed * _art_transform(sprite.texture, rect)


static func _art_transform(texture: Texture2D, rect: Dictionary) -> Transform2D:
	var size: Vector2 = texture.get_size()
	return Transform2D(0.0, Vector2(rect["w"] / size.x, rect["h"] / size.y), 0.0, Vector2(rect["x"], rect["y"]))


# Draws the tinted part `art` of a clip piece behind the rest of the clip, as
# the original's tinted parts sit at the clip's lowest depth. setRGB gives the
# part multipliers of 0 and `tint` as its offsets, and the clip's colour
# transform `color` then applies over that. An empty `art` or one with no rect
# hides the tinted part.
func _show_tint(sprite: Sprite2D, art: String, placed: Transform2D, color: Array, tint: Color) -> void:
	var node: Sprite2D = sprite.get_node_or_null("Tint")
	var rect: Dictionary = _piece_data()["art"].get(art, {}) if art != "" else {}
	if rect.is_empty():
		if node != null:
			node.visible = false
		return
	if node == null:
		node = Sprite2D.new()
		node.name = "Tint"
		node.centered = false
		node.show_behind_parent = true
		node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		node.material = ShaderMaterial.new()
		node.material.shader = PIECE_SHADER
		sprite.add_child(node)
	node.visible = true
	var path: String = PIECE_ART % art
	if node.texture == null or node.texture.resource_path != path:
		node.texture = load(path)
	node.transform = sprite.transform.affine_inverse() * placed * _art_transform(node.texture, rect)
	node.material.set_shader_parameter("multiplier", Vector4(0.0, 0.0, 0.0, color[3]))
	node.material.set_shader_parameter("offset", Vector4(color[0] * tint.r + color[4], color[1] * tint.g + color[5], color[2] * tint.b + color[6], color[7]))


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


static func pieces_file(model: String) -> String:
	return PIECES_PATTERN % model.to_lower()


# Puts the parts and the pieces in the model's depth order, back to front, after
# the shadow.
func _order_parts() -> void:
	var depths: Dictionary = _timeline().get("depths", {})
	var ordered: Array = []
	for part_name in DOLL_PARTS:
		ordered.append([depths.get(part_name, 0), _parts[part_name]])
	for depth in _piece_nodes:
		ordered.append([int(depth), _piece_nodes[depth]])
	ordered.sort_custom(func(a, b): return a[0] < b[0])
	var first: int = 1 if _body.get_node_or_null("Shadow") != null else 0
	for index in ordered.size():
		_body.move_child(ordered[index][1], first + index)


func _timeline() -> Dictionary:
	return _load_json(_animations, _model, animations_file(_model))


func _cues() -> Dictionary:
	return _load_json(_sound_cues, _model, sound_cues_file(_model))


func _piece_data() -> Dictionary:
	return _load_json(_pieces, _model, pieces_file(_model))


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
				_apply_frame_index(int(_playhead), true)
			_step_toward_target(minf(_melee_dash_base - _melee_dash_slope * _go_rat(), _melee_step_cap), frames)
			if _go_rat() >= 1.0:
				_melee_phase = MeleePhase.STRIKE
				_strike_frames = 0.0
				if _attack_label != "":
					_show_swing_frame(_label_start_frame(_attack_label), true)
				colortobe = _attack_color
		MeleePhase.STRIKE:
			_strike_frames += frames
			if _attack_label != "":
				_show_swing_frame(_playhead + frames)
			else:
				# The run label plays on to its last frame, whose script runs stop()
				# (DefineSprite_2631_MODEL7/frame_59), and holds it until the Runback.
				_show_swing_frame(minf(_playhead + frames, _label_end_frame("run")))
			if not _impact_fired and _strike_frames >= _melee_impact_frames:
				_impact_fired = true
				attack_connected.emit()
			if _strike_frames >= _melee_impact_frames + _melee_runback_frames:
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
	var share: float = coefficient * _melee_step_share * frames
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
	_apply_frame_index(int(_playhead), not jumped)
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
		_apply_frame_index(int(_playhead), true)


func _step_home(frames: float) -> void:
	_step_toward_target(-minf(_melee_runback_slope * _go_rat(), _melee_step_cap), frames)
	if _rel_x * _facing <= _melee_home_tolerance:
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
	_apply_frame_index(int(_playhead), true)


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
	_sample_mipmaps(sprite)
	var renders: Array = _load_glow_renders().get(path.get_file().get_basename(), [])
	if not renders.is_empty():
		sprite.set_meta("glow_renders", renders)
	part.add_child(sprite)


# Shows each layer that has glow renders in the render made for the scale
# nearest the one its part is drawn at on the stage. That scale takes in the
# doll's own scale, the battle zoom and a menu's scale, so the glow keeps its
# stage width through all of them, as Flash draws it.
func _fit_glow_renders() -> void:
	for part in _parts.values():
		if not part.visible:
			continue
		var drawn: float = sqrt(absf(part.get_global_transform_with_canvas().determinant()))
		if drawn == 0.0:
			continue
		for layer in part.get_children():
			if not layer.has_meta("glow_renders") or layer.is_queued_for_deletion():
				continue
			var nearest: Dictionary = {}
			for render in layer.get_meta("glow_renders"):
				if nearest.is_empty() or absf(log(render["scale"] / drawn)) < absf(log(nearest["scale"] / drawn)):
					nearest = render
			var path: String = "%s/%s.png" % [SPRITE_ROOT, nearest["art"]]
			if layer.texture.resource_path == path:
				continue
			layer.texture = load(path)
			layer.position = Vector2(nearest["x"], nearest["y"])
			var texture_size: Vector2 = layer.texture.get_size()
			layer.scale = Vector2(nearest["w"] / texture_size.x, nearest["h"] / texture_size.y)


static func _load_glow_renders() -> Dictionary:
	if not _glow_renders_loaded:
		_glow_renders_loaded = true
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(GLOW_FILE))
		if parsed is Dictionary:
			_glow_renders = parsed
	return _glow_renders


# Makes `sprite` draw its texture's mipmaps through PIECE_SHADER, which holds
# the bias that keeps a part's edges sharp when the doll draws it small.
static func _sample_mipmaps(sprite: Sprite2D) -> void:
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.material = _plain_material()


static func _plain_material() -> ShaderMaterial:
	if _plain_piece_material == null:
		_plain_piece_material = ShaderMaterial.new()
		_plain_piece_material.shader = PIECE_SHADER
	return _plain_piece_material


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
