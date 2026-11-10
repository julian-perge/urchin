# character_visual.gd
# 2D paper-doll character, the replacement for the abandoned Skeleton2D + IK
# rig. Ported from the original Flash MODEL1 clip + dressChar()
# (frame217_KRIN_BATTLE_SCENE/2_dressing_chars.txt):
#
# - The doll is a flat set of Sprite2D "parts" (head/chest/arms/legs/weapons),
#   each at a fixed rest transform pulled directly from the MODEL1 timeline
#   (exact translate/scale/rotate from the SWF, twips -> px). No bones, no IK -
#   the original was nested MovieClips with keyframe tweens, which maps to plain
#   Node2D transforms.
# - Each part composites up to three texture layers: the base skin
#   (<G>_S<CODE>_<skin>), the equipped-item art (<G>_<CODE>_<looks> for armor,
#   M_<CODE>_<looks> for weapons), and hair on the head. dress() rebuilds them.
# - Animation plays the original MODEL1 keyframe timeline directly (stand/
#   run/Attack*/runback/cast/stun/stun2/outofstun/hit/dead); only the melee
#   run-to-target motion is code-driven (the original's krinMelee/krinBoltMake
#   were code too, not a skeletal solve) - see DECODED_ALGORITHMS.md.
#
# No autoload references - textures load from res:// paths directly.
class_name CharacterVisual
extends Node2D

signal attack_connected  # the swing's Impact, when the blow lands
signal state_finished(state: int)
signal melee_finished  # the Runback has brought the doll home

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
# The original MODEL1 keyframe animations (extract_model1_animations.py):
# per-frame full affine matrices per part, 30 fps, labeled segments
# (stand/run/Attack/runback/hit/dead/... - see NEXT_PHASES).
const ANIMATIONS_FILE: String = SPRITE_ROOT + "/model1_animations.json"

# krinMelee (frame_42/DoAction_4.as:36-135) moves the fighter on every frame of
# its swing:
# - Each step moves the fighter a sixth of the way from its home to where the
#   target stands that frame, times a coefficient. The sixth is krinBodyMove
#   (10) over krinBoltTime (60) (lines 112-116 and 213-216).
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
#   (lines 117-123).
const MELEE_STEP_SHARE: float = 10.0 / 60.0
const MELEE_IMPACT_FRAMES: float = 15.0
const MELEE_RUNBACK_FRAMES: float = 14.0
const MELEE_HOME_TOLERANCE: float = 0.000001

static var _offsets: Dictionary = {}
static var _offsets_loaded: bool = false
static var _animations: Dictionary = {}
static var _animations_loaded: bool = false

