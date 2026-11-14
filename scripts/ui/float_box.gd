# float_box.gd
# A box that stacks its children at float positions with a float separation.
# Godot's BoxContainer takes its separation from a whole-pixel theme constant,
# and the SWF's pitches are fractional (spec/107-ui-foundation.md, Part 2).
# docs/agents/godot.md says when to use it.
@tool
class_name FloatBox
extends Container

@export var vertical: bool = true:
	set(value):
		vertical = value
		update_minimum_size()
		queue_sort()

@export var separation: float = 0.0:
	set(value):
		separation = value
		update_minimum_size()
		queue_sort()


func _get_minimum_size() -> Vector2:
	var total: Vector2 = Vector2.ZERO
	var shown: int = 0
	for child: Node in get_children():
		if not _placed(child):
			continue
		var min_size: Vector2 = child.get_combined_minimum_size()
		if vertical:
			total.x = maxf(total.x, min_size.x)
			total.y += min_size.y
		else:
			total.x += min_size.x
			total.y = maxf(total.y, min_size.y)
		shown += 1
	if shown > 1:
		var gaps: float = separation * (shown - 1)
		total += Vector2(0.0, gaps) if vertical else Vector2(gaps, 0.0)
	return total


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_place_children()


# FloatBox has no expand flags, no alignment and no ratios (spec/107-ui-foundation.md,
# Part 2), so it allows a child no size flag. Returning an empty list stops the
# editor offering flags that would fight its placement.
func _get_allowed_size_flags_horizontal() -> PackedInt32Array:
	return PackedInt32Array()


func _get_allowed_size_flags_vertical() -> PackedInt32Array:
	return PackedInt32Array()


# A top-level child draws at its own position and ignores the container, so,
# like a stock Container, FloatBox leaves it out of both the minimum size and
# the placement.
func _placed(child: Node) -> bool:
	return child is Control and child.visible and not child.is_set_as_top_level()


# Each child gets its own minimum size along the box's axis and the box's full
# size across it. The position and size are set directly, not through
# fit_child_in_rect(), so no size flag can shrink or centre a child and no
# pitch is rounded. A fractional pitch such as 19.05 has to reach the screen
# (docs/agents/godot.md).
func _place_children() -> void:
	var cursor: float = 0.0
	for child: Node in get_children():
		if not _placed(child):
			continue
		var min_size: Vector2 = child.get_combined_minimum_size()
		if vertical:
			child.position = Vector2(0.0, cursor)
			child.size = Vector2(size.x, min_size.y)
			cursor += min_size.y + separation
		else:
			child.position = Vector2(cursor, 0.0)
			child.size = Vector2(min_size.x, size.y)
			cursor += min_size.x + separation
