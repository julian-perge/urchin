extends GutTest

const LAYOUT: String = "res://assets/backgrounds/battle/battle_layout.json"


func _clock() -> BattleClock:
	var clock := BattleClock.new()
	var ring := TextureRect.new()
	ring.name = "Ring"
	clock.add_child(ring)
	add_child_autofree(clock)
	return clock


func _shows(clock: BattleClock) -> String:
	return (clock.get_node("Ring") as TextureRect).texture.resource_path.get_file().get_basename()


# extract_battle_screen reads BattleTimeLimit out of the battle frame's script
# and renders the ring at every BattleTimeNow up to it, on both frames.
func test_the_renders_cover_every_battle_time_now_up_to_the_limit():
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))["clock"]
	assert_eq(int(record["limit"]), int(BattleRunner.BATTLE_TIME_LIMIT), "the SWF's limit is the runner's")
	for label: String in BattleClock.LABELS.values():
		assert_has(record["labels"], label)
		for time_now in int(record["limit"]) + 1:
			var path: String = BattleClock.FRAMES % [label, time_now]
			assert_true(ResourceLoader.exists(path), "%s exists" % path)


func test_show_time_picks_the_render_of_the_side_at_that_time():
	var clock: BattleClock = _clock()
	clock.show_time(BattleClock.Side.FRIEND, 30.0)
	assert_eq(_shows(clock), "friend_030")
	clock.show_time(BattleClock.Side.ENEMY, 120.0)
	assert_eq(_shows(clock), "enemy_120")


func test_show_time_rounds_a_time_just_under_the_limit_to_the_whole_ring():
	var clock: BattleClock = _clock()
	clock.show_time(BattleClock.Side.FRIEND, BattleRunner.BATTLE_TIME_LIMIT - 0.000001)
	assert_eq(_shows(clock), "friend_120")


func test_show_time_clamps_to_the_renders_it_has():
	var clock: BattleClock = _clock()
	clock.show_time(BattleClock.Side.FRIEND, -3.0)
	assert_eq(_shows(clock), "friend_000")
	clock.show_time(BattleClock.Side.FRIEND, 500.0)
	assert_eq(_shows(clock), "friend_120")
