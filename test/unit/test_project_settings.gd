extends GutTest


# Godot draws a piece at its layout position only while both snaps are off. The
# Control snap is on by Godot's default, so losing its line from project.godot
# would turn it back on without failing any other test.
func test_pixel_snapping_stays_off():
	assert_false(
		ProjectSettings.get_setting("gui/common/snap_controls_to_pixels"),
		"Controls are drawn at their layout positions"
	)
	assert_false(
		ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel"),
		"every canvas item is drawn at its layout position"
	)
