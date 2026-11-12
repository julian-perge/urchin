# The three ItemSlot variants and their shared highlight
# (spec/107-window-shell.md, Item slots). The art comes from #161.
extends GutTest

const VARIANTS: Dictionary = {
	"res://scenes/ui/item_slot.tscn": "res://assets/ui/window/slot_inventory.png",
	"res://scenes/ui/item_slot_equip.tscn": "res://assets/ui/window/slot_equip.png",
	"res://scenes/ui/item_slot_drop.tscn": "res://assets/ui/window/slot_drop.png",
}


func _slot(path: String) -> ItemSlot:
	var slot: ItemSlot = (load(path) as PackedScene).instantiate()
	add_child_autofree(slot)
	return slot


func test_each_variant_loads_its_own_art() -> void:
	for path: String in VARIANTS:
		var art: Texture2D = _slot(path).get("texture")
		assert_not_null(art, path)
		if art != null:
			assert_eq(art.resource_path, VARIANTS[path], path)


func test_each_variant_is_31_by_31() -> void:
	for path: String in VARIANTS:
		assert_eq(_slot(path).size, Vector2(31, 31), path)


func test_the_highlight_is_a_2_px_white_border_with_no_fill() -> void:
	for path: String in VARIANTS:
		var frame: Panel = _slot(path).get_node("Highlight/Frame")
		var box := frame.get_theme_stylebox("panel") as StyleBoxFlat
		assert_not_null(box, path)
		if box == null:
			continue
		assert_false(box.draw_center, path)
		assert_eq(box.border_color, Color.WHITE, path)
		for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			assert_eq(box.get_border_width(side), 2, "%s side %d" % [path, side])


# The highlight is 32x32 around the slot's centre, so it overhangs the 31x31
# slot by half a pixel on each side.
func test_the_highlight_is_32_by_32_around_the_slot_centre() -> void:
	for path: String in VARIANTS:
		var slot: ItemSlot = _slot(path)
		var frame: Control = slot.get_node("Highlight/Frame")
		var rect := Rect2(frame.global_position - slot.global_position, frame.size)
		assert_eq(rect.size, Vector2(32, 32), path)
		assert_eq(rect.get_center(), slot.size / 2.0, path)
