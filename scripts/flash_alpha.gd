# flash_alpha.gd
# Flash keeps a clip's _alpha as a whole number of 1/256 steps. A write stores
# the whole steps of the new percent and drops the rest toward 0, and a read
# gives the steps back as a percent. Nothing holds the value between 0 and 100.
# Every fade of the original steps _alpha this way, so the port's fades keep
# their alpha in these steps too. DECODED_ALGORITHMS.md, "A clip's _alpha in
# 1/256 steps", gives the Traced runs that measured it.
class_name FlashAlpha
extends RefCounted

const STEPS: int = 256


# The steps that a write of `percent` to _alpha stores.
static func from_percent(percent: float) -> int:
	return int(percent * STEPS / 100.0)


# The percent that a read of _alpha gives for `steps`.
static func to_percent(steps: int) -> float:
	return steps * 100.0 / STEPS


# The steps that "_alpha += percent" stores when _alpha holds `steps`.
static func add(steps: int, percent: float) -> int:
	return from_percent(to_percent(steps) + percent)


# The factor that Flash multiplies each pixel's alpha by. A negative _alpha
# draws nothing. The factor is not capped at 1, because Flash multiplies by the
# value above 100 too, and Godot's modulate does the same.
static func multiplier(steps: int) -> float:
	return maxf(steps, 0) / float(STEPS)
