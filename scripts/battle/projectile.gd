# projectile.gd
# krinBoltMake port (frame_42/DoAction_4.as) for Missile-type moves: a bolt
# that starts slow and ACCELERATES (SpeedConst compounds by BOLT_INCREASE
# every original frame) rather than moving at constant speed. The per-frame
# step is a fixed fraction of the distance measured at spawn (distance / 60,
# never recomputed against the bolt's current position), and arrival is a
# coordinate-crossing test (has the bolt's x passed the target's x) rather
# than a distance threshold or a fixed duration - see DECODED_ALGORITHMS.md.
#
# No distinct clip art is extracted per projectileModel name yet (Krin.Firebolt
# etc.) - the bolt/trail are drawn tinted by the move's element color, matching
# how ability orbs and damage numbers stand in without their original art.
class_name Projectile
extends Node2D

signal arrived

const BOLT_TIME := 60.0       # krinBoltTime: step = distance / 60, fixed at spawn
const BOLT_INCREASE := 1.15   # krinBoltIncrease: SpeedConst *= 1.15 every original frame
const BOLT_FPS := 30.0        # the original ticks this once per SWF frame

var color: Color = Color.WHITE

var _step: Vector2
var _checker: float = 1.0
var _target_x: float = 0.0
var _speed_const: float = 1.0
var _alpha: float = 0.0
var _frame_accum: float = 0.0
var _trail_start: Vector2


func start(origin: Vector2, target: Vector2) -> void:
	position = origin
	_trail_start = origin
	_target_x = target.x
	_step = (target - origin) / BOLT_TIME
	_checker = 1.0 if origin.x < target.x else -1.0


func _process(delta: float) -> void:
	_frame_accum += delta * BOLT_FPS
	while _frame_accum >= 1.0:
		_frame_accum -= 1.0
		_alpha = minf(_alpha + 0.1, 1.0)
		position += _step * _speed_const
		_speed_const *= BOLT_INCREASE
		if (_target_x - position.x) * _checker <= 0.0:
			arrived.emit()
			queue_free()
			return
	queue_redraw()


func _draw() -> void:
	draw_line(_trail_start - position, Vector2.ZERO, Color(color, _alpha * 0.5), 2.0)
	draw_circle(Vector2.ZERO, 4.0, Color(color, _alpha))
