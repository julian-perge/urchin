# top_status_bar.gd
# The six status bars on the Battle screen's top panel, one for each slot. The
# original places sprite 3414 six times as p1BAR to p6BAR (frame 217), and
# slots 1, 3 and 5 sit on the left and 2, 4 and 6 on the right. This holds them
# so that the scene can hand a fighter its bar and hide the bars of slots that
# nobody fights in.
extends Control
class_name TopStatusBar

const SLOT_COUNT: int = 6


# Returns the status bar of `slot`, 1 to 6.
func bar_for_slot(slot: int) -> StatusBar:
	return get_node("Bar%d" % slot)


# Shows the bar of every slot whose unit is active and hides the rest. The
# original's battle clip hides a bar whose player is not active
# (frame_217/PlaceObject2_3389_480 onClipEvent(load), lines 19-28). The other
# bars stay where they are and do not close the gap, because each is placed on
# its own.
func show_active(units: Dictionary) -> void:
	for slot in range(1, SLOT_COUNT + 1):
		var unit: CombatUnit = units.get(slot)
		bar_for_slot(slot).visible = unit != null and unit.active
