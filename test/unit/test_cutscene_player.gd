# Unit tests for CutscenePlayer - the fade-in/video/fade-out/free sequence
# used to show CS_CUT2-5. The real clips run 16-70s (measured with ffprobe),
# far too slow to actually play out in a test, so playback completion is
# simulated by emitting the VideoStreamPlayer's own "finished" signal once
# it has started - only the fade tweens are timed for real, and those are
# scaled down to a fraction of a millisecond via animation_speed.
extends GutTest

const CutscenePlayerScene: PackedScene = preload("res://scenes/cutscenes/cutscene_player.tscn")


func test_play_fades_in_plays_video_then_fades_out_and_finishes():
	var player: CutscenePlayer = add_child_autofree(CutscenePlayerScene.instantiate())
	player.animation_speed = 1000.0
	# play() queue_free()s the player once it finishes, so the fade-out alpha
	# has to be captured the instant "finished" fires, not read back
	# afterward - by then the node may already be freed. A Dictionary is used
	# (not a bare local) because GDScript lambdas capture plain locals by
	# value, not by reference.
	var result := {"finished": false, "alpha_at_finish": -1.0}
	player.finished.connect(func():
		result.finished = true
		result.alpha_at_finish = player.fade_rect.color.a
	)

	player.play("CS_CUT4")

	# Fade-in tween is scaled to ~0.00067s - a short real wait is enough for
	# it to finish and for playback to begin. Generous relative to that
	# duration since a fixed 0.05s wait was flaky under full-suite load.
	await wait_seconds(0.2)
	assert_almost_eq(player.fade_rect.color.a, 0.0, 0.01, "faded to transparent before playback")
	assert_true(player.video.is_playing(), "video started after the fade-in")
	assert_eq(player.video.stream.get_class(), "VideoStreamTheora", "ogv resolves via the built-in importer")

	# Simulate the clip reaching its end instead of waiting out its real
	# 16.7s runtime.
	player.video.finished.emit()

	# Wait on the signal itself rather than a fixed sleep - under load (the
	# full suite running many tests) a short fixed wait was flaky, since the
	# fade-out tween needs at least one process frame to tick regardless of
	# how small its scaled duration is.
	var got_finished: bool = await wait_for_signal(player.finished, 2.0)
	assert_true(got_finished, "CutscenePlayer.finished fired")
	assert_true(result.finished, "finished handler ran")
	assert_almost_eq(result.alpha_at_finish, 1.0, 0.01, "fully opaque again when finished fires")


func test_animation_speed_zero_skips_fades_instantly():
	var player: CutscenePlayer = add_child_autofree(CutscenePlayerScene.instantiate())
	player.animation_speed = 0.0
	watch_signals(player)

	player.play("CS_CUT4")

	# With animation_speed <= 0 the fades resolve immediately (no tween, no
	# awaited frame), so playback should already be underway synchronously.
	assert_eq(player.fade_rect.color.a, 0.0, "fade-in resolved instantly")
	assert_true(player.video.is_playing())

	# Simulating the clip's end resumes play() synchronously all the way
	# through the instant fade-out, the finished signal, and queue_free().
	player.video.finished.emit()
	assert_signal_emitted(player, "finished")
	assert_eq(player.fade_rect.color.a, 1.0, "fade-out also resolved instantly")


func test_missing_cutscene_id_emits_finished_instead_of_hanging():
	var player: CutscenePlayer = add_child_autofree(CutscenePlayerScene.instantiate())
	watch_signals(player)

	# load() returns null for an id with no matching .ogv (confirmed via a
	# throwaway script: it logs an engine ERROR but does not throw). A caller
	# (the battle-victory flow) awaits our finished signal, so a bad id must
	# resolve that await rather than leaving play() parked forever on
	# `await video.finished` for a video that never starts. The engine error
	# is expected here, not a bug - mark it handled so it doesn't also fail
	# the test.
	player.play("NONEXISTENT_ID")
	for err in get_errors():
		err.handled = true

	assert_signal_emitted(player, "finished")
	assert_false(player.video.is_playing(), "never started playback for a missing stream")