# dollPartsArray order (also the back-to-front draw order once sorted by z).
# tx/ty/sx/sy/rot are the exact MODEL1 rest-pose matrix (SWF twips converted
# to px); z is the original depth (higher = drawn in front). skin_code is the
# base-skin part code (dollPartsCores2); equip_slot indexes the 7-slot
# equip_array (dollPartsCores). Thighs (leg1/leg2) reuse the ARM art, exactly
# as the original does.
const REST_POSE: Dictionary[Variant, Variant] = {
	"arm2":     {"tx": 7.9,   "ty": -18.4, "sx": 0.80,  "sy": 0.80, "rot": -2,  "z": 3,  "skin_code": "ARM",      "equip_slot": 1},
	"hand2":    {"tx": 11.6,  "ty": -8.5,  "sx": -0.71, "sy": 0.71, "rot": 153, "z": 5,  "skin_code": "HAND",     "equip_slot": 2},
	"weapon2":  {"tx": 18.8,  "ty": -17.9, "sx": 0.76,  "sy": 0.76, "rot": 19,  "z": 7,  "skin_code": "WEAPON",   "equip_slot": 6},
	"foot2":    {"tx": 10.9,  "ty": 32.7,  "sx": 0.80,  "sy": 0.80, "rot": 0,   "z": 9,  "skin_code": "FOOT",     "equip_slot": 4},
	"leg2":     {"tx": 6.0,   "ty": 4.8,   "sx": 0.79,  "sy": 0.66, "rot": -35, "z": 11, "skin_code": "ARM",      "equip_slot": 3},
	"leg4":     {"tx": 9.3,   "ty": 21.4,  "sx": 0.80,  "sy": 0.80, "rot": 1,   "z": 13, "skin_code": "LEG2",     "equip_slot": 4},
	"foot1":    {"tx": -11.1, "ty": 37.4,  "sx": 1.00,  "sy": 1.00, "rot": -2,  "z": 15, "skin_code": "FOOT",     "equip_slot": 4},
	"leg1":     {"tx": -2.4,  "ty": 3.7,   "sx": 1.18,  "sy": 0.99, "rot": 8,   "z": 17, "skin_code": "ARM",      "equip_slot": 3},
	"leg3":     {"tx": -8.6,  "ty": 24.2,  "sx": 0.93,  "sy": 0.93, "rot": 21,  "z": 19, "skin_code": "LEG2",     "equip_slot": 4},
	"chest":    {"tx": 0.5,   "ty": -16.9, "sx": 0.99,  "sy": 0.99, "rot": 7,   "z": 21, "skin_code": "CHEST",    "equip_slot": 1},
	"head":     {"tx": 4.8,   "ty": -33.8, "sx": 1.00,  "sy": 1.00, "rot": 0,   "z": 23, "skin_code": "HEAD",     "equip_slot": 0},
	"arm1":     {"tx": -7.1,  "ty": -20.0, "sx": 0.88,  "sy": 0.88, "rot": 28,  "z": 25, "skin_code": "ARM",      "equip_slot": 1},
	"shoulder": {"tx": -4.5,  "ty": -27.1, "sx": 1.00,  "sy": 1.00, "rot": 0,   "z": 27, "skin_code": "SHOULDER", "equip_slot": 1},
	"weapon1":  {"tx": 9.2,   "ty": -19.2, "sx": 0.87,  "sy": 0.87, "rot": 30,  "z": 29, "skin_code": "WEAPON",   "equip_slot": 5},
	"hand1":    {"tx": -5.4,  "ty": -7.5,  "sx": 0.69,  "sy": 0.69, "rot": -47, "z": 31, "skin_code": "HAND",     "equip_slot": 5},
}

# Menus show the doll as a static mannequin (the original only animates in
# battle and cutscenes) - flip this off to freeze the rest pose.
@export var animate: bool = true

var _parts: Dictionary = {}  # name -> Node2D holding the layered sprites
var _body: Node2D
var _state: int = State.IDLE
var _attack_fired: bool = false

# Timeline playback (labels from model1_animations.json).
var _label: String = ""
var _label_time: float = 0.0
var _label_finished: bool = false
# The melee swing. krinMelee moves the fighter's clip whatever its inner doll
# plays (frame_42/DoAction_4.as:67-135), so the swing goes on through any
# set_state(), and the doll shows the swing's labels only while its state is
# MELEE. The strike and runback play the timeline continuously from _playhead,
# because the original clip flows Attack -> attack2 -> runback on its own.
var _melee_phase: MeleePhase = MeleePhase.NONE
var _home_position: Vector2 = Vector2.ZERO
var _attack_label: String = "Attack"
var _playhead: float = 0.0  # continuous 0-based frame position
var _strike_frames: float = 0.0  # SWF frames since the strike started
var _impact_fired: bool = false
# krinMelee's targetMC, faceing, slowPoint and relX. _target_spot returns where
# the target stands now, as a spot for this doll, and an in-place strike has
# none. _facing is 1 when the target is to the right of home. _slow_point is
# the dash's x distance from home, and _rel_x and _rel_y are how far the doll
# stands from home.
var _target_spot: Callable = Callable()
var _facing: float = 1.0
var _slow_point: float = 0.0
var _rel_x: float = 0.0
var _rel_y: float = 0.0
# Stun sub-phase: 0 "stun" entry (one-shot), 1 "stun2" hold (loop, entered
# automatically when the entry finishes - baked into the clip itself, no
# code needed), 2 "outofstun" exit (one-shot, ends back at idle).
var _stun_phase: int = 0


func _ready():
	_body = Node2D.new()
	_body.name = "Body"
	add_child(_body)
	var ordered: Array = REST_POSE.keys()
	ordered.sort_custom(func(a, b): return REST_POSE[a]["z"] < REST_POSE[b]["z"])
	for part_name in ordered:
		var pose = REST_POSE[part_name]
		var part: Node2D = Node2D.new()
		part.name = part_name
		part.position = Vector2(pose["tx"], pose["ty"])
		part.scale = Vector2(pose["sx"], pose["sy"])
		part.rotation_degrees = pose["rot"]
		_body.add_child(part)
		_parts[part_name] = part
	# Animated dolls start on the original stand loop; static mannequins
	# (menus) keep the rest pose above.
	if animate:
		set_state(State.IDLE)


