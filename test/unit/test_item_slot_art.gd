# The ItemSlot's art and highlight (spec/107-window-shell.md, Item slots).
# Every slot uses the inventory art from #161. The equip and drop arts differ
# only in their shadow angle, which is too small to see.
extends GutTest

const SLOT: PackedScene = preload("res://scenes/ui/item_slot.tscn")


func _slot() -> ItemSlot:
	var slot: ItemSlot = SLOT.instantiate()
	add_child_autofree(slot)
	return slot


func test_the_slot_loads_the_inventory_art() -> void:
	var art: Texture2D = _slot().get("texture")
	assert_not_null(art)
	if art != null:
		assert_eq(art.resource_path, "res://assets/ui/window/slot_inventory.png")


func test_the_slot_is_31_by_31() -> void:
	assert_eq(_slot().size, Vector2(31, 31))


func test_the_highlight_is_a_2_px_white_border_with_no_fill() -> void:
	var frame: Panel = _slot().get_node("Highlight/Frame")
	var box := frame.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(box)
	if box == null:
		return
	assert_false(box.draw_center)
	assert_eq(box.border_color, Color.WHITE)
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		assert_eq(box.get_border_width(side), 2, "side %d" % side)


# The highlight is 32x32 around the slot's centre, so it overhangs the 31x31
# slot by half a pixel on each side.
func test_the_highlight_is_32_by_32_around_the_slot_centre() -> void:
	var slot: ItemSlot = _slot()
	var frame: Control = slot.get_node("Highlight/Frame")
	var rect := Rect2(frame.global_position - slot.global_position, frame.size)
	assert_eq(rect.size, Vector2(32, 32))
	assert_eq(rect.get_center(), slot.size / 2.0)
