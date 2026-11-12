extends GutHookScript

# GUT runs this after the last test (post_run_script in .gutconfig.json).
#
# Tests that open the hub or the main menu leave the menu music playing on the
# AudioManager autoload. When Godot quits, it stops that playback, but it only
# frees a stopped playback after the audio thread mixes once more and the main
# thread then cleans up. When Godot quits before that happens, the playback
# and its stream are never freed, and the run ends with "leaked at exit" and
# "still in use at exit" (julian-perge/urchin#187). In 2026-11-11 tests, 5 of
# 10 full runs leaked without this hook and 0 of 10 with it.
#
# So the hook stops every sound and waits long enough for several mix steps.

const AUDIO_RELEASE_SECONDS: float = 0.1


func run():
	# AudioManager's _ready() renames the AudioManagerAuto autoload node.
	gut.get_tree().root.get_node("AudioManager").stop_all_sounds()
	await gut.get_tree().create_timer(AUDIO_RELEASE_SECONDS).timeout
