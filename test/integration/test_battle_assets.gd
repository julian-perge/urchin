# These tests check the battle screen's extracted art and layout JSON, and the
# stance row and game over screen instantiated on their own. None of them
# builds battle_scene.tscn, which is why they live outside test_battle_scene.gd.
extends GutTest


# The texts sit at the rects of edit texts 2794, 2793, 2792 and 2703 in root
# frame 104, and the Re-Load and Back hit areas at the rects of buttons 2791 and
# 2702, whose only state is shape 291, a 30 px square. Heights are left out for
# the texts, because a Label grows to fit Godot's font where it is taller than
# Flash's.
func test_game_over_screen_uses_the_frame_104_rects():
	var game_over = add_child_autofree(load("res://scenes/battle/game_over_screen.tscn").instantiate())
	var texts: Dictionary = {
		"DeadLabel": Rect2(193.1, 93.75, 413.85, 45.35),
		"ReloadLabel": Rect2(250.9, 172.4, 298.2, 33.05),
		"TipLabel": Rect2(114.15, 231.65, 570.8, 115.35),
		"BackLabel": Rect2(488.15, 532.15, 304.1, 30.85),
	}
	for node_name in texts:
		var label: Label = game_over.get_node(node_name)
		assert_almost_eq(label.position, texts[node_name].position, Vector2(0.01, 0.01), "%s position" % node_name)
		assert_almost_eq(label.size.x, texts[node_name].size.x, 0.01, "%s width" % node_name)
	var hit_areas: Dictionary = {
		"ReloadButton": Rect2(255.54, 173.0, 288.92, 30.0),
		"BackButton": Rect2(604.44, 534.45, 188.12, 26.8),
	}
	for node_name in hit_areas:
		var button: Button = game_over.get_node(node_name)
		assert_almost_eq(button.position, hit_areas[node_name].position, Vector2(0.01, 0.01), "%s position" % node_name)
		assert_almost_eq(button.size, hit_areas[node_name].size, Vector2(0.01, 0.01), "%s size" % node_name)


# The layout JSON carries where each hall, sky and chrome character actually
# sits on the stage, recovered from the SWF placement rather than tuned by
# hand. The ROME sky's bottom edge lands at y = 306.0, which is what
# SKY_HORIZON_Y = 292.0 was approximating.
func test_battle_layout_json_carries_real_stage_rects():
	var file := FileAccess.open("res://assets/backgrounds/battle/battle_layout.json", FileAccess.READ)
	assert_not_null(file, "battle_layout.json exists")
	var layout: Dictionary = JSON.parse_string(file.get_as_text())
	assert_not_null(layout, "battle_layout.json parses")
	assert_eq(layout["halls"].size(), 10, "one entry per hall label")
	assert_eq(layout["skies"].size(), 9, "one entry per sky label")
	assert_eq(layout["chrome"].size(), 4, "one entry per chrome character")

	var rome: Dictionary = layout["skies"]["ROME"]
	assert_almost_eq(float(rome["y"]), 130.0, 0.01, "ROME sky top")
	assert_almost_eq(float(rome["h"]), 176.0, 0.01, "ROME sky height")
	assert_almost_eq(float(rome["y"]) + float(rome["h"]), 306.0, 0.01, "ROME sky bottom")

	var church: Dictionary = layout["halls"]["CHURCH"]
	assert_almost_eq(float(church["x"]), -45.32, 0.01, "CHURCH hall left")
	assert_almost_eq(float(church["y"]), 86.52, 0.01, "CHURCH hall top")
	assert_almost_eq(float(church["w"]), 884.50, 0.01, "CHURCH hall width")
	assert_almost_eq(float(church["h"]), 420.00, 0.01, "CHURCH hall height")

	# TUNNEL is one of the hall labels whose rect only comes out right when the
	# fighter rig (2676) is stripped before recovery runs: the rig's
	# placeholder figure pokes above TUNNEL's own opaque art, so measuring
	# against the unstripped SWF would inflate y and h past what TUNNEL.png
	# was actually cropped to.
	var tunnel: Dictionary = layout["halls"]["TUNNEL"]
	assert_almost_eq(float(tunnel["x"]), -22.07, 0.01, "TUNNEL hall left")
	assert_almost_eq(float(tunnel["y"]), 154.27, 0.01, "TUNNEL hall top")
	assert_almost_eq(float(tunnel["w"]), 844.00, 0.01, "TUNNEL hall width")
	assert_almost_eq(float(tunnel["h"]), 349.00, 0.01, "TUNNEL hall height")

	# The stage rect (3455) is the black rect the frame draws under the sky, so
	# its top edge is where SKY_FILL_COLOR starts showing.
	var stage_rect: Dictionary = layout["chrome"]["stage_rect"]
	assert_almost_eq(float(stage_rect["x"]), 15.03, 0.01, "stage rect left")
	assert_almost_eq(float(stage_rect["y"]), 130.00, 0.01, "stage rect top")
	assert_almost_eq(float(stage_rect["w"]), 770.00, 0.01, "stage rect width")
	assert_almost_eq(float(stage_rect["h"]), 314.00, 0.01, "stage rect height")

	# Every rect is design px against art rendered at 4x, so each PNG comes out
	# exactly four times its recorded width.
	for name in ["bottom_bar", "top_panel", "alert_icon", "stage_rect"]:
		var rect: Dictionary = layout["chrome"][name]
		var texture: Texture2D = load("res://assets/ui/battle/%s.png" % name)
		assert_eq(texture.get_width(), int(float(rect["w"]) * 4), "%s width" % name)
		assert_eq(texture.get_height(), int(float(rect["h"]) * 4), "%s height" % name)


