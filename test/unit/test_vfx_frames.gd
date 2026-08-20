# VfxFrames.sanitize() - turns a clip name into the filename
# dev/urchin_dev/swf/extract/vfx_scenes.py wrote for it. Frame-loading
# tests retired along with load_frames() itself - every clip now loads
# from a generated scene instead of a dynamically-scanned folder.
# docs/superpowers/specs/2026-08-19-vfx-registration-scenes-design.md.
extends GutTest


func test_sanitize_lowercases_and_collapses_non_alnum_runs():
	assert_eq(VfxFrames.sanitize("Krin.Firebolt"), "krin_firebolt")


func test_sanitize_matches_across_casing_variants():
	# KRIN.MAGICBOLT and Krin.Magicbolt are the same clip under Flash's
	# case-insensitive attachMovie lookup - both must resolve to the
	# scene extract_vfx_scenes.py actually wrote.
	assert_eq(VfxFrames.sanitize("KRIN.MAGICBOLT"), VfxFrames.sanitize("Krin.Magicbolt"))
