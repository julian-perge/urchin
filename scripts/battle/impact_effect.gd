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
	var dir: String = "%s%s/" % [VFX_DIR, _sanitize(clip_name)]
	var sprite_frames: SpriteFrames = VfxFrames.load_frames(dir, "default", false, FPS)
	if sprite_frames == null:
		queue_free()
		return
	_anim_sprite.sprite_frames = sprite_frames
	_anim_sprite.animation_finished.connect(queue_free)
	_anim_sprite.play("default")


# Mirrors dev/urchin_dev/swf/extract/vfx.py's own sanitize() exactly
# (re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_").lower()) and
# BuffIcons._sanitize()'s identical GDScript mirror of that same
# contract, so a clip name with a character the folder name can't hold
# resolves to the folder the extractor actually wrote.
static func _sanitize(name: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^A-Za-z0-9]+")
	return regex.sub(name, "_", true).lstrip("_").rstrip("_").to_lower()
