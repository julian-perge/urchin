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


# The original's Stage is 800x575, so a SWF coordinate is a viewport coordinate
# only when the viewport has the same size. The window override is twice that,
# so the 2x window shows the viewport without a fractional scale.
func test_viewport_is_the_original_stage():
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 800)
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 575)
	assert_eq(ProjectSettings.get_setting("display/window/size/window_width_override"), 1600)
	assert_eq(ProjectSettings.get_setting("display/window/size/window_height_override"), 1150)


# The state of a packed scene holds the values the .tscn types, so a test reads
# them without running the scene's scripts.
func _typed_value(scene_path: String, node_path: String, property: StringName):
	var state: SceneState = (load(scene_path) as PackedScene).get_state()
	for index in state.get_node_count():
		if str(state.get_node_path(index)) != "./" + node_path:
			continue
		for property_index in state.get_node_property_count(index):
			if state.get_node_property_name(index, property_index) == property:
				return state.get_node_property_value(index, property_index)
	return null


func test_battle_bottom_bar_ends_at_the_viewport_bottom():
	var viewport_height: int = ProjectSettings.get_setting("display/window/size/viewport_height")
	assert_eq(_typed_value("res://scenes/battle_scene.tscn", "BottomBar", &"offset_bottom"), float(viewport_height))
	assert_eq(_typed_value("res://scenes/battle_scene.tscn", "BottomBar", &"offset_top"), 445.0, "the bar is 130 px high")


func test_game_background_fill_is_the_stage_backdrop_color():
	var color: Color = _typed_value("res://scenes/game.tscn", "BackgroundFill", &"color")
	assert_eq(color.to_html(false), "0e1215")