# dressChar port. gender "M"/"F", skin/hair keys, equip = 7-slot Array of
# item "looks" strings (0 or "" = bare). Rebuilds every part's texture layers.
func dress(gender: String, skin: String, hair: String, equip: Array) -> void:
	for part_name in _parts:
		var part: Node2D = _parts[part_name]
		for child in part.get_children():
			child.queue_free()
		var pose = REST_POSE[part_name]
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
	_label_time = 0.0
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
	_start_swing(MeleePhase.DASH, attack_label)
	_playhead = _label_start_frame("run")
	_apply_frame_index(int(_playhead))
	_target_spot = target_spot
	var target_x: float = target_spot.call().x
	var reach: float = target_half_width + get_bounds().size.x / 2.0
	_facing = 1.0 if _home_position.x < target_x else -1.0
	_slow_point = target_x - _facing * reach - _home_position.x


# A strike without the run: plays the attack label where the doll stands,
# flowing through the clip's own follow-through frames, and its Runback ends
# at once. Same signals as play_melee. Nothing in the battle calls it, because
# the original's Shock moves play "cast".
func play_strike(attack_label: String = "Attack") -> void:
	_start_swing(MeleePhase.STRIKE, attack_label)
	_playhead = _label_start_frame(_attack_label)
	_target_spot = Callable()
	_slow_point = 0.0


# A swing that starts while the doll is still in its Runback keeps the doll's
# home and starts from where the doll stands. The original takes the clip's
# position at that moment as its new home (krinMelee's boltx,
# frame_42/DoAction_4.as:38-39), which leaves the fighter short of its slot
# for the rest of the battle. ADR 0005 counts that as an Original bug.
func _start_swing(phase: MeleePhase, attack_label: String) -> void:
	if _melee_phase != MeleePhase.RUNBACK:
		_home_position = position
	set_state(State.MELEE)
	_melee_phase = phase
	_attack_label = _valid_attack_label(attack_label)
	_strike_frames = 0.0
	_impact_fired = false
	_rel_x = position.x - _home_position.x
	_rel_y = position.y - _home_position.y


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
	var animations: Dictionary = _load_animations()
	if animations.get("labels", {}).has(label):
		return label
	return "Attack"


func is_idle() -> bool:
	return _state == State.IDLE


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


# --- timeline playback (model1_animations.json) ------------------------------

func _start_label(label: String) -> void:
	_label = label
	_label_time = 0.0
	_label_finished = false
	_apply_label_frame(label, 0.0)


func _label_duration(label: String) -> float:
	var animations: Dictionary = _load_animations()
	var segment: Dictionary = animations.get("labels", {}).get(label, {})
	if segment.is_empty():
		return 0.5
	var fps: float = animations.get("fps", 30.0)
	return (float(segment["end"]) - float(segment["start"]) + 1.0) / fps


func _advance_label(delta: float, loop: bool) -> void:
	_label_time += delta
	var duration: float = _label_duration(_label)
	if loop:
		_label_time = fmod(_label_time, duration)
	elif _label_time >= duration:
		_label_time = duration
		_label_finished = true
	_apply_label_frame(_label, _label_time)


# Applies the pose at `time` seconds into a labeled segment: every part gets
# the original frame's full affine matrix (rotation, scale, AND skew).
func _apply_label_frame(label: String, time: float) -> void:
	var animations: Dictionary = _load_animations()
	var segment: Dictionary = animations.get("labels", {}).get(label, {})
	if segment.is_empty():
		return
	var fps: float = animations.get("fps", 30.0)
	var start: int = int(segment["start"]) - 1
	var end: int = int(segment["end"]) - 1
	_apply_frame_index(clampi(start + int(time * fps), start, end))


func _apply_frame_index(index: int) -> void:
	var animations: Dictionary = _load_animations()
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
	var segment: Dictionary = _load_animations().get("labels", {}).get(label, {})
	return float(int(segment.get("start", 1)) - 1)


