# impact_effect.gd
# A one-shot BOOM_*/ex_* impact clip (dev/urchin_dev/swf/extract/vfx.py) -
# plays once at wherever it's positioned, then frees itself. The source
# never explicitly removes its own equivalent clips ("bbb"+counter in
# frame_42/DoAction_4.as's krinBoltMake) - a deliberate improvement, not
# an unfaithful port. See docs/superpowers/specs/2026-08-18-missile-projectile-art-design.md.
class_name ImpactEffect
extends Node2D

const VFX_DIR: String = "res://assets/vfx/impacts/"
const FPS: float = 30.0

@onready var _anim_sprite: AnimatedSprite2D = $Anim


func play(clip_name: String) -> void:
	if clip_name.is_empty():
		queue_free()
		return
	var dir: String = "%s%s/" % [VFX_DIR, VfxFrames.sanitize(clip_name)]
	var sprite_frames: SpriteFrames = VfxFrames.load_frames(dir, "default", false, FPS)
	if sprite_frames == null:
		queue_free()
		return
	_anim_sprite.sprite_frames = sprite_frames
	# The frames come off disk at the extractor's 2x density - see
	# VfxFrames.VFX_SCALE for why they have to be halved to land at the
	# size the source clip covered.
	_anim_sprite.scale = Vector2(VfxFrames.VFX_SCALE, VfxFrames.VFX_SCALE)
	_anim_sprite.animation_finished.connect(queue_free)
	_anim_sprite.play("default")
