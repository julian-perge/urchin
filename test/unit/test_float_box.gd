# FloatBox (scripts/ui/float_box.gd) places each child at a float position.
# Every expected position below is a sum of the separation and the minimum sizes
# the test reads back from the nodes.
extends GutTest

const EPSILON: float = 0.0001


func _slot(min_size: Vector2) -> Control:
	var slot: Control = Control.new()
	slot.custom_minimum_size = min_size
	return slot


func _box(vertical: bool, separation: float, slots: Array[Control]) -> FloatBox:
	var box: FloatBox = FloatBox.new()
	box.vertical = vertical
	box.separation = separation
	for slot: Control in slots:
		box.add_child(slot)
	return box


func _show(box: FloatBox) -> void:
	add_child_autofree(box)
	box.size = box.get_combined_minimum_size()
	await wait_process_frames(2)


# Returns the position along the box's axis that each shown child should get.
func _expected_offsets(box: FloatBox) -> Array[float]:
	var offsets: Array[float] = []
	var cursor: float = 0.0
	for child: Control in box.get_children():
		if not child.visible:
			offsets.append(NAN)
			continue
		offsets.append(cursor)
		var min_size: Vector2 = child.get_combined_minimum_size()
		cursor += (min_size.y if box.vertical else min_size.x) + box.separation
	return offsets


func _assert_placed(box: FloatBox) -> void:
	var offsets: Array[float] = _expected_offsets(box)
	var children: Array[Node] = box.get_children()
	for index: int in children.size():
		var child: Control = children[index]
		if not child.visible:
			continue
		var min_size: Vector2 = child.get_combined_minimum_size()
		if box.vertical:
			assert_almost_eq(child.position.y, offsets[index], EPSILON, "child %d y" % index)
			assert_almost_eq(child.position.x, 0.0, EPSILON, "child %d x" % index)
			assert_almost_eq(child.size.y, min_size.y, EPSILON, "child %d height" % index)
			assert_almost_eq(child.size.x, box.size.x, EPSILON, "child %d width" % index)
		else:
			assert_almost_eq(child.position.x, offsets[index], EPSILON, "child %d x" % index)
			assert_almost_eq(child.position.y, 0.0, EPSILON, "child %d y" % index)
			assert_almost_eq(child.size.x, min_size.x, EPSILON, "child %d width" % index)
			assert_almost_eq(child.size.y, box.size.y, EPSILON, "child %d height" % index)


func test_vertical_box_places_children_at_fractional_offsets():
	var box: FloatBox = _box(true, 2.35, [
		_slot(Vector2(40.5, 19.05)),
		_slot(Vector2(12.25, 7.3)),
		_slot(Vector2(30.0, 19.05)),
	])
	await _show(box)
	_assert_placed(box)


func test_horizontal_box_places_children_at_fractional_offsets():
	var box: FloatBox = _box(false, 3.15, [
		_slot(Vector2(17.45, 10.0)),
		_slot(Vector2(8.6, 12.5)),
		_slot(Vector2(21.05, 4.2)),
	])
	await _show(box)
	_assert_placed(box)


func test_hidden_child_takes_no_space_and_no_separation():
	var hidden: Control = _slot(Vector2(50.0, 33.3))
	hidden.visible = false
	var box: FloatBox = _box(true, 4.45, [
		_slot(Vector2(10.0, 11.15)),
		hidden,
		_slot(Vector2(10.0, 6.7)),
	])
	await _show(box)
	_assert_placed(box)
	var first: Control = box.get_child(0)
	var last: Control = box.get_child(2)
	assert_almost_eq(
		last.position.y,
		first.get_combined_minimum_size().y + box.separation,
		EPSILON,
	)