func _label_end_frame(label: String) -> float:
	var segment: Dictionary = _load_animations().get("labels", {}).get(label, {})
	return float(int(segment.get("end", 1)) - 1)


static func _load_animations() -> Dictionary:
	if not _animations_loaded:
		_animations_loaded = true
		var file: FileAccess = FileAccess.open(ANIMATIONS_FILE, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_animations = parsed
	return _animations


# The faithful krinMelee: ease-out dash (the run label freezes on its glide
# and gets interrupted by arrival), strike playing straight through the
# clip's follow-through frames, then the eased run home. The Runback takes its
# first step on the frame it starts, because the original turns the clip round
# and moves it in the same onEnterFrame (frame_42/DoAction_4.as:87-116).
func _animate_melee(delta: float) -> void:
	var frames: float = delta * _load_animations().get("fps", 30.0)
	match _melee_phase:
		MeleePhase.DASH:  # run label plays but arrival is movement-driven
			if _state == State.MELEE:
				_playhead = minf(_playhead + frames, _label_end_frame("run"))
				_apply_frame_index(int(_playhead))
			_step_toward_target(minf(1.5 - 1.45 * _go_rat(), 1.0), frames)
			if _go_rat() >= 1.0:
				_melee_phase = MeleePhase.STRIKE
				_strike_frames = 0.0
				_show_swing_frame(_label_start_frame(_attack_label))
		MeleePhase.STRIKE:  # continuous playback through the follow-through
			_strike_frames += frames
			_show_swing_frame(_playhead + frames)
			if not _impact_fired and _strike_frames >= MELEE_IMPACT_FRAMES:
				_impact_fired = true
				attack_connected.emit()
			if _strike_frames >= MELEE_IMPACT_FRAMES + MELEE_RUNBACK_FRAMES:
				_melee_phase = MeleePhase.RUNBACK
				_show_swing_frame(_label_start_frame("runback"))
				_step_home(frames)
		MeleePhase.RUNBACK:  # eased return while the runback label plays out
			_play_runback_label(frames)
			_step_home(frames)
		MeleePhase.NONE:
			_play_runback_label(frames)


# krinMelee's goRat: the share of the dash's x distance the doll has covered.
# An in-place strike has no distance, so it has covered none.
func _go_rat() -> float:
	return _rel_x / _slow_point if _slow_point != 0.0 else 0.0


# Moves the doll `coefficient` steps toward where its target stands now, over
# `frames` SWF frames. A step is a sixth of the way from the doll's home to the
# target, so it grows when the target moves away from that home. A negative
# coefficient steps back toward home.
func _step_toward_target(coefficient: float, frames: float) -> void:
	if not _target_spot.is_valid():
		return
	var target: Vector2 = _target_spot.call()
	var share: float = coefficient * MELEE_STEP_SHARE * frames
	_rel_x += share * (target.x - _home_position.x)
	_rel_y += share * (target.y - _home_position.y)
	position = _home_position + Vector2(_rel_x, _rel_y)


# Shows the swing's `frame` while the doll plays its swing. Any other state
# keeps the playhead, which the dead label also plays on.
func _show_swing_frame(frame: float) -> void:
	if _state == State.MELEE:
		_playhead = frame
		_apply_frame_index(int(_playhead))


# The runback label plays to its end and then falls into stand, as its last
# frame's script does (DefineSprite_166_MODEL1/frame_188), whether or not the
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


# The dead label plays through once, and the script on its last frame, 371,
# removes the doll before Flash draws that frame
# (DefineSprite_166_MODEL1/frame_371/DoAction.as). The playhead counts frames,
# not seconds, because a sum of 1/30 s steps drifts off whole frames and would
# remove the doll a frame early or late.
func _play_death(delta: float) -> void:
	if _label_finished:
		return
	_playhead += delta * _load_animations().get("fps", 30.0)
	if _playhead >= _label_end_frame("dead"):
		_label_finished = true
		visible = false
		state_finished.emit(State.DEAD)
		return
	_apply_frame_index(int(_playhead))


# stun(220-239, one-shot) -> stun2(240-279, loop - the clip flows into this
# on its own via its own frame-279 goto, so phase 1 just keeps looping the
# label) -> outofstun(280-295, one-shot) triggered by exit_stun().
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
