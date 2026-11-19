# The top status bar's entries. Each case reads the widths, colors and rects from
# top_bar.json, which extract_top_bar writes, so a test never types a SWF value.
extends GutTest

const StatusBarScene = preload("res://scenes/battle/status_bar.tscn")
const TopStatusBarScene = preload("res://scenes/battle/top_status_bar.tscn")


func _bar(slot: int) -> StatusBar:
	var bar: StatusBar = StatusBarScene.instantiate()
	bar.slot = slot
	add_child_autofree(bar)
	return bar


func _state(life: float, life_max: float, focus: float = 0.0, focus_max: float = 0.0) -> UnitSnapshot:
	var state := UnitSnapshot.new()
	state.life = life
	state.life_max = life_max
	state.focus = focus
	state.focus_max = focus_max
	return state


# The width a fill has at full, which is the art's width times the scale that
# the bar clip is placed with.
func _full_width(which: String) -> float:
	var bar: Dictionary = StatusBar.record()["bars"][which]
	return float(StatusBar.record()["art"][bar["art"]]["rect"][2]) * float(bar["scale_x"])


func _life_color(frame: int) -> Color:
	return Color.html(StatusBar.record()["life_colors"][frame])


# The battle frame puts the DropShadow on the p#BAR placement, and buffTicker
# attaches the buff icons into p#BAR, so every part of the bar lies inside the
# CanvasGroup that draws the shadow.
func test_every_part_of_the_bar_lies_inside_the_clip_that_draws_the_shadow() -> void:
	var bar: StatusBar = _bar(1)
	assert_true(bar.clip is CanvasGroup, "Clip is a CanvasGroup")
	for part: Node in [bar.inner, bar.inner2, bar.buff_row]:
		assert_true(bar.clip.is_ancestor_of(part), "%s lies inside Clip" % part.name)
	var material: ShaderMaterial = bar.clip.material
	assert_eq(material.shader.resource_path, "res://scenes/drop_shadow.gdshader")


func test_the_clip_takes_the_drop_shadow_of_the_bars_placement() -> void:
	var shadow: Dictionary = StatusBar.record()["shadow"]
	var material: ShaderMaterial = _bar(2).clip.material
	assert_eq(material.get_shader_parameter("shadow_color"), Color.html(shadow["color"]))
	assert_eq(material.get_shader_parameter("blur"), Vector2(shadow["blur_x"], shadow["blur_y"]))
	assert_almost_eq(float(material.get_shader_parameter("distance")), float(shadow["distance"]), 0.0001)
	assert_almost_eq(float(material.get_shader_parameter("angle")), float(shadow["angle"]), 0.0001)
	assert_almost_eq(float(material.get_shader_parameter("strength")), float(shadow["strength"]), 0.0001)


# The shadow reaches its distance plus half its blur past the art, in stage px,
# and the group's margins are in screen px.
func test_the_clip_margins_reach_as_far_as_the_shadow_at_the_windows_scale() -> void:
	var bar: StatusBar = _bar(1)
	var shadow: Dictionary = StatusBar.record()["shadow"]
	var stage_scale: float = bar.get_viewport().get_final_transform().get_scale().x
	var reach: float = (float(shadow["distance"]) + maxf(float(shadow["blur_x"]), float(shadow["blur_y"])) / 2.0) * stage_scale
	assert_gte(bar.clip.fit_margin, reach)
	assert_gte(bar.clip.clear_margin, reach)
	assert_almost_eq(float((bar.clip.material as ShaderMaterial).get_shader_parameter("stage_scale")), stage_scale, 0.0001)


# The death fade sets _alpha on p#BAR, the clip that carries the DropShadow
# (DefineSprite_57_LifeBarSmoother/frame_38), so Flash fades the bar and its
# shadow as one picture. Clip's shader applies the fade once, the parts stay
# unfaded, and each bar fades on its own.
func test_the_death_fade_reaches_the_shadow_of_that_bar_alone() -> void:
	var dying: StatusBar = _bar(1)
	var other: StatusBar = _bar(2)
	assert_ne(dying.clip.material, other.clip.material, "each bar has its own material")
	var death: Dictionary = StatusBar.record()["death"]
	dying.die()
	_advance(dying, int(death["clear_frame"]) + 3)
	assert_lt(dying.fade, 1.0, "the bar is fading")
	assert_eq(dying.modulate.a, 1.0, "the parts are not faded one by one")
	assert_almost_eq(float((dying.clip.material as ShaderMaterial).get_shader_parameter("fade")), dying.fade, 0.0001)
	assert_almost_eq(float((other.clip.material as ShaderMaterial).get_shader_parameter("fade")), 1.0, 0.0001)