# One WHITE cover among five BLACK ones is how the original shows the picked
# stance: setAG sets every b<i>.COVER to BLACK and then one to WHITE.
func test_stance_row_marks_exactly_one_button_selected():
	var row = load("res://scenes/battle/stance_row.tscn").instantiate()
	add_child_autofree(row)
	row.setup("Veradux")
	row.set_selected(Party.AggressionStance.TACTICAL)

	var selected := 0
	for mode in row.buttons.size():
		var cover: TextureRect = row.buttons[mode].get_node("Cover")
		assert_not_null(cover.texture, "button %d has a cover" % mode)
		if cover.texture.resource_path.ends_with("cover_WHITE.png"):
			selected += 1
			assert_eq(mode, int(Party.AggressionStance.TACTICAL), "the picked one is white")
		else:
			assert_true(cover.texture.resource_path.ends_with("cover_BLACK.png"),
				"button %d is black" % mode)
	assert_eq(selected, 1, "exactly one button reads as selected")


# Each button carries its own stance icon, in Party.AggressionStance order.
func test_stance_row_buttons_carry_the_five_icons():
	var row = load("res://scenes/battle/stance_row.tscn").instantiate()
	add_child_autofree(row)
	row.setup("Veradux")

	var expected := ["Phalanx", "Defensive", "Tactical", "Aggressive", "Relentless"]
	assert_eq(row.buttons.size(), expected.size(), "five stance buttons")
	for mode in expected.size():
		var texture: Texture2D = row.buttons[mode].texture_normal
		assert_not_null(texture, "button %d has an icon" % mode)
		assert_true(texture.resource_path.ends_with("%s.png" % expected[mode]),
			"button %d shows %s" % [mode, expected[mode]])


# One stance button stacks an icon from DefineSprite 3305 under an overlay
# from 3293. 3305's frame labels are _root.agModeNames verbatim, which is also
# the order of Party.AggressionStance, so the file names and the enum line up
# without a translation table.
func test_stance_button_art_is_extracted():
	for label in ["Phalanx", "Defensive", "Tactical", "Aggressive", "Relentless"]:
		var path := "res://assets/ui/battle/stance/%s.png" % label
		assert_true(ResourceLoader.exists(path), "%s icon extracted" % label)
		var texture: Texture2D = load(path)
		assert_eq(texture.get_width(), 113, "%s icon is 28.25 design px at 4x" % label)
	for state in ["BLACK", "WHITE"]:
		var path := "res://assets/ui/battle/stance/cover_%s.png" % state
		assert_true(ResourceLoader.exists(path), "cover_%s extracted" % state)
	assert_true(ResourceLoader.exists("res://assets/ui/battle/member_bar_panel.png"),
		"member bar backing extracted")


