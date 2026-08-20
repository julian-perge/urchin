# projectile.gd
# krinBoltMake port (frame_42/DoAction_4.as) for Missile-type moves: a bolt
# that starts slow and ACCELERATES (SpeedConst compounds by BOLT_INCREASE
# every original frame) rather than moving at constant speed. The per-frame
# step is a fixed fraction of the distance measured at spawn (distance / 60,
# never recomputed against the bolt's current position), and arrival is a
# coordinate-crossing test (has the bolt's x passed the target's x) rather
# than a distance threshold or a fixed duration - see DECODED_ALGORITHMS.md.
#
# Bolt/Trail art come from per-clip generated scenes
# (dev/urchin_dev/swf/extract/vfx_scenes.py's own output, under
# scenes/battle/vfx/) instantiated per clip_name in start() - each one
# already carries its own frames and its real registration offset
# (dev/urchin_dev/swf/extract/vfx_offsets.py), so nothing here computes a
# position/scale correction at runtime. The bolt clip is shown UNTINTED -
# the source's own krinBoltMake never colors the bolt clip itself, only
# the separate KrinTrail streak (Trail, its own generated scene - KrinTrail's
# real content is a genuine 33-frame fade-in/fade-out pulse baked into its
# own timeline, not a static frame this script fades manually). Both
# clips are rotated to the flight angle, which never changes after spawn.
# Trail is spawned once at the bolt's position on the first tick, handed
# over to the bolt's own parent so it can outlive it, played once
# (non-looping - its own frames already carry the fade), tinted by
# trail_color (RGB only - alpha comes from the frames), and grows scale.x
# every tick, independent of its own internal animation - see
# docs/superpowers/specs/2026-08-19-vfx-registration-scenes-design.md.
class_name Projectile
extends Node2D

signal reached_target

const BOLT_TIME := 60.0       # krinBoltTime: step = distance / 60, fixed at spawn
const BOLT_INCREASE := 1.15   # krinBoltIncrease: SpeedConst *= 1.15 every original frame
const BOLT_FPS := 30.0        # the original ticks this once per SWF frame - drives this
                                # script's own movement pacing; each clip's own animation
                                # playback speed is baked into its generated scene instead
const BOLT_SCENE_DIR := "res://scenes/battle/vfx/bolts/"
const TRAIL_SCENE: PackedScene = preload("res://scenes/battle/vfx/trail/krintrail.tscn")
# This port's own canvas is 800x600, top-left origin (SLOT_POSITIONS range
# x=161..638) - a different coordinate convention from the source's
# centered AS2 stage, so its own off-screen bounds don't transfer
# literally. A small margin past the 800-wide canvas is this port's
# equivalent, used only by the miss-fly-past logic below.
const OFF_SCREEN_MIN_X := -20.0
const OFF_SCREEN_MAX_X := 820.0
# Safety net for the miss fly-past below. A move whose caster and target
# share an x coordinate would give the bolt a zero x-step, so its x would
# never change and the off-screen test could never become true - the
# while loop would spin forever with _speed_const compounding. No slot
# pairing in SLOT_POSITIONS produces that today; the cap costs one
# comparison and closes it for good. Set far above the roughly 20 ticks a
# real caster-to-target miss takes to leave the canvas, so it can only
# ever fire on a flight that would otherwise never end.
const MAX_FLIGHT_TICKS: int = 300

var clip_name: String = ""
var trail_color: Color = Color.WHITE
# Set by battle_scene.gd before start(), from result.type != MISS. A hit
# frees the bolt the instant it reaches the target (matching source: the
# bolt is destroyed the same tick its impact clip appears). A miss keeps
# the bolt (and its growing trail) moving past the target until it exits
# this port's own screen bounds - reached_target still fires at the same
# coordinate-cross tick either way, so turn pacing/audio/the floatie land
# exactly where they do on a hit.
var did_hit: bool = true
var color: Color = Color.WHITE  # fallback tinted-circle color when clip_name has no real asset

var _bolt_root: Node2D
var _bolt_sprite: AnimatedSprite2D
var _trail_root: Node2D
var _trail_sprite: AnimatedSprite2D
# The trail scene's own baked scale, captured once so growth multiplies
# the real per-clip ratio instead of assuming every clip shares one flat
# constant.
var _trail_base_scale: Vector2 = Vector2.ONE

var _step: Vector2
var _checker: float = 1.0
var _target_x: float = 0.0
var _speed_const: float = 1.0
var _alpha: float = 0.0
var _frame_accum: float = 0.0
var _trail_start: Vector2
var _trail_spawned: bool = false
# How far the trail has stretched, as a multiple of its own natural
# length. Tracked apart from _trail_sprite.scale so the rendered scale can
# stay _trail_base_scale times this, instead of the growth increments
# quietly cancelling out the baked-in registration scale.
var _trail_growth: float = 1.0
var _reached: bool = false  # reached_target already fired - only matters for the miss fly-past
var _ticks: int = 0


