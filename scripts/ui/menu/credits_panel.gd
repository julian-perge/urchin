# credits_panel.gd
# The Credits Screen (scenes/ui/menu/credits_panel.tscn), the original's
# creditMenu, root frame 134, which the title's Credits caption opens. The
# names are typed into the scene, because the SWF types them as static text.
# The original's link to davidorr.net over David Orr's name is left out
# (docs/adr/0002-leave-out-the-armor-games-branding.md). Back is
# menu_back.tscn, which main_menu.gd connects.
class_name CreditsPanel
extends Control

# frame_134/DoAction.as fills credit_1 to credit_7 from MENU[92] to MENU[98].
const FIRST_ROLE: int = 92
const ROWS: int = 7


func _ready() -> void:
	for row in range(1, ROWS + 1):
		(get_node("Rows/Row%d/Role" % row) as Label).text = Strings.menu(FIRST_ROLE + row - 1)
