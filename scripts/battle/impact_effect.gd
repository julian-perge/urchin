# impact_effect.gd
# A one-shot BOOM_*/ex_* impact clip - plays once at wherever it's
# positioned, then frees itself. Art comes from a per-clip generated
# scene (dev/urchin_dev/swf/extract/vfx_scenes.py's own output, under
# scenes/battle/vfx/impacts/), already carrying its own frames and its
# real registration offset (dev/urchin_dev/swf/extract/vfx_offsets.py) -
# this script only instantiates it and wires cleanup. The source never
# explicitly removes its own equivalent clips ("bbb"+counter in
# frame_42/DoAction_4.as's krinBoltMake) - a deliberate improvement, not
# an unfaithful port. See docs/superpowers/specs/2026-08-19-vfx-registration-scenes-design.md.
class_name ImpactEffect
extends Node2D

const VFX_SCENE_DIR: String = "res://scenes/battle/vfx/impacts/"

var _root: Node2D
var _anim_sprite: AnimatedSprite2D


func play(clip_name: String) -> void:
	if clip_name.is_empty():
		queue_free()
		return
	var path: String = "%s%s.tscn" % [VFX_SCENE_DIR, VfxFrames.sanitize(clip_name)]
	if not ResourceLoader.exists(path):
		queue_free()
		return
	var scene: PackedScene = load(path)
	if scene == null:
		queue_free()
		return
	_root = scene.instantiate()
	add_child(_root)
	_anim_sprite = _root.get_node("AnimatedSprite2D")
	_anim_sprite.animation_finished.connect(queue_free)  # frees the whole ImpactEffect, as before
	_anim_sprite.play("default")