func start(origin: Vector2, target: Vector2) -> void:
	position = origin
	_trail_start = origin
	_target_x = target.x
	_step = (target - origin) / BOLT_TIME
	_checker = 1.0 if origin.x < target.x else -1.0
	_load_bolt_sprite()
	_load_trail_sprite()


func _load_bolt_sprite() -> void:
	if clip_name.is_empty():
		return  # no real asset - _draw()'s tinted-circle fallback below covers this
	var path: String = "%s%s.tscn" % [BOLT_SCENE_DIR, VfxFrames.sanitize(clip_name)]
	if not ResourceLoader.exists(path):
		return  # no real asset - _draw()'s tinted-circle fallback below covers this
	var scene: PackedScene = load(path)
	if scene == null:
		return  # no real asset - _draw()'s tinted-circle fallback below covers this
	_bolt_root = scene.instantiate()
	_bolt_sprite = _bolt_root.get_node("AnimatedSprite2D")
	add_child(_bolt_root)
	# The flight direction is fixed at spawn and never recomputed, so the
	# bolt's own rotation can be set here once. Rotating the wrapper
	# rotates the sprite's own baked registration offset around the
	# wrapper's origin - the clip's true pivot, not its texture's center.
	# The source rotates both (frame_42/DoAction_4.as's krinBoltMake sets
	# the bolt's _rotation, then copies it onto the trail).
	_bolt_root.rotation = _step.angle()
	_bolt_sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)  # alpha-only - never color-tinted
	_bolt_sprite.play("fly")


# KrinTrail's real content (dev/urchin_dev/swf/extract/vfx.py's
# TRAIL_SPRITE_ID) is a genuine 33-frame fade-in/fade-out pulse, not a
# static frame - the animation itself carries the alpha; this script only
# ever sets the RGB tint, never touches trail alpha manually.
func _load_trail_sprite() -> void:
	_trail_root = TRAIL_SCENE.instantiate()
	_trail_sprite = _trail_root.get_node("AnimatedSprite2D")
	_trail_base_scale = _trail_sprite.scale
	_trail_sprite.modulate = trail_color  # RGB tint only - alpha comes from the frames themselves
	_trail_root.visible = false
	# Added as the bolt's own child for now, same as _bolt_root - _spawn_trail
	# later hands it over to the bolt's parent so it can outlive the bolt.
	add_child(_trail_root)


func _process(delta: float) -> void:
	_frame_accum += delta * BOLT_FPS
	while _frame_accum >= 1.0:
		_frame_accum -= 1.0
		_ticks += 1
		_alpha = minf(_alpha + 0.1, 1.0)
		position += _step * _speed_const
		if not _trail_spawned:
			_spawn_trail()
		if _bolt_sprite != null:
			_bolt_sprite.modulate.a = _alpha
		# The trail runs its own fade to the end and frees itself, which on
		# a long miss happens while the bolt is still flying - so this has
		# to check the node is still there before touching it.
		if is_instance_valid(_trail_root) and _trail_root.visible:
			_trail_growth += 0.083 * _step.length() * _speed_const
			_trail_sprite.scale = Vector2(_trail_base_scale.x * _trail_growth, _trail_base_scale.y)
		_speed_const *= BOLT_INCREASE
		if not _reached and (_target_x - position.x) * _checker <= 0.0:
			_reached = true
			reached_target.emit()
			if did_hit:
				queue_free()
				return
		if _reached and (
			position.x < OFF_SCREEN_MIN_X
			or position.x > OFF_SCREEN_MAX_X
			or _ticks >= MAX_FLIGHT_TICKS
		):
			queue_free()
			return
	queue_redraw()


# Places the trail at the point the bolt is passing through right now,
# then hands it over to the bolt's own parent so it stops being the
# bolt's child. On a hit the bolt frees itself the instant it reaches the
# target, and KrinTrail's 33-frame fade is nowhere near finished by then -
# as the bolt's child the trail would be torn down mid-fade. The source
# has the same separation: the trail is attached to BATTLESCREEN, a
# sibling of the bolt clip, not to the bolt itself. Trail's own generated
# scene already sets top_level = true, so where it draws is unchanged by
# the move.
func _spawn_trail() -> void:
	_trail_spawned = true
	_trail_root.global_position = global_position
	_trail_root.rotation = _step.angle()
	_trail_root.visible = true
	var parent: Node = get_parent()
	if parent != null:
		remove_child(_trail_root)
		parent.add_child(_trail_root)
	_trail_sprite.animation_finished.connect(_trail_root.queue_free)
	_trail_sprite.play("pulse")


func _draw() -> void:
	if _bolt_sprite != null:
		return  # real art loaded - the fallback circle stays hidden
	draw_line(_trail_start - position, Vector2.ZERO, Color(color, _alpha * 0.5), 2.0)
	draw_circle(Vector2.ZERO, 4.0, Color(color, _alpha))