func test_vertical_minimum_size_takes_the_widest_child_and_sums_heights():
	var hidden: Control = _slot(Vector2(99.0, 99.0))
	hidden.visible = false
	var box: FloatBox = _box(true, 2.9, [
		_slot(Vector2(7.15, 4.4)),
		_slot(Vector2(11.6, 6.25)),
		hidden,
	])
	var first: Vector2 = box.get_child(0).get_combined_minimum_size()
	var second: Vector2 = box.get_child(1).get_combined_minimum_size()
	var expected: Vector2 = Vector2(maxf(first.x, second.x), first.y + box.separation + second.y)
	assert_almost_eq(box.get_combined_minimum_size(), expected, Vector2(EPSILON, EPSILON))
	box.free()


func test_horizontal_minimum_size_sums_widths_and_takes_the_tallest_child():
	var hidden: Control = _slot(Vector2(99.0, 99.0))
	hidden.visible = false
	var box: FloatBox = _box(false, 1.7, [
		_slot(Vector2(5.55, 3.0)),
		_slot(Vector2(6.35, 8.85)),
		hidden,
	])
	var first: Vector2 = box.get_child(0).get_combined_minimum_size()
	var second: Vector2 = box.get_child(1).get_combined_minimum_size()
	var expected: Vector2 = Vector2(first.x + box.separation + second.x, maxf(first.y, second.y))
	assert_almost_eq(box.get_combined_minimum_size(), expected, Vector2(EPSILON, EPSILON))
	box.free()


func test_nested_rows_in_a_column_place_cells_at_summed_offsets():
	var top_row: FloatBox = _box(false, 2.65, [
		_slot(Vector2(14.15, 19.05)),
		_slot(Vector2(9.4, 19.05)),
	])
	var bottom_row: FloatBox = _box(false, 2.65, [
		_slot(Vector2(11.8, 7.35)),
		_slot(Vector2(13.2, 7.35)),
	])
	var column: FloatBox = _box(true, 1.95, [top_row, bottom_row])
	await _show(column)
	_assert_placed(column)
	_assert_placed(top_row)
	_assert_placed(bottom_row)
	var cell: Control = bottom_row.get_child(1)
	var expected: Vector2 = Vector2(
		bottom_row.get_child(0).get_combined_minimum_size().x + bottom_row.separation,
		top_row.get_combined_minimum_size().y + column.separation,
	)
	assert_almost_eq(
		cell.get_global_rect().position - column.get_global_rect().position,
		expected,
		Vector2(EPSILON, EPSILON),
	)


func test_changing_separation_moves_children():
	var box: FloatBox = _box(true, 3.85, [
		_slot(Vector2(10.0, 5.5)),
		_slot(Vector2(10.0, 5.5)),
	])
	await _show(box)
	# A smaller separation shrinks the minimum size, so the box keeps its size
	# and does not resize. Only the setter can make the box sort its children.
	box.separation = 0.4
	await wait_process_frames(2)
	_assert_placed(box)


func test_changing_direction_moves_children():
	var box: FloatBox = _box(true, 2.2, [
		_slot(Vector2(10.0, 5.5)),
		_slot(Vector2(12.0, 5.5)),
	])
	await _show(box)
	# The box is larger than its minimum size on both axes, so the change of
	# direction does not resize it. Only the setter can make the box sort its
	# children.
	box.size = Vector2(100.0, 100.0)
	await wait_process_frames(2)
	box.vertical = false
	await wait_process_frames(2)
	_assert_placed(box)


# FloatBox gives each child its minimum size along the axis and the box's full
# size across it, whatever size flags the child carries. A child with
# SIZE_SHRINK_CENTER still fills the cross size and lands at the fractional
# offset the separation gives, so the box never rounds a pitch and never lets a
# size flag shrink or centre a child (spec/107-ui-foundation.md, Part 2).
func test_a_child_with_a_shrink_flag_fills_the_cross_size_at_a_fractional_offset():
	var shrink: Control = _slot(Vector2(10.0, 7.3))
	shrink.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	shrink.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box: FloatBox = _box(true, 2.35, [
		_slot(Vector2(30.0, 19.05)),
		shrink,
	])
	add_child_autofree(box)
	box.size = Vector2(31.0, box.get_combined_minimum_size().y)
	await wait_process_frames(2)
	# The offset of the second child is the first child's height plus the
	# separation, a fractional number the box must not round.
	var expected_y: float = 19.05 + 2.35
	assert_almost_eq(shrink.position.y, expected_y, EPSILON, "child y stays fractional")
	assert_almost_eq(shrink.position.x, 0.0, EPSILON, "child x")
	assert_almost_eq(shrink.size.y, 7.3, EPSILON, "child keeps its height")
	assert_almost_eq(shrink.size.x, box.size.x, EPSILON, "child fills the cross size")


