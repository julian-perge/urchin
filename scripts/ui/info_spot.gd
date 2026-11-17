# info_spot.gd
# One of the 20 info spots of zones 1 to 5: a hit area on the zone art, with
# the number n of the NAVTITLE[n] and NAVTEXT[n] that its press shows. The
# original's buttons (DefineButton2_3190 to 3193 and the rest) have only a hit
# state, and the zone's frame places no orb on them, so a spot draws nothing and
# has no hover look or tooltip. A press opens the Info card, as krinNavHideUI(n)
# does (frame_42/DoAction_21.as:9-25). The zone scene gives the spot its rect,
# which the rect test checks against the SWF.
class_name InfoSpot
extends TextureButton

@export var spot: int = 0


func _pressed() -> void:
	# The hotbar holds the Hub's inert state, and an inert Hub ignores the orbs
	# the same way (orb_base.gd).
	var hotbar: Node = get_tree().get_first_node_in_group("hotbar")
	if hotbar != null and hotbar.is_inert():
		return
	var card: HubCard = get_tree().get_first_node_in_group(HubCard.GROUP)
	if card == null:
		push_error("info_spot: no Info card in the scene to show spot %d" % spot)
		return
	card.show_card(Strings.text("NAVTITLE", spot), Strings.text("NAVTEXT", spot))
