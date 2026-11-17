# unit_overlay.gd
# The unmirrored per-unit overlay shown over each battling character's paper
# doll: the hover ring and the hover/click zone. The name, the bars and the buff
# icons are in the top status bar (status_bar.gd). FighterPresenter owns one per
# fighter, positions it at the doll and draws the hover ring onto its Ring node,
# whose color depends on the unit's relation to the player.
extends Control
class_name UnitOverlay

@onready var ring: Control = $Ring
@onready var hit_button: Button = $HitButton
