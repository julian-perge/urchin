# projectile.gd
# krinBoltMake port (frame_42/DoAction_4.as) for Missile-type moves: a bolt
# that starts slow and ACCELERATES (SpeedConst compounds by BOLT_INCREASE
# every original frame) rather than moving at constant speed. The per-frame
# step is a fixed fraction of the distance measured at spawn (distance / 60,
# never recomputed against the bolt's current position), and arrival is a
# coordinate-crossing test (has the bolt's x passed the target's x) rather
# than a distance threshold or a fixed duration - see DECODED_ALGORITHMS.md.
#
# Bolt art (Bolt, AnimatedSprite2D) is the real per-clip folder of
# individually-sized frame files that dev/urchin_dev/swf/extract/vfx.py
# writes (1.png, 2.png, ..., loaded by VfxFrames), shown UNTINTED - the
# source's own krinBoltMake never colors the bolt clip itself, only the
# separate KrinTrail streak (Trail, also an AnimatedSprite2D - KrinTrail's
# real content is a genuine 33-frame fade-in/fade-out pulse baked into its
# own timeline, not a static frame this script fades manually). Both
# clips are rotated to the flight angle, which never changes after spawn.
# Trail is spawned once at the bolt's position on the first tick, handed
# over to the bolt's own parent so it can outlive it, played once
# (non-looping - its own frames already carry the fade), tinted by
# trail_color (RGB only - alpha comes from the frames), and grows scale.x
# every tick, independent of its own internal animation - see
# docs/superpowers/specs/2026-08-18-missile-projectile-art-design.md.
class_name Projectile
extends Node2D

signal reached_target

const BOLT_TIME := 60.0       # krinBoltTime: step = distance / 60, fixed at spawn
const BOLT_INCREASE := 1.15   # krinBoltIncrease: SpeedConst *= 1.15 every original frame
const BOLT_FPS := 30.0        # the original ticks this once per SWF frame
const BOLT_DIR: String = "res://assets/vfx/bolts/"
const TRAIL_DIR: String = "res://assets/vfx/trail/krintrail/"
# This port's own canvas is 800x600, top-left origin (SLOT_POSITIONS range
# x=161..638) - a different coordinate convention from the source's
# centered AS2 stage, so its own off-screen bounds don't transfer
# literally. A small margin past the 800-wide canvas is this port's
# equivalent, used only by Task 5's miss-fly-past logic.
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

@onready var _bolt_sprite: AnimatedSprite2D = $Bolt
@onready var _trail_sprite: AnimatedSprite2D = $Trail

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
# stay VfxFrames.VFX_SCALE * this, instead of the growth increments
# quietly cancelling out the extractor's zoom compensation.
var _trail_growth: float = 1.0
var _reached: bool = false  # reached_target already fired - only matters for the miss fly-past
var _ticks: int = 0


func start(origin: Vector2, target: Vector2) -> void:
	position = origin
	_trail_start = origin
	_target_x = target.x
	_step = (target - origin) / BOLT_TIME
	_checker = 1.0 if origin.x < target.x else -1.0
	# The flight direction is fixed at spawn and never recomputed, so the
	# bolt's own rotation can be set here once. The trail can't: it isn't
	# placed until the first tick. The source rotates both (frame_42/
	# DoAction_4.as's krinBoltMake sets the bolt's _rotation, then copies
	# it onto the trail).
	_bolt_sprite.rotation = _step.angle()
	_load_bolt_sprite()
	_load_trail_sprite()


func _load_bolt_sprite() -> void:
	if clip_name.is_empty():
		return  # no real asset - _draw()'s tinted-circle fallback below covers this
	var dir: String = "%s%s/" % [BOLT_DIR, VfxFrames.sanitize(clip_name)]
	var sprite_frames: SpriteFrames = VfxFrames.load_frames(dir, "fly", true, BOLT_FPS)
	if sprite_frames == null:
		return  # no real asset - _draw()'s tinted-circle fallback below covers this
	_bolt_sprite.sprite_frames = sprite_frames
	# The frames come off disk at the extractor's 2x density - see
	# VfxFrames.VFX_SCALE for why they have to be halved to land at the
	# size the source clip covered.
	_bolt_sprite.scale = Vector2(VfxFrames.VFX_SCALE, VfxFrames.VFX_SCALE)
	_bolt_sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)  # alpha-only - never color-tinted
	_bolt_sprite.play("fly")


# KrinTrail's real content (dev/urchin_dev/swf/extract/vfx.py's
# TRAIL_SPRITE_ID) is a genuine 33-frame fade-in/fade-out pulse, not a
# static frame - the animation itself carries the alpha; this script only
# ever sets the RGB tint, never touches trail alpha manually.
func _load_trail_sprite() -> void:
	var sprite_frames: SpriteFrames = VfxFrames.load_frames(TRAIL_DIR, "pulse", false, BOLT_FPS)
	if sprite_frames == null:
		return
	_trail_sprite.sprite_frames = sprite_frames
	_trail_sprite.modulate = trail_color  # RGB tint only - alpha comes from the frames themselves
	_trail_sprite.visible = false


func _process(delta: float) -> void:
	_frame_accum += delta * BOLT_FPS
	while _frame_accum >= 1.0:
		_frame_accum -= 1.0
		_ticks += 1
		_alpha = minf(_alpha + 0.1, 1.0)
		position += _step * _speed_const
		if not _trail_spawned:
			_spawn_trail()
		if _bolt_sprite.sprite_frames != null:
			_bolt_sprite.modulate.a = _alpha
		# The trail runs its own fade to the end and frees itself, which on
		# a long miss happens while the bolt is still flying - so this has
		# to check the node is still there before touching it.
		if is_instance_valid(_trail_sprite) and _trail_sprite.visible:
			_trail_growth += 0.083 * _step.length() * _speed_const
			_trail_sprite.scale = Vector2(VfxFrames.VFX_SCALE * _trail_growth, VfxFrames.VFX_SCALE)
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
# sibling of the bolt clip, not to the bolt itself. Trail is already
# top_level, so where it draws is unchanged by the move.
func _spawn_trail() -> void:
	_trail_spawned = true
	_trail_sprite.global_position = global_position
	_trail_sprite.rotation = _step.angle()
	if _trail_sprite.sprite_frames == null:
		return
	_trail_sprite.visible = true
	var parent: Node = get_parent()
	if parent != null:
		remove_child(_trail_sprite)
		parent.add_child(_trail_sprite)
	_trail_sprite.animation_finished.connect(_trail_sprite.queue_free)
	_trail_sprite.play("pulse")


func _draw() -> void:
	if _bolt_sprite.sprite_frames != null:
		return  # real art loaded - the fallback circle stays hidden
	draw_line(_trail_start - position, Vector2.ZERO, Color(color, _alpha * 0.5), 2.0)
	draw_circle(Vector2.ZERO, 4.0, Color(color, _alpha))