# Clip's shadow falls under the text, so a Label that drew its own shadow would
# draw the text's shadow twice.
func test_the_labels_draw_no_shadow_of_their_own() -> void:
	var bar: StatusBar = _bar(1)
	for label: Label in [bar.name_label, bar.life_now_label, bar.life_max_label, bar.focus_now_label, bar.focus_max_label]:
		assert_eq(label.get_theme_color("font_shadow_color").a, 0.0, "%s draws a shadow" % label.name)


func test_a_bar_at_rest_shows_both_fills_at_full_width() -> void:
	var bar: StatusBar = _bar(1)
	assert_almost_eq(bar.life_fill.size.x, _full_width("life"), 0.001)
	assert_almost_eq(bar.focus_fill.size.x, _full_width("focus"), 0.001)


# A bar that has shown one state, which sets the life fill and leaves the Focus fill
# at full. The next call is the first one that plays a smoother.
func _shown_bar(slot: int, state: UnitSnapshot) -> StatusBar:
	var bar: StatusBar = _bar(slot)
	bar.show_status(state)
	return bar


func _advance(bar: StatusBar, frames: int) -> void:
	for frame in frames:
		bar.advance_frame()


# How many frames a smoother plays from `first_frame` to the frame whose script
# does `role`, read from the record.
func _frames_to(smoother: String, role: String, first_frame: int = 1) -> int:
	var scripts: Dictionary = StatusBar.record()["smoothers"][smoother]["scripts"]
	for frame: String in scripts:
		if scripts[frame] == role:
			return int(frame) - first_frame
	fail_test("%s has no %s frame" % [smoother, role])
	return 0


# How many frames a gain plays: it starts at the healSmooth label.
func _gain_frames(smoother: String) -> int:
	var label: int = int(StatusBar.record()["smoothers"][smoother]["labels"]["healSmooth"])
	return _frames_to(smoother, "gain_end", label)


func test_full_life_fills_the_bar_in_the_last_color_frame_and_shows_the_numbers() -> void:
	var bar: StatusBar = _bar(1)
	bar.show_status(_state(250.0, 250.0, 30.0, 50.0))
	assert_almost_eq(bar.life_fill.size.x, _full_width("life"), 0.001, "the life fill")
	assert_eq(bar.life_fill.modulate, _life_color(100), "in the color of frame 101")
	assert_eq(bar.life_back.modulate, _life_color(100), "and so is the fill behind it")
	assert_almost_eq(bar.focus_fill.size.x, _full_width("focus"), 0.001, "the first update leaves the Focus fill at full")
	assert_eq([bar.life_now_label.text, bar.life_max_label.text], ["250", "250"])
	assert_eq([bar.focus_now_label.text, bar.focus_max_label.text], ["30", "50"])


func test_half_life_gives_half_the_width_and_the_color_of_frame_51() -> void:
	var bar: StatusBar = _bar(1)
	bar.show_status(_state(125.0, 250.0))
	assert_almost_eq(bar.life_fill.size.x, _full_width("life") * 0.5, 0.001)
	assert_eq(bar.life_fill.modulate, _life_color(50))


func test_a_share_picks_the_color_frame_of_its_rounded_percent() -> void:
	var bar: StatusBar = _bar(1)
	bar.show_status(_state(1.0, 3.0))
	assert_eq(bar.life_fill.modulate, _life_color(33), "33.3 percent is frame 34")
	bar.show_status(_state(2.0, 3.0))
	assert_eq(bar.life_fill.modulate, _life_color(67), "66.7 percent is frame 68")


func test_the_first_update_plays_no_smoother() -> void:
	var bar: StatusBar = _bar(1)
	bar.show_status(_state(125.0, 250.0, 30.0, 50.0))
	assert_false(bar.life_band.visible)
	assert_false(bar.focus_band.visible)
	assert_false(bar.is_processing(), "and nothing runs")


