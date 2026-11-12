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
		if child is Control and child.visible:
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
		pass
