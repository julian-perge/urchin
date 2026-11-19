# The Credits panel on its own (spec/107-credits.md). The rect test checks where
# its pieces land and the names' text, and test_ui_scenes.gd checks the way in
# and out through the main menu.
extends GutTest

const CreditsScene: PackedScene = preload("res://scenes/ui/menu/credits_panel.tscn")
const ROWS: int = 7


# frame_134/DoAction.as fills credit_1 to credit_7 from KrinLang.ENGLISH.MENU[92]
# to MENU[98], which dev/converted_json/strings.json holds. The test reads the
# file itself, so a role typed into the scene or the script fails it.
func test_the_roles_come_from_menu_92_to_98() -> void:
	var menu: Array = JSON.parse_string(FileAccess.get_file_as_string("res://dev/converted_json/strings.json"))["MENU"]
	var panel: CreditsPanel = add_child_autofree(CreditsScene.instantiate())
	for row in range(1, ROWS + 1):
		var role: Label = panel.get_node("Rows/Row%d/Role" % row)
		assert_eq(role.text, menu[91 + row], "row %d shows MENU[%d]" % [row, 91 + row])


# A panel that is not in the tree yet has not run _ready, so its roles show only
# what the .tscn types.
func test_the_scene_types_no_role() -> void:
	var panel: CreditsPanel = autofree(CreditsScene.instantiate())
	for row in range(1, ROWS + 1):
		assert_eq((panel.get_node("Rows/Row%d/Role" % row) as Label).text, "", "row %d" % row)


# Frame 134 places every text with the menu captions' Glow and DropShadow.
func test_every_label_uses_the_caption_look() -> void:
	var panel: CreditsPanel = autofree(CreditsScene.instantiate())
	for row in range(1, ROWS + 1):
		for node: String in ["Role", "Name"]:
			var label: Label = panel.get_node("Rows/Row%d/%s" % [row, node])
			assert_eq(label.theme_type_variation, &"MenuCaption", "Row%d/%s" % [row, node])
