# impact_effect.gd
# A one-shot BOOM_*/ex_* impact clip (dev/urchin_dev/swf/extract/vfx.py) -
# plays once at wherever it's positioned, then frees itself. The source
# never explicitly removes its own equivalent clips ("bbb"+counter in
# frame_42/DoAction_4.as's krinBoltMake) - a deliberate improvement, not
# an unfaithful port. See docs/superpowers/specs/2026-08-18-missile-projectile-art-design.md.
class_name ImpactEffect
extends Node2D

const VFX_DIR: String = "res://assets/vfx/impacts/"

@onready var _anim_sprite: AnimatedSprite2D = $Anim


func play(clip_name: String) -> void:
	if clip_name.is_empty():
		queue_free()
		return
	var key: String = _sanitize(clip_name)
	var sheet_path: String = "%s%s.png" % [VFX_DIR, key]
	var json_path: String = "%s%s.json" % [VFX_DIR, key]
	if not ResourceLoader.exists(sheet_path):
		queue_free()
		return
	var meta: Dictionary = JSON.parse_string(FileAccess.open(json_path, FileAccess.READ).get_as_text())
	var texture: Texture2D = load(sheet_path)
	var frame_count: int = int(meta["frame_count"])
	var frame_width: int = int(meta["frame_width"])
	var frame_height: int = int(meta["frame_height"])
	var fps: float = float(meta.get("fps", 30.0))
	# SpriteFrames.new() already ships with a "default" animation slot
	# (see SpriteFrames's own constructor) - calling add_animation("default")
	# on it throws "SpriteFrames already has animation 'default'.", so this
	# reuses that slot instead of trying to (re-)create it.
	var sprite_frames := SpriteFrames.new()
	sprite_frames.set_animation_speed("default", fps)
	sprite_frames.set_animation_loop("default", false)
	for i in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * frame_width, 0, frame_width, frame_height)
		sprite_frames.add_frame("default", atlas)
	_anim_sprite.sprite_frames = sprite_frames
	_anim_sprite.animation_finished.connect(queue_free)
	_anim_sprite.play("default")


# Mirrors dev/urchin_dev/swf/extract/vfx.py's own sanitize() exactly
# (re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_").lower()) and
# BuffIcons._sanitize()'s identical GDScript mirror of that same
# contract, so a clip name with a character the filename can't hold
# resolves to the file the extractor actually wrote.
static func _sanitize(name: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^A-Za-z0-9]+")
	return regex.sub(name, "_", true).lstrip("_").rstrip("_").to_lower()