func test_zero_life_empties_the_fill() -> void:
	var bar: StatusBar = _bar(1)
	bar.show_status(_state(0.0, 250.0))
	assert_eq(bar.life_fill.size.x, 0.0)
	assert_eq(bar.life_fill.modulate, _life_color(0), "in the color of frame 1")
	assert_eq(bar.life_now_label.text, "0")


func test_a_bar_with_no_max_shows_an_empty_fill_and_not_a_not_a_number_one() -> void:
	var bar: StatusBar = _bar(1)
	bar.show_status(_state(0.0, 0.0))
	assert_eq(bar.life_fill.size.x, 0.0)
	bar.show_status(_state(0.0, 0.0, 5.0, 0.0))
	_advance(bar, 20)
	assert_eq(bar.focus_fill.size.x, 0.0)


func test_a_right_hand_bar_mirrors_inner2_and_takes_the_second_frame_of_inner() -> void:
	var record: Dictionary = StatusBar.record()
	for slot in [1, 3, 5]:
		var left: StatusBar = _bar(slot)
		assert_eq(left.inner2.scale.x, 1.0, "slot %d keeps inner2 as it is" % slot)
		assert_almost_eq(left.name_label.position.x, float(record["inner"]["frames"]["first"]["fields"].filter(func(f): return f["variable"] == "playerName")[0]["rect"][0]), 0.001, "slot %d lays its text out from the first frame" % slot)
	for slot in [2, 4, 6]:
		var right: StatusBar = _bar(slot)
		assert_eq(right.inner2.scale.x, -1.0, "slot %d mirrors inner2" % slot)
		assert_almost_eq(right.name_label.position.x, float(record["inner"]["frames"]["second"]["fields"].filter(func(f): return f["variable"] == "playerName")[0]["rect"][0]), 0.001, "slot %d lays its text out from the second frame" % slot)


func test_a_bar_sits_where_the_battle_frame_places_its_slot() -> void:
	var placements: Dictionary = StatusBar.record()["placements"]
	for slot in range(1, 7):
		var bar: StatusBar = _bar(slot)
		var placed: Dictionary = placements["p%dBAR" % slot]
		assert_eq(bar.position, Vector2(placed["x"], placed["y"]), "slot %d" % slot)
		assert_eq(bar.scale, Vector2(placed["scale"][0], placed["scale"][1]), "slot %d" % slot)


func test_the_death_clear_takes_the_name_and_the_numbers_away_and_leaves_the_fills() -> void:
	var bar: StatusBar = _bar(1)
	bar.setup("Veradux")
	bar.show_status(_state(0.0, 250.0))
	assert_true(bar.name_label.is_visible_in_tree())
	bar.clear_for_death()
	assert_false(bar.name_label.is_visible_in_tree(), "the name goes")
	assert_false(bar.life_now_label.is_visible_in_tree(), "and the numbers")
	assert_true(bar.life_back.is_visible_in_tree(), "the bars stay")
	bar.show_status(_state(0.0, 250.0))
	assert_false(bar.name_label.is_visible_in_tree(), "a later redraw leaves them cleared")


func test_a_loss_moves_the_fill_at_once_and_a_band_trails_it_and_ends_on_frame_18() -> void:
	var bar: StatusBar = _shown_bar(1, _state(250.0, 250.0, 50.0, 50.0))
	bar.show_status(_state(125.0, 250.0, 50.0, 50.0))
	assert_almost_eq(bar.life_fill.size.x, _full_width("life") * 0.5, 0.001, "the fill drops at once")
	assert_true(bar.life_band.visible, "a band shows the loss")
	assert_almost_eq(bar.life_band.size.x, _full_width("life") * 0.5, 0.01, "as wide as the loss")
	assert_almost_eq(bar.life_band.position.x, bar.life_fill.position.x + bar.life_fill.size.x, 1.0, "from the fill's new end")
	assert_eq(bar.life_band.modulate, _life_color(50), "in the color of the new life")
	var frames: int = _frames_to("LifeBarSmoother", "loss_end")
	_advance(bar, 8)
	assert_lt(bar.life_band.size.x, _full_width("life") * 0.5, "it shrinks on each frame")
	_advance(bar, frames - 9)
	assert_true(bar.life_band.visible, "it still shows the frame before its end")
	_advance(bar, 1)
	assert_false(bar.life_band.visible, "and ends on its loss_end frame")
	assert_almost_eq(bar.life_fill.size.x, _full_width("life") * 0.5, 0.001, "the fill stays")


