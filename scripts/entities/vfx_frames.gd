# vfx_frames.gd
# Loads a per-clip folder of individually-sized frame files
# (dev/urchin_dev/swf/extract/vfx.py's own output - 1.png, 2.png, ...,
# copied as-is with no packing) into a SpriteFrames animation. Shared by
# ImpactEffect and Projectile, which both need the identical loading
# logic. Frame count is discovered by probing for consecutively-
# numbered files rather than reading a sidecar, so it can never drift
# out of sync with what's actually on disk. Also the shared home for the
# two constants both of those callers need: the extractor's zoom
# compensation and the clip-name-to-folder-name transform.
class_name VfxFrames
extends RefCounted

# dev/urchin_dev/swf/extract/vfx.py renders every clip at ZOOM = 2.0, the
# same double-density every other extractor in this project uses so art
# stays crisp in the 1600x1200 window. project.godot's canvas_items
# stretch maps that window back onto the 800x600 design stage, so a
# 2x-density texture drawn at scale 1.0 would cover twice the design-space
# area the source clip did. Halving it puts it back at its intended size,
# the same compensation character_visual.gd applies to doll_art.py's own
# 2x output.
const VFX_SCALE: float = 0.5


# Mirrors dev/urchin_dev/swf/extract/vfx.py's own sanitize() exactly
# (re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_").lower()), so a clip
# name carrying a character the folder name can't hold resolves to the
# folder the extractor actually wrote. BuffIcons keeps its own copy of
# this transform for its own unrelated icon-name convention.
static func sanitize(name: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^A-Za-z0-9]+")
	return regex.sub(name, "_", true).lstrip("_").rstrip("_").to_lower()


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
