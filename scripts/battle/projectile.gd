# projectile.gd
# krinBoltMake port (frame_42/DoAction_4.as) for Missile-type moves: a bolt
# that starts slow and ACCELERATES (SpeedConst compounds by BOLT_INCREASE
# every original frame) rather than moving at constant speed. The per-frame
# step is a fixed fraction of the distance measured at spawn (distance / 60,
# never recomputed against the bolt's current position), and arrival is a
# coordinate-crossing test (has the bolt's x passed the target's x) rather
# than a distance threshold or a fixed duration - see DECODED_ALGORITHMS.md.
#
# Bolt art (Bolt, AnimatedSprite2D) is the real per-clip spritesheet
# (dev/urchin_dev/swf/extract/vfx.py), shown UNTINTED - the source's own
# krinBoltMake never colors the bolt clip itself, only the separate
# KrinTrail streak (Trail, also an AnimatedSprite2D - KrinTrail's real
# content is a genuine 33-frame fade-in/fade-out pulse baked into its own
# timeline, not a static frame this script fades manually). Trail is
# spawned once at the bolt's position on the first tick, played once
# (non-looping - its own frames already carry the fade), tinted by
# trail_color (RGB only - alpha comes from the frames), rotated once to
# the flight angle, and grows scale.x every tick, independent of its own
# internal animation - see docs/superpowers/specs/
# 2026-08-18-missile-projectile-art-design.md.
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

var clip_name: String = ""
var trail_color: Color = Color.WHITE
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
	var dir: String = "%s%s/" % [BOLT_DIR, _sanitize(clip_name)]
	var sprite_frames: SpriteFrames = VfxFrames.load_frames(dir, "fly", true, BOLT_FPS)
	if sprite_frames == null:
		return  # no real asset - _draw()'s tinted-circle fallback below covers this
	_bolt_sprite.sprite_frames = sprite_frames
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
		_alpha = minf(_alpha + 0.1, 1.0)
		position += _step * _speed_const
		if not _trail_spawned:
			_trail_spawned = true
			_trail_sprite.global_position = global_position
			_trail_sprite.rotation = _step.angle()
			if _trail_sprite.sprite_frames != null:
				_trail_sprite.visible = true
				_trail_sprite.play("pulse")
		if _bolt_sprite.sprite_frames != null:
			_bolt_sprite.modulate.a = _alpha
		if _trail_sprite.visible:
			_trail_sprite.scale.x += 0.083 * _step.length() * _speed_const
		_speed_const *= BOLT_INCREASE
		if (_target_x - position.x) * _checker <= 0.0:
			reached_target.emit()
			queue_free()
			return
	queue_redraw()


func _draw() -> void:
	if _bolt_sprite.sprite_frames != null:
		return  # real art loaded - the fallback circle stays hidden
	draw_line(_trail_start - position, Vector2.ZERO, Color(color, _alpha * 0.5), 2.0)
	draw_circle(Vector2.ZERO, 4.0, Color(color, _alpha))


# Mirrors dev/urchin_dev/swf/extract/vfx.py's own sanitize() exactly and
# BuffIcons._sanitize()/ImpactEffect._sanitize()'s identical contract.
static func _sanitize(name: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^A-Za-z0-9]+")
	return regex.sub(name, "_", true).lstrip("_").rstrip("_").to_lower()
