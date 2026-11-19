# The Hub's fade-in, the original's clip 2837 on the Navigation frame
# (frame_181/PlaceObject2_2837_1660). Its load handler sets _alpha to 99 and its
# enterFrame handler takes 15 off on each frame while _alpha is above 0.
# extract_hub_fade writes those numbers, the colour and the rect to
# assets/ui/hub_fade.json, and these tests read the same file.
extends GutTest

const AlphaSteps = preload("res://test/alpha_steps.gd")
const GameScene: PackedScene = preload("res://scenes/game.tscn")
const LAYOUT_FILE := "res://assets/ui/hub_fade.json"

var _save_before: PlayerSave


func before_each() -> void:
	_save_before = GameData.current_save
	GameData.current_save = PlayerSave.new_game("Fade", 0)


func after_each() -> void:
	GameData.current_save = _save_before
	ZoneManager.pending_victory = {}
	AudioManagerAuto.stop_music()


func _layout() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_FILE))


# The alpha the clip shows on each frame after its first, until it is clear,
# from the Traced run's replay of the clip's enterFrame (FADE case "hub" of
# alpha_steps_probe.as). Flash draws a negative _alpha as clear.
func _expected_alphas() -> Array[float]:
	var alphas: Array[float] = []
	for percent: float in AlphaSteps.values("FADE", "hub").slice(1):
		alphas.append(maxf(percent, 0.0) / 100.0)
		if percent <= 0.0:
			break
	return alphas


# The Probe's hub case starts at 99 and takes 15 off, so the log stands for the
# clip only while the JSON holds the same two numbers.
func test_the_traced_runs_case_has_the_clips_numbers():
	var layout: Dictionary = _layout()
	assert_eq(AlphaSteps.values("FADE", "hub")[0], FlashAlpha.to_percent(FlashAlpha.from_percent(float(layout["start_alpha"]))), "the load alpha")
	assert_eq(float(layout["alpha_step"]), 15.0, "the step")


# A fade whose _process() does not run, so only step_frame() moves it.
func _fade() -> HubFade:
	var fade := HubFade.new()
	add_child_autofree(fade)
	fade.set_process(false)
	return fade


func test_the_fade_starts_at_the_load_alpha_and_falls_by_the_step_each_frame_to_0():
	var fade: HubFade = _fade()
	assert_eq(fade.color.a, AlphaSteps.values("FADE", "hub")[0] / 100.0, "the load alpha")
	var shown: Array[float] = []
	for _frame: int in _expected_alphas().size():
		fade.step_frame()
		shown.append(fade.color.a)
	assert_eq(shown, _expected_alphas(), "one step a frame")
	assert_eq(fade.color.a, 0.0, "it ends clear")
	fade.step_frame()
	assert_eq(fade.color.a, 0.0, "it stays clear")


func test_the_fade_draws_the_clips_colour_over_its_rect_and_lets_clicks_through():
	var fade: HubFade = _fade()
	var layout: Dictionary = _layout()
	var rect: Dictionary = layout["rect"]
	var colour := Color(layout["color"])
	assert_eq(Color(fade.color, 1.0), colour, "the shape's colour")
	assert_eq(fade.position, Vector2(rect["x"], rect["y"]), "the rect's corner")
	assert_eq(fade.size, Vector2(rect["w"], rect["h"]), "the rect's size")
	assert_eq(fade.mouse_filter, Control.MOUSE_FILTER_IGNORE, "a clip with no button takes no click")


func test_the_fade_steps_once_for_each_frame_of_the_swf_and_never_skips_one():
	var fade: HubFade = _fade()
	var frame_seconds: float = 1.0 / float(_layout()["fps"])
	var first: float = _expected_alphas()[0]
	fade.advance(frame_seconds * 0.5)
	assert_eq(fade.color.a, AlphaSteps.values("FADE", "hub")[0] / 100.0, "half a frame steps nothing")
	fade.advance(frame_seconds * 0.5)
	assert_almost_eq(fade.color.a, first, 0.0001, "a whole frame steps once")
	# Flash plays every frame of a slow stretch late and drops none, so a long
	# delta still steps only once.
	fade.advance(frame_seconds * 5.0)
	assert_almost_eq(fade.color.a, _expected_alphas()[1], 0.0001, "a long frame steps once")


# A display whose frames do not divide the SWF's frame time must still step at
# the SWF's rate. Nine deltas of 0.7 frames are 6.3 frames, so the fade steps 6
# times. A fade that dropped the time each step ran over would step only 4 times.
func test_the_fade_keeps_the_swf_frame_rate_when_the_deltas_do_not_divide_it():
	var fade: HubFade = _fade()
	var frame_seconds: float = 1.0 / float(_layout()["fps"])
	for _delta: int in 9:
		fade.advance(frame_seconds * 0.7)
	assert_almost_eq(fade.color.a, _expected_alphas()[5], 0.0001, "six steps in 6.3 frames")


func test_after_a_win_the_hub_and_the_victory_window_show_under_the_fade_until_it_clears():
	var settlement := BattleSettlement.new()
	settlement.fighters[0] = BattleSettlement.FighterExperience.new()
	ZoneManager.pending_victory = {"settlement": settlement, "battle_id": 100, "is_boss": false}
	var game: Control = GameScene.instantiate()
	add_child_autofree(game)
	var fade: HubFade = game.get_node("HubFade")
	fade.set_process(false)
	assert_true(game.get_node("VictoryWindow").visible, "the Window is open")
	assert_eq(fade.get_index(), game.get_child_count() - 1, "the fade is over every Window and the card")
	assert_eq(fade.color.a, AlphaSteps.values("FADE", "hub")[0] / 100.0, "the Hub opens under the black")
	for _frame: int in _expected_alphas().size():
		fade.step_frame()
	assert_eq(fade.color.a, 0.0, "the Hub and the Window show after the original's frame count")


func test_a_zone_picked_on_the_world_map_fades_the_hub_in_again():
	var game: Control = GameScene.instantiate()
	add_child_autofree(game)
	var fade: HubFade = game.get_node("HubFade")
	fade.set_process(false)
	for _frame: int in _expected_alphas().size():
		fade.step_frame()
	assert_eq(fade.color.a, 0.0, "the first fade is over")
	var map: Control = game.get_node("ZoneMapOverlay")
	map.visible = true
	map._on_zone_selected(ZoneManager.current_zone)
	assert_eq(fade.color.a, AlphaSteps.values("FADE", "hub")[0] / 100.0, "the pick jumps to Navigation, which places the clip again")