# The other tests in this file only ever load CS_CUT4 (and CS_CUT5 in
# test_second_play_call_on_same_instance_is_ignored below) through
# CutscenePlayer.play(). This confirms ResourceLoader resolves every committed
# clip to a real VideoStreamTheora, CS_INTRO2 included.
func test_every_cutscene_clip_loads_as_video_stream_theora():
	for cutscene_id in ["CS_INTRO2", "CS_CUT1", "CS_CUT2", "CS_CUT3", "CS_CUT4", "CS_CUT5"]:
		var stream = load("res://assets/cutscenes/%s.ogv" % cutscene_id)
		assert_not_null(stream, "%s.ogv resolves via ResourceLoader" % cutscene_id)
		if stream != null:
			assert_eq(stream.get_class(), "VideoStreamTheora", "%s.ogv loads as a real Theora stream" % cutscene_id)


# For as long as a cutscene plays, the player should be able to click nothing
# but its SKIP button and see nothing but the cutscene. Both halves of that
# are scene structure rather than script, so they get asserted here: an IGNORE
# root would let clicks reach the battle victory screen sitting underneath (a
# second Proceed press), and living in the same canvas layer as the battle HUD
# would let the HUD draw over the video.
func test_overlay_blocks_clicks_and_draws_above_the_battle_hud():
	var player: CutscenePlayer = add_child_autofree(CutscenePlayerScene.instantiate())
	assert_eq(player.mouse_filter, Control.MOUSE_FILTER_STOP, "root swallows clicks meant for what's underneath")
	var overlay: CanvasLayer = player.get_node("Overlay")
	assert_not_null(overlay, "video and fade live on their own canvas layer")
	# battle_scene.tscn's "UI" CanvasLayer sets no layer, i.e. the default 1.
	assert_gt(overlay.layer, 1, "cutscene layer is above the battle HUD's")


# Without a timeout, a Theora stream that stalls or never decodes leaves
# play() parked on the video until the player thinks to press SKIP. Here the
# video is never told to finish and SKIP is not pressed; only the failsafe can
# end it.
func test_stalled_video_times_out_instead_of_soft_locking():
	var player: CutscenePlayer = add_child_autofree(CutscenePlayerScene.instantiate())
	player.animation_speed = 1000.0
	# The derived budget is the clip's own 16.7s plus a margin - far too long
	# to wait out in a test, so the budget is set directly instead.
	player.playback_timeout_seconds = 0.05

	player.play("CS_CUT4")

	var got_finished: bool = await wait_for_signal(player.finished, 2.0)
	assert_true(got_finished, "failsafe ended the cutscene the same way a real completion would")


func test_second_play_call_on_same_instance_is_ignored():
	var player: CutscenePlayer = add_child_autofree(CutscenePlayerScene.instantiate())
	player.animation_speed = 0.0

	player.play("CS_CUT4")
	assert_true(player.video.is_playing(), "first play() started the video")

	# A second call must not stack another fade/video coroutine on the same
	# fade_rect and eventually double queue_free() the node.
	player.play("CS_CUT5")
	assert_eq(
		player.video.stream.resource_path,
		"res://assets/cutscenes/CS_CUT4.ogv",
		"second play() call was ignored - stream from the first call is untouched"
	)

	player.video.finished.emit()
	assert_eq(player.fade_rect.color.a, 1.0, "first call's sequence still completes normally")


# CS_INTRO is a text screen, not a clip. The original's frame script fills four text
# fields from MENU[86] to MENU[89] (frame_263/DoAction.as:2-5, with the strings at
# frame_1/DoAction.as:294-297). The fields also bake in the author's text as their
# initialText, which the frame script replaces. Three of the four baked strings equal
# their MENU string, so only the first one, the field for MENU[86], can be told apart
# from the MENU text.
const CS_INTRO_LINES: Array[String] = [
	"One month ago. Sonny wakes up on the ship.",
	"He remembers nothing.",
	"The blind man gives him a tape...",
	"...then the blind man dies.",
]
const CS_INTRO_BAKED_TEXT: String = "One month ago, Sonny wakes up on the ship..."


