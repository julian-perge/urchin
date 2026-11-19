# FlashAlpha against the #442 Traced run. Each ALPHA case of the Probe sets an
# empty clip's _alpha to a load value and adds one step on every frame. The
# case's name gives both: "in20" starts at 0 and adds 20, "out15" starts at 100
# and takes 15 off, and "out15from99" starts at 99.
extends GutTest

const AlphaSteps = preload("res://test/alpha_steps.gd")


func _load_percent(case_name: String) -> float:
	if case_name.contains("from"):
		return float(case_name.get_slice("from", 1))
	return 0.0 if case_name.begins_with("in") else 100.0


func _step(case_name: String) -> float:
	var digits: String = case_name.trim_prefix("in").trim_prefix("out").get_slice("from", 0)
	return float(digits) * (1.0 if case_name.begins_with("in") else -1.0)


func test_every_logged_step_matches_the_traced_run():
	var cases: Array[String] = AlphaSteps.alpha_cases()
	assert_eq(cases.size(), 10, "the log has the Probe's ten cases")
	for case_name: String in cases:
		var logged: Array[float] = AlphaSteps.values("ALPHA", case_name)
		var steps: int = FlashAlpha.from_percent(_load_percent(case_name))
		var ported: Array[float] = [FlashAlpha.to_percent(steps)]
		for _frame: int in logged.size() - 1:
			steps = FlashAlpha.add(steps, _step(case_name))
			ported.append(FlashAlpha.to_percent(steps))
		assert_eq(ported, logged, case_name)


func test_a_negative_alpha_draws_nothing_and_one_above_100_draws_above_1():
	assert_eq(FlashAlpha.multiplier(-3), 0.0, "below 0")
	assert_eq(FlashAlpha.multiplier(FlashAlpha.STEPS), 1.0, "at 100")
	assert_eq(FlashAlpha.multiplier(306), 306.0 / 256.0, "at 119.53125")
