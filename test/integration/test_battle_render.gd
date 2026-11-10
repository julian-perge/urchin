# dev/battle_render.gd's command line, and what each of its shows and steps does
# to a Fighter presenter. The render itself needs a window, so no test here
# draws anything.
extends GutTest

const BattleRender = preload("res://dev/battle_render.gd")
const FighterPresenterScene = preload("res://scenes/battle/fighter_presenter.tscn")
# The colors of the Result flash's labels, 16763904, 10092288 and 3407871 in
# frame_42/DoAction_3.as:117-130 and 162-168.
const HIT_FLASH: Color = Color("#ffcc00")
const HEAL_FLASH: Color = Color("#99ff00")
const FOCUS_FLASH: Color = Color("#33ffff")

var _presenter: FighterPresenter
var _shield_clip: RigClip
var _layer: FloatingNumberLayer
var _unit: CombatUnit


# Builds a presenter the way battle_scene.gd does. Its Result flash, its Shield
# clip and its Floating number layer are stopped, so only step() moves them, as
# in the render.
func _present() -> void:
	_unit = CombatUnit.new()
	_unit.player_id = 2
	_unit.player_name = "Prison Guard"
	_unit.team_side = CombatUnit.Team.TWO
	_unit.life_u = 100.0
	_unit.life_n = 100.0
	_layer = add_child_autofree(FloatingNumberLayer.new())
	_layer.set_process(false)
	_presenter = add_child_autofree(FighterPresenterScene.instantiate())
	_presenter.setup(_unit, Vector2(300, 250), {}, {}, _layer)
	_presenter.get_node("ResultFlash").set_process(false)
	_shield_clip = _presenter.get_node("ShieldClip")
	_shield_clip.set_process(false)


# The color of the Result flash the doll shows, or null while it shows none.
func _flash_color() -> Variant:
	var body_shader: ShaderMaterial = _presenter.get_node("Doll/Body").material
	if not body_shader.get_shader_parameter("result_flash"):
		return null
	return body_shader.get_shader_parameter("color")


func _number_labels() -> Array:
	return _layer.numbers().map(func(number: FloatingNumber) -> String: return number.label)


func test_it_reads_the_battle_the_folder_the_shows_the_frames_and_alpha():
	var options: Dictionary = BattleRender.parse_args(PackedStringArray([
		"--battle=109", "--out=/tmp/renders", "--show=1:hit", "--show=2:shield_block",
		"--frames=0-2,5", "--alpha",
	]))
	assert_eq(options, {
		"battle": 109,
		"out": "/tmp/renders",
		"shows": [[1, "hit"], [2, "shield_block"]],
		"frames": [0, 1, 2, 5],
		"alpha": true,
	})


func test_with_only_a_battle_and_a_folder_it_saves_frame_0_with_nothing_shown():
	var options: Dictionary = BattleRender.parse_args(PackedStringArray(["--battle=12", "--out=/tmp/renders"]))
	assert_eq(options, {"battle": 12, "out": "/tmp/renders", "shows": [], "frames": [0], "alpha": false})


func test_it_refuses_a_command_line_it_cannot_render():
	var base: Array = ["--battle=109", "--out=/tmp/renders"]
	for args in [
		["--out=/tmp/renders"],
		["--battle=109"],
		["--battle=boss", "--out=/tmp/renders"],
		base + ["--show=1:punch"],
		base + ["--show=one:hit"],
		base + ["--show=1"],
		base + ["--frames=3-1"],
		base + ["--frames=a"],
		base + ["--frames=-2"],
		base + ["--frame=2"],
	]:
		var options: Dictionary = BattleRender.parse_args(PackedStringArray(args))
		assert_eq(options.keys(), ["error"], "%s is refused" % [args])


# test_fighter_presenter.gd pins each of these presenter calls in full.
func test_each_show_lands_what_it_names_on_the_fighter():
	for case in [
		["hit", HIT_FLASH, false, ["normal"]],
		["heal", HEAL_FLASH, false, ["normal"]],
		["focus", FOCUS_FLASH, false, []],
		["shield_block", null, true, ["shield"]],
		["shield_clip", null, true, []],
	]:
		_present()
		BattleRender.show_on(_presenter, _unit, case[0])
		assert_eq(_flash_color(), case[1], "%s: the Result flash" % case[0])
		assert_eq(_shield_clip.is_playing(), case[2], "%s: the Shield clip" % case[0])
		assert_eq(_number_labels(), case[3], "%s: the Floating number" % case[0])


# The Result flash is on for its frames 0 and 1 and off for frame 2. The Shield
# clip waits on its frame 1 until the first step. The hit's number leaves its
# layer after the last frame of its label.
func test_a_step_moves_the_flash_the_clip_and_the_numbers_on_by_one_swf_frame():
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FloatingNumberLayer.LAYOUT_PATH))
	var number_frames: int = layout["labels"]["normal"]["frames"].size()
	_present()
	BattleRender.show_on(_presenter, _unit, "hit")
	BattleRender.show_on(_presenter, _unit, "shield_clip")
	BattleRender.step([_presenter], _layer)
	assert_eq(_flash_color(), HIT_FLASH, "the flash is still on at its frame 1")
	assert_eq(_shield_clip.frame, 2, "the clip shows its frame 2")
	BattleRender.step([_presenter], _layer)
	assert_null(_flash_color(), "the flash is off at its frame 2")
	assert_eq(_shield_clip.frame, 3, "the clip shows its frame 3")
	for frame in number_frames - 3:
		BattleRender.step([_presenter], _layer)
	assert_eq(_number_labels(), ["normal"], "the number is up for its label's last frame")
	BattleRender.step([_presenter], _layer)
	assert_eq(_number_labels(), [], "and leaves after it")
