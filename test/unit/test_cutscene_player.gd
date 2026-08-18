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
