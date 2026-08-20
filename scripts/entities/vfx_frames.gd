# vfx_frames.gd
# Shared VFX naming helper. Frame loading and the flat zoom-compensation
# scale this class used to provide are retired - every VFX clip now gets
# its own generated scene (dev/urchin_dev/swf/extract/vfx_scenes.py) with
# real frames and a real per-clip registration offset already baked in,
# rather than being built from a dynamically-scanned PNG folder at
# runtime. sanitize() is the one piece Projectile and ImpactEffect still
# need: it turns a clip_name (Ability.animation_label/impact_effect_name)
# into the generated scene's filename.
class_name VfxFrames
extends RefCounted


# Mirrors dev/urchin_dev/swf/extract/vfx.py's own sanitize() exactly
# (re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_").lower()), so a clip
# name carrying a character the filename can't hold resolves to the
# scene the extractor actually wrote. BuffIcons keeps its own copy of
# this transform for its own unrelated icon-name convention.
static func sanitize(name: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^A-Za-z0-9]+")
	return regex.sub(name, "_", true).lstrip("_").rstrip("_").to_lower()
