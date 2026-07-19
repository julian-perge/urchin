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
# - Animation is code-driven (the original's krinMelee run was code too, not a
#   skeletal solve): a small state machine in _process applies believable
#   deltas ON TOP of the rest pose. Idle bob, melee swing, cast raise, stun
#   wobble, hit recoil, death fall - the states the project owner asked for.
#
# No autoload references - textures load from res:// paths directly.
class_name CharacterVisual
extends Node2D

signal attack_connected  # emitted mid-swing, when a melee/cast should deal its damage
signal state_finished(state: int)

enum State { IDLE, MELEE, CAST, STUN, HIT, DEAD }

const SPRITE_ROOT = "res://resources/sprites"
# Per-art render bounds extracted from the SWF (extract_doll_offsets.py):
# name -> {x, y, w, h} in px. The PNGs are high-res exports (mostly 10x), so
# each layer is positioned at (x, y) and scaled to w/h - without this every
# part draws top-left-at-joint at export resolution (the giant-blob bug).
const OFFSETS_FILE = SPRITE_ROOT + "/doll_offsets.json"

static var _offsets: Dictionary = {}
static var _offsets_loaded: bool = false

# dollPartsArray order (also the back-to-front draw order once sorted by z).
# tx/ty/sx/sy/rot are the exact MODEL1 rest-pose matrix (SWF twips converted
# to px); z is the original depth (higher = drawn in front). skin_code is the
# base-skin part code (dollPartsCores2); equip_slot indexes the 7-slot
# equip_array (dollPartsCores). Thighs (leg1/leg2) reuse the ARM art, exactly
# as the original does.
const REST_POSE = {
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

# Front-arm chain: the melee swing / cast raise rotate these together.
const FRONT_ARM_PARTS = ["arm1", "weapon1", "hand1", "shoulder"]
const IDLE_BOB_PARTS = ["head", "chest", "shoulder", "arm1", "arm2", "hand1", "hand2", "weapon1", "weapon2"]

# Menus show the doll as a static mannequin (the original only animates in
# battle and cutscenes) - flip this off to freeze the rest pose.
@export var animate: bool = true

var _parts: Dictionary = {}  # name -> Node2D holding the layered sprites
var _body: Node2D
var _state: int = State.IDLE
var _state_time: float = 0.0
var _idle_phase: float = 0.0
var _attack_fired: bool = false


func _ready():
	_body = Node2D.new()
	_body.name = "Body"
	add_child(_body)
	var ordered = REST_POSE.keys()
	ordered.sort_custom(func(a, b): return REST_POSE[a]["z"] < REST_POSE[b]["z"])
	for part_name in ordered:
		var pose = REST_POSE[part_name]
		var part = Node2D.new()
		part.name = part_name
		part.position = Vector2(pose["tx"], pose["ty"])
		part.scale = Vector2(pose["sx"], pose["sy"])
		part.rotation_degrees = pose["rot"]
		_body.add_child(part)
		_parts[part_name] = part


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
		var looks = _equip_looks(equip, pose["equip_slot"])
		if looks != "":
			if pose["skin_code"] == "WEAPON":
				_add_layer(part, "%s/M_WEAPON_%s.png" % [SPRITE_ROOT, looks])
			else:
				# Prefer gender-specific art, fall back to the male sheet
				# (female characters share male equipment art in the original).
				var path = "%s/%s_%s_%s.png" % [SPRITE_ROOT, gender, pose["skin_code"], looks]
				if not ResourceLoader.exists(path):
					path = "%s/M_%s_%s.png" % [SPRITE_ROOT, pose["skin_code"], looks]
				_add_layer(part, path)
		# Hair sits on the head, above the skin - but only when no helmet is
		# equipped (females always show hair; their helmets render over it).
		var show_hair = _equip_looks(equip, 0) == "" or gender == "F"
		if part_name == "head" and show_hair and hair != "" and hair != "0":
			_add_layer(part, "%s/HAIR_%s.png" % [SPRITE_ROOT, hair])


# Convenience: dress straight from a CombatUnit-style model array
# (["MODELx", skin, hair, gender]) plus its 7-slot equip looks.
func dress_from_model(model: Array, equip_looks: Array) -> void:
	var gender = model[3] if model.size() > 3 else "M"
	var skin = model[1] if model.size() > 1 else "ONE"
	var hair = model[2] if model.size() > 2 else ""
	dress(gender, skin, hair, equip_looks)


func set_state(new_state: int) -> void:
	_state = new_state
	_state_time = 0.0
	_attack_fired = false
	# Reset the transient transforms the previous state left behind (hit
	# recoil x-offset, stun tilt, cast tint) - without this the doll keeps
	# rocking/tilting after the state ends.
	if _body != null:
		_body.position = Vector2.ZERO
		_body.rotation = 0.0
	if new_state != State.DEAD:
		modulate = Color.WHITE


func is_idle() -> bool:
	return _state == State.IDLE


func _process(delta: float) -> void:
	if not animate:
		return
	_state_time += delta
	match _state:
		State.IDLE:
			_animate_idle(delta)
		State.MELEE:
			_animate_melee()
		State.CAST:
			_animate_cast()
		State.STUN:
			_animate_stun()
		State.HIT:
			_animate_hit()
		State.DEAD:
			_animate_dead()


# The original stands nearly still - feet planted, only a faint breathing
# drift in the upper body. No whole-body bob.
func _animate_idle(delta: float) -> void:
	_idle_phase += delta * 2.0
	for part_name in IDLE_BOB_PARTS:
		_reset_part_offset(part_name, Vector2(0, sin(_idle_phase) * 0.4), 0.0)


# ~0.45s swing: wind back, snap forward (fires attack_connected at the snap),
# recover. Body leans into it.
func _animate_melee() -> void:
	var t = _state_time / 0.45
	# Fire outside the branch so coarse frames can't step over the window.
	if not _attack_fired and t >= 0.45:
		_attack_fired = true
		attack_connected.emit()
	var swing: float
	if t < 0.35:
		swing = lerp(0.0, -22.0, t / 0.35)  # wind up
	elif t < 0.55:
		swing = lerp(-22.0, 40.0, (t - 0.35) / 0.20)  # strike
	elif t < 1.0:
		swing = lerp(40.0, 0.0, (t - 0.55) / 0.45)  # recover
	else:
		set_state(State.IDLE)
		return
	_body.position.x = -swing * 0.15
	for part_name in FRONT_ARM_PARTS:
		_reset_part_rotation(part_name, swing)


# ~0.6s cast: raise the front arm, tint blue-white at the peak, lower.
func _animate_cast() -> void:
	var t = _state_time / 0.6
	if not _attack_fired and t >= 0.5:
		_attack_fired = true
		attack_connected.emit()
	var raise: float
	if t < 0.4:
		raise = lerp(0.0, -55.0, t / 0.4)
	elif t < 0.6:
		raise = -55.0
	elif t < 1.0:
		raise = lerp(-55.0, 0.0, (t - 0.6) / 0.4)
	else:
		modulate = Color.WHITE
		set_state(State.IDLE)
		return
	var glow = clamp(1.0 - abs(t - 0.5) * 2.0, 0.0, 1.0)
	modulate = Color(1, 1, 1).lerp(Color(0.6, 0.8, 1.4), glow)
	for part_name in FRONT_ARM_PARTS:
		_reset_part_rotation(part_name, raise)


# Held wobble - stays until set_state() flips it back (stun ends when the
# turn does). Whole body tilts and jitters.
func _animate_stun() -> void:
	var tilt = 8.0 + sin(_state_time * 3.0) * 3.0
	_body.rotation_degrees = tilt
	_body.position.y = 2.0


# ~0.25s recoil flash.
func _animate_hit() -> void:
	var t = _state_time / 0.25
	if t >= 1.0:
		modulate = Color.WHITE
		_body.position.x = 0.0
		set_state(State.IDLE)
		return
	modulate = Color(1.6, 0.7, 0.7).lerp(Color.WHITE, t)
	_body.position.x = (1.0 - t) * 5.0


# ~0.6s fall-and-fade, then hold on the ground.
func _animate_dead() -> void:
	var t = min(_state_time / 0.6, 1.0)
	_body.rotation_degrees = lerp(0.0, 80.0, t)
	_body.position.y = lerp(0.0, 12.0, t)
	modulate = Color(1, 1, 1, lerp(1.0, 0.55, t))
	if t >= 1.0 and not _attack_fired:
		_attack_fired = true
		state_finished.emit(State.DEAD)


func _reset_part_rotation(part_name: String, extra_degrees: float) -> void:
	if _parts.has(part_name):
		_parts[part_name].rotation_degrees = REST_POSE[part_name]["rot"] + extra_degrees


func _reset_part_offset(part_name: String, extra_offset: Vector2, extra_rotation: float) -> void:
	if _parts.has(part_name):
		var pose = REST_POSE[part_name]
		_parts[part_name].position = Vector2(pose["tx"], pose["ty"]) + extra_offset
		_parts[part_name].rotation_degrees = pose["rot"] + extra_rotation


func _add_layer(part: Node2D, path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var entry: Dictionary = _load_offsets().get(path.get_file().get_basename(), {})
	if entry.is_empty():
		return  # 1x1 placeholder art (empty part in the original)
	var sprite = Sprite2D.new()
	sprite.texture = load(path)
	sprite.centered = false
	sprite.position = Vector2(entry["x"], entry["y"])
	var texture_size = sprite.texture.get_size()
	sprite.scale = Vector2(entry["w"] / texture_size.x, entry["h"] / texture_size.y)
	part.add_child(sprite)


static func _load_offsets() -> Dictionary:
	if not _offsets_loaded:
		_offsets_loaded = true
		var file = FileAccess.open(OFFSETS_FILE, FileAccess.READ)
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
	var looks = ["", "", "", "", "", "", ""]
	var start_slot = 0
	if unit.skin_setter != "":
		for i in 5:
			looks[i] = unit.skin_setter
		start_slot = 5
	for i in range(start_slot, 7):
		if i >= unit.equipment_ids.size():
			break
		var item_id = int(unit.equipment_ids[i])
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
	var text = str(value)
	if text == "" or text == "0":
		return ""
	return text
