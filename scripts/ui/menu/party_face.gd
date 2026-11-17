# party_face.gd
# One face of the Inventory's party bar, the original's sprite 2979 (fa0 to
# fa5) in DefineSprite_3142. The scene types the part rects, and
# test_screen_rects.gd checks them against the SWF. show_member() sets the three
# states from data and builds the face's tooltip (spec/107-inventory.md, Party
# bar). Clicks and shift-click belong to #11, which connects the HitButton.
#
# Until a member is shown, the scene is the SWF's first frame: every part is
# visible.
class_name PartyFace
extends Control

# The id of the member this face shows, or -1 while none joined this slot.
var party_id: int = -1

@onready var _parts: Control = $Parts
@onready var _face: TextureRect = $Parts/Face
@onready var _blacker: ColorRect = $Parts/Blacker
@onready var _frame: TextureRect = $Parts/Frame
@onready var hit_button: Button = $Parts/HitButton


func _ready() -> void:
	hit_button.mouse_entered.connect(_show_tooltip)
	hit_button.mouse_exited.connect(GameTooltip.hide_tooltip)


# `id` is the roster entry of this slot, a party id, or -1 for no member.
# `selected` shows the green frame. `deployed` is whether the member is in the
# Deployed pair, which takes the dim off the face.
func show_member(id: int, selected: bool, deployed: bool) -> void:
	party_id = id
	# A face that did not join hides its parts and keeps its slot in the party
	# bar. A hidden child of a FloatBox would give up its place, so the root
	# stays visible.
	_parts.visible = id >= 0
	if id < 0:
		return
	_face.texture = MenuTheme.texture(VictoryScreen.PORTRAITS[id])
	_frame.visible = selected
	# The original hides the player's dim when the clip loads
	# (PlaceObject2_2979_995, onClipEvent(load)), and updateFriends only sets the
	# dim of the companions.
	_blacker.visible = not deployed and id != Party.PLAYER_PARTY_ID


func is_joined() -> bool:
	return _parts.visible


func shows_frame() -> bool:
	return is_joined() and _frame.visible


func shows_blacker() -> bool:
	return is_joined() and _blacker.visible


# The name over the line for the member's kind, as the button's rollOver sets
# KrinToolTipper.tt and .t (DefineButton2_2895): MENU[48] for a companion and
# MENU[49] for the player.
func tooltip() -> Dictionary:
	if party_id < 0:
		return {}
	var title: String = Party.PLAYER_NAME
	if party_id != Party.PLAYER_PARTY_ID:
		title = str(Party.COMPANIONS[party_id]["name"])
	var body: String = Strings.menu(49 if party_id == Party.PLAYER_PARTY_ID else 48)
	return {"title": title, "body": body}


func _show_tooltip() -> void:
	var text: Dictionary = tooltip()
	if text.is_empty():
		return
	GameTooltip.show_sections([
		{"bg_color": TooltipTheme.BG_HEADER, "lines": [{"text": text["title"], "color": TooltipTheme.TEXT_TITLE}]},
		{"bg_color": TooltipTheme.BG_BODY, "lines": [{"text": text["body"], "color": TooltipTheme.TEXT_BODY}]},
	], hit_button)
