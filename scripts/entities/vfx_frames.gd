# vfx_frames.gd
# Loads a per-clip folder of individually-sized frame files
# (dev/urchin_dev/swf/extract/vfx.py's own output - 1.png, 2.png, ...,
# copied as-is with no packing) into a SpriteFrames animation. Shared by
# ImpactEffect and Projectile, which both need the identical loading
# logic. Frame count is discovered by probing for consecutively-
# numbered files rather than reading a sidecar, so it can never drift
# out of sync with what's actually on disk.
class_name VfxFrames
extends RefCounted


static func load_frames(dir: String, anim_name: String, loop: bool, fps: float) -> SpriteFrames:
	if not DirAccess.dir_exists_absolute(dir):
		return null
	var sprite_frames := SpriteFrames.new()
	# SpriteFrames.new() ships with a pre-existing "default" animation
	# already registered - add_animation() throws if called for a name
	# that already exists, so this must check first.
	if not sprite_frames.has_animation(anim_name):
		sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_speed(anim_name, fps)
	sprite_frames.set_animation_loop(anim_name, loop)
	var i := 1
	while true:
		var path: String = "%s%d.png" % [dir, i]
		if not ResourceLoader.exists(path):
			break
		sprite_frames.add_frame(anim_name, load(path))
		i += 1
	if sprite_frames.get_frame_count(anim_name) == 0:
		return null
	return sprite_frames