# lifeBarUpdate puts a smoother's x at the fill's width times a factor, less an
# offset (frame_42/DoAction_8.as:316 and 341). The smoother places its colour clip
# at the frame's x and x scale, and the bar clip places the smoother.
func test_a_loss_band_starts_where_lifebarupdate_puts_the_smoother() -> void:
	var bar: StatusBar = _shown_bar(1, _state(250.0, 250.0, 50.0, 50.0))
	bar.show_status(_state(125.0, 250.0, 50.0, 50.0))
	var record: Dictionary = StatusBar.record()
	var factors: Dictionary = record["smoother_factors"]
	var holder: Dictionary = record["bars"]["life"]
	var art: Dictionary = record["art"]["life_fill"]
	var first: Dictionary = record["smoothers"]["LifeBarSmoother"]["shown"][0]
	var anchor: float = bar.life_fill.size.x * float(factors["x_factor"]) - float(factors["x_offset"])
	var shape_left: float = float(art["rect"][0]) - float(art["origin"][0])
	var left: float = anchor + 0.5 * (float(first["x"]) + float(first["x_scale"]) * shape_left)
	assert_almost_eq(bar.life_band.position.x, float(holder["x"]) + float(holder["scale_x"]) * left, 0.001)


func test_a_gain_after_a_loss_holds_the_fill_until_frame_36_of_its_smoother() -> void:
	var bar: StatusBar = _shown_bar(1, _state(250.0, 250.0, 50.0, 50.0))
	bar.show_status(_state(125.0, 250.0, 50.0, 50.0))
	bar.show_status(_state(200.0, 250.0, 50.0, 50.0))
	assert_almost_eq(bar.life_fill.size.x, _full_width("life") * 0.5, 0.001, "the fill holds where the loss left it")
	assert_eq(bar.life_fill.modulate, _life_color(80), "but takes the new color")
	assert_true(bar.life_band.visible, "the band starts at the healSmooth label")
	_advance(bar, _gain_frames("LifeBarSmoother") - 1)
	assert_almost_eq(bar.life_fill.size.x, _full_width("life") * 0.5, 0.001, "still held the frame before")
	assert_true(bar.life_band.visible)
	_advance(bar, 1)
	assert_almost_eq(bar.life_fill.size.x, _full_width("life") * 0.8, 0.001, "its gain_end frame sets the width")
	assert_false(bar.life_band.visible, "and ends the band")


func test_a_change_inside_the_same_rounded_percent_leaves_the_fill_and_plays_no_band() -> void:
	var bar: StatusBar = _shown_bar(1, _state(1000.0, 1000.0))
	bar.show_status(_state(996.0, 1000.0))
	assert_almost_eq(bar.life_fill.size.x, _full_width("life"), 0.001)
	assert_false(bar.life_band.visible)
	assert_eq(bar.life_now_label.text, "996", "the number still changes")


func test_a_new_change_replaces_the_band_that_is_playing() -> void:
	var bar: StatusBar = _shown_bar(1, _state(250.0, 250.0))
	bar.show_status(_state(200.0, 250.0))
	_advance(bar, 5)
	bar.show_status(_state(100.0, 250.0))
	assert_almost_eq(bar.life_band.size.x, _full_width("life") * (100.0 / 250.0), 0.01, "the band is the second loss, from its first frame")


func test_a_focus_loss_moves_the_fill_and_plays_the_blue_band() -> void:
	var bar: StatusBar = _shown_bar(1, _state(250.0, 250.0, 50.0, 50.0))
	bar.show_status(_state(250.0, 250.0, 20.0, 50.0))
	assert_almost_eq(bar.focus_fill.size.x, _full_width("focus") * 0.4, 0.001)
	assert_true(bar.focus_band.visible)
	assert_eq(bar.focus_band.modulate, Color.html("#0099cc"), "in the Focus smoother's blue")
	assert_false(bar.life_band.visible, "and the life has none")
	_advance(bar, _frames_to("LifeBarSmoother2", "loss_end"))
	assert_false(bar.focus_band.visible, "it ends on its loss_end frame")