# The member bar's internal layout is measured off the SWF rather than typed
# into the scene by hand. Offsets are from the bar's own top-left corner.
func test_battle_layout_json_carries_the_stance_row_layout():
	var file := FileAccess.open("res://assets/backgrounds/battle/battle_layout.json", FileAccess.READ)
	assert_not_null(file, "battle_layout.json exists")
	var layout: Dictionary = JSON.parse_string(file.get_as_text())
	var row: Dictionary = layout["stance_row"]
	assert_almost_eq(float(row["bar_size"]["w"]), 285.0, 0.01, "member bar width")
	assert_almost_eq(float(row["bar_size"]["h"]), 31.5, 0.01, "member bar height")
	assert_almost_eq(float(row["button_pitch"]), 32.0, 0.01, "button pitch")
	assert_almost_eq(float(row["row_pitch"]), 37.5, 0.01, "row pitch")
	assert_almost_eq(float(row["button_size"]["w"]), 28.25, 0.01, "button width")
	assert_almost_eq(float(row["button_size"]["h"]), 13.75, 0.01, "button height")
	assert_almost_eq(float(row["first_button"]["x"]), 121.38, 0.01, "first button x")
	assert_almost_eq(float(row["first_button"]["y"]), 8.35, 0.01, "first button y")
	assert_almost_eq(float(row["name_offset"]["x"]), 8.0, 0.01, "name field x")
	assert_almost_eq(float(row["name_offset"]["y"]), 9.75, 0.01, "name field y")
	assert_almost_eq(float(row["art_zoom"]), 4.0, 0.01, "art zoom")


# The bottom bar is a render of DefineSprite 3317, which places the member bar
# container at depth 7. Each member bar carries the SWF author's placeholder
# name in a DefineEditText the game fills at runtime, so a bar rendered with
# them in has two rows of white "Thurman McPown" text burned into it. The port
# draws those rows itself with StanceRow, so the art must carry none. White
# text is the only thing on this bar brighter than 0.8 on every channel.
func test_bottom_bar_art_has_no_baked_in_member_bars():
	var texture: Texture2D = load("res://assets/ui/battle/bottom_bar.png")
	var image: Image = texture.get_image()
	var bright := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.r > 0.8 and pixel.g > 0.8 and pixel.b > 0.8:
				bright += 1
	assert_eq(bright, 0, "no placeholder text baked into the bottom bar")


# The battle frame places four chrome characters the port had never extracted:
# the shared bottom bar (3317, which the Navigation frame places too), the top
# panel frame (3465), the alert icon (3460) and the stage rect (3455).
func test_battle_chrome_art_is_extracted():
	for name in ["bottom_bar", "top_panel", "alert_icon", "stage_rect"]:
		var path := "res://assets/ui/battle/%s.png" % name
		assert_true(ResourceLoader.exists(path), "%s extracted" % name)
		var texture: Texture2D = load(path)
		assert_gt(texture.get_width(), 0, "%s is not empty" % name)


# The halls place DefineSprite 2676 six times as the character rig. Rendered
# without stripping it, each background bakes in six placeholder fighters, so
# the art has to be wider than the six slots they would occupy and must not
# carry opaque pixels where a fighter stood.
func test_hall_art_has_no_baked_in_fighter_rigs():
	var church: Texture2D = load("res://assets/backgrounds/battle/CHURCH.png")
	assert_not_null(church, "CHURCH hall art exists")
	# 3435 renders 884.5 design px wide at the CHURCH label; at 4x that is 3538.
	assert_eq(church.get_width(), 3538, "CHURCH rendered at 4x from the SWF")
	assert_eq(church.get_height(), 1680, "CHURCH rendered at 4x from the SWF")


# Every battle's hall and sky must resolve to real art. The two are separate
# fields, so a missing sky no longer falls back to a substitute - it errors.
func test_every_battle_resolves_its_hall_and_sky_art():
	var dir := DirAccess.open("res://resources/battles")
	assert_not_null(dir, "battle resources directory opens")
	var checked := 0
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var battle: BattleFight = load("res://resources/battles/%s" % file)
		var hall := "res://assets/backgrounds/battle/%s.png" % battle.zone_background.replace(" ", "_")
		var sky := "res://assets/backgrounds/sky/SKY_%s.png" % battle.sky_background.replace(" ", "_")
		assert_true(ResourceLoader.exists(hall), "%s hall %s" % [file, hall])
		assert_true(ResourceLoader.exists(sky), "%s sky %s" % [file, sky])
		checked += 1
	assert_gt(checked, 90, "checked the whole battle set")