func test_cs_intro_shows_the_four_menu_lines_and_not_the_baked_text():
	var player: CutscenePlayer = add_child_autofree(CutscenePlayerScene.instantiate())
	player.animation_speed = 0.0
	watch_signals(player)
	# play() frees the player once it finishes, so the lines are read as finished fires.
	var shown: Array[String] = []
	player.finished.connect(func():
		for node: Node in player.find_children("*", "Label", true, false):
			if node.is_visible_in_tree():
				shown.append((node as Label).text)
	)

	player.play("CS_INTRO")

	assert_signal_emitted(player, "finished")
	for line in CS_INTRO_LINES:
		assert_has(shown, line, "shows the MENU string %s" % line)
	assert_does_not_have(shown, CS_INTRO_BAKED_TEXT, "does not show the text baked into the field")


# Adds up the time the engine hands each frame, which is the time the player's timers
# and tweens count. The wall clock is no stand-in for it: the first frame after a
# test's set-up carries all of the set-up's time, so a 0.033 s fade can end in 0.01 s
# of wall time.
class FrameClock extends Node:
	var seconds: float = 0.0

	func _process(delta: float) -> void:
		seconds += delta


# The original holds CS_INTRO until its silent timer sprite runs through its frames.
# extract_cs_intro writes that frame count and the SWF's frame rate into
# cs_intro.json, and this test reads the same two numbers. It runs at 20 times the
# original's pace, so the hold takes well under a second. The two fades only add to
# the time between play() and finished.
func test_cs_intro_holds_its_lines_for_as_long_as_the_original_does():
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CsIntro.LAYOUT_PATH))
	var hold_seconds: float = float(layout["hold_frames"]) / float(layout["fps"])
	var speed: float = 20.0
	var clock: FrameClock = add_child_autofree(FrameClock.new())
	var player: CutscenePlayer = add_child_autofree(CutscenePlayerScene.instantiate())
	player.animation_speed = speed
	await wait_process_frames(1)
	var started: float = clock.seconds

	player.play("CS_INTRO")
	var got_finished: bool = await wait_for_signal(player.finished, 5.0)

	assert_true(got_finished, "CS_INTRO finishes")
	assert_gte(clock.seconds - started, hold_seconds / speed, "the lines stay up for the timer sprite's length")


# The scene a player shows for CS_INTRO, or null when it shows none.
func _intro_of(player: CutscenePlayer) -> CsIntro:
	for child in player.overlay.get_children():
		if child is CsIntro:
			return child
	return null


# Plays CS_INTRO at animation_speed 0 and returns its scene. The player frees itself as
# it finishes, but the scene stays up until the end of the frame, so a test that does
# not await can still read it.
func _play_cs_intro() -> CsIntro:
	var player: CutscenePlayer = add_child_autofree(CutscenePlayerScene.instantiate())
	player.animation_speed = 0.0
	player.play("CS_INTRO")
	return _intro_of(player)


# The cutscene draws over the Battle screen, which would show through anywhere the
# gradient does not reach, and the lines would be unreadable if it covered them.
func test_cs_intro_draws_the_gradient_over_the_whole_window_behind_its_lines():
	var intro: CsIntro = _play_cs_intro()
	assert_not_null(intro, "the intro scene is up")
	if intro == null:
		return
	var gradients: Array[Node] = intro.find_children("*", "TextureRect", true, false)
	assert_eq(gradients.size(), 1, "the intro draws one gradient")
	if gradients.size() != 1:
		return
	var gradient: TextureRect = gradients[0]
	assert_not_null(gradient.texture, "the gradient has its art")
	assert_eq(gradient.get_global_rect(), intro.get_viewport().get_visible_rect(), "it covers the whole window")
	for label: Node in intro.find_children("*", "Label", true, false):
		assert_lt(gradient.get_index(), label.get_index(), "it is behind the line %s" % (label as Label).text)