# A stock Container asks the editor which size flags a child may carry. FloatBox
# has no expand flags, no alignment and no ratios, so it allows none, and the
# editor offers no flag that would fight its placement.
func test_float_box_allows_no_size_flags() -> void:
	var box: FloatBox = FloatBox.new()
	assert_eq(box._get_allowed_size_flags_horizontal(), PackedInt32Array())
	assert_eq(box._get_allowed_size_flags_vertical(), PackedInt32Array())
	box.free()


# Changing the separation must recompute the box's minimum size, so a caller
# that reads get_combined_minimum_size() after the change sees it grow with the
# larger separation. The box has to settle first: before its cache is filled a
# child's own minimum-size signal refreshes it, which would hide a missing
# update_minimum_size() in the setter.
func test_changing_separation_updates_the_minimum_size() -> void:
	var box: FloatBox = _box(true, 0.0, [
		_slot(Vector2(10.0, 5.5)),
		_slot(Vector2(10.0, 5.5)),
	])
	add_child_autofree(box)
	await wait_process_frames(2)
	var small: Vector2 = box.get_combined_minimum_size()
	box.separation = 4.45
	await wait_process_frames(2)
	var large: Vector2 = box.get_combined_minimum_size()
	assert_almost_eq(large.y, small.y + 4.45, EPSILON, "minimum height grows by the separation")


# Changing the direction must recompute the box's minimum size too. A vertical
# box of two 10x5.5 slots has a minimum of 10 wide and 11 tall; horizontal
# swaps that to 20 wide and 5.5 tall. As above, the box settles first so only
# the setter's update_minimum_size() can refresh the cache.
func test_changing_direction_updates_the_minimum_size() -> void:
	var box: FloatBox = _box(true, 0.0, [
		_slot(Vector2(10.0, 5.5)),
		_slot(Vector2(10.0, 5.5)),
	])
	add_child_autofree(box)
	await wait_process_frames(2)
	box.vertical = false
	await wait_process_frames(2)
	# Horizontal sums the widths and takes the tallest child: 10 + 10 wide and
	# 5.5 tall, against the vertical box's 10 wide and 5.5 + 5.5 tall.
	var first: Vector2 = box.get_child(0).get_combined_minimum_size()
	var second: Vector2 = box.get_child(1).get_combined_minimum_size()
	var expected: Vector2 = Vector2(first.x + second.x, maxf(first.y, second.y))
	assert_almost_eq(box.get_combined_minimum_size(), expected, Vector2(EPSILON, EPSILON))


# A stock Container skips a child that is set as top level, because that child
# draws at its own position and ignores the container. FloatBox does the same:
# a top-level child changes neither the minimum size nor its own position.
func test_a_top_level_child_is_skipped() -> void:
	var top: Control = _slot(Vector2(50.0, 33.3))
	top.set_as_top_level(true)
	var box: FloatBox = _box(true, 2.35, [
		_slot(Vector2(10.0, 11.15)),
		top,
		_slot(Vector2(10.0, 6.7)),
	])
	var without_top: Vector2 = Vector2(10.0, 11.15 + 2.35 + 6.7)
	assert_almost_eq(
		box.get_combined_minimum_size(),
		without_top,
		Vector2(EPSILON, EPSILON),
		"the top-level child adds nothing to the minimum size",
	)
	top.position = Vector2(7.0, 9.0)
	await _show(box)
	assert_almost_eq(top.position, Vector2(7.0, 9.0), Vector2(EPSILON, EPSILON), "the top-level child keeps its own position")