func test_a_focus_gain_holds_the_fill_until_frame_39_of_its_smoother() -> void:
	var bar: StatusBar = _shown_bar(1, _state(250.0, 250.0, 50.0, 50.0))
	bar.show_status(_state(250.0, 250.0, 10.0, 50.0))
	bar.show_status(_state(250.0, 250.0, 30.0, 50.0))
	_advance(bar, _gain_frames("LifeBarSmoother2") - 1)
	assert_almost_eq(bar.focus_fill.size.x, _full_width("focus") * 0.2, 0.001, "held the frame before")
	_advance(bar, 1)
	assert_almost_eq(bar.focus_fill.size.x, _full_width("focus") * 0.6, 0.001, "its gain_end frame sets the width")


func test_a_bar_that_runs_steps_its_clips_at_the_swf_frame_rate() -> void:
	var bar: StatusBar = _shown_bar(1, _state(250.0, 250.0))
	bar.show_status(_state(125.0, 250.0))
	var frames: int = _frames_to("LifeBarSmoother", "loss_end")
	for step in frames - 1:
		bar._process(1.0 / BattleScreenClip.fps())
	assert_true(bar.life_band.visible, "one frame before the end")
	bar._process(1.0 / BattleScreenClip.fps())
	assert_false(bar.life_band.visible, "the next frame plays the loss_end frame")
	assert_false(bar.is_processing(), "and the bar stops running")


# The death, which die() starts, clears the bar on frame 17 and then fades it by
# 5 points of Flash's _alpha a frame, which Flash stores as 13/256.
func test_a_death_clears_on_frame_17_then_fades_13_256ths_a_frame_and_hides() -> void:
	var bar: StatusBar = _shown_bar(1, _state(250.0, 250.0))
	bar.show_status(_state(0.0, 250.0))
	bar.die()
	var fades: Array[float] = []
	bar.death_faded.connect(func(alpha: float): fades.append(alpha))
	watch_signals(bar)
	var death: Dictionary = StatusBar.record()["death"]
	var clear_frame: int = int(death["clear_frame"])
	_advance(bar, clear_frame - 1)
	assert_true(bar.inner.visible, "not yet cleared the frame before")
	_advance(bar, 1)
	assert_false(bar.inner.visible, "cleared on the clear frame")
	assert_eq(bar.fade, 1.0)
	var traced: Dictionary = _traced_death_alphas()
	_advance(bar, 1)
	assert_eq(bar.fade, traced[clear_frame + 1], "its step off the alpha the frame after")
	_advance(bar, 18)
	assert_eq(bar.fade, traced[clear_frame + 19], "the last step above 0")
	_advance(bar, 1)
	assert_eq(bar.fade, 0.0, "to 0")
	assert_true(bar.visible, "it hides on the frame after")
	_advance(bar, 1)
	assert_false(bar.visible)
	assert_signal_emitted(bar, "death_hidden")
	assert_eq(fades[0], 1.0, "the first fade is the clear frame's")


# The bar's alpha out of 1 on each frame after the death, from the Traced run's
# log of a death in the Flash debug player. Each frame line holds the frame in
# its third field and the bar's _alpha in its fifth.
func _traced_death_alphas() -> Dictionary:
	var alphas: Dictionary = {}
	for line in FileAccess.get_file_as_string("res://references/traced_runs/death_fade_web_flash.txt").split("\n"):
		var fields: PackedStringArray = line.split("\t")
		if fields.size() >= 5 and fields[1] == "frame":
			alphas[int(fields[2])] = float(fields[4]) / 100.0
	return alphas


func _unit(active: bool) -> CombatUnit:
	var unit := CombatUnit.new()
	unit.active = active
	return unit


# The original hides the bar of a slot whose unit is not active
# (frame_217/PlaceObject2_3389_480 onClipEvent(load)), and the other bars stay
# where they are.
func test_a_slot_with_no_active_unit_has_its_bar_hidden_and_the_others_do_not_move() -> void:
	var top: TopStatusBar = add_child_autofree(TopStatusBarScene.instantiate())
	var before: Dictionary = {}
	for slot in range(1, 7):
		before[slot] = top.bar_for_slot(slot).position
	top.show_active({1: _unit(true), 2: _unit(true), 3: _unit(false), 5: _unit(true)})
	for slot in [1, 2, 5]:
		assert_true(top.bar_for_slot(slot).visible, "slot %d fights" % slot)
	for slot in [3, 4, 6]:
		assert_false(top.bar_for_slot(slot).visible, "slot %d has no active unit" % slot)
	for slot in range(1, 7):
		assert_eq(top.bar_for_slot(slot).position, before[slot], "slot %d did not move" % slot)