# The original stacks the intro's gradient and text under the SKIP text and button at
# depths 76 and 77, and those under the fade clip at depth 80 (frame_263). So the fade
# covers the intro as it fades in and out, and SKIP stays on top of the gradient. The
# gradient has no transparency, so an intro drawn above them would hide SKIP and
# leave the fade with nothing to cover.
func test_cs_intro_is_drawn_under_skip_and_the_fade():
	var player: CutscenePlayer = add_child_autofree(CutscenePlayerScene.instantiate())
	player.animation_speed = 0.0

	player.play("CS_INTRO")

	var intro: CsIntro = _intro_of(player)
	assert_not_null(intro, "the intro scene is up")
	if intro == null:
		return
	assert_gt(intro.get_index(), player.video.get_index(), "above the place of the video")
	assert_lt(intro.get_index(), player.skip_text.get_index(), "under the SKIP text")
	assert_lt(intro.get_index(), player.skip_button.get_index(), "under the SKIP button")
	assert_lt(intro.get_index(), player.fade_rect.get_index(), "under the fade")


# All four of the original's text fields allow wrapping, and extract_cs_intro writes
# them as Labels that wrap. The original shows each MENU string on one line because it
# fits its field, so a Label that wraps one means the field, the font or the string
# is not what the extractor assumed.
func test_each_cs_intro_line_fits_on_one_line_of_its_field():
	var intro: CsIntro = _play_cs_intro()
	assert_not_null(intro, "the intro scene is up")
	if intro == null:
		return
	for label: Node in intro.find_children("*", "Label", true, false):
		assert_eq((label as Label).get_line_count(), 1, "%s fits on one line" % (label as Label).text)


# extract_cutscene_skip reads where the original puts SKIP out of the SWF: a hit
# area for button 3468 and a line of text for edit text 3469. The test reads the
# same file that the player does, and the extractor's own tests check what it
# writes there. A Control keeps its offsets and works its size out from them, so
# the numbers match to within float error. A Label is never shorter than one
# line of its font, which is taller than the field here, so only the text's
# position and width are compared.
func test_skip_covers_the_original_hit_area_and_draws_its_text_where_the_original_does():
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cutscenes/skip_button.json"))
	var player: CutscenePlayer = add_child_autofree(CutscenePlayerScene.instantiate())
	var tolerance := Vector2(0.01, 0.01)

	var hit: Dictionary = layout["button"]
	var button_rect: Rect2 = player.skip_button.get_global_rect()
	assert_almost_eq(button_rect.position, Vector2(hit["x"], hit["y"]), tolerance, "the button's corner")
	assert_almost_eq(button_rect.size, Vector2(hit["w"], hit["h"]), tolerance, "the button's size")

	var text: Dictionary = layout["text"]
	var rect: Dictionary = text["rect"]
	assert_eq(player.skip_text.text, text["string"])
	assert_almost_eq(player.skip_text.get_global_rect().position, Vector2(rect["x"], rect["y"]), tolerance, "where the text starts")
	assert_almost_eq(player.skip_text.size.x, rect["w"], 0.01, "how wide its line is")
	assert_eq(player.skip_text.horizontal_alignment, LabelLayout.ALIGNMENTS[text["align"]], "aligned as the field is")
	assert_eq(player.skip_text.get_theme_font_size("font_size"), int(text["size"]), "the field's size")
	assert_eq(player.skip_text.get_theme_color("font_color"), Color(text["color"]), "the field's color")


