# The tooltips that #364 moved off native tooltip_text, compared with the
# original's strings. The test reads strings.json and items.json itself, so a
# string typed into a script fails here.
extends GutTest

const RightColumnScene = preload("res://scenes/ui/window/right_column.tscn")
const AbilitiesScene = "res://scenes/ui/menu/abilities_window.tscn"

var _strings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://dev/converted_json/strings.json"))
var _items: Array = JSON.parse_string(FileAccess.get_file_as_string("res://dev/converted_json/items.json"))["items"]


func before_each() -> void:
	GameData.current_save = PlayerSave.new_game("TooltipTest", 0)


func after_each() -> void:
	GameData.current_save = null
	GameTooltip.hide_tooltip()


func _sell_ratio() -> float:
	var look: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://dev/converted_json/tooltip_look.json"))
	return float(look["sell_ratio"])


func _menu(index: int) -> String:
	return _strings["MENU"][index]


func _tooltip_texts() -> Array:
	var texts: Array = []
	for section in GameTooltip.sections():
		for label in section.get_child(0).get_children():
			texts.append(label.text)
	return texts


# DefineButton2_2858 on(rollOver): MENU[1] over MENU[2].
func test_the_delete_slot_shows_delete_item_over_its_warning():
	var column: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	column.delete_button.mouse_entered.emit()
	assert_eq(_tooltip_texts(), [_menu(1), _menu(2)])
	column.delete_button.mouse_exited.emit()
	assert_false(GameTooltip.is_showing())


# DefineButton2_3015 on(rollOver): MENU[3] over MENU[5] with nothing on the mouse.
func test_the_sell_slot_with_no_item_shows_the_empty_text():
	var column: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	column.show_sell_button(true)
	column.sell_button.mouse_entered.emit()
	assert_eq(_tooltip_texts(), [_menu(3), _menu(5)])


# MENU[3] over MENU[4] + " €" + Math.ceil(KRINITEM[5] * the sell ratio), for the
# item the sell slot would sell: the selected one, when nothing is dragged.
func test_the_sell_slot_names_the_selected_items_price():
	var column: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	column.show_sell_button(true)
	var item: GameItem = ItemManagerAuto.get_item(5)
	column.populate([item])
	column.slots[0].slot_clicked.emit(column.slots[0])
	column.sell_button.mouse_entered.emit()
	assert_eq(_tooltip_texts(), [_menu(3), "%s €%d" % [_menu(4), ceili(item.price * _sell_ratio())]])


# DefineButton2_2985 on(rollOver) reads KRINITEM0 for an empty cell. Its type
# is under 2, so it shows the plain layout: the name over the flavor text.
func test_an_empty_backpack_cell_shows_item_zero():
	var column: RightColumn = add_child_autofree(RightColumnScene.instantiate())
	column.populate([])
	column.slots[0].mouse_entered.emit()
	var item_zero: Dictionary = _items[0]
	assert_eq(int(item_zero["id"]), 0)
	assert_eq(_tooltip_texts(), [item_zero["display_name"], item_zero["tool_tip"]])


# DefineSprite_3142/frame_25/DoAction.as:86-88: SKILLNONE over SKILLTUT2 over
# SKILLTUT.
func test_an_empty_ability_socket_shows_the_skill_strings():
	GameData.current_save.move_matrix[3] = 0
	var window: Control = add_child_autofree(load(AbilitiesScene).instantiate())
	window.refresh()
	window.get_node("Socket3").mouse_entered.emit()
	assert_eq(_tooltip_texts(), [_strings["SKILLNONE"], _strings["SKILLTUT2"], _strings["SKILLTUT"]])


# DefineSprite_3306, the enterFrame of PlaceObject2_3305_1: MENU[54 + n] + " " +
# MENU[64] over MENU[59 + n] for stance button n.
func test_each_stance_button_shows_its_mode_name_over_its_description():
	var row: StanceRow = add_child_autofree(load("res://scenes/battle/stance_row.tscn").instantiate())
	assert_eq(row.buttons.size(), 5)
	for n in row.buttons.size():
		row.buttons[n].mouse_entered.emit()
		assert_eq(_tooltip_texts(), [_menu(54 + n) + " " + _menu(64), _menu(59 + n)], "stance %d" % n)
		row.buttons[n].mouse_exited.emit()
		assert_false(GameTooltip.is_showing())


func _files_under(dir: String, extensions: Array) -> Array:
	var found: Array = []
	for name in DirAccess.get_files_at(dir):
		if extensions.has(name.get_extension()):
			found.append(dir.path_join(name))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_files_under(dir.path_join(sub), extensions))
	return found


# Every tooltip goes through GameTooltip, so no scene or script sets Godot's own.
func test_no_scene_or_script_sets_a_native_tooltip():
	var setter: RegEx = RegEx.create_from_string("(^|\\.)tooltip_text\\s*=")
	var found: Array = []
	for path in _files_under("res://scenes", ["tscn"]) + _files_under("res://scripts", ["gd"]):
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var line: String = lines[i].strip_edges()
			if not line.begins_with("#") and setter.search(line) != null:
				found.append("%s:%d" % [path, i + 1])
	assert_eq(found, [])