# SKIP's release stops all sounds and sets cutSceneEnd (DefineButton2_3468
# on(release)), and the fade clip then fades out and goes where the clip's end
# goes (frame_263/PlaceObject2_3466_80 onClipEvent(enterFrame)). The test
# clicks the button the way a player does, which needs a viewport of its own,
# because GUT's window sits above everything in the root viewport and would
# take the click.
func test_pressing_skip_stops_the_clip_and_finishes_the_way_a_clip_that_plays_to_its_end_does():
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	add_child_autofree(viewport)
	var player: CutscenePlayer = CutscenePlayerScene.instantiate()
	player.animation_speed = 0.0
	viewport.add_child(player)
	# play() frees the player once it finishes, so the state is read the instant
	# "finished" fires. A Dictionary is used because lambdas capture plain locals
	# by value.
	var result := {"finished": 0, "clip_playing": true, "alpha": -1.0}
	player.finished.connect(func():
		result.finished += 1
		result.clip_playing = player.video.is_playing()
		result.alpha = player.fade_rect.color.a
	)

	player.play("CS_CUT4")
	assert_true(player.video.is_playing(), "the clip is playing before SKIP")
	_click(viewport, player.skip_button)

	assert_eq(result.finished, 1, "SKIP finished the cutscene")
	assert_false(result.clip_playing, "with the clip and its audio stopped")
	assert_eq(result.alpha, 1.0, "after the same fade to black")


# The button is clickable from the first frame, while the fade clip still has
# the cutscene fading in, and its release sets cutSceneEnd at once. So a press
# before the clip has started has to skip it, and the clip must never start,
# because its audio would play under the fade-out.
func test_pressing_skip_during_the_fade_in_skips_a_clip_that_has_not_started():
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	add_child_autofree(viewport)
	var player: CutscenePlayer = CutscenePlayerScene.instantiate()
	# A real tween, so the fade-in is still running when play() returns.
	player.animation_speed = 1000.0
	viewport.add_child(player)
	var result := {"clip_playing": true}
	player.finished.connect(func(): result.clip_playing = player.video.is_playing())

	player.play("CS_CUT4")
	assert_false(player.video.is_playing(), "the clip waits for the fade-in")
	_click(viewport, player.skip_button)

	# The clip is 16.7 s long, so a skip that is lost takes far longer than this.
	var got_finished: bool = await wait_for_signal(player.finished, 2.0)
	assert_true(got_finished, "the early press skipped the cutscene")
	assert_false(result.clip_playing, "and the clip never started")


# A left click on the control's center, pushed through the viewport's GUI input.
func _click(viewport: Viewport, control: Control) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = control.get_global_rect().get_center()
		event.global_position = event.position
		viewport.push_input(event, true)


# SKIP ends CS_INTRO the way it ends a clip. The tests run at 5 times the original's
# pace, so the hold still outlasts the 1.5 s wait for finished. A press that works
# finishes the cutscene a fade later, and one that is lost leaves the hold to run.
func test_pressing_skip_ends_the_cs_intro_hold():
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	add_child_autofree(viewport)
	var player: CutscenePlayer = CutscenePlayerScene.instantiate()
	player.animation_speed = 5.0
	viewport.add_child(player)

	player.play("CS_INTRO")
	await wait_until(func(): return player.fade_rect.color.a == 0.0, 2.0)
	_click(viewport, player.skip_button)

	var got_finished: bool = await wait_for_signal(player.finished, 1.5)
	assert_true(got_finished, "SKIP ended the hold")


# A press while the cutscene still fades in comes before the hold starts, so it has
# no wait to end. The hold has to see that the press already happened.
func test_pressing_skip_during_the_fade_in_skips_the_cs_intro_hold():
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	add_child_autofree(viewport)
	var player: CutscenePlayer = CutscenePlayerScene.instantiate()
	player.animation_speed = 5.0
	viewport.add_child(player)

	player.play("CS_INTRO")
	_click(viewport, player.skip_button)

	var got_finished: bool = await wait_for_signal(player.finished, 1.5)
	assert_true(got_finished, "the early press skipped the hold")
